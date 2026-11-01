# Smart Planter IoT

Smart Planter IoT adalah proyek pengembangan pendamping tanaman dalam ruangan yang menggabungkan perangkat berbasis ESP32 dengan aplikasi Android. Proyek ini dirancang untuk membantu pengguna memahami kondisi tanaman dan, pada tahap selanjutnya, mengelola perangkat perawatan tanaman secara aman.

Aplikasi Android menggunakan karakter bernama Moss sebagai antarmuka interaktif. Integrasi pemantauan perangkat keras melalui Wi-Fi lokal sedang dikembangkan dan belum diuji menyeluruh pada perangkat fisik.

## Status proyek

Proyek masih dalam tahap prototipe dan belum menjadi sistem pemantauan tanaman yang terhubung secara menyeluruh.

- Aplikasi Android sedang disiapkan untuk data langsung tanpa mode simulasi;
  koneksi dan tampilan pada ponsel fisik masih perlu diuji.
- Firmware ESP32 masih dalam pengembangan dan belum terintegrasi secara aman dengan aplikasi.
- Fondasi akun dan data privat menggunakan Supabase telah disiapkan, tetapi integrasi dengan perangkat dan pengujian menyeluruh masih diperlukan.
- Firmware hanya memiliki satu environment PlatformIO, `nodemcu-32s`.
  Startup versi 11 dan pembacaan serial telah terlihat pada log. Log tidak
  membuktikan hash terpasang, keselamatan rangkaian, atau keadaan kontak fisik.
- Sumber firmware versi 16 mencoba membaca tanah, air, MQ, DHT, cahaya, dan UV
  serta menyiapkan Wi-Fi lokal. Pengguna melaporkan meng-upload versi 14 dan
  menjalankan uji relay; log memperlihatkan sampel versi 14 tetapi tidak
  membuktikan keadaan kontak. Versi 16 belum diuji pada perangkat fisik.
  GPIO25 tetap input sementara pembacaan ADC tanah GPIO34 dicoba. Otomasi pompa
  dan lampu diaktifkan untuk uji pengguna dengan skala perkiraan; keadaan fisik
  beban belum terbukti dan input GPIO tidak mengisolasi kabel listrik.
  Sambungan, keadaan kontak dan hasil sensor belum diverifikasi; jangan anggap
  build atau logika GPIO sebagai bukti keamanan beban fisik.
- Eksperimen XGBoost berbasis data sintetis sudah disiapkan di aplikasi Moss;
  model yang divalidasi dengan data nyata dan notifikasi sensor nyata belum tersedia.
- Android SDK command-line tools, platform dan dependensi build sudah dipasang
  tanpa Android Studio. APK pratinjau serial lokal sudah dibuat pada salinan
  terisolasi dengan kunci debug sementara, tanpa Firebase atau keystore pengguna.

## Fitur aplikasi

Prototipe Android menyediakan:

- Halaman utama dengan karakter Moss dan pembacaan sensor lokal.
- Karakter merespons sentuhan dan gerakan jari; suasana langit dapat mengikuti jam ponsel atau dipilih secara manual.
- Pilihan tema terang, gelap, atau mengikuti sistem.
- Tampilan kelembapan tanah, air, suhu, cahaya, UV, dan pembacaan MQ yang tersedia.
- Halaman riwayat yang tetap kosong sampai penyimpanan riwayat diterapkan.
- Halaman perangkat dengan status sensor dan perintah relay firmware yang dilaporkan.
- Pengaturan tampilan, koneksi lokal, versi, serta cloud apabila dikonfigurasi.

Aplikasi tidak mengirim perintah pompa atau lampu. Ketika belum ada data sensor
valid, aplikasi menampilkan kondisi menunggu, bukan angka yang dibuat-buat.

## Komponen sistem

### Aplikasi Android

Aplikasi dikembangkan menggunakan Flutter dan Dart. Karakter Moss menggunakan bentuk tiga dimensi sederhana sebagai pengganti sementara untuk model yang dapat dikembangkan lebih lanjut. Kinerja dan kompatibilitas tampilan tiga dimensi masih perlu diuji pada perangkat Android fisik.

### Perangkat ESP32

Firmware menggunakan Arduino dan PlatformIO dengan target papan NodeMCU-32S. Versi tunggal mengirimkan sampel serial setiap lima detik dan menjalankan LCD. Versi lokal 16 mengaktifkan aturan relay percobaan dan tetap mencoba membaca ADC tanah tanpa menggerakkan GPIO25 sebagai output. Tanah dan cahaya memakai acuan relatif yang belum diverifikasi. UV dan MQ dapat ditampilkan sebagai persentase rentang ADC, bukan ukuran fisik terkalibrasi. Nol ADC bukan bukti sensor terpasang, bekerja, atau aman.

Pada pemeriksaan 28 Oktober 2026, Windows mendeteksi antarmuka USB–serial CP210x pada COM3. Setelah pengguna menyatakan sumber daya beban relay terputus, upaya awal identifikasi gagal. Dengan tombol BOOT ditahan, esptool mengidentifikasi ESP32-D0WD-V3 revisi 3.1 dan flash 4 MB. Pemeriksaan dapat mereset papan, tetapi tidak membaca isi atau menulis flash; firmware yang terpasang dan sambungan fisik belum terverifikasi. Program awal yang tersimpan di Git mengandung otomasi pompa dan lampu. Membalik logika GPIO bukan bukti bahwa sambungan relay aman; daya beban tetap harus terputus sampai rangkaian dan keadaan relay diverifikasi.

Pengguna melaporkan memindahkan sinyal sensor air ke GPIO33 dan kemudian menyambungkan pin tengah sensor tanah ke GPIO25; laporan sambungan fisik ini belum diverifikasi. Pada foto sensor tanah, label `GND` dan `OUT` pada satu sisi bertentangan dengan label `S` dan `−` pada sisi lain untuk pin yang sama. Jangan menganggap salah satu sisi pasti benar tanpa data pinout atau pemeriksaan listrik. Kebutuhan arus sensor tanah juga belum diketahui, sehingga kemampuan GPIO25 mencatunya belum terbukti. Jangan memberi daya pada rangkaian yang belum diperiksa. GPIO33 adalah ADC1. Modul MQ sebelumnya dilaporkan menggunakan A0 pada GPIO27 dan D0 pada GPIO14 dengan VCC 3V3; GPIO27 adalah ADC2 yang berbagi sumber daya dengan Wi-Fi. Modul MQ135 umumnya memerlukan pemanas 5 V sesuai datasheet sensornya; catu 3,3 V tidak menjamin pembacaan valid atau membuktikan rangkaian aman. Keluaran modul 5 V tidak boleh langsung dihubungkan ke input ESP32. Mematikan pembacaan dalam firmware tidak memutus daya modul MQ; rangkaian catu dan tegangan kedua keluarannya perlu diperiksa sebelum modul diberi daya atau dihubungkan ke ESP32.

Pada 29 Oktober pengguna melaporkan telah mencoba VCC sensor air pada 5 V. Jika keluaran sensor yang dicatu 5 V terhubung langsung ke GPIO33, tegangannya bisa melampaui batas ESP32; cabut semua daya sebelum melepas atau memeriksa sambungan. Mengabaikan sensor dalam kode tidak memutus sambungan fisiknya.

Kode mencoba membaca DHT sebagai DHT11 sesuai kode lama, tetapi model fisik belum diverifikasi. Pemetaan historis adalah tanah GPIO34, air GPIO33, MQ analog GPIO27 dan digital GPIO14; versi 12 mencoba membaca GPIO34 sedangkan GPIO25 tetap input karena kemungkinan konflik catu belum diperiksa. LED sensor yang dilaporkan menyala tidak membuktikan sumber daya atau tegangan sinyalnya. **Sebelum upload atau menyalakan ESP32, verifikasi pinout dan arus catu tanah serta pastikan keluaran sensor ke GPIO tidak melebihi batas ESP32.** Status ini belum dibuktikan. Membaca pin tidak mengisolasi kabel atau melindungi ESP32 dari tegangan berlebih. Log versi 11 melaporkan Wi-Fi dan cloud nonaktif; versi lokal 12 menyiapkan Wi-Fi langsung tanpa cloud. Pada GPIO27, pembacaan ADC2 selalu dicoba; kegagalan driver dilaporkan `adc_read_failed`, bukan dibuat nol, karena ADC2 dapat bertabrakan dengan Wi-Fi.

**Audit Excel menunggu konfirmasi fisik:** `Sheet1` baris 34–35 mencatat MQ
`D0 → P14` dan `A0 → P27`, sesuai firmware dan urutan 8–9 dari 5V pada sisi
kanan yang dicatat di sheet. Baris 37 mencatat `+` sensor tanah ke P25, tetapi
K20:L20 mencatat VCC/+ ke rel kanan yang menurut baris 45 terhubung 3V3. Jika
keduanya benar-benar satu net, GPIO25 yang ditarik LOW dapat menyebabkan
hubungan pendek. Kebutuhan arus dan label pin sensor juga belum diverifikasi.
Baris 8 mencatat `−` sensor air ke P2, sedangkan K17:L17 mencatat `−` ke rel
ground; sambungan aktual belum diketahui. K38:L38 mencatat LCD pada rel kiri
yang menurut baris 27 terhubung 5V; tegangan pull-up I2C belum diperiksa dan
tidak boleh diasumsikan aman untuk GPIO ESP32. Foto rangkaian sebelumnya tidak
tersedia pada pemeriksaan ini. Jangan memberi daya sebelum sambungan dan
tegangan diperiksa; daya pompa dan lampu tetap terputus.
File Excel yang diperiksa ber-SHA-256
`ECA694971F397F236EE6B8E5708366344C477488528FCCCC2B4E37C58B30ED5A`.
Log baru `device-monitor-261029-180019.log` sedang bertambah setelah perbaikan
kabel dilaporkan. Snapshot 29 Oktober pukul 18:07:23 mencakup 44.144 byte awal
(SHA-256 `F3B80AAC999FB7A0C34CDA127CFFA227678AB7B51920A202DDB1BDE1E5D5B75B`):
83 sampel versi 6 lengkap, dengan dua baris JSON rusak yang tidak dihitung.
DHT terbaca 29,7–29,9 °C dan 70% RH, tanah ADC 384–2759, dan cahaya ADC
84–3219 (skala relatif lama 21–97%). UV ADC 0 pada 83/83 sampel; air ADC 0
pada 80/83 dan 68–270 pada tiga sampel lainnya; MQ ADC 4095 dan digital 1 pada
83/83 sampel. Kondisi fisik saat tiap sampel tidak diketahui. Semua pembacaan
masih belum diverifikasi dan tidak membuktikan kalibrasi atau keamanan. Startup
mencatat Wi-Fi nonaktif serta `inactive_requested` untuk relay; catatan itu
bukan bukti keadaan kontak fisik. LED sensor yang menyala tidak membuktikan
sinyal atau kalibrasi benar. Hasil log versi 6 ini tidak membuktikan perilaku
perintah lampu versi 8; jenis lampu, catu dan polaritas relay masih perlu dicek.

### Build firmware tunggal

`src/main.cpp` adalah sumber firmware dan `include/planter-config.h` adalah acuan pin serta titik relatif. Setelah pemeriksaan rangkaian, pengguna memilih **Project Tasks → nodemcu-32s → General → Build**, lalu melakukan **Upload** sendiri; monitor serial menggunakan 115200 baud. Daya beban pompa dan lampu tetap terputus. Versi 12 meminta OFF dengan asumsi GPIO13 HIGH dan GPIO26 LOW; asumsi tersebut belum membuktikan relay fisik mati.

