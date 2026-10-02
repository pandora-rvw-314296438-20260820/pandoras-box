begin;
create or replace function public.pandora_start_bedrock_control_v1(p_operation text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions','net','pg_temp'
as $$
declare
  v_role text;
  v_operation text:=lower(coalesce(trim(p_operation),''));
  v_token text;
  v_token_sha text;
  v_ticket_id uuid;
  v_request_id bigint;
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in('postgres','service_role','supabase_admin') and v_role<>'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if v_operation not in('sync','sync_probe') then
    raise exception 'BEDROCK_CONTROL_OPERATION_INVALID' using errcode='22023';
  end if;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_token_sha:=encode(extensions.digest(v_token,'sha256'),'hex');

  insert into private.pandora_bedrock_control_tickets(token_sha256,operation,expires_at)
  values(v_token_sha,v_operation,clock_timestamp()+interval '10 minutes')
  returning id into v_ticket_id;

  select net.http_post(
    url:='https://mcpmaster.vercel.app/api/operations-inference?operation=bedrock-control',
    body:=jsonb_build_object('operation',v_operation,'ticket',v_token),
    headers:=jsonb_build_object(
      'content-type','application/json',
      'cache-control','no-store',
      'user-agent','Pandora-Bedrock-Control/1.0'
    ),
    timeout_milliseconds:=180000
  ) into v_request_id;

  if v_request_id is null or v_request_id<1 then
    raise exception 'BEDROCK_CONTROL_REQUEST_NOT_ENQUEUED' using errcode='55000';
  end if;

  v_token:=null;
  return jsonb_build_object(
    'enqueued',true,
    'operation',v_operation,
    'ticketId',v_ticket_id,
    'requestId',v_request_id
  );
end;
$$;
revoke all on function public.pandora_start_bedrock_control_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_start_bedrock_control_v1(text) to service_role;
commit;
