# Moss · Smart Planter Android

Dashboard Flutter Moss menyiapkan pemantauan ESP32 melalui Wi-Fi lokal; koneksi
dan tampilan pada ponsel fisik masih perlu diuji.

## Wi-Fi lokal ESP32 (belum diuji menyeluruh pada perangkat fisik)

Sumber aplikasi dan firmware disiapkan untuk pemantauan langsung tanpa cloud.
ESP32 membuat Wi-Fi WPA2 sendiri, bukan bergabung ke router; jaringan itu tidak
menyediakan internet. Setelah rangkaian diperiksa dan pengguna meng-upload
firmware sendiri, LCD bergiliran menampilkan nama `Moss-xxxx` dan sandi acak
yang berubah setiap boot. Pada ponsel, pilih Wi-Fi tersebut dan jika diminta
pilih tetap terhubung tanpa internet. Aplikasi mencoba terhubung secara otomatis;
tombol hubung ulang tersedia di Pengaturan. Jangan membagikan
sandi atau foto LCD. Tidak ada password router
yang diminta atau disimpan. Firmware v13 menampilkan sandi 10 karakter selama
sekitar 60 detik saat boot dan 30 detik pada setiap siklus; v12 masih memakai
halaman sekitar lima detik setiap 25 detik. Perubahan LCD v13 memerlukan upload
firmware terpisah oleh pengguna.

Protokol lokal hanya baca: ESP32 mengirim JSON satu baris setiap sampel melalui
TCP `192.168.4.1:3333`, maksimal satu klien, tanpa endpoint perintah atau
pengiriman cloud. Data dilindungi oleh sandi WPA2 access point, tetapi TCP tidak
menggunakan TLS atau autentikasi identitas perangkat tambahan; siapa pun yang
memiliki sandi dapat membaca telemetri. Setelah 20 detik tanpa sampel baru,
aplikasi membersihkan data live dan mencoba menyambung kembali otomatis hingga
pengguna memilih putus. Aplikasi tidak menyediakan mode simulasi atau angka
contoh. Waktu penerimaan di
ponsel tidak diklaim sebagai waktu pengukuran ESP32. Konektivitas radio, LCD,
dan tampilan pada ponsel fisik belum dibuktikan.

Persen tanah dan air adalah perkiraan relatif yang menggunakan rata-rata dari
cuplikan pengguna, bukan kadar air tanah atau volume tangki terukur. Cahaya
memakai skala relatif yang belum diverifikasi. UV dan MQ dapat ditampilkan sebagai persentase
rentang ADC, bukan indeks UV, CO₂, atau kualitas udara. Firmware lama memakai
ADC2 untuk MQ, yang dapat berbenturan dengan Wi-Fi; v19 dipetakan ke ADC1/SVP
sesuai laporan pengguna dan belum diuji fisik. Suhu tetap dalam °C dan data
hilang tetap kosong. Lihat `readme.md` di root untuk aturan LDR, status interlock, dan
batas keselamatan. Perintah relay yang ditampilkan bukan status beban fisik.

## Yang tersedia

- Tampilan Android dan karakter 3D bergaya dengan material yang merespons cahaya.
  Perubahan visual sejak 0.3.2 masih perlu diuji
  pada perangkat fisik; karakter tetap model geometris, bukan fotorealistis.
- Ikon peluncur Moss dengan versi adaptif untuk Android; desain sumbernya ada di
  [aset identitas visual](assets/branding/moss-icon.svg).
- Karakter mengikuti posisi jari di dalam layar aplikasi; hanya sentuhan yang
  mengenai geometri karakter atau pot memicu reaksi. Kepala dan tangan bergerak
  secara terpisah, dengan beberapa pose sentuhan; opsi sistem untuk mengurangi
  animasi dihormati. Fitur ini masih perlu diuji pada renderer dan ponsel fisik.
- Tema aplikasi dapat mengikuti sistem atau dipilih terang/gelap. Pengaturan
  tampilan tersimpan secara lokal di Android.
