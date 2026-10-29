# Smart Planter IoT

Smart Planter IoT adalah proyek pengembangan pendamping tanaman dalam ruangan yang menggabungkan perangkat berbasis ESP32 dengan aplikasi Android. Proyek ini dirancang untuk membantu pengguna memahami kondisi tanaman dan, pada tahap selanjutnya, mengelola perangkat perawatan tanaman secara aman.

Aplikasi Android menggunakan karakter bernama Moss sebagai antarmuka interaktif. Saat ini pengembangan difokuskan pada penyempurnaan aplikasi dan pengalaman pengguna sebelum integrasi perangkat keras dilanjutkan.

## Status proyek

Proyek masih dalam tahap prototipe dan belum menjadi sistem pemantauan tanaman yang terhubung secara menyeluruh.

- Aplikasi Android tersedia sebagai prototipe dengan data dan kendali simulasi yang diberi label.
- Firmware ESP32 masih dalam pengembangan dan belum terintegrasi secara aman dengan aplikasi.
- Fondasi akun dan data privat menggunakan Supabase telah disiapkan, tetapi integrasi dengan perangkat dan pengujian menyeluruh masih diperlukan.
- Firmware sekarang hanya memiliki satu environment PlatformIO, `nodemcu-32s`.
  Build lokal berhasil; upload dan pemeriksaan fisik belum dilakukan.
- Sensor air dan MQ dilaporkan terpasang tetapi belum diverifikasi; keduanya
  dilaporkan `N/A`. Otomasi pompa dan lampu belum aktif atau aman untuk beban.
- Ekspor CSV dan fitur yang dapat bernilai kosong disiapkan untuk ML;
  model terlatih dan notifikasi sensor nyata belum tersedia.
- Android SDK command-line tools, platform dan dependensi build sudah dipasang
  tanpa Android Studio. Build aplikasi dilakukan pada salinan terisolasi tanpa
  tanda tangan, Firebase, atau keystore pengguna; APK tersebut tidak dapat dipasang.

Data simulasi bukan hasil pengukuran sensor dan tidak disimpan sebagai riwayat sensor nyata.

## Fitur aplikasi

Prototipe Android menyediakan beberapa bagian untuk menggambarkan pengalaman penggunaan yang direncanakan:

- Halaman utama dengan karakter Moss dan pilihan kondisi tanaman dalam mode simulasi.
- Karakter merespons sentuhan dan gerakan jari; suasana langit dapat mengikuti jam ponsel atau dipilih secara manual.
- Pilihan tema terang, gelap, atau mengikuti sistem.
- Tampilan contoh kelembapan tanah, air, suhu, cahaya, dan kondisi udara yang ditandai sebagai simulasi.
- Halaman riwayat dengan grafik dan aktivitas contoh yang hanya ditampilkan dalam mode simulasi.
- Halaman perangkat dengan status sensor dan saklar simulasi lokal untuk pompa dan lampu.
- Pengaturan untuk mengubah mode simulasi, melihat informasi versi, dan mengakses pengaturan cloud apabila telah dikonfigurasi.

Saklar simulasi tidak mengirim perintah dan tidak dapat mengubah keadaan pompa atau lampu. Ketika mode simulasi dimatikan dan belum ada data perangkat yang valid, aplikasi menampilkan kondisi menunggu data.

## Komponen sistem

### Aplikasi Android

Aplikasi dikembangkan menggunakan Flutter dan Dart. Karakter Moss menggunakan bentuk tiga dimensi sederhana sebagai pengganti sementara untuk model yang dapat dikembangkan lebih lanjut. Kinerja dan kompatibilitas tampilan tiga dimensi masih perlu diuji pada perangkat Android fisik.

### Perangkat ESP32

Firmware menggunakan Arduino dan PlatformIO dengan target papan NodeMCU-32S. Versi tunggal mengirimkan sampel serial setiap lima detik, menjalankan LCD, dan meminta kedua relay OFF. Angka tanah dan cahaya hanya skala relatif yang belum diverifikasi; UV ditampilkan sebagai ADC mentah, bukan indeks UV. Sensor yang belum tersedia dilaporkan `N/A` atau `null`.

