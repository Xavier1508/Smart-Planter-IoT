# Tunas Smart Planter — local only

Firmware ESP32 dan aplikasi Android untuk memantau tanaman langsung melalui
Wi-Fi perangkat. Tidak ada cloud, akun, Supabase, router, token, atau TLS.

- **Firmware final:** v52 (`src/main.cpp`, `include/*.h`)
- **Aplikasi:** Flutter `0.9.4+52` (`mobile/`), jalur data lokal
- **Papan:** NodeMCU-32S / ESP32 DevKit, 4 MB flash
- **Data:** JSON per baris di TCP `192.168.4.1:3333`, sampel tiap 2 detik
- **CSV:** 25 kolom, ditulis aplikasi di HP (bukan oleh firmware)

> Pompa/relay masih dapat mengganggu jalur analog karena kabel catu/daya
> bersama. Firmware v52 menahan keputusan otomatis selama transient, tetapi
> perbaikan listrik tetap diperlukan. Perbaikan listrik: catu relay/pompa terpisah, star ground, flyback diode, dan bulk capacitor.

## 1. Cara pakai

1. Nyalakan planter. LCD menampilkan `WiFi:Moss` dan `Pass:<sandi>`.
2. Di HP, sambungkan ke Wi-Fi **Moss**. Jika Android menawarkan "Tetap
   terhubung" tanpa internet, pilih itu.
3. Buka aplikasi Tunas. Aplikasi memeriksa `192.168.4.1:3333` lalu membuka
   dashboard.
4. Data tersimpan otomatis ke CSV lokal di HP. Unduh lewat
   **Pengaturan → Unduh CSV** atau tombol di halaman Riwayat.

Sandi AP diatur di `include/local-wifi-secret.local.h` (diabaikan Git, 8–10
karakter). Jika file itu tidak ada atau nilainya tidak valid, firmware memakai
sandi acak 10 karakter dan menampilkannya di LCD. Jika sandi diubah, ubah juga
`apPassword` di `mobile/lib/src/wifi_provisioning.dart` agar tombol sambung
otomatis tetap cocok; sambungan manual lewat pengaturan Wi-Fi HP selalu bisa
memakai sandi di LCD.

## 2. Pin dan perangkat

| Fungsi | GPIO | Catatan |
|---|---:|---|
| DHT11 DATA | 4 | model diasumsikan DHT11 |
| Soil ADC | 34 | input-only; GPIO25 dibiarkan INPUT |
| LDR | 32 | 0 ADC = terang, 2100 ADC = gelap |
| UV OUT | 35 | ADC1 channel 7; sering 0 V, lihat catatan |
| Water level | 33 | ADC1 |
| MQ135 A0 | 36 | ADC1 channel 0 |
| MQ135 D0 | 14 | digital |
| Relay pompa | 13 | active-LOW (ON = LOW) |
| Relay lampu | 26 | active-HIGH (ON = HIGH) |
| LCD I2C SDA/SCL | 21/22 | alamat `0x27`, 16x2 |

Semua angka ADC adalah pembacaan listrik, bukan kalibrasi laboratorium.
`soil_percent`, `water_percent`, dan `light_percent` adalah skala relatif
perangkat. `uv_index` adalah proxy 0–14 dari ADC, bukan indeks UV terkalibrasi.
`mq_gas_index` adalah indeks relatif sesi, bukan ppm/CO₂.

## 3. Build dan flash

```powershell
# build
pio run -e nodemcu-32s

# upload (sesuaikan port bila bukan COM3)
pio run -e nodemcu-32s -t upload
```

Hasil build v52: RAM 52.440 B (16,0%), flash 825.005 B (62,9%). LDR: 0 ADC = 100% terang, 2100 ADC = 0% gelap. Binari ada di
`.pio/build/nodemcu-32s/firmware.bin`; salinan dan hash ada di
`analysis/firmware/v52-local/`.

Jangan memilih **Erase Flash** saat meng-upload kecuali memang ingin menghapus
penghitung brownout di NVS. Setelah boot, cek serial:

```json
{"type":"boot","firmware_version":52,...}
{"type":"wifi","status":"ap_ready","ssid":"Moss",...}
```