- Langit, matahari, bulan, bintang, dan warna pencahayaan berubah mengikuti jam
  lokal ponsel. Geser kartu Moss atau gunakan panah untuk memilih suasana;
  Pengaturan menyediakan waktu otomatis dan jam pilihan. Pada malam hari ada
  komet sesekali. Cahaya 3D dan satu shadow map mengikuti suasana; efek ini
  bersifat visual dan bukan pembacaan sensor cahaya. Kualitas bayangan dan
  performa belum diuji pada renderer OPPO.
- Nilai yang tidak tersedia ditampilkan kosong, bukan angka sensor palsu.
- Impor satu sampel serial di **Pengaturan → Tempel data serial** dapat
  menampilkan tanah, DHT, cahaya, UV, ADC air, serta ADC/digital MQ pada
  dashboard sebagai **snapshot**, bukan data live. Data yang ditempel disimpan
  hanya dalam memori selama aplikasi terbuka; cloud belum menerima data ESP32.
- Bila snapshot versi 7 memuat `control_preview`, halaman **Perangkat** dapat
  menampilkan hasil perhitungan ambang 50/60/20% sebagai pratinjau serial.
  Itu bukan status kontak, perintah relay, notifikasi push, atau data live.
  Air tetap tanpa persentase atau peringatan jika titik acuannya belum ada.
- Firmware lokal versi 8 meniadakan pratinjau tersebut dalam sampel yang memuat
  `pump_cmd`/`growlight_cmd` agar perhitungan hipotetis tidak disalahartikan
  sebagai perintah. Pada tahap versi 8, aplikasi belum menampilkan perintah
  tersebut atau menerima pembacaan otomatis. Sumber versi 12 menyiapkan jalur
  Wi-Fi lokal dan tampilan perintah yang tetap dibedakan dari kontak fisik.
- Kartu **Sensor udara MQ135** menampilkan **indeks gas relatif 0–100**
  terhadap baseline sesi, status kualitas sinyal, ADC terbaru, rata-rata
  hingga 12 sampel, arah sinyal, dan perkiraan tegangan pin. Rata-rata dan
  indeks dibersihkan saat data putus, gagal baca, atau mencapai rel. Nilai ini
  **bukan CO₂, ppm, atau indeks mutu udara terkalibrasi**; kalibrasi absolut
  MQ135 memerlukan R0, Vc, VRL dan RL yang terverifikasi.
- Aplikasi tidak menyediakan saklar pompa atau lampu; firmware dapat meminta
  relay ON sesuai aturan dan interlock. Riwayat tidak direkayasa.
- Halaman riwayat kosong sampai penyimpanan riwayat sensor diterapkan.
- Halaman perangkat menampilkan perintah relay firmware tanpa saklar tiruan;
  aplikasi tidak dapat mengubah keadaan pompa atau lampu nyata.
- Pengaturan menampilkan versi/build Android dan membedakan pratinjau lokal dari
  varian beta yang memeriksa pembaruan melalui App Distribution.
- Fondasi Supabase mencakup tabel perangkat dan pembacaan privat, masuk akun,
  serta pembaca Realtime di aplikasi. Pembacaan tidak valid, kedaluwarsa, atau
  terputus tidak ditampilkan sebagai data aktif.
- Dukungan lokal untuk kolom `uv_index` sudah disiapkan pada pembaca dan
  dashboard. Nilai UV yang diterima diberi label **perkiraan, belum diverifikasi**;
  pemeriksaan rentang tidak membuktikan kalibrasi. Dekoder dan model diuji
  secara lokal dengan data contoh; tampilan dan Realtime belum diuji. Perubahan
  ini belum membuat ESP32 mengirim data ke cloud.
- Ekspor CSV ML disiapkan lewat tombol **Salin CSV ML** di pengaturan cloud.
  Ekspor meminta sampai 1.000 pembacaan terbaru dari perangkat yang dipilih dan
  menyalinnya ke papan klip hanya setelah pengguna menekan tombol. Pengguna juga
  melihat jumlah baris berlabel manual; ekspor cloud saat ini tidak mengambil
  label sehingga jumlahnya nol. Data ini bersifat privat. Jalur HTTP ekspor dan
  kegagalan 503 diuji dengan [fixture lokal](postman/README.md), bukan cloud asli.

