# Moss · Smart Planter Android

Dashboard Flutter untuk pendamping tanaman Moss. Tahap ini adalah **prototipe antarmuka**, bukan sistem IoT yang sudah terhubung.

## Yang tersedia

- Tampilan Android, karakter 3D sederhana, dan tiga kondisi **simulasi**.
- Gerakan angin pelan serta respons terhadap sentuhan, geseran jari, dan pointer; opsi sistem untuk mengurangi animasi dihormati.
- Mode tanpa simulasi menampilkan nilai kosong, bukan angka sensor palsu.
- Informasi sensor air dan MQ135 disiapkan sebagai belum terpasang.
- Kontrol pompa dan lampu belum aktif; riwayat tidak direkayasa.

## Belum tersedia

Koneksi Supabase, Firebase App Distribution dan push notification, pembacaan ESP32, kontrol aktuator, penyimpanan offline, dan model machine learning belum diimplementasikan. Workflow GitHub saat ini hanya menjalankan pemeriksaan kode dan tes, belum mendistribusikan APK. Ekspresi demo menggunakan aturan sederhana, bukan prediksi emosi ilmiah. Model 3D saat ini adalah placeholder geometris orisinal dan belum diuji di berbagai perangkat Android.

## Jalankan

Memerlukan Flutter 3.47 atau lebih baru serta Android SDK yang siap digunakan:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Flutter GPU diaktifkan di manifest Android untuk renderer 3D. Uji kinerja dan kompatibilitas pada perangkat fisik sebelum presentasi. Nilai dalam mode simulasi tidak digunakan sebagai data pelatihan.
