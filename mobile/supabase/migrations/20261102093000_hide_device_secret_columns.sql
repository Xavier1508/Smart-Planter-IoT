-- Never expose device secrets to app clients, even as hashes.
-- A table-level SELECT grant implies every column, so replace it with explicit
-- column grants. The service-role Edge Function and SECURITY DEFINER RPCs still
-- read the secret columns.
revoke select on public.planter_devices from authenticated;
grant select (
  id, owner_id, display_name, created_at, hardware_id,
  firmware_version, last_seen_at, is_active
) on public.planter_devices to authenticated;
