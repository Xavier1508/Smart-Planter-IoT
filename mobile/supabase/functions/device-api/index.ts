import { createClient } from "jsr:@supabase/supabase-js@2";

// Device-facing HTTP API. The ESP32 authenticates with a per-device secret;
// the phone never calls this function. The service-role key exists only here.
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-device-id, x-device-token",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

const MAX_BODY_BYTES = 64 * 1024;
const MAX_BATCH = 24;
const tokenPattern = /^[a-f0-9]{64}$/;
const hardwarePattern = /^moss-[a-z0-9]{4,12}-[a-f0-9]{8,16}$/;
const bootPattern = /^[a-f0-9]{8,16}$/;

type Device = {
  id: string;
  hardware_id: string;
  display_name: string;
  is_active: boolean;
};

type JsonRecord = Record<string, unknown>;

function json(status: number, body: unknown, extra: HeadersInit = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extra,
    },
  });
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > max) return null;
  return trimmed;
}

function integer(value: unknown, min: number, max: number): number | null {
  if (typeof value !== "number" || !Number.isInteger(value)) return null;
  return value >= min && value <= max ? value : null;
}

function decimal(value: unknown, min: number, max: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value >= min && value <= max ? value : null;
}

function flag(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function validIso(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 40) return null;
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) return null;
  const now = Date.now();
  if (parsed > now + 5 * 60 * 1000) return null;
  if (parsed < now - 90 * 24 * 60 * 60 * 1000) return null;
  return new Date(parsed).toISOString();
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function equalHex(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let result = 0;
  for (let index = 0; index < left.length; index++) {
    result |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return result === 0;
}

async function readJson(req: Request): Promise<JsonRecord> {
  const length = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > MAX_BODY_BYTES) {
    throw new Error("payload_too_large");
  }
  const body = await req.text();
  if (body.length > MAX_BODY_BYTES) throw new Error("payload_too_large");
  const parsed = JSON.parse(body);
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("invalid_json");
  }
  return parsed as JsonRecord;
}

async function authenticate(
  req: Request,
): Promise<{ device: Device } | { response: Response }> {
  const hardwareId = req.headers.get("x-device-id")?.trim().toLowerCase() ?? "";
  const token = req.headers.get("x-device-token")?.trim().toLowerCase() ?? "";
  if (!hardwarePattern.test(hardwareId) || !tokenPattern.test(token)) {
    return { response: json(401, { error: "device_unauthorized" }) };
  }
  const { data, error } = await admin
    .from("planter_devices")
    .select("id, hardware_id, display_name, is_active, device_token_hash")
    .eq("hardware_id", hardwareId)
    .maybeSingle();
  if (
    error || !data || !data.is_active ||
    typeof data.device_token_hash !== "string"
  ) {
    return { response: json(401, { error: "device_unauthorized" }) };
  }
  const candidate = await sha256Hex(token);
  if (!equalHex(candidate, data.device_token_hash)) {
    return { response: json(401, { error: "device_unauthorized" }) };
  }
  return {
    device: {
      id: data.id,
      hardware_id: data.hardware_id,
      display_name: data.display_name,
      is_active: data.is_active,
    },
  };
}

// Best-effort per-isolate limiter. The database remains authoritative, but this
// rejects accidental retry storms and simple token probing cheaply.
const rate = new Map<string, { window: number; count: number }>();
function rateLimited(key: string, limit: number): boolean {
  const minute = Math.floor(Date.now() / 60000);
  const entry = rate.get(key);
  if (!entry || entry.window !== minute) {
    rate.set(key, { window: minute, count: 1 });
    return false;
  }
  entry.count++;
  return entry.count > limit;
}

