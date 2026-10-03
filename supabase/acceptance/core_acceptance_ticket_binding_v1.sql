-- ISOLATED ACCEPTANCE ONLY. This is deliberately outside the production
-- migration ledger. Apply after the four reviewed v2 migrations, to the exact
-- approved branch, before installing its separate private configuration row.
-- No user, grant, catalogue verification or target is fabricated by this file.
begin;

create table private.pandora_core_acceptance_runtime_config (
  singleton boolean primary key default true check (singleton),
  supabase_project_ref text not null check (supabase_project_ref ~ '^[a-z0-9]{20}$'
    and supabase_project_ref not in ('jcyqixttuebxqqfkjonq','ivmvufhcsezyhczzondn')),
  organization_id uuid not null references public.organizations(id),
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$'),
  config_sha256 text not null check (config_sha256 ~ '^[0-9a-f]{64}$'),
  canonical_json text not null check (octet_length(canonical_json) between 1 and 4096),
  check (encode(extensions.digest(canonical_json,'sha256'),'hex') = config_sha256),
  check (coalesce(canonical_json::jsonb->>'profile' = 'core_acceptance_v1',false)),
  check (coalesce(canonical_json::jsonb->>'supabaseProjectRef' = supabase_project_ref,false)),
  check (coalesce(canonical_json::jsonb->>'organizationId' = organization_id::text,false)),
  check (coalesce(canonical_json::jsonb->>'sourceSha' = source_sha,false)),
  check (coalesce(canonical_json::jsonb->>'memoryMode' = 'unavailable',false))
);
alter table private.pandora_core_acceptance_runtime_config enable row level security;
revoke all on private.pandora_core_acceptance_runtime_config from public,anon,authenticated,service_role;

create table private.pandora_core_acceptance_bedrock_ticket_bindings (
  token_sha256 text primary key references private.pandora_bedrock_chat_tickets(token_sha256) on delete cascade,
  organization_id uuid not null references public.organizations(id),
  config_sha256 text not null check (config_sha256 ~ '^[0-9a-f]{64}$'),
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$')
);
alter table private.pandora_core_acceptance_bedrock_ticket_bindings enable row level security;
revoke all on private.pandora_core_acceptance_bedrock_ticket_bindings from public,anon,authenticated,service_role;

create function private.pandora_assert_core_acceptance_ticket_scope_v1(
  p_organization_id uuid,p_config_sha256 text,p_source_sha text
) returns void language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if not exists(select 1 from private.pandora_core_acceptance_runtime_config c
    where c.singleton and c.organization_id=p_organization_id
      and c.config_sha256=p_config_sha256 and c.source_sha=p_source_sha) then
    raise exception 'CORE_RUNTIME_TARGET_MISMATCH' using errcode='42501';
  end if;
end; $$;
revoke all on function private.pandora_assert_core_acceptance_ticket_scope_v1(uuid,text,text) from public,anon,authenticated,service_role;

create function public.pandora_issue_core_acceptance_bedrock_chat_ticket_v1(
  p_model text,p_body jsonb,p_organization_id uuid,p_config_sha256 text,p_source_sha text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_token_sha text;
begin
  perform private.pandora_assert_core_acceptance_ticket_scope_v1(p_organization_id,p_config_sha256,p_source_sha);
  -- The original issuer still validates the live catalogue and request body.
  -- Issuance and binding commit together; an unbound ticket is never returned.
  v_result:=public.pandora_issue_bedrock_chat_ticket_v1(p_model,p_body);
  v_token_sha:=encode(extensions.digest(v_result->>'ticket','sha256'),'hex');
  insert into private.pandora_core_acceptance_bedrock_ticket_bindings
    (token_sha256,organization_id,config_sha256,source_sha)
    values(v_token_sha,p_organization_id,p_config_sha256,p_source_sha);
  return v_result;
end; $$;

create function public.pandora_claim_core_acceptance_bedrock_chat_ticket_v1(
  p_token_sha256 text,p_organization_id uuid,p_config_sha256 text,p_source_sha text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  perform private.pandora_assert_core_acceptance_ticket_scope_v1(p_organization_id,p_config_sha256,p_source_sha);
  if not exists(select 1 from private.pandora_core_acceptance_bedrock_ticket_bindings b
    where b.token_sha256=p_token_sha256 and b.organization_id=p_organization_id
      and b.config_sha256=p_config_sha256 and b.source_sha=p_source_sha) then
    raise exception 'BEDROCK_CHAT_TICKET_DENIED' using errcode='42501';
  end if;
  -- The existing atomic DELETE is the sole one-time claim. The FK removes the
  -- binding in the same transaction; a racing/repeated claim cannot dispatch.
  v_result:=public.pandora_claim_bedrock_chat_ticket_v1(p_token_sha256);
  return v_result||jsonb_build_object('organizationId',p_organization_id,
    'configSha256',p_config_sha256,'sourceSha',p_source_sha);
end; $$;

revoke all on function public.pandora_issue_core_acceptance_bedrock_chat_ticket_v1(text,jsonb,uuid,text,text) from public,anon,authenticated;
revoke all on function public.pandora_claim_core_acceptance_bedrock_chat_ticket_v1(text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_issue_core_acceptance_bedrock_chat_ticket_v1(text,jsonb,uuid,text,text) to service_role;
grant execute on function public.pandora_claim_core_acceptance_bedrock_chat_ticket_v1(text,uuid,text,text) to service_role;
commit;
