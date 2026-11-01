-- Cloud-primary telemetry, device enrollment, and actuator commands.
--
-- Security boundaries:
--   * the phone uses the publishable key and an authenticated JWT;
--   * the ESP32 uses a per-device secret that is stored only as a SHA-256 hash;
--   * only the device-api Edge Function (service role) may ingest readings,
--     lease commands, or acknowledge them;
--   * a phone may request a command only through the atomic RPC below.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Device identity and physical claim
-- ---------------------------------------------------------------------------

alter table public.planter_devices
  add column if not exists hardware_id text,
  add column if not exists device_token_hash text,
  add column if not exists claim_code_hash text,
  add column if not exists claim_expires_at timestamptz,
  add column if not exists firmware_version integer,
  add column if not exists last_seen_at timestamptz,
  add column if not exists is_active boolean not null default true;

alter table public.planter_devices alter column owner_id drop not null;

alter table public.planter_devices
  drop constraint if exists planter_devices_hardware_id_format;
alter table public.planter_devices
  add constraint planter_devices_hardware_id_format check (
    hardware_id is null or hardware_id ~ '^moss-[a-z0-9]{4,12}-[a-f0-9]{8,16}$'
  );

create unique index if not exists planter_devices_hardware_id_key
  on public.planter_devices (hardware_id)
  where hardware_id is not null;

create index if not exists planter_devices_owner_active_idx
  on public.planter_devices (owner_id, is_active, created_at);

-- ---------------------------------------------------------------------------
-- Full-fidelity readings
-- ---------------------------------------------------------------------------

alter table public.planter_readings
  add column if not exists boot_id text not null default 'legacy',
  add column if not exists uptime_ms bigint not null default 0,
  add column if not exists captured_at timestamptz,
  add column if not exists time_quality text not null default 'uptime_only',
  add column if not exists firmware_version integer,
  add column if not exists soil_adc smallint,
  add column if not exists water_adc smallint,
  add column if not exists water_percent smallint,
  add column if not exists water_observation_percent smallint,
  add column if not exists water_empty boolean,
  add column if not exists water_low boolean,
  add column if not exists light_adc smallint,
  add column if not exists uv_adc smallint,
  add column if not exists mq_adc smallint,
  add column if not exists mq_pin_mv integer,
  add column if not exists pump_reason text,
  add column if not exists pump_cooldown_s integer,
  add column if not exists pump_runtime_lockout boolean,
  add column if not exists light_reason text,
  add column if not exists ingest_source text not null default 'live';

alter table public.planter_readings
  drop constraint if exists planter_readings_time_quality_check;
alter table public.planter_readings
  add constraint planter_readings_time_quality_check
  check (time_quality in ('ntp', 'uptime_only'));

alter table public.planter_readings
  drop constraint if exists planter_readings_ingest_source_check;
alter table public.planter_readings
  add constraint planter_readings_ingest_source_check
  check (ingest_source in ('live', 'buffer_replay'));

alter table public.planter_readings
  drop constraint if exists planter_readings_boot_id_format;
alter table public.planter_readings
  add constraint planter_readings_boot_id_format
  check (boot_id ~ '^[a-f0-9]{8,16}$');

alter table public.planter_readings
  drop constraint if exists planter_readings_uptime_check;
alter table public.planter_readings
  add constraint planter_readings_uptime_check
  check (uptime_ms >= 0 and uptime_ms < 4294967296);

alter table public.planter_readings
  drop constraint if exists planter_readings_adc_ranges;
alter table public.planter_readings
  add constraint planter_readings_adc_ranges check (
    (soil_adc is null or soil_adc between 0 and 4095) and
    (water_adc is null or water_adc between 0 and 4095) and
    (light_adc is null or light_adc between 0 and 4095) and
    (uv_adc is null or uv_adc between 0 and 4095) and
    (mq_adc is null or mq_adc between 0 and 4095) and
    (mq_pin_mv is null or mq_pin_mv between 0 and 5000)
  );

alter table public.planter_readings
  drop constraint if exists planter_readings_some_measurement;
alter table public.planter_readings
  add constraint planter_readings_some_measurement check (
    soil_adc is not null or soil_percent is not null or
    water_adc is not null or water_percent is not null or
    light_adc is not null or light_percent is not null or
    temperature_c is not null or humidity_percent is not null or
    uv_adc is not null or uv_index is not null or mq_adc is not null
  );

create unique index if not exists planter_readings_device_boot_uptime_key
  on public.planter_readings (device_id, boot_id, uptime_ms);

create index if not exists planter_readings_device_captured_idx
  on public.planter_readings (device_id, captured_at desc, id desc)
  where captured_at is not null;