Pada pemeriksaan 28 Oktober 2026, Windows mendeteksi antarmuka USB–serial CP210x pada COM3. Setelah pengguna menyatakan sumber daya beban relay terputus, upaya awal identifikasi gagal. Dengan tombol BOOT ditahan, esptool mengidentifikasi ESP32-D0WD-V3 revisi 3.1 dan flash 4 MB. Pemeriksaan dapat mereset papan, tetapi tidak membaca isi atau menulis flash; firmware yang terpasang dan sambungan fisik belum terverifikasi. Program awal yang tersimpan di Git mengandung otomasi pompa dan lampu. Membalik logika GPIO bukan bukti bahwa sambungan relay aman; daya beban tetap harus terputus sampai rangkaian dan keadaan relay diverifikasi.

Pengguna melaporkan memindahkan sinyal sensor air ke GPIO33 dan kemudian menyambungkan pin tengah sensor tanah ke GPIO25; laporan sambungan fisik ini belum diverifikasi. Pada foto sensor tanah, label `GND` dan `OUT` pada satu sisi bertentangan dengan label `S` dan `−` pada sisi lain untuk pin yang sama. Jangan menganggap salah satu sisi pasti benar tanpa data pinout atau pemeriksaan listrik. Kebutuhan arus sensor tanah juga belum diketahui, sehingga kemampuan GPIO25 mencatunya belum terbukti. Jangan memberi daya pada rangkaian yang belum diperiksa. GPIO33 adalah ADC1. Modul MQ sebelumnya dilaporkan menggunakan A0 pada GPIO27 dan D0 pada GPIO14 dengan VCC 3V3; GPIO27 adalah ADC2 yang berbagi sumber daya dengan Wi-Fi. Modul MQ135 umumnya memerlukan pemanas 5 V sesuai datasheet sensornya; catu 3,3 V tidak menjamin pembacaan valid atau membuktikan rangkaian aman. Keluaran modul 5 V tidak boleh langsung dihubungkan ke input ESP32. Mematikan pembacaan dalam firmware tidak memutus daya modul MQ; rangkaian catu dan tegangan kedua keluarannya perlu diperiksa sebelum modul diberi daya atau dihubungkan ke ESP32.

Pada 29 Oktober pengguna melaporkan telah mencoba VCC sensor air pada 5 V. Jika keluaran sensor yang dicatu 5 V terhubung langsung ke GPIO33, tegangannya bisa melampaui batas ESP32; cabut semua daya sebelum melepas atau memeriksa sambungan. Mengabaikan sensor dalam kode tidak memutus sambungan fisiknya.

Kode mencoba membaca DHT sebagai DHT11 sesuai kode lama, tetapi model fisik belum diverifikasi. Sensor tanah default-nya `N/A` dan GPIO25 tidak dikendalikan sampai pinout serta kebutuhan arusnya terbukti aman. Sensor air dan MQ dinonaktifkan karena sambungan dan tegangannya belum dipastikan. Mengubah opsi pembacaan tidak mengisolasi kabel fisik. Wi-Fi, pengiriman cloud, dan otomasi relay belum aktif.

### Build firmware tunggal

`src/main.cpp` adalah sumber firmware dan `include/planter-config.h` adalah acuan pin serta titik relatif. Setelah pemeriksaan rangkaian, pengguna memilih **Project Tasks → nodemcu-32s → General → Build**, lalu melakukan **Upload** sendiri; monitor serial menggunakan 115200 baud. Daya beban pompa dan lampu tetap terputus. Permintaan OFF memakai asumsi GPIO13 LOW dan GPIO26 LOW; ini belum membuktikan relay fisik mati.

