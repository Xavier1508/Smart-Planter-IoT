# Smart Planter IoT

Smart Planter IoT adalah proyek pengembangan pendamping tanaman dalam ruangan yang menggabungkan perangkat berbasis ESP32 dengan aplikasi Android. Proyek ini dirancang untuk membantu pengguna memahami kondisi tanaman dan, pada tahap selanjutnya, mengelola perangkat perawatan tanaman secara aman.

Aplikasi Android menggunakan karakter bernama Moss sebagai antarmuka interaktif. Saat ini pengembangan difokuskan pada penyempurnaan aplikasi dan pengalaman pengguna sebelum integrasi perangkat keras dilanjutkan.

## Status proyek

Proyek masih dalam tahap prototipe dan belum menjadi sistem pemantauan tanaman yang terhubung secara menyeluruh.

- Aplikasi Android tersedia sebagai prototipe dengan data dan kendali simulasi yang diberi label.
- Firmware ESP32 masih dalam pengembangan dan belum terintegrasi secara aman dengan aplikasi.
- Fondasi akun dan data privat menggunakan Supabase telah disiapkan, tetapi integrasi dengan perangkat dan pengujian menyeluruh masih diperlukan.
- Sensor level air dan MQ135 belum terpasang dan tetap tidak aktif.
- Penyiraman otomatis, kendali lampu, notifikasi sensor nyata, dan model machine learning belum tersedia.

Data simulasi bukan hasil pengukuran sensor dan tidak disimpan sebagai riwayat sensor nyata.

## Fitur aplikasi

Prototipe Android menyediakan beberapa bagian untuk menggambarkan pengalaman penggunaan yang direncanakan:

- Halaman utama dengan karakter Moss dan pilihan kondisi tanaman dalam mode simulasi.
- Tampilan contoh kelembapan tanah, air, suhu, cahaya, dan kondisi udara yang ditandai sebagai simulasi.
- Halaman riwayat dengan grafik dan aktivitas contoh yang hanya ditampilkan dalam mode simulasi.
- Halaman perangkat dengan status sensor dan saklar simulasi lokal untuk pompa dan lampu.
- Pengaturan untuk mengubah mode simulasi, melihat informasi versi, dan mengakses pengaturan cloud apabila telah dikonfigurasi.

Saklar simulasi tidak mengirim perintah dan tidak dapat mengubah keadaan pompa atau lampu. Ketika mode simulasi dimatikan dan belum ada data perangkat yang valid, aplikasi menampilkan kondisi menunggu data.

## Komponen sistem

### Aplikasi Android

Aplikasi dikembangkan menggunakan Flutter dan Dart. Karakter Moss menggunakan bentuk tiga dimensi sederhana sebagai pengganti sementara untuk model yang dapat dikembangkan lebih lanjut. Kinerja dan kompatibilitas tampilan tiga dimensi masih perlu diuji pada perangkat Android fisik.

### Perangkat ESP32

Firmware menggunakan Arduino dan PlatformIO dengan target papan NodeMCU-32S. Versi diagnostik yang sedang dikembangkan secara lokal mengirimkan sampel melalui serial setiap lima detik dan meminta relay berada dalam keadaan tidak aktif. Perubahan diagnostik tersebut belum tentu sudah tersedia pada versi repositori yang dipublikasikan. Nilai mentahnya belum dikalibrasi atau diverifikasi sebagai ukuran kelembapan tanah, cahaya, maupun indeks UV. Sensor yang belum tersedia dilaporkan tanpa nilai, bukan sebagai pembacaan nol.

Pembacaan DHT belum diaktifkan sampai jenis sensor dan sambungannya diperiksa. Wi-Fi, layar LCD, pengiriman data cloud, dan otomasi belum aktif pada firmware diagnostik. Kode dalam repositori juga belum tentu sama dengan firmware yang terpasang pada perangkat.

### Layanan cloud

