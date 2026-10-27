# Moss · Smart Planter Android

Dashboard Flutter untuk pendamping tanaman Moss. Tahap ini adalah **prototipe antarmuka**, bukan sistem IoT yang sudah terhubung.

## Yang tersedia

- Tampilan Android, karakter 3D sederhana, dan tiga kondisi **simulasi**.
- Gerakan angin pelan serta respons terhadap sentuhan, geseran jari, dan pointer; opsi sistem untuk mengurangi animasi dihormati.
- Mode tanpa simulasi menampilkan nilai kosong, bukan angka sensor palsu.
- Informasi sensor air dan MQ135 disiapkan sebagai belum terpasang.
- Kontrol pompa dan lampu belum aktif; riwayat tidak direkayasa.
- Antarmuka sudah dapat menerima aliran data sensor saat sumber data disediakan;
  pembacaan tidak valid, kedaluwarsa, atau terputus tidak ditampilkan sebagai
  data aktif. Integrasi sumber cloud dan ESP32 masih harus dibuat.

## Belum tersedia

Koneksi Supabase, Firebase push notification, pembacaan ESP32, kontrol aktuator, penyimpanan offline, dan model machine learning belum diimplementasikan. Jalur Firebase App Distribution disiapkan khusus untuk build tester, tetapi belum terhubung ke project Firebase atau diuji secara menyeluruh. Ekspresi demo menggunakan aturan sederhana, bukan prediksi emosi ilmiah. Model 3D saat ini adalah placeholder geometris orisinal dan belum diuji di berbagai perangkat Android.

## Jalankan

Memerlukan Flutter 3.47 atau lebih baru serta Android SDK yang siap digunakan:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Flutter GPU diaktifkan di manifest Android untuk renderer 3D. Uji kinerja dan kompatibilitas pada perangkat fisik sebelum presentasi. Nilai dalam mode simulasi tidak digunakan sebagai data pelatihan.

## Distribusi privat (belum aktif)

Package Android: `io.github.xavier1508.smart_planter`. Varian default `production`
tidak berisi SDK self-update App Distribution dan tidak memerlukan konfigurasi
Firebase. Varian `beta` dipakai **hanya** untuk distribusi privat; jangan
unggah varian itu ke Google Play. SDK App Distribution Android masih berstatus
beta. Update APK tetap memerlukan persetujuan pemasangan dari pengguna.

Sebelum distribusi dapat digunakan:

1. Periksa kuota dan anggaran [GitHub Actions](https://docs.github.com/billing/managing-billing-for-github-actions/about-billing-for-github-actions).
   Repo privat memakai jatah menit gratis sesuai paket akun dan pemakaian
   berlebih dapat ditagihkan. Atur anggaran sesuai kebutuhan Anda dan pilih
   penghentian saat batas tercapai sebelum mengaktifkan workflow. Pemeriksaan
   dan distribusi dinonaktifkan secara default sampai variable
   `MOSS_CI_ENABLED` diatur ke `true`.
2. Daftarkan package Android di Firebase, aktifkan App Distribution dan
   [Firebase App Testers API](https://console.cloud.google.com/apis/library/firebaseapptesters.googleapis.com).
   Buat grup tester dan tambahkan email penguji. Jika tester perlu undangan,
   pengguna harus menerimanya.
3. Siapkan satu keystore release yang tetap dan simpan cadangannya dengan aman.
   Jangan commit keystore, password, token, atau service-account key. Kehilangan
   keystore berarti APK baru tidak dapat memperbarui APK yang lama secara langsung.
   Password yang disimpan dengan Windows DPAPI terikat pada akun Windows yang
   membuatnya; file `.dpapi` saja bukan cadangan yang dapat dipindahkan ke PC lain.
4. Siapkan service account khusus dengan peran Firebase App Distribution Admin.
   Peran ini dapat mengelola rilis dan tester App Distribution dalam project,
   bukan hanya satu aplikasi. Kunci JSON-nya adalah kredensial jangka panjang:
   simpan hanya sebagai GitHub repository secret, jangan commit atau bagikan,
   dan cabut serta ganti jika diduga terpapar. Tinjau aksesnya secara berkala.
5. Di **GitHub → Settings → Secrets and variables → Actions**, buat secrets:
   `FIREBASE_ANDROID_CONFIG` (isi `google-services.json`), `FIREBASE_SERVICE_ACCOUNT`,
   `MOSS_KEYSTORE_BASE64`, `MOSS_KEYSTORE_PASSWORD`, `MOSS_KEY_ALIAS`, dan
   `MOSS_KEY_PASSWORD`. Jangan kirim nilainya ke chat.
6. Buat repository variables `FIREBASE_APP_ID`, `FIREBASE_TESTER_GROUP` (alias
   grup). Setelah semuanya siap dan biaya diperiksa, set `MOSS_CI_ENABLED` dan
   `FIREBASE_DISTRIBUTION_ENABLED` ke `true`.

Workflow menjalankan format, analisis, dan tes; distribusi hanya berjalan untuk
`main` setelah tes sukses dan variabel aktivasi diisi. Setiap run baru memakai
nomor run GitHub sebagai `versionCode`. Jangan memakai **Re-run jobs** untuk
mendistribusikan ulang run lama; jalankan **Run workflow** atau push commit baru
agar nomor versi bertambah. Build tester mencari update saat aplikasi dibuka;
tidak ada instalasi diam-diam, dan App Distribution bukan notifikasi sensor.

Untuk build tester lokal, file `android/app/google-services.json` yang sesuai
harus disediakan secara lokal dan diabaikan Git. Build release juga memerlukan
environment variables `MOSS_KEYSTORE_FILE`, `MOSS_KEYSTORE_PASSWORD`,
`MOSS_KEY_ALIAS`, dan `MOSS_KEY_PASSWORD`; tidak ada fallback ke debug signing.