Build lokal pada 29 Oktober 2026 berhasil untuk ESP32: RAM 22.016 byte dan flash 295.953 byte. SHA-256 `firmware.bin` hasil build adalah `E7EF52E75A5068FA93B1CF266FAF32BB3751FB1A6930AA3A4C505247EBBEE292`; binari sementara dibersihkan, build PlatformIO milik pengguna tidak diubah. Tes fungsi host lulus dengan data contoh. Tidak ada upload atau pengujian perangkat fisik.

Riwayat: log diagnostik versi 4 pernah menunjukkan lima sampel ADC air 0 dan MQ 4095; penyebabnya belum diketahui. Mode uji relay sebelumnya mengirim `ready`, tetapi tidak menampilkan perintah uji diterima. Kedua observasi itu tidak membuktikan keadaan sensor atau kontak relay.

### Layanan cloud

Supabase digunakan sebagai fondasi autentikasi, penyimpanan data perangkat, dan pembaruan data melalui Realtime. Akses ke data perangkat dibatasi berdasarkan pemilik akun. Penyambungan perangkat, pengiriman data ESP32 yang aman, dan pengujian alur lengkap dari perangkat ke aplikasi masih dalam tahap perencanaan.

Pada perubahan lokal berikutnya, pembaca dan dashboard Moss disiapkan untuk kolom `uv_index` yang sudah tercantum pada migrasi fondasi. Angka yang diterima diberi label perkiraan dan belum diverifikasi; pemeriksaan rentang tidak membuktikan kalibrasi. Dekoder dan model diuji menggunakan data contoh, tetapi tampilan, Realtime, dan alur dari ESP32 belum diuji. Tidak ada data perangkat yang dikirim atau pengaturan cloud yang diubah dalam pekerjaan ini.

Pengujian ulang pada 29 Oktober 2026: 74 tes Flutter lulus, dua tes tambahan
lulus ketika pembaca CSV dijalankan terhadap simulasi Postman lokal (respons
normal dan 503), serta `flutter analyze` bersih. Simulasi tidak membuktikan
autentikasi, RLS, Realtime atau ingestion Supabase yang sesungguhnya. Ekspor
menampilkan jumlah label manual tetapi tidak membuat label. Data sensor di UI
diberi penanda belum diverifikasi. Rincian ada di
[dokumentasi aplikasi](mobile/README.md) dan
[fixture cloud](mobile/postman/README.md).

Dataset eksplorasi lokal disimpan di `analysis/ml/serial-observations-20261029-040023/sensor-observations.csv` (732 baris dari dua log; 728 memuat suhu dan kelembapan DHT). Kualitas angka masih `unverified`; tidak ada waktu tepercaya per sampel, label independen, data level air, atau MQ. File itu tidak disertakan dalam Git. `notes.md` di folder yang sama mencatat hash input dan output. Jangan menyatakan model terlatih atau hasil prediksi berdasarkan dataset ini saja.

Build beta pertama telah melewati pemeriksaan GitHub Actions dan dikirim ke grup penguji Firebase App Distribution. Pemasangan beta dan pembaruan antarversi pada ponsel masih perlu diuji. APK pratinjau debug lokal tidak memeriksa pembaruan Firebase otomatis. Penggunaan GitHub Actions tetap perlu memperhatikan kuota dan batas biaya akun.

## Keselamatan perangkat keras

Pengguna melaporkan pompa langsung menyala ketika baterainya disambungkan, saat ESP32 dan modul relay juga mendapat daya. Penyebab keadaan kontak fisik belum diketahui. Daya beban pompa dan lampu harus tetap terputus sampai sambungan dan rangkaian relay diperiksa. Jangan menjalankan kedua beban dengan varian otomatis sebelum masalah tersebut diselesaikan.

