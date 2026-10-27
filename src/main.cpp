/**
 * SMART INDOOR PLANTER - ESP32
 * 
 * Notes (IDE)
 * Dikembangkan dan dikompilasi menggunakan Visual Studio Code (VS Code) 
 * dengan ekstensi PlatformIO.
 * Fitur Utama:
 * 1. Otomasi Pompa Air (berdasarkan sensor kelembapan tanah dengan Hysteresis)
 * 2. Otomasi Grow Light (berdasarkan sensor LDR dengan Hysteresis)
 * 3. Monitoring Lokal via LCD 16x2 (I2C)
 * 4. Telemetri Real-Time ke Backend Node.js via HTTP POST
 */

#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <DHT.h>
#include <WiFi.h>
#include <HTTPClient.h>

// ================= KONFIGURASI JARINGAN =================
const char* ssid = "";  // Placeholder: configure securely before cloud integration.
const char* password = "";  // Placeholder: configure securely before cloud integration.
const char* serverUrl = "";  // Placeholder: configure securely before cloud integration.

// ================= DEFINISI PIN =================
// Sensor
#define DHT_PIN         4
#define DHT_TYPE        DHT11
#define SOIL_PIN        34       // ADC1: Soil Moisture
#define UV_PIN          35       // ADC1: Sensor UV
#define LDR_PIN         32       // ADC1: Modul LDR
#define SOIL_PWR        25       // VCC Soil Moisture (Hanya aktif saat membaca)

// Aktuator & I2C
#define RELAY_LIGHT_PIN 26       // Relay Grow Light
#define RELAY_PUMP_PIN  13       // Relay Pompa Air
#define I2C_SDA         21
#define I2C_SCL         22
#define LCD_ADDR        0x27

// ================= KONFIGURASI RELAY =================
// Sesuaikan dengan modul relay (true = Active-Low, false = Active-High)
#define LIGHT_ACTIVE_LOW  false
#define LIGHT_LEVEL_ON   (LIGHT_ACTIVE_LOW ? LOW  : HIGH)
#define LIGHT_LEVEL_OFF  (LIGHT_ACTIVE_LOW ? HIGH : LOW)

#define PUMP_ACTIVE_LOW   true
#define PUMP_LEVEL_ON    (PUMP_ACTIVE_LOW ? LOW  : HIGH)
#define PUMP_LEVEL_OFF   (PUMP_ACTIVE_LOW ? HIGH : LOW)

// ================= KALIBRASI & AMBANG BATAS =================
#define SOIL_DRY        0        // Nilai ADC saat di udara terbuka
#define SOIL_WET        2450     // Nilai ADC saat tercelup air sepenuhnya

#define BATAS_POMPA_ON   30      // Pompa ON jika tanah < 30%
#define BATAS_POMPA_OFF  70      // Pompa OFF jika tanah > 70%

#define BATAS_LDR_ON     60      // Lampu ON jika cahaya < 60%
#define BATAS_LDR_OFF    80      // Lampu OFF jika cahaya > 80%

// ================= INISIALISASI GLOBAL =================
DHT dht(DHT_PIN, DHT_TYPE);
LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);

bool pompaNyala = false;
bool lampuNyala = false;

// ================= FUNGSI BANTUAN =================

// Menampilkan teks pada baris LCD secara rata kiri
void tampilBaris(uint8_t baris, const char *teks) {
  char buf[17];
  snprintf(buf, sizeof(buf), "%-16s", teks);
  lcd.setCursor(0, baris);
  lcd.print(buf);
}

// Membaca dan mengonversi nilai sensor tanah ke persentase (0-100%)
int bacaTanahPersen() {
  digitalWrite(SOIL_PWR, HIGH);     
  delay(300);                       

  long total = 0;
  for (int i = 0; i < 10; i++) {    
    total += analogRead(SOIL_PIN);
    delay(10);
  }
  digitalWrite(SOIL_PWR, LOW);      

  int raw    = total / 10;
  int persen = map(raw, SOIL_DRY, SOIL_WET, 0, 100);
  return constrain(persen, 0, 100);
}

// Menerjemahkan persentase tanah ke status string
const char *statusTanah(int persen) {
  if (persen < BATAS_POMPA_ON)   return "KERING";
  if (persen <= BATAS_POMPA_OFF) return "LEMBAB";
  return "BASAH";
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(1000);

  // 1. Setup Relay (Pastikan kondisi awal MATI)
  digitalWrite(RELAY_LIGHT_PIN, LIGHT_LEVEL_OFF);
  pinMode(RELAY_LIGHT_PIN, OUTPUT);
  digitalWrite(RELAY_LIGHT_PIN, LIGHT_LEVEL_OFF);

  digitalWrite(RELAY_PUMP_PIN, PUMP_LEVEL_OFF);
  pinMode(RELAY_PUMP_PIN, OUTPUT);
  digitalWrite(RELAY_PUMP_PIN, PUMP_LEVEL_OFF);

  // 2. Setup Sensor Power
  pinMode(SOIL_PWR, OUTPUT);
  digitalWrite(SOIL_PWR, LOW);      

  // 3. Setup Komunikasi & LCD
  Wire.begin(I2C_SDA, I2C_SCL);
  dht.begin();
  lcd.init();
  lcd.backlight();
  
  tampilBaris(0, "Smart Planter");
  tampilBaris(1, "Connecting WiFi");

  // 4. Koneksi Wi-Fi opsional. Konfigurasi dinamis akan ditambahkan nanti.
  if (ssid[0] == '\0') {
    Serial.println("Wi-Fi belum dikonfigurasi; mode lokal aktif.");
    tampilBaris(1, "WiFi not set");
  } else {
    WiFi.begin(ssid, password);
    const unsigned long startWifi = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startWifi < 15000UL) {
      delay(500);
      Serial.print(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nWi-Fi terhubung.");
      tampilBaris(1, "WiFi Connected");
    } else {
      Serial.println("\nWi-Fi belum terhubung; mode lokal aktif.");
      tampilBaris(1, "WiFi offline");
    }
  }
  delay(2000);
  lcd.clear();
  Serial.println("=== SISTEM OTOMASI SMART INDOOR PLANTER AKTIF ===");
}