Supabase digunakan sebagai fondasi autentikasi, penyimpanan data perangkat, dan pembaruan data melalui Realtime. Akses ke data perangkat dibatasi berdasarkan pemilik akun. Penyambungan perangkat, pengiriman data ESP32 yang aman, dan pengujian alur lengkap dari perangkat ke aplikasi masih dalam tahap perencanaan.

Build beta pertama telah melewati pemeriksaan GitHub Actions dan dikirim ke grup penguji Firebase App Distribution. Pemasangan beta dan pembaruan antarversi pada ponsel masih perlu diuji. APK pratinjau debug lokal tidak memeriksa pembaruan Firebase otomatis. Penggunaan GitHub Actions tetap perlu memperhatikan kuota dan batas biaya akun.

## Keselamatan perangkat keras

Pada pemeriksaan terakhir, firmware meminta relay tidak aktif, tetapi pompa dilaporkan tetap menyala ketika baterainya disambungkan. Penyebab fisiknya belum diketahui. Daya baterai pompa harus tetap terputus sampai sambungan dan rangkaian relay diperiksa. Jangan mengaktifkan penyiraman otomatis atau mencoba kendali pompa sebelum masalah tersebut diselesaikan.

Konfigurasi lama menggunakan GPIO 13 untuk relay pompa dengan logika aktif rendah dan GPIO 26 untuk relay lampu dengan logika aktif tinggi. GPIO 25 yang sebelumnya digunakan sebagai daya sensor tanah belum dikendalikan oleh firmware diagnostik. Jika sensor hanya mendapat daya dari pin tersebut, pembacaannya belum dapat diandalkan. Konfigurasi ini bukan bukti bahwa sambungan fisik sudah benar.

Keadaan relay selama perangkat menyala, di-reset, atau menerima firmware baru tidak dapat dipastikan hanya dari perintah perangkat lunak. Pastikan juga sinyal yang masuk ke ESP32 sesuai dengan batas aman 3,3 V. Keluaran modul yang diberi daya 5 V perlu diperiksa dan disesuaikan; pembacaan sensor mentah bukan pengganti pemeriksaan tegangan.

## Mencoba aplikasi

Pratinjau aplikasi dapat dibuat dan dijalankan dengan Flutter serta Android SDK. APK pratinjau yang telah dibuat secara lokal ditujukan untuk Android 7 atau lebih baru dengan sistem ARM64 dan tidak disertakan dalam repositori. Kompatibilitasnya masih memerlukan pengujian lebih lanjut pada berbagai ponsel. Petunjuk persiapan, pengujian, konfigurasi cloud, dan batasan distribusi tersedia dalam [dokumentasi aplikasi Android](mobile/README.md).

APK debug lokal ditujukan hanya untuk pengujian pada perangkat dan jaringan tepercaya. APK tersebut menggunakan identitas yang terpisah dari beta release. Jika dibuat dengan kunci debug sementara, versi pratinjau berikutnya mungkin tidak dapat dipasang sebagai pembaruan langsung; menghapus aplikasi lama dapat menghapus datanya.

Pemasangan pada ponsel tetap memerlukan persetujuan pengguna. Pratinjau lokal yang tidak dikonfigurasi untuk cloud tetap dapat digunakan dalam mode simulasi atau offline.

## Rencana pengembangan

1. Menyempurnakan antarmuka, karakter Moss, dan pengalaman penggunaan pada ponsel Android.
2. Menguji kinerja aplikasi dan tampilan tiga dimensi pada perangkat fisik.
3. Memverifikasi akun, akses data privat, pembaruan data, dan distribusi beta.
4. Memeriksa keselamatan rangkaian, sambungan sensor, relay, serta kalibrasi perangkat.
5. Merancang penyambungan perangkat dan pengiriman data yang aman dari ESP32 ke cloud.
6. Mengembangkan riwayat sensor nyata, notifikasi, dan kendali perangkat setelah integrasi dan keselamatan teruji.
7. Mengevaluasi penggunaan machine learning setelah tersedia data nyata yang memadai dan relevan.

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
