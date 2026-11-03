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

- `dataset/tunas-moss-local-v4-20261103-182712.csv`
  - 2.207 baris, 25 kolom, 76,1 menit
  - SHA-256: `224261314A08603EAE4DF956DE33625DC187D081B83025A266C004BF81C15C68`
- `dataset/preview-50.csv`
  - 50 baris dari jendela ambient 10:57–11:06
  - Semua 25 kolom
  - Size: 7.920 bytes
  - SHA-256: `E874E7D2F1681600773986066B944DF8BD25387AFC1FCBEB458BA9B6C316E479`

## Catatan

- CSV penuh adalah arsip mentah; untuk ML buang `emotion`/`confidence` dan saring baris `pump_cmd=1` / `light_cmd=1`.
- Persentase tanah masih tersaturasi karena endpoint 1800; lihat laporan untuk analisis dan rekomendasi.
- UV hampir selalu nol pada dataset ini; jangan dipakai sebagai fitur tanpa perbaikan sensor.
- APK dan firmware ditandatangani/dibangun dari source pada repositori ini. Jangan bagikan sandi AP secara publik.
