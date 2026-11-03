# Firmware v52 — LDR scale calibrated to 2100

- File: `firmware.bin`
- Size: 831.584 bytes
- SHA-256: `4D9F338AC0AFF0E28C7352B81B803CC40FCCA84D39C85533F3313AB712E13B5A`
- Target: `nodemcu-32s`
- Version: **52**
- Build: `pio run -e nodemcu-32s`
- RAM: 52.440 B (16,0%)
- Flash: 825.005 B (62,9%)

## Perubahan dari v51

- Skala LDR sekarang memakai titik gelap **2100 ADC**, bukan 1800:
  `light_percent = clamp((2100 - light_adc) * 100 / 2100, 0, 100)`
- Arah tetap: **0 ADC = 100% terang**, **2100 ADC = 0% gelap**.
- Lampu otomatis ON di bawah 65% kecerahan, yaitu `light_adc > 735`.
- Metadata serial: `light_dark_adc: 2100`, `light_direction: adc_high_is_dark`.
- Semua pengaman relay/transient v51 tetap.

## Flash

```powershell
pio run -e nodemcu-32s -t upload
```

Jangan Erase Flash. Setelah boot cek `firmware_version:52`.
Setelah terhubung, cek kartu Cahaya: menutup LDR harus menaikkan ADC dan
menurunkan persentase; menyinari LDR harus menurunkan ADC dan menaikkan
persentase.

## Catatan

- Belum diuji fisik dalam sesi ini.
- Jika sensor Anda jenuh di angka lain, ubah satu baris
  `MOSS_LIGHT_RELATIVE_DARK_ADC` di `include/planter-calibration.local.h`.
- Perbaikan listrik (catu relay/pompa terpisah, star ground, flyback, bulk cap)
  tetap diperlukan untuk transient.
