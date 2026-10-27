# 🌱 Smart Indoor Planter — IoT & AIoT Ecosystem

Sistem pemantauan dan otomasi tanaman _indoor_ pintar berbasis **ESP32**, dilengkapi arsitektur _Full-Stack Web Dashboard_ bergaya **Apple HomeKit (Bento UI)** menggunakan **Node.js (Express + TypeScript)**, **MySQL (Prisma ORM)**, **MQTT**, dan **Next.js (Tailwind CSS + Recharts)**.

## Struktur Repositori

```text
.
├── platformio.ini                 # Konfigurasi PlatformIO
├── smart-planter.code-workspace   # Workspace VS Code
├── mobile/                        # Prototipe dashboard Android (Flutter)
├── src/                           # Kode firmware ESP32
├── include/                       # Header proyek
├── lib/                           # Library khusus proyek
├── test/                          # Pengujian PlatformIO
└── .vscode/                       # Pengaturan dan rekomendasi ekstensi VS Code
```

Repositori ini berisi proyek firmware ESP32 dan prototipe dashboard Android di `mobile/`. Dashboard saat ini hanya menggunakan simulasi; koneksi sensor, Supabase, notifikasi, dan machine learning belum diimplementasikan. Pin untuk sensor air dan MQ135 masih berupa placeholder nonaktif di `include/extra-sensors.h`. Wi-Fi dan alamat server firmware sengaja dikosongkan sampai pengaturan yang aman tersedia; fungsi cloud belum terhubung. Bagian backend dan frontend web di bawah merupakan panduan dan contoh lama yang masih mengasumsikan server di laptop, bukan arsitektur cloud yang sudah berjalan. Folder proyek backend dan frontend web tersebut belum tersedia di repositori ini.

---

## 🏗️ 1. Arsitektur Sistem & Pemetaan Hardware

### Tech Stack Utama

- **Edge Device (Firmware):** ESP32 (NodeMCU-32S) via PlatformIO (C++/Arduino)[cite: 1, 15].
- **Protokol Komunikasi:** Hibrida **MQTT** (HiveMQ/Mosquitto untuk kontrol _real-time_ 2 arah) & **HTTP REST API** (pengiriman log periodik ke MySQL).
- **Backend & Database:** Node.js, Express.js, TypeScript, Prisma ORM, dan **MySQL** (dilengkapi fitur _1-Click CSV Export_ untuk dataset _Machine Learning_).
- **Frontend Dashboard:** Next.js (App Router + TypeScript), Tailwind CSS (_Apple Glassmorphism & Bento Grid_), Recharts (_Live Time-Series_), dan Lucide Icons.

### Tabel Pinout Hardware (ESP32)

| Komponen                        | Pin ESP32                   | Tipe Sinyal  | Konfigurasi / Logika                                                    |
| :------------------------------ | :-------------------------- | :----------- | :---------------------------------------------------------------------- |
| **DHT11 (Suhu & Lembab Udara)** | `GPIO 4`                    | Digital      | Pembacaan suhu (°C) & kelembapan udara (%)[cite: 15]                    |
| **Soil Moisture (Data)**        | `GPIO 34` (ADC1)            | Analog In    | Kalibrasi `0` (Kering) – `2450` (Basah) $\rightarrow$ `0–100%`          |
| **Soil Moisture (VCC Power)**   | `GPIO 25`                   | Digital Out  | Menyala hanya saat membaca (mencegah korosi)                            |
| **GUVA-S12SD (Sensor UV)**      | `GPIO 35` (ADC1)            | Analog In    | `uvVoltage = (raw * 3.3) / 4095.0`, `uvIndex = V / 0.1`[cite: 15]       |
| **Modul LDR (Cahaya)**          | `GPIO 32` (ADC1)            | Analog In    | `map(raw, 4095, 0, 0, 100)` (`0%` Gelap – `100%` Terang)[cite: 15]      |
| **Relay Pompa Air (Dinamo)**    | `GPIO 13`                   | Digital Out  | **Active-HIGH** (`ON` jika Tanah `< 30%`, `OFF` jika `> 70%`)[cite: 15] |
| **Relay Grow Light (Lampu)**    | `GPIO 26`                   | Digital Out  | **Active-LOW** (`ON` jika Cahaya LDR `< 30%`)[cite: 15]                 |
| **LCD 16x2 I2C**                | `GPIO 21` (SDA), `22` (SCL) | I2C (`0x27`) | Bergantian menampilkan status Iklim & Cahaya tiap 2 detik               |

---

## ⚡ 2. Tahap 1: Setup Firmware ESP32 (PlatformIO)

Bagian ini memperbarui kode `Smart_Indoor_Planter`[cite: 15] agar tetap menjalankan otomasi lokal di LCD sekaligus mengirim data JSON ke server dan menerima perintah **Auto / Manual Override** dari Dashboard.

### 2.1. Konfigurasi `platformio.ini`

Buka file `platformio.ini`[cite: 15] dan tambahkan library `ArduinoJson` serta `PubSubClient`:

```ini
[env:nodemcu-32s]
platform = espressif32
board = nodemcu-32s
framework = arduino
monitor_speed = 115200
lib_deps =
	marcoschwartz/LiquidCrystal_I2C@^1.1.4
	adafruit/DHT sensor library@^1.4.6
	adafruit/Adafruit Unified Sensor@^1.1.14
	bblanchon/ArduinoJson@^7.0.4
	knolleary/PubSubClient@^2.8
```

