# Tunas Smart Indoor Planter — Release

Folder ini memuat artefak siap pakai untuk prototipe lokal.

## Firmware v52

- Path: `firmware/v52-local/firmware.bin`
- Size: 831.584 bytes
- SHA-256: `4D9F338AC0AFF0E28C7352B81B803CC40FCCA84D39C85533F3313AB712E13B5A`
- Target: ESP32 NodeMCU-32S (4 MB)
- Flash: `pio run -e nodemcu-32s -t upload`
- Firmware v52 memakai skala LDR: **0 ADC = 100% terang, 2100 ADC = 0% gelap**.

## APK Android 0.9.4+52

- Path: `apk/tunas-0.9.4-52.apk`
- Size: 58.938.082 bytes
- SHA-256: `11DD5F3731F3E2296C5A94A5194F2243D978F2A757D21ACFF6DFD5392673AA24`
- Package: `io.github.xavier1508.smart_planter`
- versionCode: 52
- Signed: `moss-release.jks` (cert SHA-256 `8028ffc5205f70fdd7274115f99de4c0145687874f1b11f8d3520233f2778a74`)

## Dataset

- `dataset/tunas-moss-local-v4-20261103-200134.csv`
  - 3.611 baris, 25 kolom, rentang waktu 170,5 menit
  - 3.516 baris lengkap; 94 nilai suhu dan 95 nilai kelembapan kosong
  - Median interval 2,037 detik; 6 jeda lebih dari 10 detik dan 1 reset uptime
  - Size: 536.007 bytes
  - SHA-256: `3DD08C66CC5F0634B3F09FA025A7934B7C9A023B83EE2E672B192DDD875FD4B0`

## Catatan

- CSV penuh adalah arsip mentah; untuk ML buang `emotion`/`confidence` dan saring baris `pump_cmd=1` / `light_cmd=1`.
- Persentase tanah mencapai 100% pada 3.005 dari 3.611 baris; skala ini
  menggunakan endpoint relatif 1800 ADC dan belum divalidasi terhadap kadar air tanah.
- `uv_index` adalah proxy, bukan indeks UV terkalibrasi; 2.576 dari 3.611
  nilai adalah nol dan 3.430 di bawah 1. Verifikasi sensor sebelum analisis lanjut.
- Nilai `pump_cmd` dan `light_cmd` adalah perintah, bukan konfirmasi kontak
  relay atau operasi fisik aktuator. Penyebab jeda pencatatan belum dipastikan.
- APK dan firmware ditandatangani/dibangun dari source pada repositori ini. Jangan bagikan sandi AP secara publik.
