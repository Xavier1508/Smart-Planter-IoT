// Single Smart Planter firmware. GPIO levels, wiring, and calibration remain
// unverified. Disconnect external loads during flashing and initial checks.
// Requested commands cannot guarantee relay contacts or boot-time levels.

#include <Arduino.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>
#include <Wire.h>
#include <driver/adc.h>
#include <esp_adc_cal.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
#include <lwip/sockets.h>
#include <math.h>
#include <string.h>

#include "adc-average.h"
#include "cloud-config.h"
#include "cloud-link.h"
#include "control-command.h"
#include "extra-sensors.h"
#include "local-wifi.h"
#if __has_include("local-wifi-secret.local.h")
#include "local-wifi-secret.local.h"
#endif
#include "planter-config.h"
#include "relay-safety.h"
#include "relay-staging.h"
#include "sensor-telemetry.h"
#include "soil-sensor.h"

namespace {

DHT climateSensor(planter::kDhtPin, DHT11);
LiquidCrystal_I2C lcd(0x27, 16, 2);
bool hasSample = false;
uint32_t lastSampleMs = 0;
bool watchdogReady = false;
bool mqAdcReady = false;
bool uvAdcReady = false;
planter::RelayController relayController;
planter::ControlInput lastControlInput{0, 0, 0, false, false, false, false};
bool hasControlInput = false;
planter::ObservationLabels observationLabels;
planter::LabelLineReader labelLineReader;
planter::ControlLineReader controlLineReader;
esp_adc_cal_characteristics_t mqAdcCharacteristics;
planter::AdcCalibrationMethod mqAdcCalibration = planter::AdcCalibrationMethod::unavailable;
esp_adc_cal_characteristics_t uvAdcCharacteristics;
planter::AdcCalibrationMethod uvAdcCalibration = planter::AdcCalibrationMethod::unavailable;
const IPAddress localAddress(192, 168, 4, 1);
WiFiServer localServer(localAddress, planter::kLocalTelemetryPort, 1);
WebServer localHttpServer(80);
WiFiClient localClient;
bool localWifiReady = false;
char latestTelemetry[3072] = {};
bool latestTelemetryValid = false;
char localWifiName[17] = {};
char localWifiPassword[planter::kLocalWifiPasswordLength + 1] = {};
char wifiSsid[33] = {};
char wifiPassword[65] = {};
uint32_t restartAtMs = 0;
uint8_t wifiSetupState = 0;  // 0 idle, 1 connecting, 2 connected, 3 failed
uint32_t wifiSetupStartedMs = 0;
bool restartAfterWifiSetup = false;
char bootResetReason[24] = "unknown";
uint32_t bootBrownoutCount = 0;

struct BootScanEntry {
  char ssid[33];
  int32_t rssi;
  uint8_t channel;
  bool secure;
};
constexpr size_t kBootScanCapacity = 24;
BootScanEntry bootScan[kBootScanCapacity];
size_t bootScanCount = 0;

planter::CloudLink cloudLink;

void applyControlLine(const char* line);
void applyCloudCommand(const planter::CloudCommand& command);
void sendControlAck(const planter::ControlCommand& command, bool ok,
                    const char* error);
void syncRelayCommands(bool immediate = false);
const char* pumpStartBlockReason();

struct HardwareRandom {
  uint32_t next() { return esp_random(); }
};

void scanWifiAtBoot() {
  bootScanCount = 0;
  WiFi.persistent(false);
  if (!WiFi.mode(WIFI_STA)) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"boot_scan_mode_failed\"}");
    return;
  }
  WiFi.setTxPower(WIFI_POWER_8_5dBm);
  WiFi.disconnect(false, false);
  delay(50);
  if (watchdogReady) esp_task_wdt_reset();
  const int found = WiFi.scanNetworks(false, true, false, 200);
  if (watchdogReady) esp_task_wdt_reset();
  if (found <= 0) {
    WiFi.scanDelete();
    Serial.printf("{\"type\":\"wifi\",\"status\":\"boot_scan_empty\","
                  "\"result\":%d}\n", found);
    return;
  }
  for (int index = 0; index < found; ++index) {
    const String ssid = WiFi.SSID(index);
    if (ssid.isEmpty()) continue;
    int existing = -1;
    for (size_t item = 0; item < bootScanCount; ++item) {
      if (strcmp(bootScan[item].ssid, ssid.c_str()) == 0) {
        existing = static_cast<int>(item);
        break;
      }
    }
    if (existing >= 0) {
      if (WiFi.RSSI(index) > bootScan[existing].rssi) {
        bootScan[existing].rssi = WiFi.RSSI(index);
        bootScan[existing].channel = WiFi.channel(index);
        bootScan[existing].secure =
            WiFi.encryptionType(index) != WIFI_AUTH_OPEN;
      }
      continue;
    }
    if (bootScanCount >= kBootScanCapacity) continue;
    BootScanEntry& entry = bootScan[bootScanCount++];
    snprintf(entry.ssid, sizeof(entry.ssid), "%s", ssid.c_str());
    entry.rssi = WiFi.RSSI(index);
    entry.channel = WiFi.channel(index);
    entry.secure = WiFi.encryptionType(index) != WIFI_AUTH_OPEN;
  }
  WiFi.scanDelete();
  Serial.printf("{\"type\":\"wifi\",\"status\":\"boot_scan_ready\","
                "\"networks\":%lu}\n",
                static_cast<unsigned long>(bootScanCount));
}

void loadWifiCredentials() {
  Preferences preferences;
  String ssid = MOSS_WIFI_SSID;
  String password = MOSS_WIFI_PASSWORD;
  if (preferences.begin("moss_wifi", true)) {
    const String storedSsid = preferences.getString("ssid", "");
    const String storedPassword = preferences.getString("pass", "");
    preferences.end();
    if (storedSsid.length() > 0) {
      ssid = storedSsid;
      password = storedPassword;
    }
  }
  snprintf(wifiSsid, sizeof(wifiSsid), "%s", ssid.c_str());
  snprintf(wifiPassword, sizeof(wifiPassword), "%s", password.c_str());
}

void startLocalWifi() {
  // All Wi-Fi configuration stays in RAM. The device keeps its isolated AP as
  // a fallback while optionally joining a router for cloud HTTPS.
  WiFi.persistent(false);
  // A reset caused by brownout is a strong signal that the radio cannot take
  // the extra scan current. Skip the boot scan on that boot and leave the AP
  // running; the user can still type the SSID manually.
  const bool scanAllowed = strcmp(bootResetReason, "brownout") != 0;
  if (scanAllowed) {
    scanWifiAtBoot();
  } else {
    bootScanCount = 0;
    Serial.println("{\"type\":\"wifi\",\"status\":\"boot_scan_skipped\","
                   "\"reason\":\"previous_brownout\"}");
  }
  const bool brownoutBoot = strcmp(bootResetReason, "brownout") == 0;
  const bool stationRequested =
      MOSS_CLOUD_ENABLED && strlen(wifiSsid) > 0;
  // Before credentials exist, use AP-only. This removes STA radio activity
  // and makes the setup network much more stable. After a brownout the cloud
  // stays reachable; the pump itself is held separately for one minute so a
  // power fault cannot immediately repeat while the relay is energised.
  // After saving credentials the page switches to AP+STA for the attempt.
  if (!WiFi.mode(stationRequested ? WIFI_AP_STA : WIFI_AP)) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"ap_mode_failed\"}");
    return;
  }
  // 11 dBm is enough for a phone a few metres away and draws much less peak
  // current than the default 19.5 dBm. This is a stability/range tradeoff.
  WiFi.setTxPower(WIFI_POWER_11dBm);
  // The planter is mains-powered. Disable modem sleep so the first command
  // after a long idle does not wait for a Wi-Fi wake-up interval.
  WiFi.setSleep(false);
  bool passwordReady = false;