### 2.2. Full Code `src/main.cpp` (Terintegrasi Wi-Fi, HTTP & MQTT)

Salin kode berikut ke dalam `src/main.cpp`[cite: 15]. Sesuaikan `WIFI_SSID`, `WIFI_PASS`, dan `SERVER_IP` (IPv4 laptop kamu, cek dengan ketik `ipconfig` di CMD):

```cpp
#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <LiquidCrystal_I2C.h>
#include <DHT.h>

// ---------- Konfigurasi Wi-Fi & Server ----------
const char* WIFI_SSID   = "NAMA_WIFI_ATAU_HOTSPOT_KAMU";
const char* WIFI_PASS   = "PASSWORD_WIFI_KAMU";

// Ganti dengan IPv4 Laptop yang menjalankan Backend Express.js
const char* API_URL     = "[http://192.168.1.10:4000/api/telemetry](http://192.168.1.10:4000/api/telemetry)";
const char* MQTT_BROKER = "broker.hivemq.com"; // Public Broker (bisa diganti IP lokal)
const int   MQTT_PORT   = 1883;

const char* TOPIC_TELEMETRY = "smartplanter/moss/telemetry";
const char* TOPIC_COMMAND   = "smartplanter/moss/command";

// ---------- Definisi Pin ----------
#define DHT_PIN         4
#define DHT_TYPE        DHT11
#define SOIL_PIN        34
#define UV_PIN          35
#define LDR_PIN         32
#define SOIL_PWR        25
#define RELAY_LIGHT_PIN 26
#define RELAY_PUMP_PIN  13

#define I2C_SDA         21
#define I2C_SCL         22
#define LCD_ADDR        0x27

// ---------- Konfigurasi Relay ----------
#define LIGHT_ACTIVE_LOW  true
#define LIGHT_LEVEL_ON   (LIGHT_ACTIVE_LOW ? LOW  : HIGH)
#define LIGHT_LEVEL_OFF  (LIGHT_ACTIVE_LOW ? HIGH : LOW)

#define PUMP_ACTIVE_LOW   false
#define PUMP_LEVEL_ON    (PUMP_ACTIVE_LOW ? LOW  : HIGH)
#define PUMP_LEVEL_OFF   (PUMP_ACTIVE_LOW ? HIGH : LOW)

// ---------- Kalibrasi & Threshold ----------
#define SOIL_DRY         0
#define SOIL_WET         2450
#define BATAS_POMPA_ON   30      // Pompa ON jika < 30%
#define BATAS_POMPA_OFF  70      // Pompa OFF jika > 70%
#define BATAS_LDR_KURANG 30      // Grow Light ON jika LDR < 30%

DHT dht(DHT_PIN, DHT_TYPE);
LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);
WiFiClient espClient;
PubSubClient mqttClient(espClient);

// State Sistem
bool pompaNyala = false;
bool lampuNyala = false;
bool autoMode   = true; // true = Rule-Based Otomatis, false = Manual dari Dashboard

// ---------------------------------------------------------------
// Callback MQTT: Menerima Perintah dari Dashboard Apple UI
// ---------------------------------------------------------------
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, payload, length);
  if (error) return;

  if (doc["mode"].is<const char*>()) {
    String modeStr = doc["mode"].as<String>();
    autoMode = (modeStr == "AUTO");
  }
  if (!autoMode) {
    if (doc["pump_on"].is<bool>())      pompaNyala = doc["pump_on"].as<bool>();
    if (doc["growlight_on"].is<bool>()) lampuNyala = doc["growlight_on"].as<bool>();

    digitalWrite(RELAY_PUMP_PIN, pompaNyala ? PUMP_LEVEL_ON : PUMP_LEVEL_OFF);
    digitalWrite(RELAY_LIGHT_PIN, lampuNyala ? LIGHT_LEVEL_ON : LIGHT_LEVEL_OFF);
  }
  Serial.printf("[CMD] Mode: %s | Pompa: %s | Lampu: %s\n",
                autoMode ? "AUTO" : "MANUAL",
                pompaNyala ? "ON" : "OFF",
                lampuNyala ? "ON" : "OFF");
}

void reconnectMQTT() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (!mqttClient.connected()) {
    String clientId = "ESP32-SmartPlanter-" + String(random(0xffff), HEX);
    if (mqttClient.connect(clientId.c_str())) {
      mqttClient.subscribe(TOPIC_COMMAND);
      Serial.println("[MQTT] Terhubung ke Broker & Subscribe Command!");
    }
  }
}

void tampilBaris(uint8_t baris, const char *teks) {
  char buf[17];
  snprintf(buf, sizeof(buf), "%-16s", teks);
  lcd.setCursor(0, baris);
  lcd.print(buf);
}

int bacaTanahPersen() {
  digitalWrite(SOIL_PWR, HIGH);
  delay(300);
  long total = 0;
  for (int i = 0; i < 10; i++) {
    total += analogRead(SOIL_PIN);
    delay(10);
  }
  digitalWrite(SOIL_PWR, LOW);
  int raw    = total / 10;
  int persen = map(raw, SOIL_DRY, SOIL_WET, 0, 100);
  return constrain(persen, 0, 100);
}

const char *statusTanah(int persen) {
  if (persen < BATAS_POMPA_ON)   return "KERING";
  if (persen <= BATAS_POMPA_OFF) return "LEMBAB";
  return "BASAH";
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  digitalWrite(RELAY_LIGHT_PIN, LIGHT_LEVEL_OFF);
  pinMode(RELAY_LIGHT_PIN, OUTPUT);
  digitalWrite(RELAY_PUMP_PIN, PUMP_LEVEL_OFF);
  pinMode(RELAY_PUMP_PIN, OUTPUT);

  pinMode(SOIL_PWR, OUTPUT);
  digitalWrite(SOIL_PWR, LOW);

  Wire.begin(I2C_SDA, I2C_SCL);
  dht.begin();

  lcd.init();
  lcd.backlight();
  tampilBaris(0, "Smart Planter");
  tampilBaris(1, "Connecting WiFi");

  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 15) {
    delay(500);
    Serial.print(".");
    retry++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    tampilBaris(0, "WiFi Connected!");
    tampilBaris(1, WiFi.localIP().toString().c_str());
  } else {
    tampilBaris(0, "Offline Mode");
    tampilBaris(1, "Local Auto Ready");
  }
  delay(2000);
  lcd.clear();

  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
}

void loop() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) reconnectMQTT();
    mqttClient.loop();
  }

  // 1. BACA SEMUA SENSOR
  float suhu       = dht.readTemperature();
  float kelembapan = dht.readHumidity();
  int   tanah      = bacaTanahPersen();

  int   ldrRaw     = analogRead(LDR_PIN);
  int   ldrPersen  = constrain(map(ldrRaw, 4095, 0, 0, 100), 0, 100);

  int   uvRaw      = analogRead(UV_PIN);
  float uvVoltage  = (uvRaw * 3.3) / 4095.0;
  float uvIndex    = uvVoltage / 0.1;

  float safeSuhu   = isnan(suhu) ? 0.0 : suhu;
  float safeLembab = isnan(kelembapan) ? 0.0 : kelembapan;

  // 2. LOGIKA OTOMASI (Berjalan saat mode AUTO)
  if (autoMode) {
    // Pompa Air (Hysteresis: ON < 30%, OFF > 70%)
    if (tanah < BATAS_POMPA_ON) {
      pompaNyala = true;
    } else if (tanah > BATAS_POMPA_OFF) {
      pompaNyala = false;
    }

    // Grow Light (ON jika LDR < 30%)
    lampuNyala = (ldrPersen < BATAS_LDR_KURANG);
  }

  digitalWrite(RELAY_PUMP_PIN, pompaNyala ? PUMP_LEVEL_ON : PUMP_LEVEL_OFF);
  digitalWrite(RELAY_LIGHT_PIN, lampuNyala ? LIGHT_LEVEL_ON : LIGHT_LEVEL_OFF);

  // 3. TAMPILAN LCD (Bergantian tiap 2 detik)
  static bool halamanSatu = true;
  char isiLcd[17];

  if (halamanSatu) {
    if (isnan(suhu) || isnan(kelembapan)) {
      tampilBaris(0, "DHT Error");
    } else {
      snprintf(isiLcd, sizeof(isiLcd), "T:%.1f%cC H:%.0f%%", safeSuhu, 223, safeLembab);
      tampilBaris(0, isiLcd);
    }
    snprintf(isiLcd, sizeof(isiLcd), "Soil:%2d%% Pmp:%s", tanah, pompaNyala ? "ON" : "OFF");
    tampilBaris(1, isiLcd);
  } else {
    snprintf(isiLcd, sizeof(isiLcd), "UV:%.2f LDR:%d%%", uvIndex, ldrPersen);
    tampilBaris(0, isiLcd);
    snprintf(isiLcd, sizeof(isiLcd), "Lmp:%s [%s]", lampuNyala ? "ON" : "OFF", autoMode ? "AUTO" : "MAN");
    tampilBaris(1, isiLcd);
  }
  halamanSatu = !halamanSatu;

  // 4. BUNGKUS PAYLOAD JSON & KIRIM KE MQTT + BACKEND EXPRESS
  JsonDocument doc;
  doc["device_id"]     = "esp32-planter-01";
  doc["temperature"]   = serialized(String(safeSuhu, 1));
  doc["humidity"]      = serialized(String(safeLembab, 0));
  doc["soil_moisture"] = tanah;
  doc["soil_status"]   = statusTanah(tanah);
  doc["ldr_light"]     = ldrPersen;
  doc["uv_index"]      = serialized(String(uvIndex, 2));
  doc["pump_on"]       = pompaNyala;
  doc["growlight_on"]  = lampuNyala;
  doc["mode"]          = autoMode ? "AUTO" : "MANUAL";

  String jsonPayload;
  serializeJson(doc, jsonPayload);

  if (WiFi.status() == WL_CONNECTED) {
    // Publish via MQTT (Real-time stream)
    mqttClient.publish(TOPIC_TELEMETRY, jsonPayload.c_str());

    // Kirim via HTTP POST ke Backend Node.js + MySQL
    HTTPClient http;
    http.begin(API_URL);
    http.addHeader("Content-Type", "application/json");
    int httpCode = http.POST(jsonPayload);
    http.end();
  }

  Serial.println(jsonPayload);
  delay(2000);
}
```