Setelah versi 6 di-upload oleh pengguna, startup serial menampilkan
`"version":6`, `"water":"enabled_unverified"`, dan
`"mq135":"enabled_unverified"`. Baris `sample` mencantumkan `soil_raw`,
`light_raw`, `uv_raw`, `water_level.adc_raw`, serta `mq135.adc_raw` dan
`digital_raw`. Nol adalah angka ADC yang terbaca, bukan bukti otomatis bahwa
sensor bekerja atau mati. LCD berganti halaman setiap sampel: DHT/tanah,
cahaya/UV, lalu air/MQ. Aplikasi Moss belum menerima data ini karena cloud
belum terhubung.

Build lokal **versi 5** pada 29 Oktober 2026 berhasil untuk ESP32: RAM 22.016 byte dan flash 295.953 byte. SHA-256 `firmware.bin` hasil build adalah `E7EF52E75A5068FA93B1CF266FAF32BB3751FB1A6930AA3A4C505247EBBEE292`.

Build lokal terisolasi **versi 6** berhasil: RAM 22.016 byte, flash 296.569 byte,
dan SHA-256 `firmware.bin` `C44B992F4B031543E76C0E80639D6EE0CCCEE6888076ED834BB845ECF3A42923`.
Tes host untuk format sensor dan level perintah relay lulus menggunakan fixture.
Binari sementara dibersihkan dan build PlatformIO milik pengguna tidak diubah;
log kemudian menunjukkan startup dan pembacaan versi 6. Log tidak membuktikan
pinout, tegangan atau keadaan kontak fisik.

Build lokal terisolasi **versi 7** untuk environment yang sama berhasil, dengan
RAM 22.016 byte dan flash 296.569 byte dilaporkan PlatformIO. SHA-256
`firmware.bin` adalah
`D214D64269B8528978811699C5C1324A523072CF3BC72D76FEC207B635C638E7`; salinan
privat dan batasannya ada di
`analysis/platformio/firmware-v7-diagnostic-d214d64269b8/`. Build belum
di-upload atau diuji pada ESP32.

Versi 7 mengevaluasi **pratinjau saja**: tanah di bawah 50% menghasilkan
`pump_on: true`, cahaya di bawah 60% menghasilkan `growlight_on: true`, dan air
di bawah 20% menghasilkan `water_low: true` bila skala relatif air sudah
dikonfigurasi. Pada nilai tepat 50/60/20 hasilnya `false`. Nilai hilang atau
skala air yang belum ditentukan menghasilkan `null`. Tanah/cahaya masih memakai
skala historis belum diverifikasi; titik air kosong/penuh belum diketahui dan
skala air dinonaktifkan. JSON menandai perhitungan `diagnostic_only`, sedangkan
`pump_state` dan `growlight_state` tetap `null`; LCD menambahkan halaman
`PRV PUMP`/`PRV LIGHT`, yang bukan keadaan kontak atau perintah relay. Wi-Fi,
cloud, notifikasi dan otomasi aktuator nyata tetap belum aktif.

Tes host mencakup ambang, nilai hilang, titik air contoh dua arah dan JSON;
fixture C++ juga diparsing oleh Dart. `flutter analyze` bersih. Tes terisolasi
untuk model dan widget perangkat lulus 13 kasus dengan fixture tema, tanpa
renderer 3D. Tes Flutter proyek penuh tidak selesai dalam delapan menit ketika
kompilasi shader `flutter_scene`; APK baru dan pengujian ponsel belum tersedia.

Build lokal terisolasi **versi 8** berhasil untuk environment yang sama: RAM
22.072 byte, flash 298.297 byte, SHA-256 `firmware.bin`
`604E839AF45332804605E3262CBDE01297C8505E275245F6764C1A6A44B27FE0`.
Salinan dan batasannya tersedia di
`analysis/platformio/firmware-v8-no-604e839af453/`. Saat build dibuat, build
tersebut belum di-upload atau diuji pada perangkat. Log terpisah kemudian
menunjukkan startup versi 8, tetapi tidak membuktikan bahwa binari dengan hash
tersebut terpasang. Tes host lulus dengan fixture; tidak membuktikan keadaan
kontak, tegangan, polaritas relay, maupun watchdog fisik.

Versi 8 mengikuti kode lampu awal: asumsi input aktif-HIGH, perintah ON di bawah
60% dan OFF di atas 80%, dengan waktu minimum 30 detik setiap keadaan. Kedua
relay diminta OFF saat setup; ada jeda startup lima detik. Angka 0/4095 pada
ADC cahaya dianggap tidak cukup andal untuk kendali dan meminta lampu OFF.
Perhitungan cahaya menggunakan skala historis yang belum dikalibrasi. Perintah
dan alasannya ditampilkan di LCD dan JSON sebagai `pump_cmd`/`growlight_cmd`;
`pump_state` dan `growlight_state` tetap `null` karena kontak tidak diukur.
Saat perintah otomatis tersedia, `control_preview` menjadi `null` agar hasil
hipotetis tidak disalahartikan sebagai perintah yang sedang berlaku.

Pompa **tidak akan diminta ON** pada konfigurasi ini: skala air belum tersedia
dan skala tanah belum dikonfirmasi. Setelah kedua skala diperiksa dan diaktifkan,
aturan lokal menggunakan ON di bawah 50%, OFF pada 55% atau lebih, serta inhibisi
air di bawah 20%/tidak tersedia, durasi maksimal 30 detik dan jeda 5 menit,
termasuk setelah boot. Input ADC pada batas, sampel kedaluwarsa 15 detik atau
watchdog yang tidak tersedia meminta OFF. Firmware meminta watchdog task 8 detik;
pengaman software hanya bekerja dalam batas runtime dan tidak menjamin keadaan
kontak pada boot, hang, kegagalan rangkaian atau relay lengket. Wi-Fi dan cloud
tetap nonaktif; tidak ada notifikasi push atau model ML pada build ini.

Build lokal terisolasi **versi 9** berhasil untuk environment yang sama: RAM
22.072 byte, flash 298.793 byte, SHA-256 `firmware.bin`
`B62AB9B527692702C681CE45835A551DC7605480E22B8D1901D09EE4672FFC8C`.
Salinan dan batasannya berada di
`analysis/platformio/firmware-v9-water-reference-b62ab9b52769/`. Build ini
belum di-upload atau diuji pada perangkat. Tes host lulus untuk asumsi level
GPIO, batas acuan air, interlock, timer dan format telemetri; tes tersebut bukan
pengujian kontak atau tegangan fisik.

Versi 9 mengembalikan **asumsi** pompa aktif-LOW dari kode awal: OFF meminta
GPIO13 HIGH, ON meminta LOW. Lampu tetap diasumsikan aktif-HIGH. Ini hanya
kandidat koreksi karena polaritas masukan relay belum diperiksa; sambungan
bypass, kontak atau penyebab lain masih mungkin. JSON baru menampilkan
`pump_gpio_level_requested` dan `growlight_gpio_level_requested`, yaitu level
yang diminta, bukan pengukuran level listrik atau keadaan kontak. Perintah ON
pompa tetap dihambat selama skala tanah dan air belum dikonfirmasi.

Acuan air dari pengguna dipakai sebagai perbandingan ADC mentah pada LCD dan
JSON: hingga 850 rendah, 851–899 mendekati batas, dan 900 ke atas di atas acuan;
ADC 0 dan 4095 tetap ambigu. Acuan ini belum diverifikasi, bukan persentase atau
jaminan air tersedia, dan tidak mengaktifkan pompa. UV tetap ADC mentah, bukan
perkiraan yang diturunkan dari LDR; MQTT, Wi-Fi, cloud, notifikasi dan model ML
belum diaktifkan pada build ini.

Build lokal terisolasi **versi 10** berhasil untuk environment yang sama: RAM
22.184 byte, flash 302.625 byte, SHA-256 `firmware.bin`
`A1EEFAA4685731BD5339D4BB99A3ED5EEA92DBAA2A46F49C810560367B43953B`.
Salinan dan batasannya berada di
`analysis/platformio/firmware-v10-sensor-quality-a1eefaa46857/`. Tes host,
parsing enam fixture JSON, dan penerimaan fixture oleh parser snapshot serial
Moss yang ada lulus. Parser tersebut belum menggunakan label/kualitas baru.
Saat build dibuat, binari tersebut belum di-upload atau diuji pada ESP32;
pekerjaan build tidak membuka port serial. Log berikutnya menunjukkan startup
yang melaporkan versi 10 dan sampel perangkat, tetapi hash binari terpasang,
tegangan, serta kontak fisik belum diverifikasi.

Versi 10 mempertahankan asumsi relay pompa aktif-LOW sebagai **kandidat**,
tetapi menahan perintah ON pompa dan lampu. Lampu dilaporkan panas sehingga
otomasi lampu dinonaktifkan pada `kLightAutomationEnabled`; ini bukan bukti
kontak terbuka. `kSoilPowerWiringVerified` default `false`: GPIO25 dikonfigurasi
input, tanah dilaporkan `null`/`not_configured`, dan pemeriksaan fisik tetap
wajib sebelum daya diberikan. Input GPIO tidak mengisolasi kabel atau membatasi
tegangan sensor. Mengubah konfigurasi hanya setelah pemeriksaan nyata; jangan
anggap pengaman software menggantikan pemeriksaan listrik.

Setiap sampel versi 10 memuat versi firmware, `uptime_ms`, dan
`recorded_at_utc:null` karena tidak ada jam kalender tepercaya. Label kualitas
ADC membedakan batas 0/4095, rentang tengah, dan data tidak tersedia tanpa
menyimpulkan sensor rusak atau kondisi fisik. MQ juga melaporkan
`adc_pin_mv_estimate` bila ADC2 berhasil dan bukan pada batas; sumber konversi
eFuse atau perkiraan default dicatat terpisah. Angka tersebut adalah perkiraan
tegangan **pin ESP32**, bukan tegangan modul yang telah dikoreksi pembagi,
bukan bukti tegangan aman, dan bukan kalibrasi gas. `co2_ppm` dan
`air_quality` tetap `null`; pemanasan dan kompensasi suhu/kelembapan belum
diverifikasi atau diterapkan. DHT tetap dicatat sebagai konteks belum
terverifikasi, bukan koefisien tropis yang dianggap universal.

Build lokal terisolasi **versi 11** berhasil: RAM 22.184 byte, flash 302.953
byte, SHA-256 `firmware.bin`
`1800B161632D22E5EE5710764D0DCEF1B2417CD3A82B9D093B5B2778DF0035F9`.
Salinan dan batasannya ada di
`analysis/platformio/firmware-v11-soil-adc-1800b161632d/`. Tes host,
parsing tujuh fixture JSON dan kompatibilitas parser snapshot Moss lulus. Saat
build dibuat binari belum di-upload atau diuji pada perangkat. Log berikutnya
melaporkan startup versi 11 dan data ADC tanah, tetapi hash binari terpasang dan
rangkaian fisik belum diverifikasi; pekerjaan analisis tidak membuka port.

Pada versi 10, kode memang tidak membaca tanah saat `kSoilPowerWiringVerified`
false meskipun LED sensor dilaporkan menyala. Versi 11 mencoba membaca GPIO34
secara terpisah dan mempertahankan GPIO25 sebagai input; tidak ada perintah
output GPIO25 pada konfigurasi default. Tes GPIO palsu memeriksa urutan tersebut,
bukan rangkaian fisik. Sumber daya dan tegangan keluaran sensor belum diketahui;
hasil ADC tetap `unverified`. Jika sensor hanya mendapat daya dari GPIO25,
versi ini tidak mencatunya dan hasil mungkin tidak valid. Firmware tidak
melindungi GPIO34 dari tegangan berlebih, dan perintah ON pompa serta lampu
tetap dihambat. Sensor lain tetap dicoba seperti sebelumnya.