Pada audit 29 Oktober 2026, lima baris terbaru dari log berformat program awal menunjukkan **perintah pompa ON**. Nilai tanah yang menjadi dasar otomasi dihitung menggunakan titik dan ambang historis yang belum dikalibrasi; log tidak membuktikan kondisi tanah atau kontak relay. Dalam kode awal, perintah ON dapat tetap bertahan sampai angka estimasi melewati ambang OFF. Pengguna menjelaskan ESP32 dan modul relay juga bertenaga saat pompa langsung menyala; ini konsisten dengan perintah ON yang tercatat, tetapi tidak membuktikan keadaan kontak atau menyingkirkan masalah rangkaian. Pengguna ingin baterai tetap terhubung nantinya, dengan beban normalnya terputus oleh relay; hal itu belum diverifikasi secara fisik dan tidak dapat dijamin hanya dengan membalik level GPIO.

Pada pemeriksaan log berikutnya (`device-monitor-261029-030912.log`, sekitar 03.13), 91 sampel berformat program awal teridentifikasi di bagian akhir log. Enam sampel dengan estimasi tanah di atas ambang OFF mencatat perintah pompa OFF; lima sampel terakhir yang dibaca kembali mencatat ON. Pemeriksaan berikutnya sekitar 03.19 menemukan 240 sampel dalam log yang sama: enam di atas ambang juga tercatat OFF, sedangkan lima sampel terakhir masih mencatat ON. Pengguna melaporkan relay berbunyi dan pompa tetap menyala saat baterai ditempelkan. Waktu kejadian fisik itu belum dapat dicocokkan dengan sampel tertentu; log tidak menunjukkan keadaan kontak, kabel, atau putaran pompa. Pesan awal yang terlihat berasal dari varian otomatis, bukan penanda varian terkunci. Jangan menyimpulkan polaritas fisik hanya dari bunyi atau label perintah.

Program awal menggunakan GPIO13 untuk pompa dengan perintah ON LOW; firmware tunggal membalik asumsi itu sehingga OFF meminta LOW. Lampu GPIO26 juga meminta OFF LOW. Kedua asumsi tersebut **belum terbukti** menonaktifkan relay fisik. Pembacaan sensor tidak dapat meminta ON pada firmware saat ini, dan timer/jeda pompa belum dibuat. Sebelum otomasi diaktifkan, periksa kontak dan polaritas, lalu rancang batas durasi serta jeda yang tidak bergantung pada operasi jaringan. Kode tidak dapat menjamin keadaan selama boot, reset, macet, atau kontak lengket.

Pastikan rangkaian dan tegangan GPIO aman sebelum menyalakan ESP32; baterai pompa dan sumber daya lampu tetap terputus selama upload dan pemeriksaan. Jika memakai multimeter, ukur kontinuitas COM/NO hanya setelah memastikan kontak terisolasi dari semua sumber tegangan. Pada relay SPDT biasa, NO terbuka saat kumparan tidak bertenaga sedangkan NC tertutup; memindahkan kabel ke NC tidak membuat keadaan mati menjadi default.

### Acuan kalibrasi sensor

- **Tanah:** tentukan dua pembacaan stabil pada media yang sama, satu kering dan satu basah, setelah pinout, tegangan, dan catu sensor aman. Persentase hasil dua titik adalah skala relatif untuk kondisi itu, bukan kadar air volumetrik yang terukur. Konstanta historis `SOIL_DRY=0` dan `SOIL_WET=2450` belum terbukti sebagai titik kalibrasi rangkaian ini.
- **Cahaya/LDR:** rentang gelap–terang pada posisi yang sama dapat digunakan sebagai skala relatif. Untuk satuan lux diperlukan acuan luxmeter serta kurva/kalibrasi yang sesuai rangkaian dan sensornya; angka persentase lama bukan hasil lux.
- **UV:** identifikasi jenis dan respons spektral modul, lalu gunakan datasheet dan pengukuran acuan UV yang sesuai. Pembacaan LDR/luxmeter biasa bukan pengganti acuan indeks UV; rumus historis belum terbukti menghasilkan indeks UV yang benar.
- **Suhu/kelembapan udara:** pastikan model DHT yang digunakan dan bandingkan dengan termometer serta higrometer acuan pada kondisi yang sesuai. Hasil bacaan yang gagal tetap tidak tersedia, bukan nol.
- **Water level:** ditunda sesuai permintaan. MQ135 belum menghasilkan konsentrasi tepercaya tanpa rangkaian dan kalibrasi yang sesuai.