---

## 🗄️ 3. Tahap 2: Setup Backend & Database (Node.js + Express + TypeScript + MySQL)

Backend ini bertugas menerima data dari ESP32 (baik lewat MQTT maupun HTTP POST), menyimpannya ke **MySQL**, mengatur kendali aktuator, dan menyediakan endpoint ekspor **CSV** untuk pelatihan model _Machine Learning_.

### 3.1. Inisialisasi Proyek Backend

Buka terminal baru dan jalankan perintah berikut:

```bash
mkdir smart-planter-backend
cd smart-planter-backend
npm init -y
npm install express cors dotenv mqtt @prisma/client
npm install -D typescript ts-node-dev @types/node @types/express @types/cors prisma
npx tsc --init
npx prisma init
```

### 3.2. Konfigurasi `.env` dan `prisma/schema.prisma`

Buka file `.env` dan atur koneksi MySQL kamu:

```env
DATABASE_URL="mysql://root:@localhost:3306/smart_indoor_planter"
PORT=4000
MQTT_BROKER="mqtt://broker.hivemq.com:1883"
```

Buka file `prisma/schema.prisma` dan ganti isinya dengan skema berikut:

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "mysql"
  url      = env("DATABASE_URL")
}

model TelemetryLog {
  id            Int      @id @default(autoincrement())
  deviceId      String   @default("esp32-planter-01")
  temperature   Float
  humidity      Float
  soilMoisture  Int
  soilStatus    String
  ldrLight      Int
  uvIndex       Float
  pumpOn        Boolean
  growlightOn   Boolean
  mode          String   @default("AUTO")
  createdAt     DateTime @default(now())

  @@index([createdAt])
}