-- ---------------------------------------------------------------------------
-- Commands requested by the phone and executed by the device
-- ---------------------------------------------------------------------------

create table if not exists public.actuator_commands (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.planter_devices(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  actuator text not null check (actuator in ('pump', 'light')),
  action text not null check (action in ('on', 'off', 'auto')),
  duration_seconds smallint check (
    duration_seconds is null or duration_seconds between 1 and 1800
  ),
  status text not null default 'pending' check (
    status in ('pending', 'delivered', 'acked', 'rejected', 'expired', 'superseded')
  ),
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null,
  delivered_at timestamptz,
  acked_at timestamptz,
  delivery_count integer not null default 0 check (delivery_count >= 0),
  error_code text,
  result jsonb,
  constraint actuator_commands_request_unique
    unique (requested_by, client_request_id),
  constraint actuator_commands_pump_duration check (
    actuator <> 'pump' or action <> 'on' or
    (duration_seconds is not null and duration_seconds between 1 and 30)
  ),
  constraint actuator_commands_light_duration check (
    actuator <> 'light' or action <> 'on' or
    (duration_seconds is not null and duration_seconds between 1 and 1800)
  )
);

create index if not exists actuator_commands_device_active_idx
  on public.actuator_commands (device_id, actuator, status, created_at desc);
create index if not exists actuator_commands_expiry_idx
  on public.actuator_commands (expires_at)
  where status in ('pending', 'delivered');

-- ---------------------------------------------------------------------------
-- API surface: claim, request, lease, acknowledge
-- ---------------------------------------------------------------------------

create or replace function public.claim_device(
  p_hardware_id text,
  p_claim_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_device public.planter_devices;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_hardware_id is null or p_claim_code is null then
    raise exception 'invalid_claim' using errcode = '22023';
  end if;

  select * into v_device
    from public.planter_devices
   where hardware_id = lower(trim(p_hardware_id))
     and owner_id is null
     and is_active
     and claim_expires_at > now()
     and claim_code_hash = encode(extensions.digest(trim(p_claim_code), 'sha256'), 'hex')
     for update;

  if not found then
    raise exception 'invalid_or_expired_claim_code' using errcode = 'P0001';
  end if;

  update public.planter_devices
     set owner_id = v_uid,
         claim_code_hash = null,
         claim_expires_at = null
   where id = v_device.id
   returning * into v_device;

  return jsonb_build_object(
    'device_id', v_device.id,
    'hardware_id', v_device.hardware_id,
    'display_name', v_device.display_name
  );
end;
$$;

revoke all on function public.claim_device(text, text) from public, anon;
grant execute on function public.claim_device(text, text) to authenticated;

create or replace function public.request_actuator_command(
  p_device_id uuid,
  p_actuator text,
  p_action text,
  p_duration_seconds integer,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.actuator_commands;
  v_command public.actuator_commands;
  v_duration integer := p_duration_seconds;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_device_id is null or p_client_request_id is null then
    raise exception 'invalid_command' using errcode = '22023';
  end if;
  if p_actuator not in ('pump', 'light') or p_action not in ('on', 'off', 'auto') then
    raise exception 'invalid_command' using errcode = '22023';
  end if;
  if p_action <> 'on' then
    v_duration := null;
  elsif p_actuator = 'pump' and (p_duration_seconds is null or p_duration_seconds not between 1 and 30) then
    raise exception 'invalid_pump_duration' using errcode = '22023';
  elsif p_actuator = 'light' and (p_duration_seconds is null or p_duration_seconds not between 1 and 1800) then
    raise exception 'invalid_light_duration' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.planter_devices
     where id = p_device_id and owner_id = v_uid and is_active
  ) then
    raise exception 'device_not_found' using errcode = '42501';
  end if;

  -- A retried request with the same client UUID must never create a second
  -- physical action, even if the first HTTP response was lost.
  select * into v_existing
    from public.actuator_commands
   where requested_by = v_uid and client_request_id = p_client_request_id;
  if found then
    return jsonb_build_object(
      'id', v_existing.id,
      'status', v_existing.status,
      'actuator', v_existing.actuator,
      'action', v_existing.action,
      'duration_seconds', v_existing.duration_seconds,
      'expires_at', v_existing.expires_at,
      'duplicate', true
    );
  end if;

  -- Serialize requests for the same physical actuator. Without this, two
  -- simultaneous taps could both stay pending and arrive out of order.
  perform pg_advisory_xact_lock(
    hashtextextended(p_device_id::text || ':' || p_actuator, 0)
  );

  update public.actuator_commands
     set status = 'superseded'
   where device_id = p_device_id
     and actuator = p_actuator
     and status in ('pending', 'delivered');

  insert into public.actuator_commands (
    device_id, requested_by, client_request_id, actuator, action,
    duration_seconds, expires_at
  ) values (
    p_device_id, v_uid, p_client_request_id, p_actuator, p_action,
    v_duration, now() + interval '30 seconds'
  )
  on conflict (requested_by, client_request_id) do nothing
  returning * into v_command;

  if v_command.id is null then
    select * into v_command
      from public.actuator_commands
     where requested_by = v_uid and client_request_id = p_client_request_id;
  end if;

  return jsonb_build_object(
    'id', v_command.id,
    'status', v_command.status,
    'actuator', v_command.actuator,
    'action', v_command.action,
    'duration_seconds', v_command.duration_seconds,
    'expires_at', v_command.expires_at,
    'duplicate', false
  );
end;
$$;

revoke all on function public.request_actuator_command(uuid, text, text, integer, uuid)
  from public, anon;
grant execute on function public.request_actuator_command(uuid, text, text, integer, uuid)
  to authenticated;

create or replace function public.lease_device_commands(
  p_device_id uuid,
  p_limit integer default 4
)
returns table (
  id uuid,
  actuator text,
  action text,
  duration_seconds smallint,
  expires_in_ms integer,
  delivery_count integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 4), 8));