## Mencoba aplikasi

Pratinjau aplikasi dapat dibuat dan dijalankan dengan Flutter serta Android SDK. APK pratinjau yang telah dibuat secara lokal ditujukan untuk Android 7 atau lebih baru dengan sistem ARM64 dan tidak disertakan dalam repositori. Kompatibilitasnya masih memerlukan pengujian lebih lanjut pada berbagai ponsel. Petunjuk persiapan, pengujian, konfigurasi cloud, dan batasan distribusi tersedia dalam [dokumentasi aplikasi Android](mobile/README.md).

SDK yang dipulihkan berada di `C:\Users\ThinkPad\AppData\Local\Android\sdk`;
platform 35 dan 36, build-tools, NDK 28.2 dan CMake 3.22.1 terpasang, tanpa
Android Studio atau emulator. Ukuran yang terukur setelah build sekitar 2,67 GiB.
Kompilasi ARM64 debug berhasil pada salinan tanpa signing; hasilnya bukan APK
yang dapat dipasang dan dibersihkan bersama cache sementara setelah pemeriksaan.

APK debug lokal ditujukan hanya untuk pengujian pada perangkat dan jaringan tepercaya. APK tersebut menggunakan identitas yang terpisah dari beta release. Jika dibuat dengan kunci debug sementara, versi pratinjau berikutnya mungkin tidak dapat dipasang sebagai pembaruan langsung; menghapus aplikasi lama dapat menghapus datanya.

Pemasangan pada ponsel tetap memerlukan persetujuan pengguna. Pratinjau lokal yang tidak dikonfigurasi untuk cloud tetap dapat digunakan dalam mode simulasi atau offline.

## Rencana pengembangan

1. Menyempurnakan antarmuka, karakter Moss, dan pengalaman penggunaan pada ponsel Android.
2. Menguji kinerja aplikasi dan tampilan tiga dimensi pada perangkat fisik.
3. Memverifikasi akun, akses data privat, pembaruan data, dan distribusi beta.
4. Memeriksa keselamatan rangkaian, sambungan sensor, relay, serta kalibrasi perangkat.
5. Merancang penyambungan perangkat dan pengiriman data yang aman dari ESP32 ke cloud.
6. Mengembangkan riwayat sensor nyata, notifikasi, dan kendali perangkat setelah integrasi dan keselamatan teruji.
7. Melatih dan mengevaluasi kandidat XGBoost setelah data nyata berlabel tersedia; integrasi ekspresi Moss dan prediksi harus diuji sebelum dipakai.

## Struktur repositori

- [mobile](mobile/) berisi aplikasi Android, pengujian Flutter, dan migrasi basis data.
- [src](src/) berisi firmware ESP32.
- [include](include/) berisi konfigurasi dan komponen pendukung firmware.
- [lib](lib/) berisi pustaka khusus proyek.
- [test](test/) berisi pengujian firmware.
- [GitHub Actions](.github/workflows/) berisi alur pemeriksaan dan distribusi aplikasi.

## Privasi dan keamanan data

Data perangkat dirancang agar hanya dapat diakses oleh pemilik yang berwenang. Integrasi cloud masih memerlukan pengujian lanjutan, dan sesi akun pada prototipe saat ini hanya disimpan dalam memori aplikasi.

Kata sandi, token, kunci privat, dan berkas konfigurasi rahasia tidak boleh disertakan dalam repositori atau aplikasi. Rancangan lama untuk backend dan dashboard web bukan bagian layanan yang tersedia dalam repositori ini.

## Lisensi

Belum ada informasi lisensi yang ditetapkan dalam repositori. Hubungi pemilik proyek sebelum menggunakan atau mendistribusikan ulang materi proyek.
