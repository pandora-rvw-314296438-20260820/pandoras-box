create or replace function private.pandora_coordinator_gate_invoke_v1(p_body jsonb)
returns bigint
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_action text;
  v_key text;
  v_request_id bigint;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt() ->> 'role','') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;

  if p_body is null or jsonb_typeof(p_body) <> 'object' then
    raise exception 'coordinator request must be an object' using errcode='22023';
  end if;
  if octet_length(p_body::text) > 49152 then
    raise exception 'coordinator request too large' using errcode='22023';
  end if;

  v_action := coalesce(p_body ->> 'action','');
  if v_action not in (
    'publish','read','claimMerge','completeMerge','abortMerge','expire',
    'readSnapshot','promoteSnapshot','abortSnapshot'
  ) then
    raise exception 'unsupported coordinator action' using errcode='22023';
  end if;

  select decrypted_secret into strict v_key
  from vault.decrypted_secrets
  where name='pandora_coordinator_gate_internal_v1'
  limit 1;
  if nullif(btrim(v_key),'') is null then
    raise exception 'coordinator credential unavailable' using errcode='55000';
  end if;

  select net.http_post(
    url := 'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-coordinator-gate',
    body := p_body,
    headers := jsonb_build_object(
      'content-type','application/json',
      'x-pandora-coordinator-key',v_key
    ),
    timeout_milliseconds := 15000
  ) into v_request_id;

  return v_request_id;
end;
$fn$;

revoke all on function private.pandora_coordinator_gate_invoke_v1(jsonb)
  from public, anon, authenticated;
grant execute on function private.pandora_coordinator_gate_invoke_v1(jsonb)
  to service_role;