model DeviceState {
  deviceId      String   @id @default("esp32-planter-01")
  mode          String   @default("AUTO") // "AUTO" | "MANUAL"
  pumpOn        Boolean  @default(false)
  growlightOn   Boolean  @default(false)
  updatedAt     DateTime @updatedAt
}
```

Jalankan migrasi database ke MySQL:

```bash
npx prisma db push
```

### 3.3. Kode Server Utama (`src/server.ts`)

Buat folder `src` dan file `src/server.ts`, lalu _paste_ kode berikut:

```typescript
import express, { Request, Response } from "express";
import cors from "cors";
import dotenv from "dotenv";
import mqtt from "mqtt";
import { PrismaClient } from "@prisma/client";

dotenv.config();

const app = express();
const prisma = new PrismaClient();
const PORT = process.env.PORT || 4000;

app.use(cors());
app.use(express.json());

// ---------- Koneksi MQTT ----------
const MQTT_BROKER = process.env.MQTT_BROKER || "mqtt://broker.hivemq.com:1883";
const TOPIC_TELEMETRY = "smartplanter/moss/telemetry";
const TOPIC_COMMAND = "smartplanter/moss/command";

const mqttClient = mqtt.connect(MQTT_BROKER);

// Cache data terakhir di memori agar pembacaan real-time sangat cepat
let latestData: any = {
  device_id: "esp32-planter-01",
  temperature: 26.8,
  humidity: 65,
  soil_moisture: 45,
  soil_status: "LEMBAB",
  ldr_light: 55,
  uv_index: 0.25,
  pump_on: false,
  growlight_on: false,
  mode: "AUTO",
  updatedAt: new Date().toISOString(),
};

mqttClient.on("connect", () => {
  console.log(`[MQTT] Connected to ${MQTT_BROKER}`);
  mqttClient.subscribe(TOPIC_TELEMETRY);
});

// Simpan data ke MySQL (dibatasi tiap 5 detik agar DB tidak penuh terlalu cepat)
let lastSavedTime = 0;
async function processTelemetry(payload: any) {
  latestData = { ...payload, updatedAt: new Date().toISOString() };

  const now = Date.now();
  if (now - lastSavedTime >= 5000) {
    lastSavedTime = now;
    try {
      await prisma.telemetryLog.create({
        data: {
          deviceId: payload.device_id || "esp32-planter-01",
          temperature: Number(payload.temperature) || 0,
          humidity: Number(payload.humidity) || 0,
          soilMoisture: Number(payload.soil_moisture) || 0,
          soilStatus: String(payload.soil_status || "KERING"),
          ldrLight: Number(payload.ldr_light) || 0,
          uvIndex: Number(payload.uv_index) || 0,
          pumpOn: Boolean(payload.pump_on),
          growlightOn: Boolean(payload.growlight_on),
          mode: String(payload.mode || "AUTO"),
        },
      });
    } catch (err) {
      console.error("[DB Error]", err);
    }
  }
}

mqttClient.on("message", async (topic, message) => {
  if (topic === TOPIC_TELEMETRY) {
    try {
      const data = JSON.parse(message.toString());
      await processTelemetry(data);
    } catch (e) {
      console.error("[MQTT Parse Error]", e);
    }
  }
});

// 1. Endpoint HTTP POST dari ESP32 (Fallback / Dual-Mode)
app.post("/api/telemetry", async (req: Request, res: Response) => {
  await processTelemetry(req.body);
  res.status(200).json({ status: "ok" });
});

// 2. Endpoint GET Data Real-Time + 25 Riwayat Terakhir untuk Grafik Dashboard
app.get("/api/dashboard", async (_req: Request, res: Response) => {
  try {
    const history = await prisma.telemetryLog.findMany({
      orderBy: { createdAt: "desc" },
      take: 25,
    });
    res.json({
      latest: latestData,
      history: history.reverse(),
    });
  } catch (error) {
    res.status(500).json({ error: "Failed to fetch dashboard data" });
  }
});

