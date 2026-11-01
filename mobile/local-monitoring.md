# Pemantauan lokal Moss

Moss menggunakan aplikasi Android yang sama untuk pemantauan Wi-Fi ESP32.
ESP32 membuat jaringan WPA2 `Moss-xxxx` sendiri,
bukan bergabung ke router. Setelah ponsel bergabung ke `Moss-xxxx` dan memilih
tetap terhubung tanpa internet, aplikasi mencoba terhubung secara otomatis saat
dibuka. Jika koneksi putus, aplikasi mencoba kembali secara otomatis; tombol
hubung ulang juga tersedia di Pengaturan.
Nilai lama dihapus saat data tidak lagi tersedia. Tidak diperlukan Tailscale
atau kata sandi router. Stream hanya baca; siapa pun yang mengetahui sandi
jaringan dapat membaca data, karena tidak ada autentikasi tambahan pada
protokol aplikasi.

Firmware v13 menampilkan sandi acak 10 karakter pada LCD selama kurang lebih
satu menit setelah boot, lalu selama 30 detik dalam setiap siklus tampilan.
Sandi berubah setelah reboot. Firmware v12 tetap kompatibel dengan aplikasi,
tetapi memakai tampilan sandi yang lebih singkat. Firmware baru perlu di-upload
ke ESP32 secara terpisah dari pembaruan Android.

Pada firmware v16, aturan lampu mencoba ON ketika kecerahan LDR relatif di bawah
40% dan proksi UV di bawah 7; OFF saat kecerahan mencapai 60% atau proksi UV
di atas 7. Zona antara mempertahankan keadaan sebelumnya. Nilai ADC UV 0
diperlakukan sebagai proksi UV rendah sesuai permintaan, tetapi 0 juga dapat
berarti sensor atau sambungan bermasalah. Jangan menganggapnya bukti UV rendah.
Proksi UV adalah pemetaan ADC perkiraan, bukan indeks UV terkalibrasi.

Pada firmware lokal v21, relay pompa memakai polaritas **active-LOW** (ON = LOW,
OFF = HIGH) dan relay lampu **active-HIGH** (ON = HIGH, OFF = LOW). Lampu
memakai **LDR saja** dengan satu ambang 65%; pada perangkat ini LDR gelap
sekitar 0 ADC dan terang sekitar 2360 ADC. UV hanya dipantau.

Pompa memakai histeresis: ON di bawah **1000 ADC**, OFF pada **1200 ADC** ke
atas. Setelah berhenti karena batas waktu 30 detik, pompa menunggu **5 menit**
agar air meresap sebelum mencoba lagi. ADC 4095 atau data tidak tersedia
menghalangi ON. Tanah kering terverifikasi 0 ADC, jenuh 1800 ADC; 0 = 0% dan
1200 ≈ 67%. Air memakai rentang **826 (rendah) sampai 1150 (penuh)**; indikator
Full dimulai pada 50% rentang karena pin atas sudah terendam di sekitar 1000.
Semua input ADC memakai median 5 sampel.

Halaman **Perangkat** menyediakan kendali manual pompa/lampu lewat socket lokal
yang sama. Pompa ON manual dibatasi 1–30 detik lalu kembali otomatis; pompa OFF
dan lampu manual bertahan sampai AUTO. Perintah memakai baris `CTRL` dan
mendapat balasan `ack`. Jaringan tetap WPA2 lokal tanpa TLS; jangan bagikan
password AP. Scheduler app-side belum diaktifkan pada versi ini.
Interlock air, watchdog, batas waktu, jeda pompa, dan jeda lampu tetap berlaku.
Nilai rata-rata memakai lima konversi berturutan per siklus untuk setiap input
ADC, bukan rata-rata lima siklus. DHT dan input digital MQ tidak dirata-ratakan.
Sumber v20 belum membuktikan perilaku fisik relay atau sensor.

MQ v19 dipetakan ke SVP/GPIO36 (ADC1) sesuai laporan pengguna; versi lama
memakai GPIO27 (ADC2). Tegangan dan sambungan nyata belum diverifikasi.
Aplikasi 0.3.9 menampilkan **indeks gas relatif 0–100** yang dihitung dari
rasio resistansi sinyal MQ135 terhadap baseline sesi, ditambah ADC, rata-rata
12 sampel (maksimum 60 detik uptime perangkat), arah sinyal, dan perkiraan
tegangan pin. Indeks 0 berarti pada/di bawah sinyal terbersih yang teramati;
nilai lebih tinggi berarti perubahan gas yang lebih kuat. Baseline mengikuti
sinyal yang lebih bersih dengan cepat dan pulih perlahan. Rata-rata dan indeks
dihapus saat data putus, gagal baca, atau mencapai rel 0/4095. Indeks ini
**bukan ppm, CO₂, atau mutu udara terkalibrasi**; ia hanya indikator relatif
untuk asap/VOC dan gas umum lain yang dideteksi MQ135.

Kalibrasi MQ135 memerlukan catu dan beban yang diketahui, pemanasan awal lebih
dari 48 jam, serta R0 dari udara bersih yang diverifikasi. Manual Winsen
mencantumkan NH₃, sulfida, benzena, hidrogen dan asap sebagai gas target, bukan
CO₂ sebagai pengukuran tunggal. Rumus `Rs = (Vc/VRL - 1) × RL` hanya dapat
dihitung bila Vc, VRL dan RL diketahui; tegangan pin 509–559 mV yang tercatat
bukan bukti nilai-nilai itu. Untuk CO₂ tanaman yang dapat dipercaya, gunakan
sensor CO₂ optik (NDIR atau photoacoustic seperti Sensirion SCD41) dan
verifikasi datasheet serta catunya. Tanpa itu, aplikasi tidak menampilkan
angka CO₂.

Tanah, air, dan cahaya ditampilkan sebagai persentase relatif yang belum
divalidasi. UV ditampilkan sebagai posisi ADC 12-bit, bukan indeks UV. MQ
ditampilkan sebagai ADC dan rata-rata sinyal, bukan konsentrasi gas atau mutu
udara. Suhu tetap dalam °C. Pembacaan yang hilang ditampilkan `—`/`--`, bukan
angka buatan. Perangkat, skala dan sambungannya masih memerlukan verifikasi
fisik.

Firmware v14 dan sesudahnya dapat meminta relay ON sesuai aturannya; perintah ON/OFF yang
ditampilkan aplikasi bukan pengukuran keadaan kontak atau beban fisik. Aplikasi
tidak mengirim perintah relay dan tidak menggunakan model sintetis sebagai data.

Konfigurasi firmware dalam repositori menggunakan acuan umum yang belum
terverifikasi. Acuan khusus perangkat dapat disimpan di
`include/planter-calibration.local.h`; berkas ini diabaikan Git agar observasi
privat tidak ikut dipublikasikan. Kode dan APK tidak boleh memuat log atau
snapshot sensor pengguna.
