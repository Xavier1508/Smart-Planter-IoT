# Simulasi pembaca cloud

Fixture lokal ini diturunkan dari kolom `planter_readings` pada migrasi
fondasi dan permintaan `CloudTelemetry.exportTrainingCsv`. Isinya hanya tiga
baris **contoh**, bukan data sensor. Fixture memeriksa proyeksi, filter
perangkat, urutan dan batas baris; endpoint lain menjawab 501. Mock pemilik
tidak dicari di workspace pihak lain pada sesi ini.

Untuk menjalankan tes, siapkan dependensi Flutter seperti biasa, lalu jalankan
kedua simulasi pada dua terminal dari direktori `mobile`:

```powershell
postman simulation run postman/simulations/cloud-readings.sim.yaml --port 49211 --no-history --output ndjson
postman simulation run postman/simulations/cloud-readings-error.sim.yaml --port 49212 --no-history --output ndjson
```

Setelah masing-masing mencatat event `listening`, di terminal ketiga:

```powershell
$env:MOSS_READINGS_FIXTURE = 'http://127.0.0.1:49211/supabase'
$env:MOSS_READINGS_ERROR_FIXTURE = 'http://127.0.0.1:49212/supabase'
flutter test --no-pub test/cloud_export_simulation_test.dart
```

Hentikan kedua simulasi setelah selesai. Tes menolak host non-loopback dan
hanya menggunakan kunci contoh. Tanpa environment tersebut, kedua tes
di-skip. Simulasi kedua menginjeksikan HTTP 503 sebelum permintaan mencapai
handler, sehingga tidak ada event `request` pada mock untuk kegagalan itu.
Jangan mengarahkan tes ke proyek Supabase nyata atau memakai kredensial nyata.

Ini menguji client HTTP ekspor terhadap fixture dan penanganan 503, **bukan**
RLS, login, Realtime, penulisan, pairing, ESP32, atau layanan Supabase asli.
Fixture tidak menyimpan maupun menerima data pengguna dan tidak dideploy.
