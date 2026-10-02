begin;

-- Lane G go-live follow-up.
-- Ticket issuance must commit before Vercel attempts the OIDC-backed claim.
-- The previous synchronous SQL bridge inserted the ticket and called Vercel in
-- one transaction, so the external claim could never observe the uncommitted row.
create or replace function public.pandora_issue_bedrock_chat_ticket_v1(
  p_model text,
  p_body jsonb
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions','pg_temp'
as $$
declare
  v_role text;
  v_target text;
  v_provider text;
  v_token text;
  v_token_sha text;
  v_expires_at timestamptz;
  v_max_tokens integer;
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in('postgres','service_role','supabase_admin') and v_role<>'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  if coalesce(p_model,'')!~'^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$'
     or p_body is null
     or jsonb_typeof(p_body)<>'object'
     or jsonb_typeof(p_body->'parts')<>'array'
     or jsonb_array_length(p_body->'parts') not between 1 and 64 then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_body) k where k not in('system','parts','maxTokens')) then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end if;
  begin
    v_max_tokens:=coalesce(nullif(p_body->>'maxTokens','')::integer,4096);
  exception when others then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end;
  if v_max_tokens not between 1 and 8192 or octet_length(p_body::text)>1048576 then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end if;

  select c.invocation_target,c.provider_name
  into v_target,v_provider
  from private.pandora_bedrock_reasoning_catalog c
  where c.model_id=p_model
    and c.routable=true
    and c.conversational=true
    and c.present_in_latest_sync=true
    and c.runtime_verification_status='passed'
    and c.lifecycle_status='ACTIVE'
    and nullif(c.invocation_target,'') is not null
  limit 1;
  if v_target is null then
    raise exception 'BEDROCK_CHAT_MODEL_UNAVAILABLE' using errcode='55000';
  end if;

  delete from private.pandora_bedrock_chat_tickets
  where expires_at<=clock_timestamp();

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_token_sha:=encode(extensions.digest(v_token,'sha256'),'hex');
  v_expires_at:=clock_timestamp()+interval '2 minutes';

  insert into private.pandora_bedrock_chat_tickets(
    token_sha256,model_id,invocation_target,provider_name,request_body,expires_at
  ) values(
    v_token_sha,p_model,v_target,v_provider,
    p_body||jsonb_build_object('maxTokens',v_max_tokens),v_expires_at
  );

  return jsonb_build_object('ticket',v_token,'expiresAt',v_expires_at);
end;
$$;

revoke all on function public.pandora_issue_bedrock_chat_ticket_v1(text,jsonb)
from public,anon,authenticated;
grant execute on function public.pandora_issue_bedrock_chat_ticket_v1(text,jsonb)
to service_role;

comment on function public.pandora_issue_bedrock_chat_ticket_v1(text,jsonb)
is 'Service-role-only one-time Bedrock chat ticket issuer. The issuing RPC commits before the caller sends the opaque ticket to the Vercel OIDC signer.';

commit;