## Belum tersedia

Pairing akun perangkat, pengiriman data ESP32 ke Supabase, Firebase push notification, kontrol aktuator, penyimpanan offline, dan model ML yang divalidasi dengan data nyata belum diimplementasikan. Pada pemeriksaan read-only 29 Oktober 2026, kedua tabel cloud kosong; alur masuk/Realtime belum diuji menyeluruh pada perangkat. Jalur Firebase App Distribution belum diuji secara menyeluruh. Ekspresi demo menggunakan aturan sederhana, bukan prediksi emosi ilmiah. Model 3D saat ini adalah placeholder geometris orisinal dan belum diuji di berbagai perangkat Android.

## Jalankan

Memerlukan Flutter 3.47 atau lebih baru serta Android SDK yang siap digunakan:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Flutter GPU diaktifkan di manifest Android untuk renderer 3D. Uji kinerja dan kompatibilitas pada perangkat fisik sebelum presentasi.

### Menampilkan sampel serial

1. Setelah rangkaian dinyatakan aman dan firmware versi 6 berjalan, salin satu
   baris JSON lengkap dengan `"type":"sample"` dari Serial Monitor ke papan
   klip **ponsel** menggunakan cara privat pilihan Anda. Jangan menyalin
   password atau kredensial.
2. Pada aplikasi yang sudah memuat perubahan ini, pilih **Pengaturan → Tempel
   data serial**. Dashboard menampilkan label **SERIAL** dan menegaskan bahwa
   waktu pengukuran tidak diketahui. Untuk kembali ke sumber cloud/offline,
   pilih **Pengaturan → Hapus snapshot**.
3. Pembacaan tidak diperbarui otomatis; salin dan tempel lagi untuk sampel baru.
   Tidak ada pengiriman ke cloud dan data yang ditempel hilang saat aplikasi
   ditutup. Jika APK pratinjau dibuat dengan satu snapshot bawaan, snapshot
   tersebut dapat muncul lagi saat aplikasi dibuka ulang.

Tanah/cahaya berupa skala relatif yang belum diverifikasi. UV, air, dan MQ
ditampilkan sebagai ADC mentah; nol atau 4095 bukan bukti sensor mati/hidup
dan bukan hasil kalibrasi. Snapshot tidak menghasilkan prediksi ML atau perintah
aktuator. Pemasukan ini sudah diuji dengan fixture dan satu sampel serial versi
6 yang diamati, tetapi belum diuji pada ponsel fisik.

Build pratinjau lokal dapat diberi `MOSS_SERIAL_SNAPSHOT` melalui
`--dart-define-from-file` yang disimpan di scratch privat. Tanpa define itu,
tidak ada snapshot bawaan. APK yang menyertakan data sensor **bersifat privat**;
jangan unggah APK, define, atau CSV ke repositori publik.

APK debug lokal hanya untuk melihat pratinjau. APK tersebut tidak menyertakan
pemeriksaan pembaruan Firebase dan menggunakan package terpisah
`io.github.xavier1508.smart_planter.preview`, sehingga tidak menggantikan beta
release. Jika ditandatangani dengan kunci debug sementara, build debug berikutnya
dengan kunci berbeda juga tidak dapat memperbarui pratinjau yang lama secara
langsung. Menghapus aplikasi dapat menghapus datanya; jangan hapus aplikasi yang
ada tanpa memastikan data dan konsekuensinya terlebih dahulu.

APK pratinjau serial yang dibuat pada sesi ini tersedia di
`analysis/android/moss-serial-preview-7f51b67669a1/moss-serial-preview.apk`
dari root proyek. APK ini memuat satu sampel pribadi dan telah diverifikasi
tanda tangannya, tetapi belum diuji pada ponsel. Tidak memperbarui beta yang
sudah terpasang; kunci debug sementara dihapus setelah build.

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
tetap berjalan dengan pemantauan lokal/offline. Sesi akun saat ini hanya disimpan
dalam memori dan pengguna perlu masuk kembali setelah aplikasi ditutup.