function sampleRow(
  raw: unknown,
  index: number,
  deviceId: string,
  replay: boolean,
): { row?: JsonRecord; rejected?: { index: number; code: string } } {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return { rejected: { index, code: "not_object" } };
  }
  const sample = raw as JsonRecord;
  const uptime = integer(sample.uptime_ms, 0, 4294967295);
  if (uptime === null) return { rejected: { index, code: "uptime_ms" } };

  let capturedAt: string | null = null;
  let timeQuality = sample.time_quality;
  if (timeQuality !== "ntp" && timeQuality !== "uptime_only") {
    return { rejected: { index, code: "time_quality" } };
  }
  if (timeQuality === "ntp") {
    capturedAt = validIso(sample.captured_at);
    if (capturedAt === null) {
      return { rejected: { index, code: "captured_at" } };
    }
  }

  const adc = (key: string) => {
    const value = sample[key];
    if (value === null || value === undefined) return null;
    return integer(value, 0, 4095);
  };
  const pct = (key: string) => {
    const value = sample[key];
    if (value === null || value === undefined) return null;
    return integer(value, 0, 100);
  };
  const reason = (key: string) => {
    const value = sample[key];
    if (value === null || value === undefined) return null;
    if (typeof value !== "string" || !/^[a-z0-9_]{1,64}$/.test(value)) {
      return undefined;
    }
    return value;
  };

  const values: Record<string, number | null> = {
    soil_adc: adc("soil_adc"),
    soil_percent: pct("soil_percent"),
    water_adc: adc("water_adc"),
    water_percent: pct("water_percent"),
    water_observation_percent: pct("water_observation_percent"),
    light_adc: adc("light_adc"),
    light_percent: pct("light_percent"),
    uv_adc: adc("uv_adc"),
    mq_adc: adc("mq_adc"),
  };
  for (const [key, value] of Object.entries(values)) {
    const supplied = sample[key];
    if (supplied !== null && supplied !== undefined && value === null) {
      return { rejected: { index, code: key } };
    }
  }
  const mqPinMv = sample.mq_pin_mv === null || sample.mq_pin_mv === undefined
    ? null
    : integer(sample.mq_pin_mv, 0, 5000);
  if (sample.mq_pin_mv != null && mqPinMv === null) {
    return { rejected: { index, code: "mq_pin_mv" } };
  }
  const temperature = sample.temperature_c === null ||
      sample.temperature_c === undefined
    ? null
    : decimal(sample.temperature_c, -40, 80);
  if (sample.temperature_c != null && temperature === null) {
    return { rejected: { index, code: "temperature_c" } };
  }
  const humidity = sample.humidity_percent === null ||
      sample.humidity_percent === undefined
    ? null
    : integer(sample.humidity_percent, 0, 100);
  if (sample.humidity_percent != null && humidity === null) {
    return { rejected: { index, code: "humidity_percent" } };
  }
  const uvIndex = sample.uv_index === null || sample.uv_index === undefined
    ? null
    : decimal(sample.uv_index, 0, 25);
  if (sample.uv_index != null && uvIndex === null) {
    return { rejected: { index, code: "uv_index" } };
  }
  const cooldown = sample.pump_cooldown_s === null ||
      sample.pump_cooldown_s === undefined
    ? null
    : integer(sample.pump_cooldown_s, 0, 86400);
  if (sample.pump_cooldown_s != null && cooldown === null) {
    return { rejected: { index, code: "pump_cooldown_s" } };
  }
  const pumpReason = reason("pump_reason");
  const lightReason = reason("light_reason");
  if (pumpReason === undefined || lightReason === undefined) {
    return { rejected: { index, code: "reason" } };
  }

  const numericValues = [
    ...Object.values(values),
    mqPinMv,
    temperature,
    humidity,
    uvIndex,
  ];
  if (!numericValues.some((value) => value !== null)) {
    return { rejected: { index, code: "no_measurement" } };
  }

  return {
    row: {
      device_id: deviceId,
      boot_id: typeof sample.boot_id === "string" ? sample.boot_id : undefined,
      uptime_ms: uptime,
      captured_at: capturedAt,
      time_quality: timeQuality,
      soil_adc: values.soil_adc,
      soil_percent: values.soil_percent,
      water_adc: values.water_adc,
      water_percent: values.water_percent,
      water_observation_percent: values.water_observation_percent,
      water_empty: flag(sample.water_empty),
      water_low: flag(sample.water_low),
      light_adc: values.light_adc,
      light_percent: values.light_percent,
      temperature_c: temperature,
      humidity_percent: humidity,
      uv_adc: values.uv_adc,
      uv_index: uvIndex,
      mq_adc: values.mq_adc,
      mq_pin_mv: mqPinMv,
      pump_on: flag(sample.pump_cmd),
      pump_reason: pumpReason,
      pump_cooldown_s: cooldown,
      pump_runtime_lockout: flag(sample.pump_runtime_lockout),
      growlight_on: flag(sample.light_cmd),
      light_reason: lightReason,
      ingest_source: replay ? "buffer_replay" : "live",
    },
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  const url = new URL(req.url);
  const action = url.searchParams.get("action") ?? "";
  if (rateLimited(`${req.headers.get("x-device-id") ?? req.headers.get("x-forwarded-for") ?? "unknown"}:${action}`, 180)) {
    return json(429, { error: "rate_limited" }, { "Retry-After": "60" });
  }
  if (action !== "register" && action !== "ingest" && action !== "commands" && action !== "ack") {
    return json(404, { error: "not_found" });
  }
  if (action === "commands" ? req.method !== "GET" : req.method !== "POST") {
    return json(405, { error: "method_not_allowed" }, { Allow: action === "commands" ? "GET" : "POST" });
  }

  const auth = await authenticate(req);
  if ("response" in auth) return auth.response;
  const device = auth.device;

  try {
    if (action === "register") {
      const body = await readJson(req);
      const firmware = integer(body.firmware_version, 1, 10000);
      if (firmware === null) return json(400, { error: "firmware_version" });
      const { error } = await admin
        .from("planter_devices")
        .update({
          firmware_version: firmware,
          last_seen_at: new Date().toISOString(),
        })
        .eq("id", device.id);
      if (error) throw error;
      return json(200, {
        ok: true,
        device_id: device.id,
        hardware_id: device.hardware_id,
        display_name: device.display_name,
        server_time: new Date().toISOString(),
      });
    }

    if (action === "commands") {
      const { data, error } = await admin.rpc("lease_device_commands", {
        p_device_id: device.id,
        p_limit: 4,
      });
      if (error) throw error;
      await admin
        .from("planter_devices")
        .update({ last_seen_at: new Date().toISOString() })
        .eq("id", device.id);
      return json(200, { commands: data ?? [], server_time: new Date().toISOString() });
    }

    if (action === "ack") {
      const body = await readJson(req);
      const commandId = text(body.command_id, 36);
      if (!commandId || !/^[0-9a-f-]{36}$/i.test(commandId)) {
        return json(400, { error: "command_id" });
      }
      if (typeof body.ok !== "boolean") return json(400, { error: "ok" });
      const errorCode = body.error_code == null ? null : text(body.error_code, 64);
      if (body.error_code != null && errorCode === null) {
        return json(400, { error: "error_code" });
      }
      const result = body.result && typeof body.result === "object" &&
          !Array.isArray(body.result)
        ? body.result
        : {};
      const { data, error } = await admin.rpc("ack_device_command", {
        p_device_id: device.id,
        p_command_id: commandId,
        p_ok: body.ok,
        p_error_code: errorCode,
        p_result: result,
      });
      if (error) throw error;
      return json(200, { ok: true, command: data });
    }

    // ingest
    const body = await readJson(req);
    const bootId = text(body.boot_id, 16)?.toLowerCase() ?? "";
    const firmware = integer(body.firmware_version, 1, 10000);
    const samples = body.samples;
    if (body.schema !== 1) return json(400, { error: "schema" });
    if (!bootPattern.test(bootId)) return json(400, { error: "boot_id" });
    if (firmware === null) return json(400, { error: "firmware_version" });
    if (!Array.isArray(samples) || samples.length < 1 || samples.length > MAX_BATCH) {
      return json(400, { error: "samples" });
    }
    const replay = body.replay === true ||
      req.headers.get("x-moss-replay") === "1";
    const rows: JsonRecord[] = [];
    const rejected: { index: number; code: string }[] = [];
    samples.forEach((sample, index) => {
      const parsed = sampleRow(sample, index, device.id, replay);
      if (parsed.row) {
        parsed.row.boot_id = bootId;
        parsed.row.firmware_version = firmware;
        rows.push(parsed.row);
      } else if (parsed.rejected) {
        rejected.push(parsed.rejected);
      }
    });
    if (rows.length === 0) {
      return json(422, { accepted: 0, duplicates: 0, rejected });
    }
    const { data, error } = await admin
      .from("planter_readings")
      .upsert(rows, {
        onConflict: "device_id,boot_id,uptime_ms",
        ignoreDuplicates: true,
      })
      .select("id");
    if (error) throw error;
    const accepted = data?.length ?? 0;
    await admin
      .from("planter_devices")
      .update({
        firmware_version: firmware,
        last_seen_at: new Date().toISOString(),
      })
      .eq("id", device.id);
    return json(202, {
      accepted,
      duplicates: rows.length - accepted,
      rejected,
      server_time: new Date().toISOString(),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    if (message === "payload_too_large") {
      return json(413, { error: "payload_too_large" });
    }
    if (message === "invalid_json" || message.startsWith("Unexpected")) {
      return json(400, { error: "invalid_json" });
    }
    console.error("device-api failure", message);
    return json(500, { error: "server_error" });
  }
});