// ================= LOOP UTAMA =================
void loop() {
  // 1. PEMBACAAN SENSOR
  float suhu       = dht.readTemperature();
  float kelembapan = dht.readHumidity();
  int   tanah      = bacaTanahPersen();
  
  int   ldrRaw     = analogRead(LDR_PIN);
  int   ldrPersen  = constrain(map(ldrRaw, 4095, 0, 0, 100), 0, 100);
  
  int   uvRaw      = analogRead(UV_PIN);
  float uvIndex    = ((uvRaw * 3.3) / 4095.0) / 0.1; 

  // 2. LOGIKA KONTROL POMPA (Hysteresis)
  if (tanah < BATAS_POMPA_ON) {
    pompaNyala = true;
  } else if (tanah > BATAS_POMPA_OFF) {
    pompaNyala = false;
  }
  digitalWrite(RELAY_PUMP_PIN, pompaNyala ? PUMP_LEVEL_ON : PUMP_LEVEL_OFF);

  // 3. LOGIKA KONTROL CAHAYA (Hysteresis)
  if (ldrPersen < BATAS_LDR_ON) {
    lampuNyala = true;
  } else if (ldrPersen > BATAS_LDR_OFF) {
    lampuNyala = false;
  }
  digitalWrite(RELAY_LIGHT_PIN, lampuNyala ? LIGHT_LEVEL_ON : LIGHT_LEVEL_OFF);

  // 4. TELEMETRI HTTP POST
  if (WiFi.status() == WL_CONNECTED && serverUrl[0] != '\0') {
    HTTPClient http;
    http.begin(serverUrl);
    http.addHeader("Content-Type", "application/json");

    // Pembentukan payload JSON
    String jsonPayload = "{";
    jsonPayload += "\"deviceId\":\"esp32-planter-01\",";
    jsonPayload += "\"temperature\":" + String(isnan(suhu) ? 0.0 : suhu) + ",";
    jsonPayload += "\"humidity\":" + String(isnan(kelembapan) ? 0.0 : kelembapan) + ",";
    jsonPayload += "\"soilMoisture\":" + String(tanah) + ",";
    jsonPayload += "\"soilStatus\":\"" + String(statusTanah(tanah)) + "\",";
    jsonPayload += "\"ldrLight\":" + String(ldrPersen) + ",";
    jsonPayload += "\"uvIndex\":" + String(uvIndex) + ",";
    jsonPayload += "\"pumpOn\":" + String(pompaNyala ? "true" : "false") + ",";
    jsonPayload += "\"growlightOn\":" + String(lampuNyala ? "true" : "false");
    jsonPayload += "}";

    int httpResponseCode = http.POST(jsonPayload);
    if (httpResponseCode > 0) {
      Serial.printf("Telemetri terkirim! HTTP Response: %d\n", httpResponseCode);
    } else {
      Serial.printf("Gagal mengirim data: %s\n", http.errorToString(httpResponseCode).c_str());
    }
    http.end();
  } else {
    Serial.println("Wi-Fi terputus, mencoba menghubungkan ulang...");
    WiFi.reconnect();
  }

  // 5. PEMBARUAN LCD (Bergantian setiap iterasi loop)
  static bool halamanSatu = true;
  char isiLcd[17];

  if (halamanSatu) {
    if (isnan(suhu) || isnan(kelembapan)) {
      tampilBaris(0, "DHT Error");
    } else {
      snprintf(isiLcd, sizeof(isiLcd), "T:%.1f%cC H:%.0f%%", suhu, 223, kelembapan);
      tampilBaris(0, isiLcd);
    }
    snprintf(isiLcd, sizeof(isiLcd), "Soil:%2d%% Pmp:%s", tanah, pompaNyala ? "ON" : "OFF");
    tampilBaris(1, isiLcd);
  } else {
    snprintf(isiLcd, sizeof(isiLcd), "UV:%.2f LDR:%d%%", uvIndex, ldrPersen);
    tampilBaris(0, isiLcd);
    snprintf(isiLcd, sizeof(isiLcd), "GrowLight : %s", lampuNyala ? "ON" : "OFF");
    tampilBaris(1, isiLcd);
  }
  halamanSatu = !halamanSatu;

  // 6. OUTPUT SERIAL MONITOR
  Serial.printf("Soil: %d%% (%s) -> Pompa: %s | LDR: %d%%, UV: %.2f -> Lampu: %s | T: %.1fC, H: %.0f%%\n",
                tanah, statusTanah(tanah), pompaNyala ? "ON" : "OFF",
                ldrPersen, uvIndex, lampuNyala ? "ON" : "OFF",
                isnan(suhu) ? 0.0 : suhu, isnan(kelembapan) ? 0.0 : kelembapan);

  delay(2000);
}
