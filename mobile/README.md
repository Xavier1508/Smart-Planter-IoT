# Moss · Smart Planter Android

Dashboard Flutter untuk pendamping tanaman Moss. Tahap ini adalah **prototipe antarmuka**, bukan sistem IoT yang sudah terhubung.

## Yang tersedia

- Tampilan Android, karakter 3D sederhana, dan tiga kondisi **simulasi**.
- Ikon peluncur Moss dengan versi adaptif untuk Android; desain sumbernya ada di
  [aset identitas visual](assets/branding/moss-icon.svg).
- Karakter merespons arah jari dan sentuhan dengan kedipan, gerakan, dan efek visual; opsi sistem untuk mengurangi animasi dihormati.
- Tema aplikasi dapat mengikuti sistem atau dipilih terang/gelap. Pengaturan
  tampilan tersimpan secara lokal di Android.
- Langit, matahari, bulan, bintang, dan warna pencahayaan berubah mengikuti jam
  lokal ponsel. Suasana waktu atau jam tertentu juga dapat dipilih sendiri di
  Pengaturan; efek ini bersifat visual dan bukan pembacaan sensor cahaya.
- Mode tanpa simulasi menampilkan nilai kosong, bukan angka sensor palsu.
- Informasi sensor air dan MQ135 disiapkan sebagai belum terpasang.
- Kontrol pompa dan lampu belum aktif; riwayat tidak direkayasa.
- Halaman riwayat menampilkan grafik dan aktivitas **contoh** hanya saat mode
  simulasi aktif; data contoh tidak disimpan sebagai riwayat sensor.
- Halaman perangkat menyediakan saklar **simulasi lokal**. Saklar tersebut tidak
  mengirim perintah dan tidak dapat mengubah keadaan pompa atau lampu nyata.
- Pengaturan menampilkan versi/build Android dan membedakan pratinjau lokal dari
  varian beta yang memeriksa pembaruan melalui App Distribution.
- Fondasi Supabase mencakup tabel perangkat dan pembacaan privat, masuk akun,
  serta pembaca Realtime di aplikasi. Pembacaan tidak valid, kedaluwarsa, atau
  terputus tidak ditampilkan sebagai data aktif.

## Belum tersedia

Pasangan perangkat, pengiriman data ESP32 ke Supabase, Firebase push notification, kontrol aktuator, penyimpanan offline, dan model machine learning belum diimplementasikan. Tabel cloud masih kosong dan alur masuk/Realtime belum diuji menyeluruh pada perangkat. Jalur Firebase App Distribution belum diuji secara menyeluruh. Ekspresi demo menggunakan aturan sederhana, bukan prediksi emosi ilmiah. Model 3D saat ini adalah placeholder geometris orisinal dan belum diuji di berbagai perangkat Android.

## Jalankan

Memerlukan Flutter 3.47 atau lebih baru serta Android SDK yang siap digunakan:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Flutter GPU diaktifkan di manifest Android untuk renderer 3D. Uji kinerja dan kompatibilitas pada perangkat fisik sebelum presentasi. Nilai dalam mode simulasi tidak digunakan sebagai data pelatihan.

APK debug lokal hanya untuk melihat pratinjau. APK tersebut tidak menyertakan
pemeriksaan pembaruan Firebase dan menggunakan package terpisah
`io.github.xavier1508.smart_planter.preview`, sehingga tidak menggantikan beta
release. Jika ditandatangani dengan kunci debug sementara, build debug berikutnya
dengan kunci berbeda juga tidak dapat memperbarui pratinjau yang lama secara
langsung. Menghapus aplikasi dapat menghapus datanya; jangan hapus aplikasi yang
ada tanpa memastikan data dan konsekuensinya terlebih dahulu.

## Cloud dan keamanan data

Migrasi `supabase/migrations/20261027164712_planter_foundation.sql` membuat
`planter_devices` dan `planter_readings` tanpa data contoh. RLS hanya mengizinkan
akun yang masuk membaca perangkat dan pembacaannya sendiri. Belum ada izin tulis
untuk aplikasi atau perangkat: metode pairing dan kredensial khusus ESP32 harus
dirancang sebelum pengiriman diaktifkan. Jangan memasukkan service-role key
atau password Wi-Fi ke dalam aplikasi atau repositori.

Aplikasi memerlukan **publishable key** Supabase melalui compile-time define
`SUPABASE_PUBLISHABLE_KEY` untuk menampilkan opsi akun dan mengakses cloud.
Di GitHub Actions define ini berasal dari repository variable dengan nama yang
sama. Kunci publishable memang ikut berada di APK dan bukan pengganti RLS;
**jangan gunakan secret/service-role key**. Jika variable belum diisi, aplikasi
tetap berjalan dalam mode simulasi/offline. Sesi akun saat ini hanya disimpan
dalam memori dan pengguna perlu masuk kembali setelah aplikasi ditutup.

Realtime sudah disiapkan untuk `planter_readings`, tetapi pengujian dengan
akun pengguna, perangkat fisik, dan data asli masih diperlukan. Sebelum mulai
merekam data otomatis, tentukan interval kirim dan retensi agar kuota gratis
database tidak habis secara tidak sengaja.

### Rancangan lanjutan (belum aktif)

- Pairing perlu membuktikan akses fisik ke perangkat dan dilakukan oleh akun
  yang sudah masuk. Kode pairing harus sekali pakai, berumur pendek, serta
  tidak disimpan dalam source code atau Git.
- Setiap ESP32 memerlukan kredensial sendiri yang dapat dicabut; backend harus
  membatasi penulisan pada perangkat itu, memvalidasi nilai, dan membatasi
  frekuensi permintaan. Kunci service-role tidak digunakan di ESP32 maupun APK.
- Telemetri dikirim melalui TLS ke layanan cloud, dengan timestamp penerimaan
  dari server. Gangguan jaringan tidak boleh menghentikan otomasi lokal atau
  mengubah nilai simulasi menjadi data sensor.
- Interval, batas penyimpanan, retensi otomatis, dan cara provisioning serta
  penyimpanan kredensial pada ESP32 masih harus ditentukan dan diuji. Jangan
  mengaktifkan ingestion sebelum mekanisme tersebut siap dan sesuai kuota.

## Distribusi beta privat

Build beta pertama telah lulus pemeriksaan Flutter dan dikirim ke grup penguji.
Pemasangan dan pembaruan antarversi pada ponsel masih perlu diuji; status
Firebase App Testers API juga belum diverifikasi. Build pertama berjalan dalam
mode demo/offline karena publishable key Supabase belum dikonfigurasi.

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