## 4. Endpoint lokal

| Alamat | Isi |
|---|---|
| `http://192.168.4.1/` | halaman status sederhana (browser) |
| `http://192.168.4.1/api/v1/telemetry` | satu sampel JSON terakhir |
| `http://192.168.4.1/api/v1/health` | versi, uptime, heap, client AP |
| `192.168.4.1:3333` | stream JSON per baris untuk aplikasi |

Perintah manual dari aplikasi memakai baris TCP:

```text
CTRL pump=on dur=5 id=12
CTRL pump=off id=13
CTRL pump=auto
CTRL light=on id=14
CTRL light=auto
```

Firmware membalas `{"type":"ack",...}`. Perintah manual tetap tunduk pada
watchdog, data basi, air rendah, dan batas waktu.

## 5. Pengaman v52

- Pompa otomatis baru menyala setelah **5 sampel kering berturut-turut** (~10 s).
- Lampu otomatis baru menyala setelah **3 sampel gelap berturut-turut** (~6 s).
- Setiap perubahan relay memulai **quiet window 3 detik**: nilai mentah tetap
  dicatat, tetapi tidak ada start pompa otomatis atau perubahan lampu otomatis.
- Dua relay tidak pernah switching bersamaan; jarak minimum **500 ms**.
- Output relay ditulis ulang setiap loop untuk memulihkan modul yang terlempar
  akibat transient.
- Batas keras pompa otomatis 5 menit, cooldown 30 detik, soak 10 menit setelah
  batas keras, pompa manual maksimum 30 detik.
- Watchdog 8 detik; LCD I2C memakai timeout 50 ms agar bus macet tidak
  menggantung loop.

## 6. Dataset CSV

Aplikasi menulis satu file per perangkat per hari dengan header tetap:

```text
timestamp_utc,device_id,firmware_version,uptime_ms,soil_adc,soil_percent,water_adc,water_percent,water_observation_percent,water_empty,water_low,light_adc,light_percent,temperature_c,humidity_percent,uv_adc,uv_index,mq_adc,mq_gas_index,pump_cmd,pump_reason,light_cmd,light_reason,emotion,confidence
```

- `timestamp_utc` = waktu HP saat sampel diterima; `uptime_ms` = waktu perangkat.
- `emotion` dan `confidence` adalah **output model**, bukan fitur. Untuk
  training, buang kedua kolom ini.
- Baris dengan `pump_cmd=1` atau `pump_reason=relay_settle` adalah jendela
  transient; saring jika ingin data analog bersih.
- Detail kontrak dan audit dataset ada di laporan lokal (tidak dipublikasikan).

Fitur model yang tersedia langsung dari CSV: `soil_percent`, `water_percent`,
`light_percent`, `temperature_c`, `humidity_percent`, `uv_index`,
`mq_gas_index`, ditambah turunan `soil*water`, tren tanah/air, dan penanda
pompa.

## 7. Struktur repo

```text
src/main.cpp              firmware v52 (logika utama, local only)
include/                  konfigurasi, telemetri, relay safety, sensor
platformio.ini            satu environment: nodemcu-32s
mobile/                   aplikasi Flutter (tanpa Supabase)
tools/ml/                 training model offline (Python)
docs/                     laporan dan dokumentasi lokal (tidak dipush)
analysis/                 bukti build/APK/log (gitignored)
release/                  firmware, APK, dan dataset
```

## 8. Batasan yang jujur

- UV terbaca di channel ADC, tetapi pada beberapa log nilainya 0 V. Itu bisa
  berarti ruangan gelap, kaca menghalangi UV, atau modul/kabel bermasalah.
  Firmware tidak bisa membuat modul 0 V menghasilkan data. Uji dengan
  `SENSOR_SCAN` saat pompa mati.
- DHT11 dan MQ135 bisa kehilangan satu pembacaan saat rel daya bergerak.
  Nilai yang gagal tetap dilaporkan sebagai `null`, bukan angka palsu.
- Interferensi pompa/relay tidak bisa dihilangkan dari firmware. Lihat
  Lihat laporan lokal bagian hardware-power untuk perbaikan kabel.
