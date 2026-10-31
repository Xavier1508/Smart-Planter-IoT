# Pemantauan lokal Moss

Moss menggunakan aplikasi Android yang sama untuk pemantauan Wi-Fi ESP32 dan
model XGBoost eksperimental. ESP32 membuat jaringan WPA2 `Moss-xxxx` tanpa
akses internet; setelah ponsel bergabung, pilih **Pengaturan → Hubungkan Wi-Fi
lokal**. Tidak diperlukan Tailscale atau kata sandi router. Stream hanya baca;
siapa pun yang mengetahui sandi jaringan dapat membaca data, karena tidak ada
autentikasi tambahan pada protokol aplikasi.

Firmware v13 menampilkan sandi acak 10 karakter pada LCD selama kurang lebih
satu menit setelah boot, lalu selama 30 detik dalam setiap siklus tampilan.
Sandi berubah setelah reboot. Firmware v12 tetap kompatibel dengan aplikasi,
tetapi memakai tampilan sandi yang lebih singkat. Firmware baru perlu di-upload
ke ESP32 secara terpisah dari pembaruan Android.

Tanah, air, dan cahaya ditampilkan sebagai persentase relatif yang belum
divalidasi. Persen UV dan MQ adalah **posisi ADC 12-bit**, bukan indeks UV,
konsentrasi gas, atau mutu udara. Suhu tetap dalam °C. Pembacaan yang hilang
ditampilkan `—`/`--`, bukan angka buatan; ketika ADC2 MQ gagal saat Wi-Fi aktif,
status digitalnya dapat tetap muncul. Perangkat, skala dan sambungannya masih
memerlukan verifikasi fisik.

Model XGBoost dilatih menggunakan aturan dan data sintetis, bukan diagnosis
tanaman. Model tidak mengontrol relay. Perintah ON lampu dan pompa tetap
dihambat, dan perintah OFF tidak membuktikan bahwa beban fisik mati.

Konfigurasi firmware dalam repositori menggunakan acuan umum yang belum
terverifikasi. Acuan khusus perangkat dapat disimpan di
`include/planter-calibration.local.h`; berkas ini diabaikan Git agar observasi
privat tidak ikut dipublikasikan. Kode dan APK tidak boleh memuat log atau
snapshot sensor pengguna.
