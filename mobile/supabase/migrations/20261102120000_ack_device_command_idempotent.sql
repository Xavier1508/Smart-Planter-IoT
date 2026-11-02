-- Acknowledgement is terminal state, not a request that can fail forever.
-- A command can be superseded or expired between lease and ACK; the device
-- must receive 200 and stop retrying instead of generating a 500 storm.
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
as $function$
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

  if found then
    return jsonb_build_object(
      'id', v_command.id,
      'status', v_command.status,
      'acked_at', v_command.acked_at
    );
  end if;

  -- The command already reached a terminal state (superseded/expired) or was
  -- replaced by a newer request. Report the current state without raising.
  select * into v_command
    from public.actuator_commands
   where id = p_command_id
     and device_id = p_device_id;

  if found then
    return jsonb_build_object(
      'id', v_command.id,
      'status', v_command.status,
      'acked_at', v_command.acked_at
    );
  end if;

  return jsonb_build_object(
    'id', p_command_id,
    'status', 'unknown',
    'acked_at', null
  );
end;
$function$;

revoke all on function public.ack_device_command(uuid, uuid, boolean, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.ack_device_command(uuid, uuid, boolean, text, jsonb)
  to service_role;