// 3. Endpoint POST Kontrol Aktuator & Mode (Auto / Manual) dari Dashboard
app.post("/api/control", async (req: Request, res: Response) => {
  const { mode, pump_on, growlight_on } = req.body;

  const commandPayload = {
    mode: mode ?? latestData.mode,
    pump_on: pump_on ?? latestData.pump_on,
    growlight_on: growlight_on ?? latestData.growlight_on,
  };

  latestData = { ...latestData, ...commandPayload };

  // Kirim perintah instan ke ESP32 via MQTT
  mqttClient.publish(TOPIC_COMMAND, JSON.stringify(commandPayload));

  try {
    await prisma.deviceState.upsert({
      where: { deviceId: "esp32-planter-01" },
      update: {
        mode: commandPayload.mode,
        pumpOn: commandPayload.pump_on,
        growlightOn: commandPayload.growlight_on,
      },
      create: {
        deviceId: "esp32-planter-01",
        mode: commandPayload.mode,
        pumpOn: commandPayload.pump_on,
        growlightOn: commandPayload.growlight_on,
      },
    });
  } catch (e) {}

  res.json({ status: "Command sent", state: commandPayload });
});

// 4. Endpoint GET Export CSV untuk Dataset Machine Learning (AoL Project)
app.get("/api/export-csv", async (_req: Request, res: Response) => {
  const logs = await prisma.telemetryLog.findMany({
    orderBy: { createdAt: "asc" },
  });

  const header =
    "id,timestamp,temperature,humidity,soil_moisture,soil_status,ldr_light,uv_index,pump_on,growlight_on,mode\n";
  const rows = logs
    .map(
      (r) =>
        `${r.id},${r.createdAt.toISOString()},${r.temperature},${r.humidity},${r.soilMoisture},${r.soilStatus},${r.ldrLight},${r.uvIndex},${r.pumpOn ? 1 : 0},${r.growlightOn ? 1 : 0},${r.mode}`,
    )
    .join("\n");

  res.setHeader("Content-Type", "text/csv");
  res.setHeader(
    "Content-Disposition",
    'attachment; filename="smart_planter_dataset.csv"',
  );
  res.send(header + rows);
});

app.listen(PORT, () => {
  console.log(`🚀 Smart Planter Backend running on http://localhost:${PORT}`);
});
```

Jalankan server backend dengan perintah:

```bash
npx ts-node-dev src/server.ts
```

---

## 🍎 4. Tahap 3: Setup Frontend Dashboard (Next.js + Apple Bento UI)

Antarmuka ini menggunakan filosofi desain **Apple HomeKit & macOS Sonoma** (_Bento Grid_, _translucent backdrop-blur_, tipografi bersih, indikator _ring progress_, dan grafik _smooth gradient_).

### 4.1. Inisialisasi Proyek Next.js

Buka terminal baru dan jalankan perintah berikut:

```bash
npx create-next-app@latest smart-planter-dashboard --typescript --tailwind --eslint --app
cd smart-planter-dashboard
npm install recharts lucide-react clsx tailwind-merge
```

### 4.2. Full Code Dashboard (`app/page.tsx`)

Buka file `app/page.tsx` (atau `src/app/page.tsx`), hapus seluruh isinya, dan _paste_ kode lengkap di bawah ini:

```tsx
"use client";

import React, { useEffect, useState } from "react";
import {
  Thermometer,
  Droplets,
  Sun,
  Sprout,
  Power,
  Cpu,
  Download,
  RefreshCw,
  Sparkles,
  Lightbulb,
  Waves,
  Activity,
} from "lucide-react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";

const API_BASE = "http://localhost:4000/api";

interface Telemetry {
  temperature: number;
  humidity: number;
  soil_moisture: number;
  soil_status: string;
  ldr_light: number;
  uv_index: number;
  pump_on: boolean;
  growlight_on: boolean;
  mode: "AUTO" | "MANUAL";
  updatedAt?: string;
}