Realtime sudah disiapkan untuk `planter_readings`, tetapi pengujian dengan
akun pengguna, perangkat fisik, dan data asli masih diperlukan. Sebelum mulai
merekam data otomatis, tentukan interval kirim dan retensi agar kuota gratis
database tidak habis secara tidak sengaja.

Kolom `uv_index` sudah ada pada migrasi fondasi; tidak ada migrasi baru dalam
perubahan ini. Rumus UV historis pada firmware belum boleh dianggap hasil
kalibrasi atau dikirim sebagai pengukuran terverifikasi. Jenis modul, kondisi
referensi, konversi, dan kalibrasi masih harus dibuktikan.

Kontrak pembacaan yang diharapkan: `soil_percent` dan `light_percent` hanya
dipakai untuk hasil yang telah dikalibrasi; `temperature_c` dan
`humidity_percent` perlu berasal dari model dan pembacaan DHT yang diverifikasi;
`uv_index` pada tampilan tetap diberi label belum diverifikasi. Nilai hilang
tetap `null`. Pembacaan ADC atau estimasi historis tidak boleh diubah menjadi
hasil fisik tepercaya hanya karena angkanya berada dalam rentang database.

### Dataset dan rencana ML

CSV versi 1 (`lib/src/ml_dataset.dart`) menyertakan waktu server, ID pembacaan,
identitas perangkat opsional, versi firmware/kalibrasi opsional, serta fitur
tanah, suhu, kelembapan udara, cahaya, UV, level air, dan ADC MQ. Fitur yang
tidak tersedia dibiarkan kosong dengan penanda `missing=1`; angka nol valid
tetap nol. Nilai yang ada diberi kualitas `unverified`, bukan dianggap telah
terkalibrasi. Label dan sumber label tetap kosong sampai ada observasi atau
tinjauan manusia; ekspor tidak menggunakan data simulasi atau membuat label.
Rata-rata/perubahan tanah dan rata-rata cahaya satu jam dihitung dari baris
saat ini dan sebelumnya untuk satu perangkat, disertai jumlah sampel. Awal
ekspor 1.000 baris dapat kekurangan riwayat sebelum rentang tersebut; penanda
dan jumlah sampel tidak boleh diabaikan. Serializer dan fitur rolling telah
diuji lokal dengan data contoh, bukan dengan data cloud atau perangkat.

Ekstraksi log serial historis menggunakan kolom sumber dan `time_quality` yang
sama, tetapi waktu per sampel, ID server, dan labelnya kosong karena tidak
tercatat. Angka UV dari rumus lama disimpan terpisah sebagai `uv_legacy_proxy`,
bukan indeks UV terverifikasi; fitur satu jam tidak dibuat tanpa waktu. Data
historis tersebut hanya untuk eksplorasi, bukan bukti kinerja model deret waktu.

Snapshot serial versi 6 yang lebih lengkap disimpan sebagai CSV lokal
`analysis/ml/serial-v6-9d06d52ed8cc/sensor-observations.csv` dari root proyek
(175 baris). Skema `serial-1` menyertakan ADC mentah, penanda missing dan batas
ADC, uptime serta nomor baris sumber; waktu kalender dan label tetap kosong.
CSV ini tidak dimasukkan ke APK atau Git. Snapshot sebelumnya yang berisi 42
baris tumpang tindih dengan snapshot ini; jangan gabungkan keduanya tanpa
deduplikasi. Catatan dan hash masing-masing ada di `notes.md` sebelah CSV.

Log versi 6 yang lebih baru setelah perbaikan kabel juga disimpan sebagai CSV
privat `analysis/ml/serial-v6-f3b80aac999f/sensor-observations.csv` dari root
proyek (83 sampel lengkap; dua baris rusak dikecualikan). Belum ada label atau
waktu kalender tepercaya; file ini bukan model terlatih.

