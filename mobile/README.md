# Tunas Android

Aplikasi Flutter untuk memantau planter langsung dari access point ESP32.
Tidak ada cloud, akun, Supabase, atau mode online.

## Menjalankan

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

## Alur data

1. HP tersambung ke Wi-Fi **Moss** (`192.168.4.1`).
2. Aplikasi membuka TCP `192.168.4.1:3333` dan membaca JSON per baris.
3. Setiap sampel ditulis ke CSV lokal 25 kolom di penyimpanan aplikasi.
4. Tombol **Unduh CSV** di Pengaturan/Riwayat menyalin seluruh file harian ke
   `Downloads/Tunas/`.

Kontrol manual pompa/lampu dikirim lewat TCP yang sama:

```text
CTRL pump=on dur=5 id=12
CTRL pump=auto id=13
CTRL light=on id=14
CTRL light=auto id=15
```

Balasan `ack` menampilkan `ok`, `error`, sisa waktu pompa, dan status cooldown.

## CSV dan ML

Header dan arti kolom ada di [docs/dataset-contract.md](../docs/dataset-contract.md).
Kolom `emotion`/`confidence` adalah output model; buang sebelum training.

## Struktur penting

| Path | Isi |
|---|---|
| `lib/main.dart` | entry point local-only |
| `lib/src/local_moss_gate.dart` | gerbang wajib Wi-Fi Moss |
| `lib/src/local_wifi.dart` | stream TCP + parser sampel |
| `lib/src/dashboard.dart` | UI, riwayat, kontrol, ekspor CSV |
| `lib/src/journal_page.dart` | `HistoryCsv` 25 kolom |
| `android/app/src/main/kotlin/.../WifiProvisioning.kt` | izin + bind jaringan Android |

## Android

- Minimal Android 7; build ARM64.
- Izin Wi-Fi perangkat sekitar (`NEARBY_WIFI_DEVICES`) dan lokasi (≤ Android 12)
  diperlukan untuk menyambung ke AP tanpa internet.
- `network_security_config.xml` hanya mengizinkan HTTP lokal ke `192.168.4.1`.
- Notifikasi memakai `flutter_local_notifications` lokal, bukan Firebase.

## Batasan

- Sandi AP ditampilkan di LCD; jangan bagikan foto LCD.
- TCP lokal tidak memakai TLS; siapa pun yang tahu sandi AP dapat membaca data.
- Aplikasi tidak menyediakan angka simulasi. Nilai yang tidak terbaca
  ditampilkan kosong.
- Data internal hilang bila aplikasi di-uninstall; unduh CSV terlebih dahulu.