Versi 11 menampilkan skala air **perkiraan** berdasarkan rata-rata cuplikan
rendah/hampir penuh: 984/1430 ADC. LCD dan JSON `observation_scale` menandai
skala belum diverifikasi dan bukan untuk kendali; 0% berarti acuan rendah yang
dilaporkan pengguna, bukan tangki kosong, dan 100% berarti acuan hampir penuh,
bukan volume penuh yang diukur. Batas ADC 0/4095 tetap ambigu. Skala kendali
`water_level.relative_percent` dan `low` masih `null`, sehingga tidak membuka
interlock pompa. Acuan lama 850/900 ditandai `historical_conflicting`.

#### Label pengamatan manual

Label tidak dibuat otomatis dari ADC. Monitor serial yang mendukung pengiriman
baris dengan newline dapat mengirim, misalnya `LABEL WATER LOW`,
`LABEL WATER MID`, `LABEL WATER NEAR_FULL`, `LABEL SOIL AIR`,
`LABEL SOIL WATER`, `LABEL SOIL DRY_SOIL`, `LABEL SOIL WET_SOIL`,
`LABEL LIGHT DARK`, `LABEL LIGHT AMBIENT`, `LABEL UV COVERED`, `LABEL UV SUN`,
`LABEL UV SHADE`, atau `LABEL MQ AMBIENT`. Gunakan hanya jika kondisi itu benar
menurut pengamatan operator. Firmware menjawab event `set` lalu menambahkan
`observation_label` dengan sumber `operator_reported` ke sampel berikutnya;
label hanya untuk sensor yang disebut, bukan semua sensor. Label berakhir setelah
180 detik, reset, `LABEL CLEAR`, atau perintah tidak valid. Kirim `LABEL CLEAR`
**sebelum** mengubah kondisi. Jika monitor hanya bisa membaca, catat batas
pengamatan secara terpisah; jangan mengira label terkirim. Label ini bukan
kebenaran independen, tidak mengendalikan relay, dan belum otomatis diekspor
ke CSV oleh firmware.

#### Acuan riset dan keterbatasan