Untuk data nyata yang cukup, kandidat awal adalah **XGBoost berbasis pohon**
dengan fitur historis/rolling yang hanya menggunakan data masa lalu. Pohon
XGBoost dapat mempelajari arah untuk nilai hilang; fitur yang selalu kosong
selama pelatihan tetap tidak memberi informasi, sehingga pemasangan sensor baru
memerlukan data dan evaluasi ulang. Gunakan pemisahan kronologis dengan jeda
sesuai jendela fitur, uji pada perangkat/periode berbeda bila tersedia, dan
bandingkan dengan baseline sederhana menggunakan metrik sesuai target. Jangan
gunakan label masa depan, simulasi, atau ambang yang sama sebagai label yang
diklaim independen.

Eksperimen lokal kini melatih **XGBoost 3.1.2** memakai **60.000 baris sintetis**:
48.000 untuk pelatihan dan 12.000 untuk pengujian sintetis. Sumbernya adalah
rentang buatan dan aturan prototipe, bukan observasi nyata yang diberi label.
Rentang tanah, air relatif, dan LDR sintetis 0–100; UV sintetis 1–14 atau
kosong. Angka DHT/MQ sintetis juga hanya contoh dan tidak menjadi fitur model.
CSV, parameter, hash, dan batasannya ada di
`analysis/ml/xgboost-synthetic-rules-v2/`; skrip yang dapat diulang ada di
`tools/ml/train-synthetic-model.py` dengan versi paket pada `requirements.txt`.
CSV sintetis tidak boleh digabung atau dipresentasikan sebagai data sensor nyata.

Model dan baseline aturan sama-sama mencocokkan 100% holdout sintetis yang
labelnya dibuat dengan aturan yang sama. Ini hanya membuktikan peniruan aturan
pada data buatan, **bukan akurasi pada tanaman atau sensor nyata**. Hasil model
portable dibandingkan dengan keluaran XGBoost pada 100 fixture, termasuk UV
kosong. Model tetap tersedia sebagai artefak riset, tetapi tidak dimuat atau
ditampilkan di aplikasi pemantauan langsung. Score sintetis bukan probabilitas
kesehatan tanaman, dan model tidak mengendalikan relay. Model nyata yang
divalidasi masih memerlukan label relevan dan pengujian independen.