export default function AppleSmartPlanterDashboard() {
  const [data, setData] = useState<Telemetry>({
    temperature: 26.8,
    humidity: 65,
    soil_moisture: 24,
    soil_status: "KERING",
    ldr_light: 22,
    uv_index: 0.12,
    pump_on: true,
    growlight_on: true,
    mode: "AUTO",
  });
  const [history, setHistory] = useState<any[]>([]);
  const [isConnected, setIsConnected] = useState<boolean>(false);

  const fetchDashboard = async () => {
    try {
      const res = await fetch(`${API_BASE}/dashboard`);
      if (!res.ok) throw new Error("Server offline");
      const json = await res.json();
      if (json.latest) setData(json.latest);
      if (json.history) {
        const formatted = json.history.map((item: any) => ({
          time: new Date(item.createdAt).toLocaleTimeString("id-ID", {
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
          }),
          soil: item.soilMoisture,
          ldr: item.ldrLight,
          temp: item.temperature,
          uv: item.uvIndex,
        }));
        setHistory(formatted);
      }
      setIsConnected(true);
    } catch (err) {
      setIsConnected(false);
    }
  };

  useEffect(() => {
    fetchDashboard();
    const interval = setInterval(fetchDashboard, 2000);
    return () => clearInterval(interval);
  }, []);

  const sendControl = async (payload: Partial<Telemetry>) => {
    try {
      setData((prev) => ({ ...prev, ...payload }));
      await fetch(`${API_BASE}/control`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
    } catch (error) {
      console.error("Failed to send control command", error);
    }
  };

  return (
    <div className="min-h-screen bg-[#F5F5F7] text-[#1D1D1F] font-sans selection:bg-emerald-500 selection:text-white pb-16">
      {/* Apple Blurred Sticky Top Navbar */}
      <header className="sticky top-0 z-30 bg-white/75 backdrop-blur-xl border-b border-black/[0.06] px-6 py-4">
        <div className="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-gradient-to-tr from-emerald-500 to-teal-400 flex items-center justify-center shadow-sm shadow-emerald-500/20 text-white">
              <Sprout className="w-5 h-5"/>
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-lg font-semibold tracking-tight">
                  Smart Indoor Planter
                </h1>
                <span className="text-xs font-medium px-2.5 py-0.5 rounded-full bg-black/[0.05] text-neutral-600">
                  ESP32-S
                </span>
              </div>
              <p className="text-xs text-neutral-500">
                Real-Time Telemetry & Rule-Based Hysteresis Automation
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            {/* Connection Pill */}
            <div className="flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-white border border-black/[0.06] shadow-2xs text-xs font-medium">
              <span
                className={`w-2 h-2 rounded-full ${
                  isConnected
                    ? "bg-emerald-500 animate-pulse"
                    : "bg-amber-500"
                }`}
              />
              {isConnected ? "Live Synced (2s)" : "Demo / Offline Mode"}
            </div>

            {/* Export Dataset Button for ML */}
            <a
              href={`${API_BASE}/export-csv`}
              className="flex items-center gap-2 px-4 py-2 rounded-full bg-[#1D1D1F] hover:bg-neutral-800 text-white text-xs font-medium transition-all shadow-xs active:scale-95"
            >
              <Download className="w-3.5 h-3.5"/>
              Export ML Dataset (.CSV)
            </a>
          </div>
        </div>
      </header>

      {/* Main Bento Grid Container */}
      <main className="max-w-7xl mx-auto px-6 pt-8 space-y-6">
        {/* ROW 1: 4 Apple HomeKit Sensor Cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
          {/* Card 1: Soil Moisture */}
          <div className="bg-white/90 backdrop-blur-xl rounded-3xl p-6 border border-black/[0.05] shadow-[0_8px_30px_rgb(0,0,0,0.04)] flex flex-col justify-between">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold uppercase tracking-wider text-neutral-400">
                Kelembapan Tanah
              </span>
              <div className="w-9 h-9 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center">
                <Waves className="w-5 h-5"/>
              </div>
            </div>

            <div className="my-4">
              <div className="flex items-baseline gap-2">
                <span className="text-4xl font-semibold tracking-tight">
                  {data.soil_moisture}%
                </span>
                <span
                  className={`text-xs font-semibold px-2.5 py-0.5 rounded-full ${
                    data.soil_moisture < 30
                      ? "bg-rose-100 text-rose-700"
                      : data.soil_moisture <= 70
                      ? "bg-emerald-100 text-emerald-700"
                      : "bg-blue-100 text-blue-700"
                  }`}
                >
                  {data.soil_status}
                </span>
              </div>
              {/* Progress Bar */}
              <div className="w-full h-2 bg-neutral-100 rounded-full mt-3 overflow-hidden">
                <div
                  className="h-full bg-gradient-to-r from-blue-500 to-cyan-400 rounded-full transition-all duration-500"
                  style={{ width: `${data.soil_moisture}%` }}
                />
              </div>
            </div>

            <p className="text-[11px] text-neutral-400 flex items-center justify-between">
              <span>Hysteresis Rule</span>
              <span className="font-medium text-neutral-600">
                ON &lt; 30% • OFF &gt; 70%
              </span>
            </p>
          </div>

          {/* Card 2: Cahaya LDR */}
          <div className="bg-white/90 backdrop-blur-xl rounded-3xl p-6 border border-black/[0.05] shadow-[0_8px_30px_rgb(0,0,0,0.04)] flex flex-col justify-between">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold uppercase tracking-wider text-neutral-400">
                Intensitas Cahaya (LDR)
              </span>
              <div className="w-9 h-9 rounded-2xl bg-amber-50 text-amber-500 flex items-center justify-center">
                <Sun className="w-5 h-5"/>
              </div>
            </div>

            <div className="my-4">
              <div className="flex items-baseline gap-2">
                <span className="text-4xl font-semibold tracking-tight">
                  {data.ldr_light}%
                </span>
                <span
                  className={`text-xs font-semibold px-2.5 py-0.5 rounded-full ${
                    data.ldr_light < 30
                      ? "bg-amber-100 text-amber-800"
                      : "bg-emerald-100 text-emerald-700"
                  }`}
                >
                  {data.ldr_light < 30 ? "REDUP" : "TERANG"}
                </span>
              </div>
              <div className="w-full h-2 bg-neutral-100 rounded-full mt-3 overflow-hidden">
                <div
                  className="h-full bg-gradient-to-r from-amber-400 to-yellow-500 rounded-full transition-all duration-500"
                  style={{ width: `${data.ldr_light}%` }}
                />
              </div>
            </div>

            <p className="text-[11px] text-neutral-400 flex items-center justify-between">
              <span>Threshold Grow Light</span>
              <span className="font-medium text-neutral-600">
                Auto ON &lt; 30%
              </span>
            </p>
          </div>

          {/* Card 3: Suhu & Kelembapan Udara (DHT11) */}
          <div className="bg-white/90 backdrop-blur-xl rounded-3xl p-6 border border-black/[0.05] shadow-[0_8px_30px_rgb(0,0,0,0.04)] flex flex-col justify-between">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold uppercase tracking-wider text-neutral-400">
                Iklim Ruangan (DHT11)
              </span>
              <div className="w-9 h-9 rounded-2xl bg-rose-50 text-rose-500 flex items-center justify-center">
                <Thermometer className="w-5 h-5"/>
              </div>
            </div>

            <div className="my-4 flex items-baseline justify-between">
              <div>
                <span className="text-4xl font-semibold tracking-tight">
                  {Number(data.temperature).toFixed(1)}°C
                </span>
                <p className="text-xs text-neutral-400 mt-1">Suhu Udara</p>
              </div>
              <div className="text-right border-l border-neutral-100 pl-4">
                <span className="text-2xl font-semibold text-teal-600">
                  {Number(data.humidity).toFixed(0)}%
                </span>
                <p className="text-xs text-neutral-400 mt-1">Kelembapan</p>
              </div>
            </div>

            <p className="text-[11px] text-neutral-400 flex items-center justify-between">
              <span>Sensor Pin</span>
              <span className="font-medium text-neutral-600">GPIO 4 (Digital)</span>
            </p>
          </div>

          {/* Card 4: Indeks UV (GUVA-S12SD) */}
          <div className="bg-white/90 backdrop-blur-xl rounded-3xl p-6 border border-black/[0.05] shadow-[0_8px_30px_rgb(0,0,0,0.04)] flex flex-col justify-between">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold uppercase tracking-wider text-neutral-400">
                Radiasi Sinar UV
              </span>
              <div className="w-9 h-9 rounded-2xl bg-purple-50 text-purple-600 flex items-center justify-center">
                <Sparkles className="w-5 h-5"/>
              </div>
            </div>

            <div className="my-4">
              <div className="flex items-baseline gap-2">
                <span className="text-4xl font-semibold tracking-tight">
                  {Number(data.uv_index).toFixed(2)}
                </span>
                <span className="text-xs font-medium text-purple-600 bg-purple-50 px-2.5 py-0.5 rounded-full">
                  UV Index
                </span>
              </div>
              <p className="text-xs text-neutral-400 mt-2">
                GUVA-S12SD • Spektrum 240–370nm
              </p>
            </div>

            <p className="text-[11px] text-neutral-400 flex items-center justify-between">
              <span>Sensor Pin</span>
              <span className="font-medium text-neutral-600">GPIO 35 (ADC1)</span>
            </p>
          </div>
        </div>

        {/* ROW 2: Apple HomeKit Control Center & Live Time-Series Chart */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left Column (4 cols): Actuator Control Center */}
          <div className="lg:col-span-4 bg-white/90 backdrop-blur-xl rounded-3xl p-6 border border-black/[0.05] shadow-[0_8px_30px_rgb(0,0,0,0.04)] flex flex-col justify-between space-y-6">
            <div>
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h2 className="text-base font-semibold">Control Center</h2>
                  <p className="text-xs text-neutral-400">
                    Manajemen Mode & Relay Aktuator
                  </p>
                </div>
                <Cpu className="w-5 h-5 text-neutral-400"/>
              </div>

              {/* Segmented Control: AUTO vs MANUAL */}
              <div className="grid grid-cols-2 bg-[#F5F5F7] p-1 rounded-2xl mb-6">
                <button
                  onClick={() => sendControl({ mode: "AUTO" })}
                  className={`py-2 text-xs font-semibold rounded-xl transition-all ${
                    data.mode === "AUTO"
                      ? "bg-white text-[#1D1D1F] shadow-xs"
                      : "text-neutral-500 hover:text-neutral-800"
                  }`}
                >
                  Auto (Rule-Based)
                </button>
                <button
                  onClick={() => sendControl({ mode: "MANUAL" })}
                  className={`py-2 text-xs font-semibold rounded-xl transition-all ${
                    data.mode === "MANUAL"
                      ? "bg-white text-[#1D1D1F] shadow-xs"
                      : "text-neutral-500 hover:text-neutral-800"
                  }`}
                >
                  Manual Override
                </button>
              </div>

              {/* Actuator Tile 1: Water Pump */}
              <div className="space-y-3">
                <div
                  className={`p-4 rounded-2xl border transition-all flex items-center justify-between ${
                    data.pump_on
                      ? "bg-blue-600 text-white border-blue-600 shadow-lg shadow-blue-600/20"
                      : "bg-[#F5F5F7] text-[#1D1D1F] border-transparent"
                  }`}
                >
                  <div className="flex items-center gap-3.5">
                    <div
                      className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                        data.pump_on
                          ? "bg-white/20 text-white"
                          : "bg-white text-blue-600 shadow-2xs"
                      }`}
                    >
                      <Droplets className="w-5 h-5"/>
                    </div>
                    <div>
                      <p className="text-sm font-semibold">Pompa Air (Pin 13)</p>
                      <p
                        className={`text-xs ${
                          data.pump_on ? "text-blue-100" : "text-neutral-500"
                        }`}
                      >
                        {data.pump_on ? "Menyiram Tanaman (ON)" : "Standby (OFF)"}
                      </p>
                    </div>
                  </div>

                  <button
                    disabled={data.mode === "AUTO"}
                    onClick={() => sendControl({ pump_on: !data.pump_on })}
                    className={`px-3.5 py-1.5 rounded-full text-xs font-semibold transition-all ${
                      data.mode === "AUTO"
                        ? "opacity-50 cursor-not-allowed bg-black/10"
                        : data.pump_on
                        ? "bg-white text-blue-600"
                        : "bg-[#1D1D1F] text-white"
                    }`}
                  >
                    {data.pump_on ? "ON" : "OFF"}
                  </button>
                </div>

                {/* Actuator Tile 2: Grow Light */}
                <div
                  className={`p-4 rounded-2xl border transition-all flex items-center justify-between ${
                    data.growlight_on
                      ? "bg-amber-500 text-white border-amber-500 shadow-lg shadow-amber-500/20"
                      : "bg-[#F5F5F7] text-[#1D1D1F] border-transparent"
                  }`}
                >
                  <div className="flex items-center gap-3.5">
                    <div
                      className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                        data.growlight_on
                          ? "bg-white/20 text-white"
                          : "bg-white text-amber-500 shadow-2xs"
                      }`}
                    >
                      <Lightbulb className="w-5 h-5"/>
                    </div>
                    <div>
                      <p className="text-sm font-semibold">Grow Light (Pin 26)</p>
                      <p
                        className={`text-xs ${
                          data.growlight_on ? "text-amber-100" : "text-neutral-500"
                        }`}
                      >
                        {data.growlight_on ? "Menyinari (ON)" : "Mati (OFF)"}
                      </p>
                    </div>
                  </div>

                  <button
                    disabled={data.mode === "AUTO"}
                    onClick={() =>
                      sendControl({ growlight_on: !data.growlight_on })
                    }
                    className={`px-3.5 py-1.5 rounded-full text-xs font-semibold transition-all ${
                      data.mode === "AUTO"
                        ? "opacity-50 cursor-not-allowed bg-black/10"
                        : data.growlight_on
                        ? "bg-white text-amber-600"
                        : "bg-[#1D1D1F] text-white"
                    }`}
                  >
                    {data.growlight_on ? "ON" : "OFF"}
                  </button>
                </div>
              </div>
            </div>

            <div className="p-3.5 rounded-2xl bg-[#F5F5F7] text-[11px] text-neutral-500 leading-relaxed">
              💡 Saat mode <strong>Auto</strong> aktif, ESP32 mengeksekusi logika
              secara mandiri. Ubah ke <strong>Manual Override</strong> untuk
              mengetes saklar relay langsung dari web.
            </div>
          </div>

          {/* Right Column (8 cols): Real-Time Telemetry Chart */}
          <div className="lg:col-span-8 bg-white/90 backdrop-blur-xl rounded-3xl p-6 border border-black/[0.05] shadow-[0_8px_30px_rgb(0,0,0,0.04)] flex flex-col justify-between">
            <div className="flex flex-wrap items-center justify-between gap-2 mb-6">
              <div>
                <h2 className="text-base font-semibold flex items-center gap-2">
                  <Activity className="w-4 h-4 text-emerald-500"/>
                  Grafik Telemetri Real-Time
                </h2>
                <p className="text-xs text-neutral-400">
                  Tren Kelembapan Tanah (%) vs Intensitas Cahaya LDR (%)
                </p>
              </div>
              <div className="flex items-center gap-4 text-xs font-medium">
                <span className="flex items-center gap-1.5 text-blue-600">
                  <span className="w-2.5 h-2.5 rounded-full bg-blue-500" />
                  Kelembapan Tanah (%)
                </span>
                <span className="flex items-center gap-1.5 text-amber-600">
                  <span className="w-2.5 h-2.5 rounded-full bg-amber-400" />
                  Cahaya LDR (%)
                </span>
              </div>
            </div>

            <div className="h-72 w-full">
              <ResponsiveContainer height="100%" width="100%">
                <AreaChart data="{history}">
                  <defs>
                    <linearGradient id="colorSoil" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#3B82F6" stopOpacity={0.25} />
                      <stop offset="95%" stopColor="#3B82F6" stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="colorLdr" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#F59E0B" stopOpacity={0.25} />
                      <stop offset="95%" stopColor="#F59E0B" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid stroke="#F0F0F2" strokeDasharray="3 3"/>
                  <XAxis "#8E8E93" 11, axisLine="{false}" dataKey="time" fill: fontSize: tick="{{" tickLine="{false}" }}/>
                  <YAxis "#8E8E93" 100]} 11, axisLine="{false}" domain="{[0," fill: fontSize: tick="{{" tickLine="{false}" }}/>
                  <Tooltip "0 "12px", "16px", "1px "rgba(255, 0.92)", 10px 255, 25px backgroundColor: border: borderRadius: boxShadow: contentStyle="{{" fontSize: rgba(0,0,0,0.06)", solid }}/>
                  <Area dataKey="soil" fill="url(#colorSoil)" fillOpacity="{1}" name="Soil Moisture (%)" stroke="#3B82F6" strokeWidth="{2.5}" type="monotone"/>
                  <Area dataKey="ldr" fill="url(#colorLdr)" fillOpacity="{1}" name="Cahaya LDR (%)" stroke="#F59E0B" strokeWidth="{2.5}" type="monotone"/>
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}
```