- [Manual Winsen MQ135](https://www.winsen-sensor.com/manual/mq135.html)
  menyatakan respons terhadap beberapa gas, pengaruh suhu/kelembapan, dan
  kondisi uji pemanas 5 V; nilai pemanas, rangkaian, beban dan titik acuan tidak
  dapat ditebak untuk modul ini. Sensor tunggal tidak memisahkan jenis gas dan
  bukan alat ukur CO₂ atau alarm keselamatan yang telah tervalidasi. Kondisi
  pemanasan awal pada datasheet tidak berarti aman membiarkan rangkaian yang
  belum diperiksa menyala lama.
- [Dokumentasi ADC Espressif](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/adc.html)
  membedakan ADC mentah dari konversi tegangan; eFuse atau Vref default dan
  batas rentang pengukuran memengaruhi ketelitian. ADC 5–7 tidak dapat langsung
  ditetapkan sebagai UV index; model sensor dan konversi perlu dibuktikan.
- [Contoh kalibrasi tanah terbuka](https://github.com/makerportal/soil-moisture-cal)
  menunjukkan metode referensi yang bergantung pada sensor dan media. Titik
  atau koefisien sensor lain tidak dipindahkan sebagai kalibrasi rangkaian ini.

Riwayat: log diagnostik versi 4 pernah menunjukkan lima sampel ADC air 0 dan MQ 4095; penyebabnya belum diketahui. Mode uji relay sebelumnya mengirim `ready`, tetapi tidak menampilkan perintah uji diterima. Kedua observasi itu tidak membuktikan keadaan sensor atau kontak relay.

Pada pemeriksaan log `device-monitor-261029-105249.log` tanggal 29 Oktober,
startup mencatat mode tunggal versi 5. Dalam 31 sampel yang diamati (baris
18–78), DHT melaporkan 24,6–24,9 °C dan kelembapan 71–73%; ADC cahaya pada
GPIO32 berubah antara 1151–1357. Keduanya belum diverifikasi atau dikalibrasi.
ADC UV GPIO35 bernilai 0 pada 31/31 sampel; penyebabnya belum diketahui. Versi 5
memang tidak membaca tanah GPIO34 atau mengendalikan GPIO25, dan tidak membaca
water level GPIO33 maupun MQ GPIO27/14. Ketiganya dilaporkan `null`, bukan nol
hasil pengukuran. Status relay `inactive_requested` hanya perintah, bukan bukti
keadaan kontak fisik. Log sedang bertambah saat dibaca; angka ini adalah satu
snapshot, bukan keseluruhan sesi. SHA-256 untuk **13.864 byte awal** log yang
diamati: `B22B109143B0941531E5F7CA36D778E718F8D5D7E376EB3B8D09D24B6CCA9E19`.
Pada CSV eksplorasi yang dibuat dari dua log firmware lama, 732/732 nilai
`uv_legacy_proxy` juga 0. Nilai lama adalah hasil rumus historis, bukan ADC
mentah atau indeks UV terverifikasi, sehingga tidak membuktikan kondisi sensor.

Log versi 6 `device-monitor-261029-111604.log` kemudian memperlihatkan upaya
pembacaan semua sensor yang dikonfigurasi. Snapshot 42 sampel diolah menjadi
`analysis/ml/serial-v6-d52578f94f2b/sensor-observations.csv`; UV dan air berada
di ADC 0, MQ di ADC 4095 pada seluruh 42 sampel tersebut. Nilai mentah dan
penanda batas ADC dipertahankan tanpa menyimpulkan penyebab atau membuat label.
`notes.md` menyimpan hash sumber snapshot dan CSV. Waktu pengukuran per sampel
tidak diketahui; skala tanah/cahaya serta DHT masih belum diverifikasi.
Snapshot berikutnya mencakup seluruh log yang tersedia saat diperiksa, yaitu
175 sampel pada `analysis/ml/serial-v6-9d06d52ed8cc/sensor-observations.csv`.
Pada snapshot tersebut UV 0, air 0, dan MQ 4095 masing-masing terjadi 175/175
kali. Snapshot 42 dan 175 baris saling tumpang tindih; jangan menggabungkannya
tanpa menghapus duplikat berdasarkan file sumber dan nomor baris.
Cuplikan log baru setelah penggantian kabel juga disimpan sebagai CSV privat
`analysis/ml/serial-v6-f3b80aac999f/sensor-observations.csv`: 83 sampel,
dua baris rusak dikecualikan, tanpa label atau waktu kalender tepercaya. Hash
dan rincian kualitas dicatat dalam `notes.md` pada folder yang sama.

Snapshot log `device-monitor-261031-020103.log` pada 31 Oktober mencakup 161
sampel lengkap mulai dari baris pertama log yang tersimpan. File CSV privat
berada di `analysis/ml/serial-calibration-85430ef7dfc0/sensor-observations.csv`;
`notes.md` mencatat hash dan batasannya. CSV 104 sampel yang lebih awal berada
di `analysis/ml/serial-calibration-fca439149be5/`; 104 baris pertamanya sama
dengan snapshot 161 baris dan tidak boleh dihitung dua kali. Log tidak memuat
startup, sehingga versi firmware snapshot ini tidak dapat ditentukan.

Pada 161 sampel tersebut, DHT mencatat 29,1–35,4 °C dan kelembapan 50–71%;
tanah ADC 33–3264, cahaya ADC 0–4007, air ADC 829–1191, dan UV ADC 0–25
(96/161 bernilai nol). MQ ADC 4095 dan digital 1 pada 161/161 sampel; MQ tetap
dalam riset pengguna dan angka itu bukan konsentrasi CO₂. Semua angka sensor
belum diverifikasi. Dua puluh sampel terakhir mencatat tanah 2117–3090 ADC;
rentang ini cukup berubah dan belum menjadi titik kalibrasi stabil. Pengguna
melaporkan probe tanah tercelup selama sesi, tetapi waktu pastinya tidak
tercatat, sehingga label per baris dan titik basah/kering tidak dibuat.

Pengguna kemudian melaporkan mematikan lampu karena panas dan khawatir lem
meleleh. Tidak ada waktu perpindahan lampu yang dapat dicocokkan ke baris
tertentu; perintah relay lampu juga bukan bukti lampu fisik menyala. Log dan
CSV yang sudah ada digunakan tanpa perlu menyalakan kembali lampu untuk sampel.
Seluruh 161 sampel mencatat `pump_cmd:false` dan alasan `water_unavailable`,
sedangkan pengguna secara terpisah melaporkan pompa masih berputar. Ini bukan
bukti kondisi kontak atau penyebabnya; baterai pompa dan catu lampu harus
terputus selama pemeriksaan.

Pada 31 Oktober pukul 03:09:55–03:12:05, 25 sampel baru dari log
`device-monitor-261031-030710.log` direkam ke
`analysis/ml/serial-calibration-1730021a8321-window/sensor-observations.csv`.
Pengguna melaporkan air berada pada batas bawah, dengan perkiraan ketinggian
2–3,5 cm; waktu awal kondisi dan tinggi untuk setiap baris tidak tercatat,
sehingga laporan dicatat dalam `notes.md` tanpa membuat label per baris. ADC air
955–1009, sedangkan MQ ADC 633–639, digital 1; MQ tetap belum terkalibrasi.
Tanah `not_configured` pada seluruh 25 sampel karena pengaman GPIO25; UV ADC 0.
Kedua beban diminta OFF pada seluruh 25 sampel, tetapi keadaan fisik tidak
diukur. Hasil air yang dilaporkan rendah ini berada di atas acuan lama 850 dan
masuk `above_reference`, sehingga klasifikasi lama tidak boleh dianggap batas
aman atau dipakai untuk mengaktifkan pompa.

Pada pukul 03:17:01–03:19:11 direkam 25 sampel tambahan dalam kondisi yang
pengguna laporkan hampir penuh dan menutupi sensor air. CSV berada di
`analysis/ml/serial-calibration-bc156d465b76-window/sensor-observations.csv`;
ADC air 1393–1521, median 1426, dibandingkan median 988 pada cuplikan kondisi
rendah. Kedua rentang tidak tumpang tindih dalam dua cuplikan tersebut, tetapi
tinggi pasti, keadaan konektor, ketepatan dan kestabilan jangka panjang belum
diverifikasi. Tidak ada label per baris yang dibuat dari laporan sesi. Perintah
pompa dan lampu OFF pada seluruh 25 sampel, bukan pengukuran kontak fisik.
Pemeriksaan konektor kering dan pengujian lanjutan masih diperlukan;
pembacaan ini belum mengizinkan pengoperasian pompa.

Atas permintaan pengguna, sampel titik tengah tidak diambil untuk sementara.
Rata-rata aritmetika dari 25 sampel rendah adalah 983,8 ADC dan dari 25 sampel
hampir penuh 1429,92 ADC; titik tengah matematis antara kedua rata-rata adalah
1206,86 ADC. Dua titik ini dapat digunakan sebagai usulan skala relatif linear,
bukan bukti bahwa ketinggian atau volume air benar-benar 50% pada nilai tengah.
Kondisi fisik dan rentang sensor masih belum diverifikasi. Versi 11 menggunakan
nilai dibulatkan hanya untuk tampilan seperti dijelaskan di atas; interlock
pompa tetap tidak boleh diaktifkan.

Pada pukul 03:44:28–03:45:39, log versi 11
`device-monitor-261031-034146.log` menghasilkan 13 sampel tanah setelah
pengguna melaporkan probe terendam air. CSV dan hash disimpan di
`analysis/ml/serial-calibration-a4234a4b3be6-window/`; ADC tanah 1519–2290,
rata-rata 1857,46 dan median 1909, dengan status `unverified` pada 13/13
sampel. GPIO25 dilaporkan input dan catu tanah belum diverifikasi. Rentang ini
cukup berubah-ubah; pencelupan ke air bukan kalibrasi tanah jenuh dan belum
menetapkan titik basah stabil. Tidak ada label kondisi per baris yang dibuat.
Pompa dan lampu diminta OFF pada seluruh sampel, bukan pengukuran beban fisik.

Pada pukul 03:50:07–03:51:17, setelah pengguna meminta pemeriksaan kondisi
kering, direkam 13 sampel versi 11 ke
`analysis/ml/serial-calibration-e3be742fc020-window/sensor-observations.csv`.
ADC tanah 0–662, rata-rata 308,23 dan median 192; satu sampel bernilai 0 yang
masih ambigu. Kondisi kering merupakan laporan sesi pengguna, bukan posisi
probe atau label yang dibuktikan untuk setiap baris. Seluruh 13 sampel berstatus
`unverified` dan mencatat catu tanah belum diverifikasi.

Sebagai pembanding awal, rentang 13 sampel kering tidak tumpang tindih dengan
13 sampel probe terendam di atas (1519–2290, rata-rata 1857,46). Kedua
cuplikan berfluktuasi dan belum menetapkan titik kalibrasi tetap atau ambang
pompa yang aman; probe terendam air juga bukan bukti tanah jenuh. Pompa dan
lampu diminta OFF pada seluruh sampel kering, bukan pengukuran beban fisik.
Hash CSV dan asal data tersimpan dalam `notes.md` pada folder cuplikan.

### Wi-Fi lokal dan aturan lampu versi 12

Build firmware terisolasi berhasil untuk `nodemcu-32s`: RAM 48.576 byte,
flash 784.433 byte, SHA-256 `firmware.bin`
`D9F09DF517BD9B2E6230403D1AA71C881A8E2BC3E472F641C572626BE8A8E16B`.
Binari dan catatan berada di
`analysis/platformio/firmware-v12-local-wifi-d9f09df517bd/`. Tes host dan
kompatibilitas tujuh fixture firmware ke parser aplikasi lulus; pengujian
loopback aplikasi menggunakan data fixture, bukan ESP32 atau radio fisik.

Firmware dan aplikasi lokal disiapkan untuk koneksi langsung: ESP32 membuat
access point WPA2 `Moss-xxxx`; LCD bergantian menampilkan nama jaringan dan
sandi yang dibuat ulang setiap boot. Sandi tidak ditulis ke serial, file atau
telemetri. Ponsel memilih jaringan tersebut, lalu aplikasi menggunakan tombol
**Pengaturan → Hubungkan Wi-Fi lokal**. Ini bukan koneksi ke router dan jaringan
ESP32 tidak menyediakan internet. Protokol hanya baca berupa JSON satu baris
setiap sampel pada `192.168.4.1:3333`; tidak ada perintah aktuator atau
pengiriman ke cloud. TCP sendiri tidak memakai TLS atau autentikasi aplikasi;
siapa pun yang memiliki sandi Wi-Fi dapat membaca data, dan identitas perangkat
tidak diverifikasi di lapisan aplikasi. Pembacaan yang tidak diperbarui 20 detik
dihapus dari tampilan live. Versi ini belum diuji pada perangkat fisik.

Skala tanah tampilan menggunakan rata-rata kering 308 ADC dan terendam 1857 ADC;
0/100% bukan persentase kadar air tanah terukur. Air memakai 984/1430 ADC
untuk rendah/hampir penuh, bukan tangki kosong/penuh. LDR memakai skala historis
belum diverifikasi. UV tetap ADC mentah, bukan UV index atau persen, dan MQ tidak
dijadikan persen kualitas udara. Sensor tetap dicoba dibaca; khususnya ADC2 MQ
dapat gagal saat Wi-Fi aktif dan harus ditampilkan sebagai tidak tersedia.

Aturan lampu yang diuji dengan fixture: OFF bila LDR minimal 70% **atau** UV
index di atas 7; kandidat ON bila LDR di bawah 65% **dan** UV index di bawah 7.
Jika tidak ada kondisi OFF dan kedua nilai tersedia, LDR 65–69% atau tepat
indeks UV 7 mempertahankan keadaan. Nilai tidak tersedia tidak dianggap gelap;
tanpa kondisi OFF yang jelas kandidat menjadi tidak tersedia. UV index 7 bukan
7%, dan UV bukan pengganti
langsung intensitas cahaya yang dibutuhkan tanaman. UV perangkat ini belum
memiliki indeks terkalibrasi, LDR belum diverifikasi, lampu dilaporkan panas,
dan relay fisik belum diperiksa: otomatisasi ON tetap dihambat. Perintah OFF
bukan bukti beban mati; khususnya pengguna pernah melaporkan pompa masih
berputar. Daya pompa dan lampu harus terputus saat pemeriksaan awal.

Contoh publik [SoilMoistureSensor](https://github.com/ajinkyagorad/SoilMoistureSensor)
menyebut ADC kering 3100 dan basah 2200, berlawanan arah dengan dua cuplikan
perangkat ini. Contoh tersebut digunakan hanya sebagai fixture uji arah skala,
bukan dicampur ke pengamatan pengguna atau dijadikan kalibrasi perangkat.

### Tampilan versi 13

Pengguna melaporkan telah meng-upload v12. Firmware v13 disiapkan dan dibangun
lokal, tetapi belum di-upload atau diverifikasi pada perangkat. LCD menampilkan
sandi acak 10 karakter selama sekitar 60 detik pada awal dan 30 detik pada
setiap siklus berikutnya. Sampel tetap dibaca tiap lima detik. Tanda `~` adalah
skala relatif; `--` berarti belum ada nilai yang dapat digunakan. Persen ADC UV
dan MQ bukan indeks UV atau kualitas udara. Pembacaan MQ analog tetap dicoba;
MQ digital ditampilkan jika analog gagal. Suhu tetap memakai °C.

File `include/planter-calibration.local.h` berisi acuan tampilan khusus yang
tidak dikirim ke Git, sedangkan sumber yang disinkronkan memakai nilai contoh
umum. Binari lokal mengandung acuan khusus dan tetap berada dalam `analysis/`.
Build v13: `analysis/platformio/firmware-v13-display-2ac199ce5950/firmware.bin`,
SHA-256 `2AC199CE59501E65A10D2D5005EADDDF600356FE6843A28A27A5E491B041AC46`.
Keadaan relay, kalibrasi, Wi-Fi dan LCD fisik masih perlu diuji dengan aman.
Kode aplikasi dan firmware dikirim ke GitHub sebagai commit `776cca3`; pada
saat ini GitHub Actions melaporkan build beta nomor 9 telah didistribusikan.
Log sensor dan berkas acuan lokal tidak termasuk commit tersebut.

### Uji relay firmware versi 14

Build lokal berhasil: `analysis/platformio/firmware-v14-relay-06b04b3adcd7/firmware.bin`,
SHA-256 `06B04B3ADCD7B4E371B0CA11C5774022BD15066037D4454469A4C19745DCBF77`.
Pengguna melaporkan meng-upload dan mencoba firmware ini; log versi 14 terlihat,
tetapi keadaan kontak belum terukur. Aplikasi build 9 yang sudah didistribusikan
tidak diganti lagi dalam pekerjaan firmware ini.

Atas permintaan pengguna, pompa memakai HIGH untuk ON dan LOW untuk OFF,
kebalikan dari kode legacy; lampu tetap memakai HIGH untuk ON dan LOW untuk OFF
sebagaimana legacy. Ini adalah **perintah GPIO**, bukan bukti keadaan kontak.
Pompa mencoba ON saat tanah relatif di bawah 50% dan air relatif minimal 20%,
dan OFF saat tanah mencapai 55% atau air tidak memenuhi syarat. Lampu mencoba
ON saat LDR di bawah 65% dan proksi UV di bawah 7; OFF saat LDR minimal 70%
atau proksi UV di atas 7. Batas pertengahan mempertahankan keadaan sebelumnya.
Proksi UV hanyalah pemetaan ADC 0–4095 ke skala asumsi 0–14, **bukan indeks UV
terkalibrasi**. Nilai ADC rel 0/4095 atau input yang hilang tidak dianggap data
valid untuk menyalakan beban. Watchdog dan data terlambat tetap meminta OFF;
pompa dibatasi 30 detik per siklus dengan jeda 30 detik.

Semua pembacaan sensor tetap dicoba, termasuk MQ ADC2 yang dapat gagal saat
Wi-Fi aktif. GPIO25 tetap input akibat konflik catu yang belum diverifikasi; jika
sensor tanah hanya mendapat daya dari pin itu, pembacaan belum tentu bekerja.
Pemeriksaan host tidak membuktikan polaritas atau keadaan beban. Sebelum upload
atau uji, pastikan rangkaian aman dan sumber daya pompa serta lampu terputus;
uji indikator relay tanpa beban terlebih dahulu, khususnya karena sebelumnya
pompa dilaporkan berputar meskipun OFF dan lampu dilaporkan panas.

### Revisi ambang pompa versi 15

Acuan basah relatif lokal diperbarui dari rata-rata 15 sampel log terakhir pada
cuplikan uji yang dilaporkan basah; acuan kering tetap memakai pengamatan
sebelumnya. Nilai perangkat dan log tetap lokal, bukan kalibrasi kadar air tanah.
Pompa mencoba ON di bawah 40% relatif dan OFF pada 50% atau lebih. Di antara
keduanya, keadaan sebelumnya dipertahankan. Pembatasan air, watchdog, data
hilang, waktu dan pemetaan GPIO tetap seperti versi 14; aturan lampu dan semua
pembacaan sensor tidak diubah. Pada cuplikan log versi 14 tersebut pompa sudah
diminta OFF; perintah ini tidak membuktikan kontak relay atau beban fisik mati.
Pengujian host mencakup batas ADC, kondisi basah/kering, hysteresis, kegagalan
input dan pemetaan GPIO untuk acuan lokal dan acuan generik.

### Revisi lampu versi 16

Build lokal: `analysis/platformio/firmware-v16-ldr-54e6719c0c86/firmware.bin`,
SHA-256 `54E6719C0C86E19318C32286478DEAAAA575F7F50EF1A4D69F5B44BD4D72A5DE`.
Build ini menggunakan acuan privat lokal dan belum di-upload.

Log versi 14 menunjukkan input UV ADC 0 diperlakukan sebagai tidak tersedia,
sehingga kondisi gelap pada LDR tetap meminta lampu OFF. Berdasarkan pengamatan
pengguna, acuan LDR lokal diperbarui dari kelompok pembacaan terang dan gelap;
angka ADC yang lebih besar menunjukkan lebih gelap. Lampu mencoba ON saat
kecerahan LDR relatif di bawah 40% dan proksi UV di bawah 7, serta OFF ketika
LDR minimal 60% atau proksi UV di atas 7. ADC UV 0 dipakai sebagai proksi
rendah sesuai permintaan, tetapi 0 juga mungkin merupakan kesalahan sambungan;
proksi tersebut bukan indeks UV terkalibrasi. Data LDR hilang/rel dan UV yang
benar-benar tidak tersedia tidak menyalakan lampu. GPIO26 tetap HIGH untuk
meminta ON dan LOW untuk meminta OFF; perintah bukan keadaan beban yang diukur.

### Diagnostik pompa versi 17

Build lokal: `analysis/platformio/firmware-v17-pump-debug-3ce1984e91b2/firmware.bin`,
SHA-256 `3CE1984E91B2C7335BE8CD2047DCCCAE402D7FD29A8BC06B5391D9EE8A36B32A`.
Build ini mengandung acuan privat dan belum di-upload.

Firmware lokal menambahkan diagnostik tanah `dry`, `wet`, `hold` dan
`unavailable`. Kering berarti di bawah ambang ON 40%; basah berarti minimal
ambang OFF 50%; di antaranya keadaan sebelumnya dipertahankan. Status ini
hanya pengelompokan berdasarkan skala relatif yang belum diverifikasi, bukan
pengukuran kelembapan terkalibrasi. Nilai hilang atau rel ADC tetap tidak
tersedia. Pada LCD halaman relay, `KERING`, `BASAH`, `TAHAN`, atau `N/A`
ditampilkan bersama `P:ON/OFF cmd`; `cmd` adalah perintah, bukan keadaan kontak.
Telemetri juga memuat `pump_soil_debug`, `pump_reason`, `pump_cmd`, dan level
GPIO yang diminta. Pengaman air, watchdog dan waktu tidak diubah; hasil kondisi
tanah tidak mengesampingkan pengaman itu. Tes host memakai acuan lokal dan
generik serta sampel sintetis; perangkat fisik belum diuji. Firmware belum
di-upload oleh pengguna.

Pada enam sampel terakhir dari log v14 yang sudah tersimpan, semuanya meminta
`pump_cmd:false` dan GPIO13 `LOW`: lima beralasan `soil_not_dry` dan satu
`water_low`. Ini hanya mengamati keluaran perangkat lunak pada cuplikan lama,
bukan keadaan pompa saat ini atau kontak relay. Sumber lokal:
`.opencode-tmp/serial-monitor/logs/device-monitor-261031-134622.log`, 2.525.075
byte, SHA-256 `957DCE7991BC6E92C9A4EFDF61C0B6095C2BAA4C2AA66F2863B17FE7A67FD988`;
pemeriksaan memakai 32.768 byte terakhir dan tidak membuka port serial.

Pada pemeriksaan berikutnya, cuplikan log v17
`.opencode-tmp/serial-monitor/logs/device-monitor-261031-171121.log` berisi
41 sampel lengkap dalam 94.420 byte pertama (SHA-256 cuplikan
`BD2A17D4F7AD0B9F08BB556BF1935FCCFCF472C7B2562B6000FE768E3BF13983`).
Sebanyak 20 sampel terakhir, uptime 106.599–201.638 ms, melaporkan tanah 100%
relatif, band `wet`, perintah pompa OFF, GPIO13 LOW dan alasan `soil_not_dry`.
Pembacaan ini sesuai laporan pengguna bahwa probe sedang di air, tetapi tidak
membuktikan keadaan fisik relay atau pompa. Port serial tidak dibuka oleh agen.

Setelah pengguna melaporkan probe tanah sudah kering, cuplikan 65.536 byte
dari log yang sama, offset 350.567 pada panjang 416.103 byte, SHA-256 cuplikan
`6C98E6064E7B6F3C975737C8318D2496F917EEF565541F26E9557537EC27202C`,
menunjukkan sepuluh sampel terakhir semuanya tanah ADC 0 / band `unavailable`,
pompa OFF / GPIO13 LOW dengan alasan `water_low`. Pada cuplikan berikutnya,
pembacaan tanah berubah dari wet menjadi ADC 0 bersamaan dengan turunnya skala
air di bawah ambang; penyebabnya belum diketahui. Rel ADC 0 bisa merupakan
ekstrem nyata atau gangguan suplai/sambungan. Tidak ada bypass pengaman atau
kesimpulan mengenai kontak relay, dan agen tidak membuka port serial.

### Perbaikan interpretasi air versi 18

Build lokal: `analysis/platformio/firmware-v18-low-water-de50b8d10bab/firmware.bin`,
SHA-256 `DE50B8D10BABAF9943A80C7B7E9E1800119E9B3455F39FCF4E06C9744056F90F`.
Build ini mengandung acuan privat dan belum di-upload.

Pengguna melaporkan kisaran ADC air sekitar 700–800 pada ketinggian sekitar
2–3 cm, diperkirakan seperdelapan wadah dan hampir habis. Perkiraan ini bukan
kalibrasi volume. Pada cuplikan log berikutnya, sepuluh sampel mencatat ADC air
870–916 dengan pengaman `water_low`, tanah ADC 0 dan pompa OFF / GPIO13 LOW;
kondisi fisik tidak diverifikasi oleh agen. Sumber lokal: 65.536 byte pada
offset 444.427 dari log v17 di atas, panjang snapshot 509.963 byte, SHA-256
cuplikan `4E5B9B778F2190C941792120A914DB2B673393AAE3A8A08CB8EA899500CC8B15`.

Versi 18 mempertahankan pengaman dan ambang pompa, tetapi tidak lagi menyajikan
skala air yang dijepit ke 0 sebagai persentase isi wadah yang pasti. Di LCD,
kondisi di bawah ambang ditandai `Air:RENDAH ref`; telemetri mempertahankan ADC
mentah, `low`, dan `control_band`. Aplikasi yang ada dapat menampilkan ADC
ketika persentase tidak tersedia. ADC tanah 0 tetap ambigu dan tidak dipakai
untuk menyalakan pompa. Tes host dan kompatibilitas aplikasi menggunakan data
buatan; build ini belum di-upload atau diuji pada perangkat fisik.

### Brownout setelah laporan pengguna

Cuplikan log `.opencode-tmp/serial-monitor/logs/device-monitor-261031-174226.log`
berisi 5.865 byte dengan SHA-256
`3967F69892E40444CDD1EBEC20520151FA3A5C15C46AA02291C7926255D344EE`.
Cuplikan tersebut memuat 15 pesan brownout dan 16 header reset, tanpa pesan
startup firmware atau sampel sensor yang dapat dikenali. Ini menunjukkan
pengulangan reset terkait tegangan rendah, tetapi tidak menentukan versi
firmware terpasang, penyebab penurunan tegangan, atau keadaan kontak relay.
Jangan menonaktifkan brownout detector; putuskan sumber daya beban dan pastikan
catu serta pengkabelan aman sebelum pengujian lanjutan. Agen tidak membuka port.

### Pembaruan Moss untuk data langsung

Aplikasi mencoba tersambung otomatis ke ESP32 melalui jaringan `Moss-xxxx` dan
mencoba kembali ketika koneksi putus. Nilai lama dihapus saat data tidak lagi
tersedia. Pilihan mode simulasi, grafik contoh dan kartu model sintetis tidak
ditampilkan. Riwayat belum disimpan; aplikasi tidak mengarang riwayat. Skala
tanah, air, cahaya, UV dan MQ masih memiliki keterbatasan kalibrasi, dan
perintah relay bukan bukti keadaan kontak. Pengujian koneksi pada ponsel fisik
masih diperlukan.

Pembaruan aplikasi dikirim ke `main` dalam commit `c28b826`. Pemeriksaan lokal
lulus: format, analisis dan 95 tes; dua tes ekspor cloud dilewati karena
simulasinya tidak dikonfigurasi. Hasil build dan distribusi Firebase belum dapat
diverifikasi dari sesi ini. Firmware, acuan kalibrasi dan log tetap lokal.

### Konfirmasi kondisi air penuh dan tampilan aplikasi

Pengguna kemudian mengonfirmasi bahwa pembacaan air sekitar **1711–1777 ADC**
yang ditemukan di log lama adalah kondisi **penuh**. Ini adalah laporan pengguna
untuk sesi tersebut, bukan label yang direkam pada setiap baris atau verifikasi
tinggi air secara independen. Log v10
`.opencode-tmp/serial-monitor/logs/device-monitor-261031-030710.log`, snapshot
576.595 byte dengan SHA-256
`8BACD2F7844E3A6D28E96BE46DABA1AACD02DFD54914424233F34257BDACC2CD`,
memuat kedua nilai itu; label dan waktu kalender per sampel tidak tersedia.
Catatan ini tidak mengubah bukti lama. Cuplikan terpisah yang sebelumnya
dilaporkan hampir penuh tetap 1393–1521 ADC seperti dicatat pada
`analysis/ml/serial-calibration-bc156d465b76-window/notes.md`.

Aplikasi mengelompokkan hasil firmware menjadi Low/Medium/Full secara kasar.
`low:true` atau skala di bawah 20% berarti Low, 20% sampai di bawah 90%
Medium, dan minimal 90% Full. Acuan 100% firmware saat ini berasal dari
pengamatan *hampir* penuh yang lebih rendah daripada laporan penuh di atas;
karena itu Full bisa muncul sebelum wadah benar-benar penuh. Batas tersebut
sementara, bukan kalibrasi isi atau ukuran tinggi air, dan tidak mengubah
ambang atau pengaman pompa. Data hilang, rel ADC, atau input yang bertentangan
tidak diklasifikasikan. Angka acuan lokal tidak dimasukkan ke aplikasi.

Pembaruan aplikasi versi 0.3.6 dikirim ke `main` dalam commit `3de75e0`.
Pemeriksaan lokal memakai salinan terisolasi: format dan analisis Flutter
bersih, 98 tes lulus, dan dua tes simulasi cloud dilewati karena simulasinya
tidak disiapkan. Tes mencakup level air, input tidak valid, tampilan sempit,
dan stream loopback sintetis. Tes host serta kompatibilitas delapan frame
firmware v18 sintetis juga lulus; tidak ada perangkat yang dihubungi. Build
GitHub Actions dan distribusi Firebase belum terverifikasi dari sesi ini.
Firmware lokal, log, acuan privat, dan perubahan lain tidak masuk commit.

Cuplikan log `.opencode-tmp/serial-monitor/logs/device-monitor-261031-174411.log`
yang diperiksa setelah build berisi 10 sampel lengkap dan melaporkan versi 18;
snapshot 25.698 byte memiliki SHA-256
`CF3E8490C78AA1892C6EF4920E062772D5E090DD8C2C3706D1924CC17F37CA29`.
ADC tanah awalnya bukan rel, lalu menjadi 0; penyebabnya belum diketahui. MQ
melaporkan pembacaan analog gagal dan digital 1. Ini adalah pengamatan pada log,
bukan bukti hash binari terpasang, sambungan, atau kondisi sensor saat ini.
Agen tidak membuka port serial atau mengubah pengkabelan.

### Rujukan MQ135 dan keterbatasan sambungan

[Manual Winsen MQ135](https://www.winsen-sensor.com/manual/mq135.html)
menyebut kondisi standar pemanas dan rangkaian 5 V, pra-pemanasan awal lebih
dari 48 jam, serta respons terhadap beberapa gas. Hambatan sensor dalam
rangkaian contoh adalah `Rs = (Vc / Vrl - 1) * RL`; rasio `Rs/R0` harus
dibandingkan dengan kurva dan kondisi rujukan yang sesuai. Ini bukan bukti
bahwa modul yang terpasang sudah memenuhi kondisi itu, atau bahwa konsentrasi
CO2 dapat ditentukan secara unik. Catu modul, RL, tegangan keluar, suhu,
kelembapan, dan kondisi referensi belum diverifikasi.

Menurut [dokumentasi ADC Espressif untuk ESP32](https://docs.espressif.com/projects/esp-idf/en/v4.4.7/esp32/api-reference/peripherals/adc.html),
GPIO27 menggunakan ADC2 yang berbagi sumber daya dengan Wi-Fi. Catatan v10
yang menunjukkan angka analog dibuat saat Wi-Fi nonaktif; v18 melaporkan
`adc_read_failed` saat Wi-Fi aktif, sesuai keterbatasan tersebut namun tidak
mengesampingkan masalah fisik lain. Digital `1` hanya level pin komparator,
bukan ppm atau bukti udara bersih. Jangan mengubah catu atau sambungan tanpa
memastikan pinout, tegangan A0/D0 yang aman untuk ESP32 dan ADC1 yang bebas.

### Peninjauan ulang peta pin Excel

Workbook `Tata letak kabel ESP32 Iot Smart Planter.xlsx` dibaca ulang secara
read-only; SHA-256 tetap
`ECA694971F397F236EE6B8E5708366344C477488528FCCCC2B4E37C58B30ED5A`.
`Sheet1` baris 42–43 mencatat `SVN` dan `SVP` kosong. Kandidat rencana adalah
memindahkan **A0 MQ135 dari P27 ke SVP/VP (GPIO36, ADC1 channel 0)** setelah
memastikan label dan ketersediaan pin fisik serta batas tegangan sinyal. VN
(GPIO39, ADC1 channel 3) merupakan alternatif setelah diperiksa. Pemetaan
VP/VN ini mengikuti [referensi pin Espressif](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html#header-block),
bukan verifikasi fisik papan. GPIO36 dan GPIO39 hanya input.

Sinyal tanah P34 sudah memakai ADC1; belum ada bukti bahwa ADC tanah 0
disebabkan konflik ADC2/Wi-Fi. Terdapat pertentangan catatan catu dan label
tanah serta ground air sebagaimana audit Excel di atas; periksa sebelum
memberi daya. GPIO14 untuk D0 MQ, GPIO4 DHT, serta GPIO13/26 relay digunakan
secara digital dan tidak perlu dipindahkan hanya karena punya fungsi ADC2.
Rencana MQ memerlukan perubahan firmware: `readMqRaw` saat ini memakai ADC2
channel 7 dan karakterisasi ADC2. Kabel, firmware, dan port serial tidak
diubah atau diakses dalam peninjauan ini.

### Firmware lokal v19: SVP, diagnostik pompa dan lampu LDR

Setelah peninjauan tersebut, pengguna **melaporkan** A0 MQ dipindah ke SVP;
kode v19 sekarang menggunakan GPIO36 / ADC1 channel 0 serta karakterisasi ADC1.
Sambungan nyata dan tegangan A0/D0 belum diverifikasi. MQ tetap melaporkan ADC
dan digital saja: tidak ada perhitungan ppm atau klaim kualitas udara.

Pompa memakai satu batas pada rata-rata ADC tanah: 1–1199 meminta ON dan 1200
atau lebih meminta OFF; 0, 4095, serta data hilang tidak dapat menyalakan pompa.
Penjagaan air rendah/tidak tersedia, watchdog, sampel basi, maksimum 30 detik
menyala dan jeda 30 detik tetap aktif. Kondisi tanah saja bukan jaminan bahwa
pompa boleh ON. Lampu memakai LDR saja, ON di bawah 40% relatif dan OFF pada 60%
ke atas, dengan zona tahan dan jeda sebelum menyalakan kembali. UV tetap untuk
pemantauan, bukan syarat lampu. Tanah, cahaya, UV, air dan MQ analog memakai
rata-rata lima konversi berturutan setiap siklus lima detik. Bila ada kegagalan
baca atau sampel rail bercampur nilai lain, nilai menjadi tidak tersedia; lima
nilai rail seragam tetap ditampilkan mentah tetapi tidak mengizinkan kontrol
pompa/lampu. DHT dan MQ digital tidak dirata-ratakan.

Build lokal: `analysis/platformio/firmware-v19-adc1-1b3eabab3efe/firmware.bin`
(792704 byte), SHA-256
`1B3EABAB3EFEF6E27788ED5E6708E70775CBCB3FD6F9959E67D11A83ED9F2364`.
Image aplikasi ini mengandung acuan privat dan belum di-upload. Tes host lulus
dengan acuan lokal dan umum; masing-masing mencakup seluruh 4094 nilai ADC
non-rel dari kedua keadaan awal, pengaman, 15 frame sintetis dan loopback tiga
frame pada parser aplikasi. Panjang frame terbesar yang diuji 2599 byte dari
buffer firmware 3072 byte; rincian dan hash input ada pada `notes.md` build.
`esptool image_info` memvalidasi checksum dan hash internal image tanpa
terhubung ke perangkat. Catatan bukti lokal tersimpan pada folder build yang
diabaikan Git.
Tes tidak menghubungi ESP32 atau membuktikan radio, aplikasi terpasang, sensor,
kontak relay, catu ataupun pengkabelan fisik.

Aplikasi 0.3.6 tetap menerima data dan perintah ON/OFF sintetis dalam tes,
namun belum mengenali alasan lampu `ldr_low`, `ldr_sufficient`, dan
`ldr_input_unavailable`; teks alasannya dapat tidak muncul. Perintah bukan
pengukuran kontak. Pompa pernah dilaporkan tampak menyala saat perintah OFF dan
pernah ada brownout; penyebabnya belum diketahui. Sebelum upload atau memberi
daya ke beban, putuskan daya beban dan verifikasi tegangan A0/D0 serta catu,
polaritas relay, kontak dan sambungan sensor. Jangan memublikasikan binari ini.

### Pengamatan MQ135 setelah pengguna melaporkan pembacaan muncul

Prefix 81.462 byte dari log yang sudah ada,
`.opencode-tmp/serial-monitor/logs/device-monitor-261031-190206.log`, memiliki
SHA-256 `51EAE2107D6AD5C550C9354D722D564E2ED17E7C584B7E6D6087AC01D31A294E`.
Cuplikan ini memuat satu startup dan 33 sampel lengkap firmware yang melaporkan
v19, dengan uptime 1.550–161.821 ms. Seluruh 33 sampel melaporkan ADC1 MQ
non-rel; rata-ratanya **504,82 ADC**, rentang **458–521 ADC**, dan rata-rata
10 sampel terakhir **500,00 ADC**. Semua nilai digital dalam cuplikan adalah 1;
itu hanya level komparator, bukan kesimpulan mutu udara. Firmware melaporkan
perkiraan tegangan pada pin ADC dengan sumber `efuse_vref`: rata-rata 546,09 mV,
rentang 509–559 mV. Ini bukan pengukuran multimeter atau bukti tegangan A0 dan
D0 selalu aman. Rata-rata tersebut dihitung dari keluaran per siklus, yang
masing-masing sudah dilaporkan sebagai rata-rata lima konversi berturutan.

Pengamatan ini belum membuktikan sensor stabil, udara bersih, lama pemanasan
heater, hash firmware terpasang, atau kondisi sambungan fisik. Log tidak memuat
gas rujukan, nilai RL, tegangan rangkaian/sensor, ataupun rasio pembagi bila
ada. Karena itu angka di atas **belum dipakai sebagai R0, ppm, atau kalibrasi
kualitas udara**. Manual Winsen mencantumkan kondisi uji standar, pemanasan awal
lebih dari 48 jam, sensitivitas terhadap beberapa gas, serta rumus
`Rs = (Vc / VRL - 1) × RL`; perkiraan tegangan GPIO tidak otomatis sama dengan
VRL modul. Rujukan: [manual MQ135 Winsen](https://www.winsen-sensor.com/manual/mq135.html)
dan [ADC ESP32 Espressif](https://docs.espressif.com/projects/esp-idf/en/v4.4.7/esp32/api-reference/peripherals/adc.html).
Log asli dan bukti lokal dipertahankan; agen tidak membuka port serial.

Aplikasi Moss **0.3.7+12** (commit `1473500`) menampilkan ADC MQ terbaru,
rata-rata hingga 12 sampel dalam jendela 60 detik uptime, arah sinyal, dan
perkiraan tegangan pin. Rata-rata dibersihkan saat data putus, gagal baca,
atau mencapai rel. Kartu menyatakan nilai ini **bukan CO₂/ppm**. Pemeriksaan
lokal: `flutter analyze` bersih, 105 tes Flutter lulus, dua tes simulasi cloud
dilewati, dan smoke test socket lokal lulus. Workflow GitHub/Firebase tidak
dapat diverifikasi dari sesi ini karena repo privat dan `gh` tidak tersedia;
periksa tab Actions dan App Tester. Dokumen aplikasi menyebut sensor CO₂ optik
seperti SCD41 sebagai jalur yang dapat dikalibrasi, bukan MQ135.

### Firmware lokal v20: lampu 65% dan kalibrasi tanah 308–1800

Lampu sekarang memakai **LDR saja dengan satu ambang**: kecerahan relatif di
bawah **65%** meminta ON dan 65% ke atas meminta OFF. Tidak ada lagi syarat UV
atau zona tahan; UV tetap dikirim sebagai pemantauan. Jeda minimum 5 detik
tetap mencegah perpindahan cepat.

Pengguna menetapkan titik tanah **kering 308 ADC** dan **jenuh 1800 ADC**
(setelah probe direndam). Dengan rentang itu, ambang pompa **1200 ADC** setara
**≈59,8% kelembapan relatif**, sehingga perhitungan pengguna sekitar 60% cocok.
Pompa tetap ON di 1–1199 dan OFF pada 1200 ke atas; ADC 0/4095 atau data hilang
tetap menghalangi ON. Persentase tanah kini dibulatkan agar 1200 tampil 60%,
bukan terpotong menjadi 59%. Pengaman air, watchdog, data basi, maksimum 30
detik, dan jeda 30 detik tidak berubah.

MQ135 ditampilkan sebagai **indeks gas relatif 0–100** terhadap baseline sesi,
ditambah ADC, rata-rata 12 sampel, arah sinyal, dan perkiraan tegangan pin—bukan
CO₂/ppm. Indeks dihitung dari rasio istilah resistansi `(Vc/VRL - 1)` terhadap
baseline yang mengikuti sinyal terbersih; Vc diasumsikan 5 V. Untuk data ML,
fitur yang tersedia adalah ADC, rata-rata, tren, suhu, dan kelembapan; label gas
tidak dikarang. Kalibrasi absolut MQ135 tetap memerlukan R0, Vc, VRL, dan RL
yang terverifikasi.

Build lokal: `analysis/platformio/firmware-v20-single-edge-e29cd1fed4ea/firmware.bin`
(792.784 byte), SHA-256
`E29CD1FED4EAABB8A4450CD3F7F1E7AB7B823F47D3179CC7E47561EEC9DF753B`.
Image aplikasi ini memuat acuan privat, belum di-upload, dan tidak diuji pada
perangkat fisik dalam sesi ini.

### Firmware v21: polaritas relay, tanah 0–1800, air 826–1150

Contoh kerja pengguna mengonfirmasi relay pompa **active-LOW** (ON = LOW,
OFF = HIGH) dan relay lampu **active-HIGH** (ON = HIGH, OFF = LOW). Firmware
sebelumnya memakai active-HIGH untuk pompa, sehingga pin OFF (LOW) justru
menyalakan modul relay. v21 membalik polaritas pompa dan mempertahankan lampu
sesuai contoh; aturan 65% LDR tidak berubah.

Log pengguna menunjukkan tanah benar-benar kering membaca **0 ADC** dan jenuh
**1800 ADC**; 0 karena itu diperlakukan sebagai kering pada perangkat ini,
dengan pengaman air dan watchdog tetap aktif. Pompa memakai histeresis ON di
bawah **1000 ADC**, OFF pada **1200 ADC**, dan jeda rendam **5 menit** setelah
batas waktu 30 detik agar tidak bersiklus cepat. Air dikalibrasi ulang ke
**826 rendah – 1150 penuh**; indikator Full dimulai pada 50% rentang. Semua
input ADC memakai **median 5 sampel**.

LDR perangkat ini memakai arah **ADC lebih besar = lebih gelap**: gelap
**2360 ADC**, terang **0 ADC**. Ambang 65% tidak berubah. Aplikasi juga toleran terhadap beberapa
frame stream rusak tanpa langsung memutus koneksi, dan halaman Perangkat kini
menampilkan status koneksi dinamis serta tarik-untuk-menyegarkan.

Build lokal: `analysis/platformio/firmware-v21-manual-control-f6ac19f83552/firmware.bin`
(788.400 byte), SHA-256
`F6AC19F83552065F1A9945436874717DD79DAF7696DCC6293342E7804B3E8A38`.
Image ini memuat acuan privat dan password AP lokal, belum di-upload, dan
belum diuji fisik.

Aplikasi Moss **0.3.12+17** dikirim ke `main` dalam commit `74c03c4`. Halaman
Perangkat kini memiliki kendali manual pompa (ON 1–30 detik, OFF, AUTO) dan
lampu (ON/OFF/AUTO) lewat socket lokal, serta **scheduler app-side** yang
disimpan di SharedPreferences Android. Jadwal dicek setiap detik dan dikirim
saat aplikasi terbuka serta socket lokal aktif; jadwal yang terlewat lebih dari
2 menit dilewati. Pompa manual dan jadwal tetap dibatasi 30 detik. Password AP
tetap dari header lokal yang diabaikan Git. Pemeriksaan lokal: `flutter
analyze` bersih, **118 tes Flutter lulus**, dua simulasi cloud dilewati.
Distribusi Firebase belum dapat diverifikasi dari sesi ini; periksa Actions dan
App Tester.

### Firmware v23: pompa berjalan sampai tanah basah

Log pengguna `device-monitor-261101-080331.log` memperlihatkan pompa menyala
hanya **5 detik** lalu berhenti dengan alasan `water_low`, menunggu 30 detik,
lalu mengulang pola yang sama. Penyebabnya: ADC air turun dari sekitar 960 ke
sekitar 890 tepat setelah pompa menyala, tepat di bawah ambang 20% (sekitar 891
pada skala 826–1150). Beban pompa sendiri mengganggu bacaan sensor air, sehingga
pengaman air menghentikan pompa yang sebenarnya sehat. Pola 5 detik ON / 30
detik OFF inilah yang terdengar seperti relay klik-klik.

v23 mengubah dua hal:

- Pompa otomatis boleh **menyala terus sampai sensor tanah mencapai 1200 ADC**,
  dengan batas keras **5 menit** per siklus. Jika batas keras tercapai, pompa
  dikunci **30 menit** agar tanah tidak tergenang. Pompa manual dan jadwal tetap
  dibatasi **30 detik**.
- Saat pompa sedang menyala, bacaan air rendah harus bertahan **6 sampel
  berturut-turut (30 detik)** sebelum pompa dihentikan. Saat pompa mati, satu
  sampel air rendah tetap langsung memblokir start berikutnya. Ini memisahkan
  gangguan beban pompa dari tangki yang benar-benar kosong.

Histeresis tanah 1000/1200, kalibrasi tanah 0–1800, air 826–1150, median 5
sampel, dan aturan lampu LDR 65% tidak berubah. Pengguna mengonfirmasi lampu
sudah pas; logika lampu tidak disentuh.

Build lokal: `analysis/platformio/firmware-v23-water-low-confirm-eba51e16/firmware.bin`
(788.448 byte), SHA-256
`EBA51E16A013B7DB49BC38E15328914C3BE1F3611CAC1E4AAB5B67D10FB0EBD7`.
Image ini memuat acuan privat dan password AP lokal, belum di-upload, dan belum
diuji fisik. Tes host lokal dan generik lulus; 16 frame sintetis v23 serta
loopback tiga frame lulus; `esptool image_info` memvalidasi checksum dan
validation hash.

Aplikasi **0.3.12+17** tetap kompatibel; tidak ada perubahan runtime aplikasi
untuk v23. Commit `390512c` memperbaiki daftar jadwal yang tidak bisa diubah saat
dimuat. CI run `41264094618` sukses termasuk distribusi APK tester lewat Firebase
App Distribution.

### Firmware v24: label lockout 30 menit

v24 hanya memperbaiki label diagnostik. Selama lockout 30 menit setelah
`runtime_limit`, alasan pompa tetap `runtime_limit`, bukan `cooldown`. Perilaku
pompa tidak berubah dari v23: otomatis maksimal 5 menit, lockout 30 menit,
manual/jadwal 30 detik, konfirmasi air rendah 6 sampel saat pompa berjalan.

Build lokal: `analysis/platformio/firmware-v24-lockout-label-a4d316b1/firmware.bin`
(788.448 byte), SHA-256
`A4D316B1BB9596585D2D5FD515A827C00A01E0A8D1E72E6C90572355982F320B`.
Tes host lokal/generik, 16 frame sintetis v24, dan validasi `esptool` lulus.

### Firmware v25: relay staging dan log brownout

v25 menambahkan pengaman urutan relay dan diagnostik daya:

- Jika pompa dan lampu harus ON bersamaan, pompa ON lebih dulu dan lampu
  menyusul **150 milidetik** kemudian. OFF selalu langsung; tidak ada penundaan
  untuk mematikan.
- Kedua coil ditahan OFF selama **2 detik** pertama setelah setup. Kontrol tetap
  menunggu boot grace 5 detik dan sampel pertama, jadi relay pertama tidak aktif
  sebelum sekitar 5 detik.
- Setiap boot mencetak satu baris JSON **hanya ke serial**:
  `{"type":"boot","firmware_version":25,"reset_reason":"...","brownout_count":N,"nvs_ready":true}`.
  Hitungan brownout disimpan di NVS dan bertambah setiap reset brownout.
- Brownout detector tetap aktif; tidak dimatikan lewat software.

Build lokal: `analysis/platformio/firmware-v25-relay-staging-9a3671cd/firmware.bin`
(791.664 byte), SHA-256
`9A3671CDBBC95E4E36730856B0957355788F6F65CF40037D193C93F80CCF8A31`.
Tes host lokal/generik, timing relay, 16 frame sintetis v25, dan validasi
`esptool` lulus. Staging hanya mengurangi inrush; adaptor lemah dan pull-up relay
saat boot tetap perlu diperbaiki di hardware.

### Firmware v26: AP password dan status Wi-Fi

`include/local-wifi-secret.local.h` berisi password 19 karakter, sedangkan
buffer firmware hanya 10 karakter. Firmware lama menolaknya lalu mematikan
Wi-Fi, sehingga LCD menampilkan **“Local AP failed”** dan tidak ada jaringan.
Password lokal di header sekarang 10 karakter; nilai aktualnya tetap hanya di
header lokal yang diabaikan Git. Jika header di masa depan tidak valid,
firmware memakai password acak 10 karakter alih-alih mematikan AP.
Status AP dicetak ke serial (`ap_ready`, `ap_failed`, `local_password_rejected`,
dan sebagainya).

Build lokal: `analysis/platformio/firmware-v26-wifi-password-fec68a0a/firmware.bin`
(798.192 byte), SHA-256
`FEC68A0ACBFA116344080A7768F92A34F8A4C1C6A857D31699F7822C0FD04BC5`.
Tes host, 16 frame sintetis v26, dan validasi `esptool` lulus.

### Firmware v28: EMPTY, durasi lampu, manual immediate

- Status air **EMPTY** saat raw ADC ≤450. `LOW` tetap untuk nilai di bawah
  referensi 826; pompa memakai cutoff raw **600**, jadi 700 masih boleh menyala
  dan baru berhenti di bawah 600.
- Seluruh teks LCD menjadi bahasa Inggris: `Water:EMPTY`, `Water:LOW`,
  `Water:~50%`, `P:ON cmd DRY`, `L:OFF cmd`. `cmd` berarti perintah yang
  diminta, bukan keadaan kontak relay; akhiran `ref`/`rel` dihapus.
- Lampu manual menerima durasi 1–1800 detik (maks 30 menit). Setelah durasi
  habis lampu OFF dan tetap manual OFF sampai AUTO dipilih.
- Perintah manual memakai jalur **immediate** (melewati jeda staging 150 ms),
  Wi-Fi modem sleep dimatikan, dan TCP client memakai `setNoDelay(true)` supaya
  perintah pertama setelah idle tidak tertahan.

Build lokal: `analysis/platformio/firmware-v28-empty-lamp-duration-9a1b51c5/firmware.bin`
(798.768 byte), SHA-256
`9A1B51C52A5B7B34663B365C41BCB3E17C1652289E408593D03CFCF400033817`.
Tes host, 16 frame sintetis v28, dan validasi `esptool` lulus.

### Aplikasi Tunas 0.5.0: kontrol, histori CSV, dan model pohon

Nama aplikasi yang terlihat pengguna berubah dari **Moss** menjadi **Tunas ·
Smart Planter**. Moss tetap dipakai sebagai nama profil/karakter pertama, bukan
nama aplikasi. Profil perangkat disimpan di SharedPreferences Android melalui
kanal `moss/profile` dan dapat berisi sampai enam planter.

- Setiap profil punya nama planter, nama karakter, alamat IP/host, port, dan
  pilihan karakter. Alamat dapat diedit agar ESP32 di jaringan yang sama bisa
  dipakai tanpa membangun ulang aplikasi.
- Tombol hubungkan/putuskan memindahkan sesi aktif ke profil yang dipilih.
  Riwayat sesi dikosongkan saat berpindah perangkat.
- Tiga karakter memakai rig primitif yang sama dengan palet, aksesori, dan tempo
  gerak berbeda: **Moss** (daun), **Bara** (topi matahari), **Rintik** (awan
  hujan). Pemilih karakter memakai geser ala game dan tombol konfirmasi.
- Halaman **Riwayat** menampilkan kartu karakter aktif, grafik tanah/air/cahaya,
  dan 14 sampel terakhir. Histori ditulis append-only ke CSV harian per perangkat
  di penyimpanan aplikasi; UI hanya membaca 240 baris terakhir. Tombol ekspor di
  kanan atas menyalin seluruh CSV ke `Downloads/Tunas`.
- **Kendali manual** memakai tombol segmen ON/OFF/AUTO dengan warna dan label
  AKTIF yang jelas. Pompa memakai durasi 1–30 detik; lampu memakai menit + detik
  (1 detik–30 menit). Jadwal juga mendukung durasi lampu.
- Halaman **Perangkat** hanya menampilkan **Tersedia / Tidak tersedia / Tidak
  dapat menampilkan data**; angka ADC mentah tidak lagi ditampilkan di sana.
  Blok "Kendali perangkat" yang redundan di bagian bawah dihapus.
- **Emosi ML** dijalankan di ponsel dengan decision tree 3 kelas (healthy,
  warning, critical) berfitur 8, termasuk interaksi tanah×air. Model dilatih dari
  band agronomi sintetis (holdout 96,2%; 93 node) dan mencakup banjir,
  kekeringan, panas, serta gas tinggi. Aturan ambang tetap menjadi pengaman:
  tanah ≥85% atau air <20% tidak boleh tampil "Nyaman". Ini model demo, bukan
  diagnosis agronomi tervalidasi; CSV ekspor disiapkan untuk retraining dengan
  data nyata.
- Halaman utama menampilkan status "Belum ada perangkat terhubung" dan tidak
  mengarang nilai saat tidak ada sampel.
- **Notifikasi HP native**: peringatan air rendah (<20%, maksimal sekali per 30
  menit) dan ringkasan prediksi setiap 3 jam lewat `NotificationManager` +
  `AlarmManager`. Tombol "Izinkan notifikasi" dan "Tes notifikasi" ada di
  Pengaturan. Data real-time hanya masuk saat aplikasi terhubung; notifikasi
  berkala memakai prediksi terakhir yang tersimpan di alarm.
- Kartu "Belum ada perangkat" yang muncul-hilang di dalam halaman diganti
  **pop-up singkat di atas layar** (4 detik) saat koneksi terputus. Status
  offline yang stabil tetap ada di header.

Alasan ML di ponsel: model sudah berupa JSON dan inferensi pohon murni Dart;
ESP32 klasik tetap menjadi pengendali relay real-time yang deterministik, tanpa
menambah beban flash/RAM atau risiko TinyML. Data tetap di LAN, tanpa server.
Untuk lintas perangkat dalam satu jaringan, firmware masih mode AP (192.168.4.1);
tahap berikutnya adalah mode STA pada hotspot/router bersama agar beberapa ESP32
punya alamat berbeda di jaringan yang sama.

Pemeriksaan lokal: `flutter analyze` bersih, **135 tes lulus, 2 dilewati**.
Versi aplikasi `0.5.0+20`.

### Model XGBoost sintetis lama (arsip)

Catatan: aplikasi 0.5.0 memakai model decision tree 3 kelas di
`assets/ml/plant-health.json`, bukan model XGBoost 6 kelas ini. Bagian ini
dipertahankan untuk mereproduksi eksperimen awal.

Model eksperimental dilatih dengan 60.000 baris buatan berdasarkan rentang
0–100 untuk tanah, air relatif, dan LDR serta UV sintetis 1–14 atau kosong.
Label mengikuti aturan prototipe, bukan diagnosis atau label tanaman nyata.
Data sintetis dan hasil berada di `analysis/ml/xgboost-synthetic-rules-v2/`,
sedangkan skrip pelatihan ada di `tools/ml/train-synthetic-model.py`.
Model dan aturan pembuat label sama-sama cocok 100% pada 12.000 baris holdout
sintetis; itu bukan pengujian independen atas tanaman atau sensor nyata. Pelatihan
ulang pada lingkungan dan versi pustaka yang sama menghasilkan hash CSV, model,
dan fixture yang identik. Evaluator portable Python juga cocok dengan aturan
pada 2.520 kombinasi sintetis di sekitar ambang tanah, air, LDR, dan UV bilangan
bulat/kosong; pengujian ini tidak mencakup validasi sensor atau UV pecahan.

Model ini tetap sebagai hasil eksperimen lokal, tetapi tidak lagi dimuat atau
ditampilkan pada aplikasi yang disiapkan untuk data sensor langsung. Skor
sintetis bukan peluang kesehatan atau kelembapan yang tervalidasi. UV nyata
belum tersedia sebagai indeks terkalibrasi, dan model tidak mengendalikan relay.

Verifikasi sebelum perubahan tampilan v13 memakai salinan kerja terisolasi:
format Dart dan analisis Flutter lulus, **94 tes Flutter lulus** dan dua tes simulasi cloud
dilewati karena fixture-nya tidak dijalankan. Tes mencakup 100 vektor XGBoost,
tampilan model, input air yang hilang/rel ADC, model rusak, dan stream loopback
lokal. Tes host firmware juga lulus menggunakan fixture. Hasil ini bukan uji
APK terpasang, radio Wi-Fi, sensor, atau relay fisik.

Pembersihan sesi menghapus sekitar 5,49 GiB berkas sementara. Pada pemeriksaan
terakhir, Windows masih menahan sebagian `.opencode-tmp/v12-mobile/` (sekitar
1,87 GiB SDK sementara), sehingga folder itu belum seluruhnya terhapus. Log
serial yang sudah ada tetap dipertahankan.

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

Pembaruan lokal berikutnya menambah impor satu sampel JSON serial melalui papan
klip pada aplikasi. Snapshot tidak dianggap live, tidak dikirim ke cloud, dan
data yang ditempel hanya di memori. APK pratinjau lokal dapat menyertakan satu
snapshot bawaan privat yang muncul kembali saat aplikasi dibuka ulang. Tes
Flutter terbaru lulus; tampilan juga diuji dengan satu sampel serial versi 6
yang diamati. Fitur ini belum diuji pada ponsel fisik.

APK pratinjau yang berisi satu sampel privat tersedia di
`analysis/android/moss-serial-preview-7f51b67669a1/moss-serial-preview.apk`.
Tanda tangan debug diverifikasi, package-nya terpisah dari beta, dan kunci debug
sementara dihapus setelah build. APK ini bukan distribusi beta dan data sampel
di dalamnya tidak memperbarui diri otomatis; jangan bagikan secara publik.

Dataset eksplorasi lokal disimpan di `analysis/ml/serial-observations-20261029-040023/sensor-observations.csv` (732 baris dari dua log; 728 memuat suhu dan kelembapan DHT). Kualitas angka masih `unverified`; tidak ada waktu tepercaya per sampel, label independen, data level air, atau MQ. File itu tidak disertakan dalam Git. `notes.md` di folder yang sama mencatat hash input dan output. Jangan menyatakan model terlatih atau hasil prediksi berdasarkan dataset ini saja.

Build beta pertama telah melewati pemeriksaan GitHub Actions dan dikirim ke grup penguji Firebase App Distribution. Pemasangan beta dan pembaruan antarversi pada ponsel masih perlu diuji. APK pratinjau debug lokal tidak memeriksa pembaruan Firebase otomatis. Penggunaan GitHub Actions tetap perlu memperhatikan kuota dan batas biaya akun.

## Keselamatan perangkat keras

Pengguna melaporkan kedua beban sempat menggunakan kontak NC dan kemudian
dipindahkan kembali ke **NO**. Pada relay yang benar-benar tidak bertenaga,
kontak NO seharusnya terbuka; ini tidak menjamin keadaan saat boot, input relay
aktif karena polaritas tidak sesuai, atau kontak lengket. Belum ada pengujian
kontak maupun polaritas fisik yang dicatat. Lepaskan sumber daya pompa dan
lampu saat upload dan pemeriksaan sampai rangkaian aman.

Pengguna melaporkan pompa langsung menyala ketika baterainya disambungkan, saat ESP32 dan modul relay juga mendapat daya. Penyebab keadaan kontak fisik belum diketahui. Daya beban pompa dan lampu harus tetap terputus sampai sambungan dan rangkaian relay diperiksa. Jangan menjalankan kedua beban dengan varian otomatis sebelum masalah tersebut diselesaikan.

Pada audit 29 Oktober 2026, lima baris terbaru dari log berformat program awal menunjukkan **perintah pompa ON**. Nilai tanah yang menjadi dasar otomasi dihitung menggunakan titik dan ambang historis yang belum dikalibrasi; log tidak membuktikan kondisi tanah atau kontak relay. Dalam kode awal, perintah ON dapat tetap bertahan sampai angka estimasi melewati ambang OFF. Pengguna menjelaskan ESP32 dan modul relay juga bertenaga saat pompa langsung menyala; ini konsisten dengan perintah ON yang tercatat, tetapi tidak membuktikan keadaan kontak atau menyingkirkan masalah rangkaian. Pengguna ingin baterai tetap terhubung nantinya, dengan beban normalnya terputus oleh relay; hal itu belum diverifikasi secara fisik dan tidak dapat dijamin hanya dengan membalik level GPIO.

Pada pemeriksaan log berikutnya (`device-monitor-261029-030912.log`, sekitar 03.13), 91 sampel berformat program awal teridentifikasi di bagian akhir log. Enam sampel dengan estimasi tanah di atas ambang OFF mencatat perintah pompa OFF; lima sampel terakhir yang dibaca kembali mencatat ON. Pemeriksaan berikutnya sekitar 03.19 menemukan 240 sampel dalam log yang sama: enam di atas ambang juga tercatat OFF, sedangkan lima sampel terakhir masih mencatat ON. Pengguna melaporkan relay berbunyi dan pompa tetap menyala saat baterai ditempelkan. Waktu kejadian fisik itu belum dapat dicocokkan dengan sampel tertentu; log tidak menunjukkan keadaan kontak, kabel, atau putaran pompa. Pesan awal yang terlihat berasal dari varian otomatis, bukan penanda varian terkunci. Jangan menyimpulkan polaritas fisik hanya dari bunyi atau label perintah.

Program awal menggunakan GPIO13 untuk pompa dengan ON LOW, tetapi lampu GPIO26
dengan ON HIGH. Atas arahan pengguna, versi 8 memakai asumsi lampu awal untuk
keduanya: ON HIGH dan OFF LOW. Asumsi itu **belum terbukti** sesuai dengan kedua
modul fisik. Versi 9 kembali ke asumsi pompa ON LOW sebagai kandidat, bukan
sebagai bukti polaritas. Lampu dapat diminta ON oleh pembacaan cahaya, sedangkan
perintah ON pompa dihambat sampai skala air dan tanah dikonfirmasi. Timer/jeda
pompa sudah ada di kode tetapi belum diuji pada perangkat. Kode tidak dapat
menjamin keadaan selama boot, reset, macet, atau kontak lengket.

Pastikan rangkaian dan tegangan GPIO aman sebelum menyalakan ESP32; baterai pompa dan sumber daya lampu tetap terputus selama upload dan pemeriksaan. Jika memakai multimeter, ukur kontinuitas COM/NO hanya setelah memastikan kontak terisolasi dari semua sumber tegangan. Pada relay SPDT biasa, NO terbuka saat kumparan tidak bertenaga sedangkan NC tertutup; memindahkan kabel ke NC tidak membuat keadaan mati menjadi default.

### Acuan kalibrasi sensor

- **Tanah:** tentukan dua pembacaan stabil pada media yang sama, satu kering dan satu basah, setelah pinout, tegangan, dan catu sensor aman. Persentase hasil dua titik adalah skala relatif untuk kondisi itu, bukan kadar air volumetrik yang terukur. Konstanta historis `SOIL_DRY=0` dan `SOIL_WET=2450` belum terbukti sebagai titik kalibrasi rangkaian ini.
- **Cahaya/LDR:** rentang gelap–terang pada posisi yang sama dapat digunakan sebagai skala relatif. Untuk satuan lux diperlukan acuan luxmeter serta kurva/kalibrasi yang sesuai rangkaian dan sensornya; angka persentase lama bukan hasil lux.
- **UV:** identifikasi jenis dan respons spektral modul, lalu gunakan datasheet dan pengukuran acuan UV yang sesuai. Pembacaan LDR/luxmeter biasa bukan pengganti acuan indeks UV; rumus historis belum terbukti menghasilkan indeks UV yang benar.
- **Suhu/kelembapan udara:** pastikan model DHT yang digunakan dan bandingkan dengan termometer serta higrometer acuan pada kondisi yang sesuai. Hasil bacaan yang gagal tetap tidak tersedia, bukan nol.
- **Water level:** versi 9 menambahkan perbandingan ADC mentah terhadap acuan pengguna 850/900; nilainya belum menjadi level atau persentase terkalibrasi. MQ135 belum menghasilkan konsentrasi tepercaya tanpa rangkaian dan kalibrasi yang sesuai.

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
