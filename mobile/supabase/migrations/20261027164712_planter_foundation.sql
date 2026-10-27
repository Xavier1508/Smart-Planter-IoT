-- Private Smart Planter data model. No devices or sensor readings are seeded.
-- Device enrollment and authenticated ingestion are intentionally separate:
-- an app user may read their own data, but cannot forge sensor measurements.

create table public.planter_devices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 60),
  created_at timestamptz not null default statement_timestamp()
);

create index planter_devices_owner_id_idx on public.planter_devices (owner_id, id);

create table public.planter_readings (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.planter_devices(id) on delete cascade,
  recorded_at timestamptz not null default statement_timestamp(),
  soil_percent smallint check (soil_percent between 0 and 100),
  temperature_c numeric(5,2) check (temperature_c between -40 and 80),
  humidity_percent smallint check (humidity_percent between 0 and 100),
  light_percent smallint check (light_percent between 0 and 100),
  uv_index numeric(5,2) check (uv_index between 0 and 25),
  pump_on boolean,
  growlight_on boolean,
  constraint planter_readings_some_measurement check (
    soil_percent is not null or temperature_c is not null or
    humidity_percent is not null or light_percent is not null or
    uv_index is not null
  )
);

create index planter_readings_device_time_idx
  on public.planter_readings (device_id, recorded_at desc, id desc);

alter table public.planter_devices enable row level security;
alter table public.planter_readings enable row level security;

revoke all on table public.planter_devices from public, anon, authenticated;
revoke all on table public.planter_readings from public, anon, authenticated;
grant select on table public.planter_devices, public.planter_readings to authenticated;

create policy planter_devices_read_own on public.planter_devices
  for select to authenticated
  using (owner_id = (select auth.uid()));

create policy planter_readings_read_own on public.planter_readings
  for select to authenticated
  using (
    exists (
      select 1 from public.planter_devices as device
      where device.id = planter_readings.device_id
        and device.owner_id = (select auth.uid())
    )
  );

-- Postgres Changes respects the table's read policy for subscribers. Only the
-- intended readings table is added; do not recreate the existing publication.
alter publication supabase_realtime add table public.planter_readings;