begin
  update public.actuator_commands
     set status = 'expired'
   where device_id = p_device_id
     and status in ('pending', 'delivered')
     and expires_at <= now();

  return query
  with picked as (
    select c.id
      from public.actuator_commands c
     where c.device_id = p_device_id
       and c.expires_at > now()
       and c.status in ('pending', 'delivered')
       and c.delivery_count < 8
     order by c.created_at
     limit v_limit
     for update skip locked
  )
  update public.actuator_commands c
     set status = 'delivered',
         delivered_at = coalesce(c.delivered_at, now()),
         delivery_count = c.delivery_count + 1
    from picked
   where c.id = picked.id
  returning
    c.id,
    c.actuator,
    c.action,
    c.duration_seconds,
    greatest(
      0,
      floor(extract(epoch from (c.expires_at - now())) * 1000)
    )::integer,
    c.delivery_count;
end;
$$;

revoke all on function public.lease_device_commands(uuid, integer) from public, anon, authenticated;
grant execute on function public.lease_device_commands(uuid, integer) to service_role;

create or replace function public.ack_device_command(
  p_device_id uuid,
  p_command_id uuid,
  p_ok boolean,
  p_error_code text default null,
  p_result jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_command public.actuator_commands;
begin
  update public.actuator_commands
     set status = case when p_ok then 'acked' else 'rejected' end,
         acked_at = coalesce(acked_at, now()),
         error_code = case
           when p_ok then null
           else left(coalesce(p_error_code, 'device_rejected'), 64)
         end,
         result = coalesce(p_result, '{}'::jsonb)
   where id = p_command_id
     and device_id = p_device_id
     and status in ('delivered', 'acked', 'rejected')
  returning * into v_command;

  if not found then
    raise exception 'command_not_found' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'id', v_command.id,
    'status', v_command.status,
    'acked_at', v_command.acked_at
  );
end;
$$;

revoke all on function public.ack_device_command(uuid, uuid, boolean, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.ack_device_command(uuid, uuid, boolean, text, jsonb)
  to service_role;

-- ---------------------------------------------------------------------------
-- RLS and grants
-- ---------------------------------------------------------------------------

alter table public.actuator_commands enable row level security;

revoke all on table public.planter_devices, public.planter_readings,
  public.actuator_commands from public, anon, authenticated;
grant select on table public.planter_devices, public.planter_readings,
  public.actuator_commands to authenticated;

grant all on table public.planter_devices, public.planter_readings,
  public.actuator_commands to service_role;

drop policy if exists actuator_commands_read_own on public.actuator_commands;
create policy actuator_commands_read_own on public.actuator_commands
  for select to authenticated
  using (
    exists (
      select 1 from public.planter_devices as device
      where device.id = actuator_commands.device_id
        and device.owner_id = (select auth.uid())
    )
  );

-- Keep the existing read policies; replace only if a migration rerun needs it.
drop policy if exists planter_devices_read_own on public.planter_devices;
create policy planter_devices_read_own on public.planter_devices
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists planter_readings_read_own on public.planter_readings;
create policy planter_readings_read_own on public.planter_readings
  for select to authenticated
  using (
    exists (
      select 1 from public.planter_devices as device
      where device.id = planter_readings.device_id
        and device.owner_id = (select auth.uid())
    )
  );

do $$
begin
  alter publication supabase_realtime add table public.actuator_commands;
exception
  when duplicate_object then null;
end;
$$;
