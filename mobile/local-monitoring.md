# Pemantauan lokal Moss

Moss menggunakan aplikasi Android yang sama untuk pemantauan Wi-Fi ESP32.
ESP32 membuat jaringan WPA2 `Moss-xxxx` sendiri,
bukan bergabung ke router. Setelah ponsel bergabung ke `Moss-xxxx` dan memilih
tetap terhubung tanpa internet, aplikasi mencoba terhubung secara otomatis saat
dibuka. Jika koneksi putus, aplikasi mencoba kembali secara otomatis; tombol
hubung ulang juga tersedia di Pengaturan.
Nilai lama tetap ditampilkan sebagai data terakhir saat koneksi sementara
terputus, dengan status yang jelas; data baru menggantikannya setelah stream
pulih. Tidak diperlukan Tailscale atau kata sandi router. Stream hanya baca;
siapa pun yang mengetahui sandi jaringan dapat membaca data, karena tidak ada
autentikasi tambahan pada protokol aplikasi.

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
memakai **LDR saja** dengan satu ambang 65%; pada perangkat ini ADC yang
**lebih besar berarti lebih gelap** (gelap sekitar 2360, terang sekitar 0).
UV hanya dipantau.

Pompa memakai histeresis: ON di bawah **1000 ADC**, OFF pada **1200 ADC** ke
atas. Sejak v23 pompa otomatis boleh menyala terus sampai sensor tanah mencapai
1200, dengan batas keras **5 menit**. Jika batas itu tercapai, pompa dikunci
**30 menit** agar tanah tidak tergenang; pompa manual tetap dibatasi 30 detik.
Saat pompa menyala, bacaan sensor air ikut turun karena beban pompa, jadi air
rendah harus bertahan **6 sampel (30 detik)** sebelum pompa yang sedang berjalan
dihentikan. Saat pompa mati, satu sampel air rendah langsung memblokir start
berikutnya. ADC 4095 atau data tidak tersedia menghalangi ON. Tanah kering
terverifikasi 0 ADC, jenuh 1800 ADC; 0 = 0% dan 1200 ≈ 67%. Air memakai bucket
raw **≤450 EMPTY, ≤800 LOW, 801–1099 MEDIUM, ≥1100 FULL**; pompa tetap memakai
cutoff raw 600. Semua input ADC memakai median 5 sampel.

Firmware v25 menambahkan **relay staging**: jika pompa dan lampu harus ON
bersamaan, pompa ON lebih dulu dan lampu menyusul **150 milidetik** kemudian.
OFF selalu langsung untuk keduanya. Kedua coil juga ditahan OFF selama 2 detik
pertama setelah setup. Setiap boot mencetak `reset_reason` dan `brownout_count`
hanya ke serial. Brownout detector tetap aktif; staging hanya mengurangi inrush,
bukan menggantikan adaptor 5V yang kuat atau pull-up relay saat boot.

Firmware v26 memperbaiki AP yang gagal menyala: password lokal harus 8–10
karakter agar muat di buffer LCD; nilai 19 karakter ditolak dan AP dimatikan.
Password lokal harus 8–10 karakter agar muat di buffer LCD; nilai aktualnya ada
di header lokal yang diabaikan Git. Jika header tidak valid, firmware memakai
password acak 10 karakter, bukan mematikan AP. Status AP dicetak ke serial.
Aplikasi 0.4.1 menambahkan notifikasi HP untuk air rendah dan ringkasan prediksi
setiap 3 jam, plus pop-up singkat di atas layar saat koneksi terputus.

Firmware v30 memakai bucket air raw **EMPTY/LOW/MED/FULL**, flag `low` pada
raw ≤800, dan pompa cutoff raw 600. Pindah dari manual ON ke AUTO langsung
mengevaluasi sampel terakhir, dan client TCP setengah terbuka dibuang.
Aplikasi **Tunas 0.6.0** menambahkan dialog durasi wajib sebelum ON, wizard
jadwal (Sekarang atau kalender + jam + menit + detik, lalu durasi, lalu
konfirmasi), daftar aksi berurutan dengan hitungan mundur dan pembatalan,
eksekusi satu job per tick, histori CSV harian permanen, ekspor CSV ke
`Downloads/Tunas`, serta model decision tree 3 kelas dengan deteksi banjir.
CSV menyimpan semua angka sensor dan perintah untuk retraining model.

Halaman **Perangkat** menyediakan kendali manual pompa/lampu lewat socket lokal
yang sama. Pompa ON manual dibatasi 1–30 detik lalu kembali otomatis; lampu
manual berakhir OFF sampai AUTO. Perintah memakai baris `CTRL` dan mendapat
balasan `ack`. Jaringan tetap WPA2 lokal tanpa TLS; jangan bagikan password AP.
Scheduler app-side aktif selama aplikasi terbuka dan socket lokal terhubung;
jadwal yang terlewat lebih dari 2 menit dilewati, sedangkan aksi "Sekarang"
menunggu koneksi berikutnya. Interlock air, watchdog, batas waktu, jeda pompa,
dan jeda lampu tetap berlaku.

Aplikasi **Tunas 0.4.0** menggantikan nama tampilan Moss. Moss tetap menjadi
profil/karakter pertama. Sampai enam profil planter dapat didaftarkan dengan
nama, karakter, alamat IP/host, dan port sendiri; tombol hubungkan/putuskan
memindahkan sesi aktif. Tiga karakter memakai rig yang sama dengan palet,
aksesori, dan tempo gerak berbeda: Moss (daun), Bara (topi), Rintik (awan).
Emosi karakter ditentukan di ponsel; versi 0.6.0 memakai decision tree 3 kelas
(healthy/warning/critical) dengan pengaman aturan ambang. Riwayat kini
append-only CSV per perangkat, bukan hanya sesi. Firmware masih mode AP, jadi
beberapa ESP32 baru bisa berada di satu jaringan setelah mode STA ditambahkan;
alamat profil sudah bisa diedit untuk tahap itu.

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