#ifdef MOSS_LOCAL_WIFI_PASSWORD
  // Fixed local-only WPA2 password from an ignored header. The phone stores it
  // once and can reconnect automatically after every ESP32 reboot. An invalid
  // local value must not disable the AP; fall back to the boot-random password
  // so the LCD can still show a usable network.
  const size_t fixedLength = strlen(MOSS_LOCAL_WIFI_PASSWORD);
  if (fixedLength >= 8 && fixedLength < sizeof(localWifiPassword)) {
    memcpy(localWifiPassword, MOSS_LOCAL_WIFI_PASSWORD, fixedLength + 1);
    passwordReady = true;
  } else {
    Serial.println("{\"type\":\"wifi\",\"status\":\"local_password_rejected\"}");
  }
#endif
  if (!passwordReady) {
    HardwareRandom random;
    if (!planter::makeLocalWifiPassword(localWifiPassword,
                                        sizeof(localWifiPassword), random)) {
      Serial.println("{\"type\":\"wifi\",\"status\":\"password_failed\"}");
      WiFi.mode(WIFI_OFF);
      return;
    }
  }
  snprintf(localWifiName, sizeof(localWifiName), "Moss");
  if (!WiFi.softAPConfig(localAddress, localAddress, IPAddress(255, 255, 255, 0)) ||
      !WiFi.softAP(localWifiName, localWifiPassword, 6, false, 4)) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"ap_failed\"}");
    WiFi.softAPdisconnect(true);
    return;
  }
  localServer.begin();
  localWifiReady = static_cast<bool>(localServer);
  if (!localWifiReady) {
    Serial.println("{\"type\":\"wifi\",\"status\":\"server_failed\"}");
    WiFi.softAPdisconnect(true);
  } else {
    Serial.printf("{\"type\":\"wifi\",\"status\":\"ap_ready\",\"ssid\":\"%s\"}\n",
                  localWifiName);
    localHttpServer.on("/", HTTP_GET, []() {
      localHttpServer.send(200, "text/html; charset=utf-8", R"HTML(<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tunas Setup</title>
<style>
:root{--ink:#213027;--forest:#315E48;--paper:#F7F5EF;--line:#DDE5DA;--muted:#6A756B;--ok:#1F6B45;--err:#A33B2B}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.5 system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:36rem;margin:auto;padding:24px 16px 48px}.hero{display:flex;gap:14px;align-items:center;margin:8px 0 18px}
.logo{width:52px;height:52px;border-radius:18px;background:#DDE9DA;display:grid;place-items:center;font-size:28px}
h1{font-size:24px;margin:0;letter-spacing:-.02em}p{margin:.25rem 0;color:var(--muted)}
.card{background:#fff;border:1px solid var(--line);border-radius:20px;padding:18px;margin:12px 0;box-shadow:0 8px 28px rgba(33,48,39,.05)}
.row{display:flex;justify-content:space-between;gap:12px;font-size:13px}code{font-size:12px;background:#F1F4EF;padding:3px 7px;border-radius:7px}
label{display:block;font-weight:650;font-size:13px;margin:15px 0 6px}
select,input{width:100%;padding:12px 13px;border:1px solid #CBD7C9;border-radius:12px;background:#fff;color:var(--ink);font:inherit;outline:none}
select:focus,input:focus{border-color:var(--forest);box-shadow:0 0 0 3px rgba(49,94,72,.12)}
.scanrow,.passrow{display:flex;gap:8px}.scanrow select{flex:1}.scanrow button,.passrow button{white-space:nowrap;border:1px solid var(--line);background:#F1F4EF;border-radius:12px;padding:0 14px;font-weight:650;color:var(--forest)}
button{cursor:pointer;font:inherit}button:disabled{opacity:.55;cursor:not-allowed}
.primary{width:100%;margin-top:18px;padding:14px;border:0;border-radius:13px;background:var(--forest);color:#fff;font-weight:750;font-size:15px}
.hint{font-size:12px;color:var(--muted);margin-top:10px}
.status{border-radius:14px;padding:13px 14px;margin:14px 0;background:#F1F4EF;border:1px solid var(--line);display:grid;gap:3px}
.status strong{font-size:14px}.status span{font-size:12.5px;color:var(--muted)}
.status.ok{background:#EAF5EC;border-color:#B9D9C2}.status.ok span{color:var(--ok)}
.status.err{background:#FCEFEB;border-color:#E8C2B8}.status.err span{color:var(--err)}
.status.busy{background:#FFF8E7;border-color:#E9D7A7}
.spinner{width:15px;height:15px;border:2px solid #D8E1D5;border-top-color:var(--forest);border-radius:50%;display:inline-block;vertical-align:-2px;margin-right:7px;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
details{margin-top:12px;font-size:13px;color:var(--muted)}summary{cursor:pointer;font-weight:650;color:var(--ink)}
.badge{font-size:11px;font-weight:750;letter-spacing:.04em;color:var(--forest);text-transform:uppercase}
</style>
</head>
<body><main>
<div class="hero"><div class="logo">🌱</div><div><span class="badge">Tunas Smart Planter</span><h1>Hubungkan ke Wi-Fi rumah</h1><p>Pilih jaringan, masukkan password, lalu tunggu status koneksi.</p></div></div>
<div class="card">
<div class="row"><span>ID perangkat</span><code id="device-id">memuat...</code></div>
<p id="diag" class="hint"></p>
<div id="status" class="status"><strong id="status-title">Menyiapkan halaman...</strong><span id="status-text">Membaca status perangkat.</span></div>
<label for="ssid-select">Wi-Fi yang terdeteksi</label>
<div class="scanrow"><select id="ssid-select"><option value="">Pilih Wi-Fi...</option></select><button id="scan-btn" onclick="scan()">Scan</button></div>
<label for="ssid-manual">Atau ketik SSID manual</label>
<input id="ssid-manual" maxlength="32" autocomplete="off" placeholder="Nama Wi-Fi tersembunyi">
<label for="pass">Password Wi-Fi</label>
<div class="passrow"><input id="pass" type="password" maxlength="63" autocomplete="current-password" placeholder="Minimal 8 karakter"><button type="button" onclick="togglePass()">Lihat</button></div>
<p class="hint">ESP32 hanya mendukung Wi-Fi <b>2,4 GHz</b> dan WPA2/WPA2-PSK. SSID 5 GHz tidak akan terlihat.</p>
<button id="connect" class="primary" onclick="save()">Simpan &amp; sambungkan</button>
<p class="hint">Setelah koneksi berhasil, perangkat restart otomatis. Halaman ini akan terputus sebentar; sambungkan kembali ke <b>Moss</b> lalu buka halaman ini untuk melihat status cloud.</p>
</div>
<div class="card"><strong>Jika ponsel menolak Wi-Fi ini</strong><p>Android kadang berpindah ke data seluler karena AP belum punya internet. Pilih <b>Tetap terhubung</b>, matikan sementara data seluler, dan matikan auto-switch Wi-Fi.</p></div>
<details><summary>Wi-Fi tidak muncul saat scan?</summary><p>Jauhkan ponsel 1–2 meter dari perangkat, tekan Scan ulang, atau ketik SSID manual. Scan dapat membuat AP sempat terputus sebentar; tunggu sampai daftar muncul.</p></details>
</main>
<script>
const $=id=>document.getElementById(id);
let busy=false, pollTimer=null, pollFails=0;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function setStatus(kind,title,text,spin){
  const box=$('status'); box.className='status '+kind;
  const heading=$('status-title'); heading.textContent='';
  if(spin){const dot=document.createElement('span');dot.className='spinner';heading.appendChild(dot);}
  heading.appendChild(document.createTextNode(title));
  $('status-text').textContent=text||'';
}
function togglePass(){const p=$('pass');p.type=p.type==='password'?'text':'password';}
async function readJson(url,opts){
  const r=await fetch(url,Object.assign({cache:'no-store'},opts||{}));
  let j={}; try{j=await r.json();}catch(e){}
  return {r,j};
}
function addNetwork(n){
  if(!n.ssid) return;
  const o=document.createElement('option');
  o.value=n.ssid;
  o.textContent=n.ssid+'  •  '+n.rssi+' dBm'+(n.secure?'  🔒':'  terbuka');
  $('ssid-select').appendChild(o);
}
async function scan(){
  if(busy) return;
  $('scan-btn').disabled=true;
  setStatus('busy','Memindai Wi-Fi sekitar...','Scan dapat membuat AP terputus sebentar.',true);
  try{
    for(let i=0;i<20;i++){
      const {r,j}=await readJson('/api/v1/wifi/scan');
      if(r.status===202){await sleep(1200);continue;}
      if(!r.ok) throw new Error(j.error||'scan_failed');
      $('ssid-select').innerHTML='<option value="">Pilih Wi-Fi...</option>';
      (j.networks||[]).forEach(addNetwork);
      const count=(j.networks||[]).length;
      if(count===0) setStatus('','Tidak ada Wi-Fi ditemukan','Coba Scan ulang atau ketik SSID manual.');
      else setStatus('ok','Ditemukan '+count+' Wi-Fi','Pilih jaringan rumah Anda dari daftar.');
      return;
    }
    setStatus('err','Scan terlalu lama','Tekan Scan untuk mencoba lagi.');
  }catch(e){
    const msg=String(e&&e.message||'');
    if(msg.includes('scan_unavailable')){
      setStatus('err','Scan tidak tersedia','Ketik SSID rumah secara manual di kolom bawah. Ini lebih stabil saat daya/radio terbatas.');
    }else{
      setStatus('err','Scan gagal','Perangkat mungkin sedang sibuk atau AP terputus. Coba lagi atau ketik SSID manual.');
    }
  }finally{$('scan-btn').disabled=false;}
}
async function save(){
  if(busy) return;
  const manual=$('ssid-manual').value.trim();
  const ssid=manual || $('ssid-select').value;
  const pass=$('pass').value;
  if(!ssid){setStatus('err','Wi-Fi belum dipilih','Pilih dari daftar atau ketik SSID manual.');return;}
  if(pass.length>0 && pass.length<8){setStatus('err','Password terlalu pendek','Password WPA2 minimal 8 karakter.');return;}
  busy=true; $('connect').disabled=true;
  setStatus('busy','Menyimpan dan menghubungkan...','Mengirim kredensial ke perangkat.',true);
  try{
    const {r,j}=await readJson('/api/v1/wifi',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ssid:ssid,password:pass})});
    if(!r.ok) throw new Error(j.error||'save_failed');
    setStatus('busy','Menghubungkan ke '+ssid,'Menunggu hasil dari ESP32...',true);
    poll();
  }catch(e){
    setStatus('busy','Memeriksa status perangkat...','AP bisa terputus sebentar saat mencoba Wi-Fi rumah.',true);
    pollTimer=setTimeout(poll,1500);
  }
}
async function poll(){
  clearTimeout(pollTimer);
  try{
    const {r,j}=await readJson('/api/v1/wifi/status');
    if(!r.ok) throw new Error('status');
    pollFails=0;
    if(j.state==='connected'){
      const restart=Number(j.restart_in_ms||0);
      setStatus('ok','Tersambung ke '+(j.ssid||'Wi-Fi rumah'),'IP '+(j.ip||'-')+' • sinyal '+j.rssi+' dBm');
      if(restart>0){
        $('status-text').textContent='IP '+(j.ip||'-')+' • perangkat restart dalam '+Math.ceil(restart/1000)+' detik.';
      }else if(!j.cloud_enabled){
        $('status-text').textContent='IP '+(j.ip||'-')+' • setelah restart, cloud aktif otomatis.';
      }
      pollTimer=setTimeout(poll,1000);
    }else if(j.state==='connecting'){
      setStatus('busy','Menghubungkan ke '+(j.ssid||'Wi-Fi...'),'Menunggu DHCP dan verifikasi password...',true);
      pollTimer=setTimeout(poll,1200);
    }else if(j.state==='failed'){
      const names={0:'idle',1:'SSID tidak ditemukan',2:'scan selesai',3:'terhubung',4:'password/keamanan ditolak',5:'koneksi hilang',6:'terputus'};
      const code=(j.sta_status==null?'':' Status driver: '+(names[j.sta_status]||j.sta_status)+'.');
      setStatus('err','Gagal terhubung ke '+(j.ssid||'Wi-Fi'),'Periksa password, pilih jaringan 2,4 GHz, dan gunakan WPA2. Perangkat tetap di AP Moss.'+code);
      busy=false; $('connect').disabled=false;
    }else{
      setStatus('','Belum terhubung ke Wi-Fi rumah','Pilih jaringan lalu tekan Simpan & sambungkan.');
      busy=false; $('connect').disabled=false;
    }
  }catch(e){
    pollFails++;
    if(pollFails<5){
      setStatus('busy','Menunggu perangkat...','AP mungkin berpindah kanal atau perangkat sedang restart.',true);
      pollTimer=setTimeout(poll,1500);
      return;
    }
    setStatus('err','Perangkat sedang restart atau tidak terjangkau','Sambungkan kembali ke Moss lalu buka http://192.168.4.1/.');
    busy=false; $('connect').disabled=false;
  }
}
$('ssid-select').addEventListener('change',()=>{if($('ssid-select').value) $('ssid-manual').value='';});
fetch('/api/v1/health').then(r=>r.json()).then(j=>{ $('device-id').textContent=j.hardware_id||'-'; if(Number(j.brownout_count)>0){ $('diag').textContent='Peringatan daya: brownout '+j.brownout_count+' kali. Gunakan adaptor 5V/USB yang kuat.'; $('diag').style.color='#A33B2B'; } }).catch(()=>{$('device-id').textContent='tidak tersedia';});
poll();
setStatus('','Siap memindai Wi-Fi','Tekan tombol Scan untuk melihat jaringan di sekitar perangkat.');
</script>
</body></html>)HTML");
    });
    localHttpServer.on("/api/v1/telemetry", HTTP_GET, []() {
      if (!latestTelemetryValid) {
        localHttpServer.send(503, "application/json",
                             "{\"error\":\"no_sample_yet\"}");
        return;
      }
      localHttpServer.send(200, "application/json", latestTelemetry);
    });
    localHttpServer.on("/api/v1/health", HTTP_GET, []() {
      char body[800];
      snprintf(body, sizeof(body),
               "{\"firmware_version\":%u,\"uptime_ms\":%lu,"
               "\"hardware_id\":\"%s\","
               "\"reset_reason\":\"%s\",\"brownout_count\":%lu,"
               "\"sta_status\":%d,\"scan_cached\":%lu,"
               "\"ap_clients\":%d,\"tx_power\":%d,"
               "\"local_ap\":%s,\"sta_connected\":%s,\"cloud_enabled\":%s,"
               "\"cloud_online\":%s,\"storage_ready\":%s,"
               "\"cloud_status\":\"%s\",\"buffered_batches\":%lu,"
               "\"queued_samples\":%lu,\"last_upload_age_s\":%lu,"
               "\"dropped_samples\":%lu,\"free_heap\":%lu}",
               planter::kFirmwareVersion,
               static_cast<unsigned long>(millis()),
               MOSS_DEVICE_ID,
               bootResetReason,
               static_cast<unsigned long>(bootBrownoutCount),
               static_cast<int>(WiFi.status()),
               static_cast<unsigned long>(bootScanCount),
               static_cast<int>(WiFi.softAPgetStationNum()),
               static_cast<int>(WiFi.getTxPower()),
               localWifiReady ? "true" : "false",
               WiFi.status() == WL_CONNECTED ? "true" : "false",
               cloudLink.enabled() ? "true" : "false",
               cloudLink.cloudOnline() ? "true" : "false",
               cloudLink.storageReady() ? "true" : "false",
               cloudLink.statusText(),
               static_cast<unsigned long>(cloudLink.bufferedBatches()),
               static_cast<unsigned long>(cloudLink.queuedSamples()),
               static_cast<unsigned long>(cloudLink.lastUploadAgeSeconds()),
               static_cast<unsigned long>(cloudLink.droppedSamples()),
               static_cast<unsigned long>(ESP.getFreeHeap()));
      localHttpServer.send(200, "application/json", body);
    });
    localHttpServer.on("/api/v1/wifi/scan", HTTP_GET, []() {
      // The boot scan runs before the AP starts, so reading its cache does not
      // make the phone lose the access point. Use ?refresh=1 only when the
      // caller explicitly accepts a brief radio interruption.
      if (bootScanCount > 0 && localHttpServer.arg("refresh") != "1") {
        JsonDocument cached;
        JsonArray networks = cached["networks"].to<JsonArray>();
        for (size_t index = 0; index < bootScanCount; ++index) {
          JsonObject network = networks.add<JsonObject>();
          network["ssid"] = bootScan[index].ssid;
          network["rssi"] = bootScan[index].rssi;
          network["channel"] = bootScan[index].channel;
          network["secure"] = bootScan[index].secure;
        }
        cached["count"] = networks.size();
        cached["source"] = "boot";
        String body;
        serializeJson(cached, body);
        localHttpServer.send(200, "application/json", body);
        return;
      }
      if (bootScanCount == 0) {
        localHttpServer.send(
            503, "application/json",
            "{\"error\":\"scan_unavailable\","
            "\"message\":\"Scan boot tidak tersedia; ketik SSID manual.\"}");
        return;
      }
      int result = WiFi.scanComplete();
      if (result == WIFI_SCAN_RUNNING) {
        localHttpServer.send(202, "application/json",
                             "{\"status\":\"scanning\"}");
        return;
      }
      if (result == WIFI_SCAN_FAILED) {
        WiFi.scanDelete();
        const int started = WiFi.scanNetworks(true, true, false, 120);
        if (started == WIFI_SCAN_RUNNING) {
          localHttpServer.send(202, "application/json",
                               "{\"status\":\"scanning\"}");
          return;
        }
        if (started < 0) {
          localHttpServer.send(500, "application/json",
                               "{\"error\":\"scan_failed\"}");
          return;
        }
        result = started;
      }

      JsonDocument document;
      JsonArray networks = document["networks"].to<JsonArray>();
      for (int index = 0; index < result; ++index) {
        const String ssid = WiFi.SSID(index);
        if (ssid.isEmpty()) continue;
        JsonObject network = networks.add<JsonObject>();
        network["ssid"] = ssid;
        network["rssi"] = WiFi.RSSI(index);
        network["channel"] = WiFi.channel(index);
        network["secure"] = WiFi.encryptionType(index) != WIFI_AUTH_OPEN;
      }
      document["count"] = networks.size();
      String body;
      serializeJson(document, body);
      WiFi.scanDelete();
      localHttpServer.send(200, "application/json", body);
    });
    localHttpServer.on("/api/v1/wifi/status", HTTP_GET, []() {
      const bool connected = WiFi.status() == WL_CONNECTED;
      const char* state = "idle";
      if (connected) {
        state = "connected";
      } else if (wifiSetupState == 1 || wifiSetupState == 2) {
        state = "connecting";
      } else if (wifiSetupState == 3) {
        state = "failed";
      }
      JsonDocument document;
      document["configured"] = strlen(wifiSsid) > 0;
      document["ssid"] = wifiSsid;
      document["state"] = state;
      document["sta_connected"] = connected;
      document["sta_status"] = static_cast<int>(WiFi.status());
      document["ip"] = connected ? WiFi.localIP().toString() : "";
      document["rssi"] = connected ? WiFi.RSSI() : 0;
      document["cloud_enabled"] = cloudLink.enabled();
      document["cloud_online"] = cloudLink.cloudOnline();
      document["restart_in_ms"] =
          restartAtMs == 0
              ? 0
              : static_cast<int32_t>(restartAtMs - millis()) > 0
                    ? static_cast<uint32_t>(restartAtMs - millis())
                    : 0;
      document["attempt_elapsed_ms"] =
          wifiSetupState == 1 ? millis() - wifiSetupStartedMs : 0;
      String body;
      serializeJson(document, body);
      localHttpServer.send(200, "application/json", body);
    });
    localHttpServer.on("/api/v1/wifi", HTTP_POST, []() {
      const String payload = localHttpServer.arg("plain");
      if (payload.length() == 0 || payload.length() > 512) {
        localHttpServer.send(413, "application/json",
                             "{\"error\":\"payload_size\"}");
        return;
      }
      JsonDocument document;
      if (deserializeJson(document, payload)) {
        localHttpServer.send(400, "application/json",
                             "{\"error\":\"invalid_json\"}");
        return;
      }
      const String ssid = document["ssid"] | "";
      const String password = document["password"] | "";
      if (ssid.length() < 1 || ssid.length() > 32 ||
          password.length() > 63 ||
          (password.length() > 0 && password.length() < 8)) {
        localHttpServer.send(422, "application/json",
                             "{\"error\":\"invalid_credentials\"}");
        return;
      }
      Preferences preferences;
      if (!preferences.begin("moss_wifi", false)) {
        localHttpServer.send(500, "application/json",
                             "{\"error\":\"nvs_unavailable\"}");
        return;
      }
      const bool saved = preferences.putString("ssid", ssid) > 0 &&
                         preferences.putString("pass", password) >= 0;
      preferences.end();
      if (!saved) {
        localHttpServer.send(500, "application/json",
                             "{\"error\":\"save_failed\"}");
        return;
      }

      WiFi.scanDelete();
      snprintf(wifiSsid, sizeof(wifiSsid), "%s", ssid.c_str());
      snprintf(wifiPassword, sizeof(wifiPassword), "%s", password.c_str());
      if (WiFi.getMode() != WIFI_AP_STA) {
        WiFi.mode(WIFI_AP_STA);
      }
      WiFi.setTxPower(WIFI_POWER_11dBm);
      WiFi.disconnect(false, false);
      WiFi.begin(wifiSsid, wifiPassword);
      wifiSetupState = 1;
      wifiSetupStartedMs = millis();
      restartAtMs = 0;
      restartAfterWifiSetup = true;
      Serial.println("{\"type\":\"wifi\",\"status\":\"setup_begin\"}");

      JsonDocument response;
      response["status"] = "connecting";
      response["ssid"] = ssid;
      String body;
      serializeJson(response, body);
      localHttpServer.send(202, "application/json", body);
    });
    localHttpServer.onNotFound([]() {
      localHttpServer.send(404, "application/json",
                           "{\"error\":\"not_found\"}");
    });
    localHttpServer.begin();
    if (stationRequested) {
      WiFi.begin(wifiSsid, wifiPassword);
      wifiSetupState = 1;
      wifiSetupStartedMs = millis();
      const bool cloudReady = cloudLink.begin(
          MOSS_SUPABASE_URL, MOSS_DEVICE_ID, MOSS_DEVICE_TOKEN, wifiSsid,
          wifiPassword);
      Serial.printf(
          "{\"type\":\"cloud\",\"event\":\"begin\",\"enabled\":%s,"
          "\"hardware_id\":\"%s\",\"status\":\"%s\"}\n",
          cloudReady ? "true" : "false", cloudLink.hardwareId(),
          cloudLink.statusText());
    } else {
      Serial.printf("{\"type\":\"cloud\",\"event\":\"disabled\","
                    "\"reason\":\"%s\"}\n",
                    brownoutBoot ? "brownout_safe_mode"
                                 : "no_sta_credentials");
    }
  }
}

void pollLocalWifi() {
  if (!localWifiReady) return;
  if (localClient && !localClient.connected()) {
    // Drop a half-open peer so a fresh phone connection can be accepted.
    localClient.stop();
  }
  if (localClient) {
    // Read a bounded number of command bytes per loop so serial/telemetry and
    // the watchdog are never starved. The command reader is line-bounded.
    for (unsigned count = 0; count < 64 && localClient.available() > 0; ++count) {
      const int value = localClient.read();
      if (value < 0) break;
      const planter::ControlLineReader::Result result =
          controlLineReader.push(static_cast<char>(value));
      if (result == planter::ControlLineReader::Result::ready) {
        applyControlLine(controlLineReader.line());
      } else if (result == planter::ControlLineReader::Result::rejected) {
        sendControlAck(planter::ControlCommand{}, false, "\"line_too_long\"");
      }
    }
  }
  if (!localClient) {
    localClient.stop();
    localClient = localServer.available();
    if (localClient) localClient.setNoDelay(true);
  } else if (localServer.hasClient()) {
    WiFiClient extra = localServer.available();
    extra.stop();
  }
}

void sendLocalLine(const char* line) {
  if (!localWifiReady || !localClient || line == nullptr) return;
  char buffer[256];
  const size_t length = strlen(line);
  if (length + 1 >= sizeof(buffer)) return;
  memcpy(buffer, line, length);
  buffer[length] = '\n';
  const int written = send(localClient.fd(), buffer, length + 1, MSG_DONTWAIT);
  if (written != static_cast<int>(length + 1)) localClient.stop();
}

void sendControlAck(const planter::ControlCommand& command, bool ok,
                    const char* error) {
  char ack[256];
  const planter::ControlStatus status = relayController.status();
  const uint32_t nowMs = millis();
  const uint32_t remainingS =
      (relayController.pumpManualRemainingMs(nowMs) + 999) / 1000;
  const uint32_t lockoutS =
      (relayController.pumpCooldownRemainingMs(nowMs) + 999) / 1000;
  snprintf(ack, sizeof(ack),
           "{\"type\":\"ack\",\"id\":%lu,\"ok\":%s,\"error\":%s,"
           "\"pump_manual\":%s,\"pump_on\":%s,\"pump_remaining_s\":%lu,"
           "\"pump_cooldown_s\":%lu,\"pump_runtime_lockout\":%s,"
           "\"light_manual\":%s,\"light_on\":%s}",
           command.id, ok ? "true" : "false",
           error == nullptr ? "null" : error,
           relayController.pumpManual() ? "true" : "false",
           status.pumpOn ? "true" : "false",
           static_cast<unsigned long>(remainingS),
           static_cast<unsigned long>(lockoutS),
           relayController.pumpRuntimeLockout() ? "true" : "false",
           relayController.lightManual() ? "true" : "false",
           status.lightOn ? "true" : "false");
  sendLocalLine(ack);
}

// Manual ON is still a physical pump command. Empty water, a missing reading,
// a stale sample, or an unavailable watchdog must reject it just like AUTO.
const char* pumpStartBlockReason() {
  if (!hasControlInput || !watchdogReady) return "sensor_unavailable";
  if (millis() - lastSampleMs > planter::kSampleStaleMs) return "sample_stale";
  if (lastControlInput.waterAdcRaw < 0) return "water_unavailable";
  if (lastControlInput.waterAdcRaw < planter::kPumpWaterLowRawAdc) {
    return "water_low";
  }
  return nullptr;
}

void applyControlCommand(const planter::ControlCommand& command, bool localAck) {
  const char* block = command.pumpSet && !command.pumpAuto && command.pumpOn
                          ? pumpStartBlockReason()
                          : nullptr;
  if (block != nullptr) {
    if (localAck) {
      char quoted[32];
      snprintf(quoted, sizeof(quoted), "\"%s\"", block);
      sendControlAck(command, false, quoted);
    }
    return;
  }

  const uint32_t nowMs = millis();
  bool autoRequested = false;
  if (command.pumpSet) {
    if (command.pumpAuto) {
      relayController.setPumpAuto();
      autoRequested = true;
    } else {
      relayController.setPumpManual(nowMs, command.pumpOn,
                                    command.durationSeconds * 1000UL);
    }
  }
  if (command.lightSet) {
    if (command.lightAuto) {
      relayController.setLightAuto();
      autoRequested = true;
    } else {
      relayController.setLightManual(nowMs, command.lightOn,
                                     command.durationSeconds * 1000UL);
    }
  }
  if (autoRequested && hasControlInput) {
    // Apply the last measured sample immediately so AUTO does not keep a
    // manual ON output until the next 5-second sample.
    relayController.accept(nowMs, lastControlInput);
  }
  syncRelayCommands(true);
  if (localAck) sendControlAck(command, true, "null");
}

void applyControlLine(const char* line) {
  const planter::ControlCommand command = planter::parseControlLine(line);
  if (!command.valid) {
    sendControlAck(command, false, "\"invalid\"");
    return;
  }
  applyControlCommand(command, true);
}

void applyCloudCommand(const planter::CloudCommand& command) {
  if (!command.valid) return;
  if (command.expiresInMs < 1000) {
    cloudLink.enqueueAck(command, false, "expired_before_execution");
    return;
  }
  planter::ControlCommand local;
  local.valid = true;
  if (strcmp(command.actuator, "pump") == 0) {
    local.pumpSet = true;
    local.pumpAuto = strcmp(command.action, "auto") == 0;
    local.pumpOn = strcmp(command.action, "on") == 0;
  } else if (strcmp(command.actuator, "light") == 0) {
    local.lightSet = true;
    local.lightAuto = strcmp(command.action, "auto") == 0;
    local.lightOn = strcmp(command.action, "on") == 0;
  } else {
    cloudLink.enqueueAck(command, false, "invalid_actuator");
    return;
  }
  local.durationSeconds = command.durationSeconds;
  const char* block = local.pumpSet && !local.pumpAuto && local.pumpOn
                          ? pumpStartBlockReason()
                          : nullptr;
  if (block != nullptr) {
    cloudLink.enqueueAck(command, false, block);
    return;
  }
  applyControlCommand(local, false);
  cloudLink.enqueueAck(command, true, nullptr);
  // The next 5-second sample will include the new relay state and be uploaded
  // immediately instead of waiting for the normal batch window.
  cloudLink.requestFlush();
}

void sendLocalSample(char* output, size_t capacity) {
  if (!localWifiReady || !localClient) return;
  const size_t length = strlen(output);
  if (length + 1 >= capacity) {
    localClient.stop();
    return;
  }
  output[length] = '\n';
  // A slow or disconnected client must not block sampling or the watchdog.
  const int written = send(localClient.fd(), output, length + 1, MSG_DONTWAIT);
  if (written != static_cast<int>(length + 1)) localClient.stop();
  output[length] = '\0';
}

const char* resetReasonName(esp_reset_reason_t reason) {
  switch (reason) {
    case ESP_RST_POWERON: return "poweron";
    case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_SW: return "software";
    case ESP_RST_PANIC: return "panic";
    case ESP_RST_INT_WDT: return "interrupt_watchdog";
    case ESP_RST_TASK_WDT: return "task_watchdog";
    case ESP_RST_WDT: return "watchdog";
    case ESP_RST_DEEPSLEEP: return "deep_sleep";
    case ESP_RST_EXT: return "external";
    default: return "unknown";
  }
}

void logBootReason() {
  Preferences prefs;
  uint32_t brownouts = 0;
  bool nvsReady = false;
  const esp_reset_reason_t reason = esp_reset_reason();
  nvsReady = prefs.begin("moss_boot", false);
  if (nvsReady) {
    brownouts = prefs.getUInt("brownouts", 0);
    if (reason == ESP_RST_BROWNOUT) {
      ++brownouts;
      prefs.putUInt("brownouts", brownouts);
    }
    prefs.end();
  }
  snprintf(bootResetReason, sizeof(bootResetReason), "%s", resetReasonName(reason));
  bootBrownoutCount = brownouts;
  // Serial diagnostic only; this line is never sent over the TCP telemetry
  // stream, so the Android parser is unaffected.
  Serial.printf(
      "{\"type\":\"boot\",\"firmware_version\":%u,\"reset_reason\":\"%s\","
      "\"brownout_count\":%lu,\"nvs_ready\":%s}\n",
      planter::kFirmwareVersion, resetReasonName(reason),
      static_cast<unsigned long>(brownouts), nvsReady ? "true" : "false");
}

struct ArduinoGpio {
  void write(int pin, bool high) { digitalWrite(pin, high ? HIGH : LOW); }
  void enableOutput(int pin) { pinMode(pin, OUTPUT); }
};

int medianAnalogRead(int pin) {
  return planter::medianAdc([pin]() { return analogRead(pin); });
}

struct ArduinoSoilGpio {
  void write(int pin, bool high) { digitalWrite(pin, high ? HIGH : LOW); }
  void enableOutput(int pin) { pinMode(pin, OUTPUT); }
  void enableInput(int pin) { pinMode(pin, INPUT); }
  void delayMs(uint32_t milliseconds) { delay(milliseconds); }
  int readAnalog(int pin) { return medianAnalogRead(pin); }
};

ArduinoGpio relayGpio;
planter::RelayStager<ArduinoGpio> relayStager;

void syncRelayCommands(bool immediate) {
  const planter::ControlStatus status = relayController.status();
  relayStager.update(millis(), status.pumpOn, status.lightOn, relayGpio,
                     immediate);
}

int readSoilRaw() {
  // ADC34 can be sampled without driving the unverified GPIO25 supply pin.
  ArduinoSoilGpio gpio;
  return planter::acquireSoilRaw(gpio, planter::kSoilAdcReadEnabled,
                                 planter::kSoilPowerWiringVerified);
}

void readObservationCommands() {
  // Bound work per loop so serial input cannot starve the watchdog.
  for (unsigned count = 0; count < 64 && Serial.available() > 0; ++count) {
    const int value = Serial.read();
    if (value < 0) break;
    const planter::LabelLineResult line = labelLineReader.push(static_cast<char>(value));
    if (line == planter::LabelLineResult::pending) continue;
    const uint32_t nowMs = millis();
    const planter::LabelCommandResult result = observationLabels.apply(
        line == planter::LabelLineResult::ready ? labelLineReader.line() : nullptr,
        nowMs);
    if (result == planter::LabelCommandResult::set) {
      const planter::ObservationLabel* label = observationLabels.current(nowMs);
      Serial.printf("{\"type\":\"annotation\",\"event\":\"set\","
                    "\"uptime_ms\":%lu,\"sensor\":\"%s\",\"condition\":\"%s\","
                    "\"source\":\"operator_reported\",\"max_duration_ms\":%lu}\n",
                    static_cast<unsigned long>(nowMs), label->sensor,
                    label->condition,
                    static_cast<unsigned long>(planter::kObservationLabelTtlMs));
    } else {
      Serial.printf("{\"type\":\"annotation\",\"event\":\"%s\","
                    "\"uptime_ms\":%lu}\n",
                    result == planter::LabelCommandResult::cleared ? "cleared"
                                                                   : "rejected_and_cleared",
                    static_cast<unsigned long>(nowMs));
    }
  }
}

// User-reported SVP/GPIO36 is ADC1 channel 0. ADC1 remains usable while Wi-Fi
// runs; neither an ADC value nor firmware can verify safe module voltages.
int readMqRaw() {
  static_assert(extra_sensors::kMq135Pin == 36, "Update ADC1 channel for MQ pin");
  if (!mqAdcReady) return -1;
  return planter::medianAdc([]() { return adc1_get_raw(ADC1_CHANNEL_0); });
}

// GPIO35 is ADC1 channel 7. Reading the channel explicitly avoids relying on
// Arduino pin remapping and makes a 0 V output distinguishable from a missing
// read. A 0 V result is reported as rail_low, never as a valid UV index.
void logUvProbe() {
  Serial.printf(
      "{\"type\":\"uv_probe\",\"gpio32\":%d,\"gpio33\":%d,\"gpio34\":%d,"
      "\"gpio35\":%d,\"gpio36\":%d,\"gpio39\":%d}\n",
      adc1_get_raw(ADC1_CHANNEL_4), adc1_get_raw(ADC1_CHANNEL_5),
      adc1_get_raw(ADC1_CHANNEL_6), adc1_get_raw(ADC1_CHANNEL_7),
      adc1_get_raw(ADC1_CHANNEL_0), adc1_get_raw(ADC1_CHANNEL_3));
}

int readUvRaw() {
  static_assert(planter::kUvPin == 35, "Update ADC1 channel for UV pin");
  if (!uvAdcReady) return -1;
  return planter::medianAdc([]() { return adc1_get_raw(ADC1_CHANNEL_7); });
}

void lcdLine(uint8_t row, const char* text) {
  char padded[17];
  snprintf(padded, sizeof(padded), "%-16.16s", text);
  lcd.setCursor(0, row);
  lcd.print(padded);
}

void updateLcd(uint32_t nowMs) {
  // The LCD is a pairing aid, not a rotating sensor dashboard. The device ID
  // scrolls on line 1; the claim code stays fixed on line 2. This avoids the
  // user having to chase a page while typing credentials into the app.
  static char idText[48] = {};
  if (idText[0] == '\0') {
    snprintf(idText, sizeof(idText), "  ID:%s  ", MOSS_DEVICE_ID);
  }
  const size_t length = strlen(idText);
  char window[17] = {};
  if (length > 0) {
    const size_t offset = (nowMs / 450U) % length;
    for (size_t index = 0; index < 16; ++index) {
      window[index] = idText[(offset + index) % length];
    }
  }
  lcdLine(0, window);
  char claim[17] = {};
  snprintf(claim, sizeof(claim), "Claim:%s", MOSS_DEVICE_CLAIM_CODE);
  lcdLine(1, claim);
}

void printSample(uint32_t nowMs) {
  const int uvRaw = readUvRaw();
  // esp_adc_cal returns a non-zero intercept for raw 0. Report 0 mV
  // explicitly so a 0 V rail is not mistaken for a live 142 mV signal.
  const int uvPinMillivolts =
      uvRaw == 0
          ? 0
          : (uvRaw > 0 &&
                     uvAdcCalibration != planter::AdcCalibrationMethod::unavailable
                 ? static_cast<int>(
                       esp_adc_cal_raw_to_voltage(uvRaw, &uvAdcCharacteristics))
                 : -1);
  const int mqRaw = readMqRaw();
  const int mqPinMillivolts =
      planter::controlAnalogUsable(mqRaw) &&
              mqAdcCalibration != planter::AdcCalibrationMethod::unavailable
          ? static_cast<int>(esp_adc_cal_raw_to_voltage(mqRaw, &mqAdcCharacteristics))
          : -1;
  planter::SensorSnapshot sample = {
      nowMs,
      planter::kDhtEnabled ? climateSensor.readTemperature() : NAN,
      planter::kDhtEnabled ? climateSensor.readHumidity() : NAN,
      readSoilRaw(),
      medianAnalogRead(planter::kLightPin),
      uvRaw,
      planter::kDhtEnabled,
      medianAnalogRead(extra_sensors::kWaterLevelPin),
      true,
      planter::kSoilAdcReadEnabled,
      planter::kDhtModelVerified,
      mqRaw,
      digitalRead(extra_sensors::kMq135DigitalPin),
      true,
      mqRaw >= 0,
      mqPinMillivolts,
      mqAdcCalibration,
      uvPinMillivolts,
  };

  sample.uptimeMs = millis();
  if (uvRaw == 0) {
    static uint32_t lastUvProbeMs = 0;
    if (lastUvProbeMs == 0 || sample.uptimeMs - lastUvProbeMs >= 60000) {
      lastUvProbeMs = sample.uptimeMs;
      logUvProbe();
    }
  }
  const planter::RulePreview preview = planter::previewRules(sample);
  // A rail can be a real extreme or a disconnected signal. For actuator
  // control, reject the ambiguity rather than interpreting it as darkness or
  // dryness. The unmodified raw values remain visible in telemetry.
  const bool soilUsable = planter::soilAnalogUsable(sample.soilAdcRaw);
  // LDR rails are valid bright/dark extremes; a failed read is still -1.
  const bool lightUsable = planter::validAdcRaw(sample.lightAdcRaw);
  const bool waterUsable = planter::controlWaterAdcUsable(sample.waterAdcRaw);
  const planter::ControlInput input = {
      soilUsable ? sample.soilAdcRaw : -1,
      lightUsable ? preview.lightPercent : -1,
      waterUsable ? preview.waterPercent : -1,
      planter::kPumpSoilScaleConfirmed || planter::kPumpAllowEstimatedSoil,
      planter::kWaterRelativeScaleEnabled,
      watchdogReady,
      planter::kLightAutomationEnabled,
      waterUsable ? sample.waterAdcRaw : -1,
  };
  lastControlInput = input;
  hasControlInput = true;
  if (strcmp(bootResetReason, "brownout") == 0 &&
      millis() < planter::kBrownoutPumpHoldMs) {
    relayController.inhibit(sample.uptimeMs, "brownout_hold");
  } else {
    relayController.accept(sample.uptimeMs, input);
  }
  syncRelayCommands();
  planter::ControlStatus control = relayController.status();
  control.pumpRuntimeLockout = relayController.pumpRuntimeLockout();
  control.pumpCooldownRemainingS =
      (relayController.pumpCooldownRemainingMs(sample.uptimeMs) + 999) / 1000;

  // Avoid placing the entire network frame on the ESP32 loop task's stack.
  static char output[3072];
    if (planter::formatTelemetry(sample, output, sizeof(output), &control,
                                observationLabels.current(sample.uptimeMs))) {
    snprintf(latestTelemetry, sizeof(latestTelemetry), "%s", output);
    latestTelemetryValid = true;
    Serial.println(output);
    sendLocalSample(output, sizeof(output));
  } else {
    Serial.println("{\"type\":\"error\",\"code\":\"encoding_failed\"}");
  }
  if (cloudLink.enabled()) {
    planter::CloudSample cloud;
    cloud.uptimeMs = sample.uptimeMs;
    cloud.soilAdc =
        planter::validAdcRaw(sample.soilAdcRaw) ? sample.soilAdcRaw : -1;
    const int soilPercent = planter::observedSoilRelativePercent(sample);
    cloud.soilPercent = soilPercent >= 0 ? soilPercent : -1;
    cloud.waterAdc = waterUsable ? sample.waterAdcRaw : -1;
    const int waterPercent = planter::observedWaterRelativePercent(sample);
    cloud.waterPercent = waterPercent >= 0 ? waterPercent : -1;
    cloud.waterObservationPercent = waterPercent;
    cloud.lightAdc =
        planter::validAdcRaw(sample.lightAdcRaw) ? sample.lightAdcRaw : -1;
    cloud.lightPercent = preview.lightPercent >= 0 ? preview.lightPercent : -1;
    cloud.uvAdc = planter::validAdcRaw(sample.uvAdcRaw) ? sample.uvAdcRaw : -1;
    if (sample.mqAdcReadable && planter::validAdcRaw(sample.mqAdcRaw)) {
      cloud.mqAdc = sample.mqAdcRaw;
    }
    if (sample.mqAdcPinMillivolts >= 0) {
      cloud.mqPinMv = sample.mqAdcPinMillivolts;
    }
    if (planter::validTemperature(sample.temperatureC)) {
      cloud.temperatureC = sample.temperatureC;
      cloud.hasTemperature = true;
    }
    if (planter::validHumidity(sample.humidityPercent)) {
      cloud.humidityPercent =
          static_cast<int16_t>(roundf(sample.humidityPercent));
    }
    cloud.waterEmpty =
        waterUsable && sample.waterAdcRaw <= planter::kWaterEmptyRawReferenceAdc;
    cloud.waterLow = waterUsable && preview.waterLow == 1;
    cloud.pumpOn = control.pumpOn;
    cloud.pumpCooldownS = control.pumpCooldownRemainingS;
    cloud.pumpRuntimeLockout = control.pumpRuntimeLockout;
    cloud.lightOn = control.lightOn;
    snprintf(cloud.pumpReason, sizeof(cloud.pumpReason), "%s",
             control.pumpReason == nullptr ? "" : control.pumpReason);
    snprintf(cloud.lightReason, sizeof(cloud.lightReason), "%s",
             control.lightReason == nullptr ? "" : control.lightReason);
    cloud.capturedAtValid =
        planter::CloudLink::currentUtcIso(cloud.capturedAt,
                                          sizeof(cloud.capturedAt));
    cloudLink.enqueueSample(cloud);
  }
  updateLcd(sample.uptimeMs);
}

}  // namespace

void setup() {
  ArduinoGpio gpio;
  planter::configureRelaysInactive(gpio);
  relayStager.begin(millis(), relayGpio);
  relayController.begin(millis());
  Serial.begin(115200);
  delay(50);
  logBootReason();
  const esp_err_t watchdogInit =
      esp_task_wdt_init(planter::kWatchdogTimeoutSeconds, true);
  watchdogReady = (watchdogInit == ESP_OK || watchdogInit == ESP_ERR_INVALID_STATE) &&
                  (esp_task_wdt_status(nullptr) == ESP_OK ||
                   esp_task_wdt_add(nullptr) == ESP_OK);
  if (!watchdogReady) {
    relayController.inhibit(millis(), "watchdog_unavailable");
    syncRelayCommands();
  }
  Wire.begin(planter::kLegacyI2cSdaPin, planter::kLegacyI2cSclPin);
  lcd.init();
  lcd.backlight();
  lcdLine(0, "Smart Planter");
  lcdLine(1, "Relay cmd: OFF");
  if (planter::kDhtEnabled) climateSensor.begin();
  analogReadResolution(12);
  // ADC characterization estimates GPIO36 voltage from the averaged sample.
  // It does not establish the module's supply, divider ratio, or electrical safety.
  const bool adcWidthReady = adc1_config_width(ADC_WIDTH_BIT_12) == ESP_OK;
  mqAdcReady = adcWidthReady &&
               adc1_config_channel_atten(ADC1_CHANNEL_0, ADC_ATTEN_DB_12) == ESP_OK;
  uvAdcReady = adcWidthReady &&
               adc1_config_channel_atten(ADC1_CHANNEL_7, ADC_ATTEN_DB_12) == ESP_OK;
  if (mqAdcReady) {
    const esp_adc_cal_value_t mqCal = esp_adc_cal_characterize(
        ADC_UNIT_1, ADC_ATTEN_DB_12, ADC_WIDTH_BIT_12, 1100, &mqAdcCharacteristics);
    switch (mqCal) {
      case ESP_ADC_CAL_VAL_EFUSE_TP:
        mqAdcCalibration = planter::AdcCalibrationMethod::efuse_two_point;
        break;
      case ESP_ADC_CAL_VAL_EFUSE_VREF:
        mqAdcCalibration = planter::AdcCalibrationMethod::efuse_vref;
        break;
      case ESP_ADC_CAL_VAL_DEFAULT_VREF:
        mqAdcCalibration = planter::AdcCalibrationMethod::default_vref;
        break;
      default:
        mqAdcCalibration = planter::AdcCalibrationMethod::unavailable;
    }
  }
  if (uvAdcReady) {
    const esp_adc_cal_value_t uvCal = esp_adc_cal_characterize(
        ADC_UNIT_1, ADC_ATTEN_DB_12, ADC_WIDTH_BIT_12, 1100, &uvAdcCharacteristics);
    switch (uvCal) {
      case ESP_ADC_CAL_VAL_EFUSE_TP:
        uvAdcCalibration = planter::AdcCalibrationMethod::efuse_two_point;
        break;
      case ESP_ADC_CAL_VAL_EFUSE_VREF:
        uvAdcCalibration = planter::AdcCalibrationMethod::efuse_vref;
        break;
      case ESP_ADC_CAL_VAL_DEFAULT_VREF:
        uvAdcCalibration = planter::AdcCalibrationMethod::default_vref;
        break;
      default:
        uvAdcCalibration = planter::AdcCalibrationMethod::unavailable;
    }
  }
  for (int channel = 0; channel < 8; ++channel) {
    adc1_config_channel_atten(static_cast<adc1_channel_t>(channel),
                              ADC_ATTEN_DB_12);
  }
  logUvProbe();
  pinMode(extra_sensors::kWaterLevelPin, INPUT);
  pinMode(extra_sensors::kMq135DigitalPin, INPUT);
  ArduinoSoilGpio soilGpio;
  planter::configureSoilPower(soilGpio, planter::kSoilPowerWiringVerified);
  loadWifiCredentials();
  startLocalWifi();

  Serial.printf(
      "{\"type\":\"startup\",\"mode\":\"single\",\"version\":%u,"
      "\"relay_control\":\"automatic_requested\",\"soil_power\":\"%s\","
      "\"soil_adc\":\"%s\",\"dht\":\"%s\",\"water\":\"%s\",\"mq135\":\"%s\","
      "\"control_preview\":\"diagnostic_only\",\"watchdog\":\"%s\","
      "\"pump_polarity\":\"active_low_assumed\","
      "\"light_polarity\":\"active_high_assumed\","
      "\"light_automation\":\"%s\",\"annotations\":\"operator_reported\","
      "\"wifi\":\"%s\",\"cloud\":\"%s\"}\n",
      planter::kFirmwareVersion,
      planter::kSoilPowerWiringVerified ? "gpio25_switched_verified_by_operator"
                                       : "gpio25_input_unverified",
      planter::kSoilAdcReadEnabled ? "enabled_unverified" : "not_configured",
      planter::kDhtEnabled ? "DHT11_assumed" : "not_configured",
      "enabled_unverified", "enabled_unverified",
      watchdogReady ? "subscribed_unverified" : "unavailable",
      planter::kLightAutomationEnabled ? "enabled" : "inhibited",
      localWifiReady ? "local_ap_requested" : "local_ap_unavailable",
      cloudLink.enabled() && strlen(wifiSsid) > 0
          ? "https_configured"
          : "disabled");
}

void loop() {
  if (wifiSetupState == 2 && WiFi.status() != WL_CONNECTED) {
    // The link dropped after a boot/setup connection. Keep the AP available
    // and show an honest reconnecting state instead of a stale "connected".
    wifiSetupState = 1;
    wifiSetupStartedMs = millis();
    restartAtMs = 0;
    restartAfterWifiSetup = false;
  }
  if (wifiSetupState == 1) {
    if (WiFi.status() == WL_CONNECTED) {
      wifiSetupState = 2;
      if (restartAfterWifiSetup) {
        restartAtMs = millis() + 8000;
        Serial.println("{\"type\":\"wifi\",\"status\":\"setup_connected\","
                       "\"restart_in_ms\":8000}");
      }
    } else if (millis() - wifiSetupStartedMs > 30000) {
      wifiSetupState = 3;
      Serial.printf("{\"type\":\"wifi\",\"status\":\"setup_failed\","
                    "\"sta_status\":%d}\n", static_cast<int>(WiFi.status()));
    }
  }
  if (restartAtMs != 0 && millis() >= restartAtMs) {
    relayController.inhibit(millis(), "wifi_setup_restart");
    syncRelayCommands(true);
    delay(100);
    ESP.restart();
  }
  const uint32_t nowMs = millis();
  static uint32_t lastLcdUpdateMs = 0;
  if (nowMs - lastLcdUpdateMs >= 400) {
    lastLcdUpdateMs = nowMs;
    updateLcd(nowMs);
  }
  if (watchdogReady && esp_task_wdt_reset() != ESP_OK) {
    watchdogReady = false;
    relayController.inhibit(nowMs, "watchdog_unavailable");
  }
  relayController.tick(nowMs);
  syncRelayCommands();
  pollLocalWifi();
  if (localWifiReady) localHttpServer.handleClient();
  cloudLink.poll();
  planter::CloudCommand cloudCommand;
  while (cloudLink.takeCommand(cloudCommand)) {
    applyCloudCommand(cloudCommand);
  }
  readObservationCommands();
  if (!hasSample ||
      planter::sampleDue(nowMs, lastSampleMs, planter::kSampleIntervalMs)) {
    hasSample = true;
    lastSampleMs = nowMs;
    printSample(nowMs);
  }
  delay(10);
}