Referensi: [XGBoost dan nilai hilang](https://xgboost.readthedocs.io/en/stable/faq.html),
[benchmark model tabular NeurIPS](https://papers.neurips.cc/paper_files/paper/2022/file/0378c7692da36807bdec87ab043cdadc-Paper-Datasets_and_Benchmarks.pdf),
dan [pemisahan data deret waktu](https://scikit-learn.org/stable/modules/generated/sklearn.model_selection.TimeSeriesSplit.html).

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

#### Batas implementasi pairing saat ini

Paket ESP32 yang terpasang memiliki antarmuka provisioning BLE dan Security 1
dengan proof-of-possession; header `manager.h` pada paket ini hanya menyebut
Security 0 dan 1. Dokumentasi Espressif versi terbaru merekomendasikan Security 2
untuk produksi, tetapi keberadaannya pada framework ini belum terbukti. Tidak
boleh memakai Security 0 atau Security 1 tanpa PoP untuk mengirim kredensial.
Klien provisioning di Moss, pertukaran PoP yang terikat pada perangkat fisik,
dan mekanisme kredensial perangkat di backend belum diimplementasikan.
`WiFiClientSecure` menyediakan verifikasi sertifikat, tetapi jalur TLS, waktu
untuk memvalidasi sertifikat, dan pergantian CA belum diuji. Jangan memakai
`setInsecure()` sebagai jalan pintas.

Saat meninjau [kode sumber library provisioning Android Espressif
`lib-2.4.4`](https://github.com/espressif/esp-idf-provisioning-android/blob/lib-2.4.4/provisioning/src/main/java/com/espressif/provisioning/ESPDevice.java#L707-L749),
terlihat perintah log debug yang mencetak PoP dan pemilihan versi keamanan
berdasarkan informasi dari perangkat, termasuk Security 0. Ini adalah pengamatan
kode sumber, bukan pengujian paket biner. Jangan mengintegrasikan library ini
apa adanya: pastikan PoP tidak tercatat dan terapkan kebijakan yang menolak
mode tanpa autentikasi/enkripsi, lalu uji perilaku pada build yang dipakai.

Wi-Fi dan kredensial perangkat yang disimpan di flash bisa diakses oleh pihak
yang memperoleh akses fisik jika perlindungan penyimpanan tidak dikonfigurasi.
Status enkripsi flash/NVS papan belum diperiksa. Mengaktifkan fitur keamanan
perangkat keras dapat membatasi flashing berikutnya dan tidak dilakukan otomatis.
Sebelum aktivasi dibutuhkan tes pairing kedaluwarsa/sekali pakai, isolasi akun,
revokasi, pembatasan frekuensi, penanganan koneksi gagal, dan peninjauan kuota.

Dashboard saat ini menandai data lebih dari dua menit sebagai kedaluwarsa.
Misalnya, interval satu menit menghasilkan sampai 1.440 baris per perangkat per
hari dan batas ekspor 1.000 baris mencakup kurang dari 17 jam; angka ini bukan
keputusan retensi. Selaraskan interval, indikator kesegaran, batas penyimpanan,
ekspor data dan anggaran sebelum menyalakan pengiriman otomatis. Tidak ada data
yang dihapus otomatis dalam rancangan yang tersedia saat ini.

Referensi: [provisioning Espressif](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/provisioning/provisioning.html),
[enkripsi flash ESP32](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/security/flash-encryption.html).

## Distribusi beta privat

Catatan OPPO menunjukkan beta 0.2.0 build 3 crash pada layar pemasangan Firebase
karena tema Android tidak kompatibel. Beta 0.3.1 build 5 dengan perbaikan tema
berhasil dipasang melalui Firebase App Tester dan versinya diverifikasi lewat
ADB. Penguji kemudian melaporkan bahwa pembaruan dari dalam Moss ke build 6
berhasil; versi build 6 belum diverifikasi kembali melalui ADB. Penguji juga
melaporkan tidak ada indikator unduhan yang terlihat. Penguji mengonfirmasi
melalui Pengaturan Moss bahwa 0.3.2 build 7 sudah terpasang; build 7 belum
diverifikasi kembali melalui ADB.

Build 7 menampilkan status dan progres byte dari callback Firebase, tetapi
indikatornya belum diuji dengan unduhan nyata: pembaruan dari build 6 ke build 7
masih menggunakan pemutakhir lama. Pengujian indikator memerlukan build beta
berikutnya dan persetujuan pengguna untuk memasangnya. Perubahan swipe, komet,
grafik, dan pencahayaan disiapkan untuk 0.3.3 dan masih memerlukan pengujian
pada OPPO. Build beta berjalan dalam mode demo/offline karena publishable key
Supabase belum dikonfigurasi.

Package Android: `io.github.xavier1508.smart_planter`. Varian default `production`
tidak berisi SDK self-update App Distribution dan tidak memerlukan konfigurasi
Firebase. Varian `beta` dipakai **hanya** untuk distribusi privat; jangan
unggah varian itu ke Google Play. SDK App Distribution Android masih berstatus
beta. Update APK tetap memerlukan persetujuan pemasangan dari pengguna.

Perubahan Wi-Fi lokal, kartu MQ135, dan XGBoost berada pada aplikasi yang sama,
bukan aplikasi pratinjau baru. Sumber saat ini memakai `0.3.9+14`. Pengguna melaporkan build 8
sudah ada di App Tester; workflow GitHub menggunakan run berikutnya sebagai
version code untuk membangun dan menandatangani varian `beta` dengan kunci
release yang sama. Jangan mengirim keystore, password, konfigurasi privat, atau
isi sensor ke chat. Pemasangan pembaruan dan uji ponsel masih perlu dilakukan.

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
