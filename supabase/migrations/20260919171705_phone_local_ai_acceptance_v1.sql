create table if not exists private.phone_local_ai_acceptance_challenges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$'),
  nonce uuid not null default gen_random_uuid(),
  expected_apk_sha256 text not null check (expected_apk_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '10 minutes'),
  consumed_at timestamptz,
  unique (nonce)
);

create table if not exists private.phone_local_ai_acceptance_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  challenge_id uuid not null unique references private.phone_local_ai_acceptance_challenges(id) on delete restrict,
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$'),
  apk_sha256 text not null check (apk_sha256 ~ '^[0-9a-f]{64}$'),
  model_name text not null check (length(model_name) between 1 and 255),
  model_sha256 text not null check (model_sha256 ~ '^[0-9a-f]{64}$'),
  device_id_hash text not null check (device_id_hash ~ '^[0-9a-f]{64}$'),
  runtime_backend text not null check (runtime_backend in ('cpu','vulkan','gpu','npu','nnapi')),
  network_state text not null check (network_state = 'offline'),
  local_only_path_verified boolean not null check (local_only_path_verified),
  cloud_used boolean not null check (not cloud_used),
  physical_device boolean not null check (physical_device),
  emulator_detected boolean not null check (not emulator_detected),
  cancellation_verified boolean not null check (cancellation_verified),
  unload_reload_verified boolean not null check (unload_reload_verified),
  model_load_ms bigint check (model_load_ms is null or model_load_ms >= 0),
  time_to_first_token_ms bigint not null check (time_to_first_token_ms >= 0),
  generation_ms bigint not null check (generation_ms > 0),
  generated_token_events integer not null check (generated_token_events > 0),
  token_events_per_second double precision not null check (token_events_per_second > 0),
  evidence jsonb not null,
  receipt_sha256 text not null unique check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  captured_at timestamptz not null default clock_timestamp()
);

create or replace function private.reject_phone_local_ai_receipt_mutation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  raise exception 'phone-local AI acceptance receipts are immutable' using errcode='42501';
end;
$$;

drop trigger if exists phone_local_ai_acceptance_receipts_immutable
  on private.phone_local_ai_acceptance_receipts;
create trigger phone_local_ai_acceptance_receipts_immutable
before update or delete on private.phone_local_ai_acceptance_receipts
for each row execute function private.reject_phone_local_ai_receipt_mutation();

create or replace function public.begin_phone_local_ai_acceptance(
  p_organization_id uuid, p_source_sha text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  build public.pandora_local_ai_build_receipts%rowtype;
  challenge private.phone_local_ai_acceptance_challenges%rowtype;
begin
  if uid is null then raise exception 'authentication required' using errcode='42501'; end if;
  if p_source_sha !~ '^[0-9a-f]{40}$' then raise exception 'invalid source sha' using errcode='22023'; end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=uid and m.status::text='active'
  ) then raise exception 'active organization membership required' using errcode='42501'; end if;

  select * into build from public.pandora_local_ai_build_receipts b
  where b.source_sha=p_source_sha
    and b.status in ('passed','success','ready')
    and b.apk_sha256 ~ '^[0-9a-f]{64}$'
    and b.apk_size_bytes > 0
  order by b.updated_at desc limit 1;
  if build.build_id is null then
    raise exception 'verified exact-source APK build required' using errcode='55000';
  end if;

  insert into private.phone_local_ai_acceptance_challenges(
    organization_id,user_id,source_sha,expected_apk_sha256
  ) values (p_organization_id,uid,p_source_sha,build.apk_sha256)
  returning * into challenge;

  return jsonb_build_object(
    'challengeId',challenge.id,'nonce',challenge.nonce,'sourceSha',challenge.source_sha,
    'expectedApkSha256',challenge.expected_apk_sha256,'expiresAt',challenge.expires_at
  );
end;
$$;

create or replace function public.capture_phone_local_ai_acceptance(
  p_challenge_id uuid, p_nonce uuid, p_evidence jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  c private.phone_local_ai_acceptance_challenges%rowtype;
  r private.phone_local_ai_acceptance_receipts%rowtype;
  basis text; digest_hex text;
  apk_sha text := lower(coalesce(p_evidence->>'apkSha256',''));
  model_sha text := lower(coalesce(p_evidence->>'modelSha256',''));
  device_hash text := lower(coalesce(p_evidence->>'deviceIdHash',''));
  backend text := lower(coalesce(p_evidence->>'runtimeBackend',''));
  model_name text := nullif(trim(coalesce(p_evidence->>'modelName','')),'');
  network_state text := lower(coalesce(p_evidence->>'networkState',''));
  ttft bigint; generation bigint; token_events integer; token_rate double precision; load_ms bigint;
begin
  if uid is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into c from private.phone_local_ai_acceptance_challenges where id=p_challenge_id for update;
  if c.id is null or c.user_id<>uid or c.nonce<>p_nonce or c.consumed_at is not null
     or c.expires_at < clock_timestamp() then
    raise exception 'invalid or expired acceptance challenge' using errcode='42501';
  end if;
  if p_evidence->>'sourceSha' <> c.source_sha
     or apk_sha <> c.expected_apk_sha256 or apk_sha !~ '^[0-9a-f]{64}$'
     or model_sha !~ '^[0-9a-f]{64}$' or device_hash !~ '^[0-9a-f]{64}$'
     or model_name is null or backend not in ('cpu','vulkan','gpu','npu','nnapi')
     or network_state <> 'offline'
     or coalesce((p_evidence->>'localOnlyPathVerified')::boolean,false) is not true
     or coalesce((p_evidence->>'cloudUsed')::boolean,true) is not false
     or coalesce((p_evidence->>'physicalDevice')::boolean,false) is not true
     or coalesce((p_evidence->>'emulatorDetected')::boolean,true) is not false
     or coalesce((p_evidence->>'cancellationVerified')::boolean,false) is not true
     or coalesce((p_evidence->>'unloadReloadVerified')::boolean,false) is not true then
    raise exception 'invalid phone-local acceptance evidence' using errcode='22023';
  end if;
  begin
    ttft := (p_evidence->>'timeToFirstTokenMs')::bigint;
    generation := (p_evidence->>'generationMs')::bigint;
    token_events := (p_evidence->>'generatedTokenEvents')::integer;
    token_rate := (p_evidence->>'tokenEventsPerSecond')::double precision;
    load_ms := nullif(p_evidence->>'modelLoadMs','')::bigint;
  exception when others then
    raise exception 'invalid phone-local acceptance metrics' using errcode='22023';
  end;
  if ttft < 0 or generation <= 0 or token_events <= 0 or token_rate <= 0
     or (load_ms is not null and load_ms < 0) then
    raise exception 'invalid phone-local acceptance metrics' using errcode='22023';
  end if;
  basis := concat_ws('|','pandora-phone-local-ai-acceptance-v1',
    c.organization_id::text,c.user_id::text,c.id::text,c.nonce::text,
    c.source_sha,c.expected_apk_sha256,model_name,model_sha,device_hash,
    backend,network_state,ttft::text,generation::text,token_events::text,
    token_rate::text,coalesce(load_ms::text,''));
  digest_hex := encode(extensions.digest(convert_to(basis,'UTF8'),'sha256'),'hex');
  update private.phone_local_ai_acceptance_challenges set consumed_at=clock_timestamp() where id=c.id;
  insert into private.phone_local_ai_acceptance_receipts(
    organization_id,user_id,challenge_id,source_sha,apk_sha256,model_name,model_sha256,
    device_id_hash,runtime_backend,network_state,local_only_path_verified,cloud_used,
    physical_device,emulator_detected,cancellation_verified,unload_reload_verified,
    model_load_ms,time_to_first_token_ms,generation_ms,generated_token_events,
    token_events_per_second,evidence,receipt_sha256
  ) values (
    c.organization_id,uid,c.id,c.source_sha,apk_sha,model_name,model_sha,device_hash,
    backend,network_state,true,false,true,false,true,true,load_ms,ttft,generation,
    token_events,token_rate,p_evidence,digest_hex
  ) returning * into r;
  return jsonb_build_object(
    'verified',true,'authority','PHONE_LOCAL_AI_ACCEPTANCE_V1',
    'receiptId',r.id,'receiptSha256',r.receipt_sha256,'sourceSha',r.source_sha,
    'apkSha256',r.apk_sha256,'modelSha256',r.model_sha256,'deviceIdHash',r.device_id_hash,
    'runtimeBackend',r.runtime_backend,'capturedAt',r.captured_at
  );
end;
$$;

create or replace function public.get_phone_local_ai_acceptance_status(
  p_organization_id uuid, p_source_sha text
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.phone_local_ai_acceptance_receipts%rowtype;
begin
  perform private.assert_control_service_role();
  select * into r from private.phone_local_ai_acceptance_receipts
  where organization_id=p_organization_id and source_sha=p_source_sha
  order by captured_at desc limit 1;
  if r.id is null then return null; end if;
  return jsonb_build_object(
    'verified',true,'authority','PHONE_LOCAL_AI_ACCEPTANCE_V1','receiptId',r.id,
    'receiptSha256',r.receipt_sha256,'sourceSha',r.source_sha,'apkSha256',r.apk_sha256,
    'modelName',r.model_name,'modelSha256',r.model_sha256,'deviceIdHash',r.device_id_hash,
    'runtimeBackend',r.runtime_backend,'networkState',r.network_state,
    'modelLoadMs',r.model_load_ms,'timeToFirstTokenMs',r.time_to_first_token_ms,
    'generationMs',r.generation_ms,'generatedTokenEvents',r.generated_token_events,
    'tokenEventsPerSecond',r.token_events_per_second,'capturedAt',r.captured_at
  );
end;
$$;

revoke all on table private.phone_local_ai_acceptance_challenges from public, anon, authenticated;
revoke all on table private.phone_local_ai_acceptance_receipts from public, anon, authenticated;
revoke all on function private.reject_phone_local_ai_receipt_mutation() from public, anon, authenticated, service_role;
revoke all on function public.begin_phone_local_ai_acceptance(uuid,text) from public, anon;
revoke all on function public.capture_phone_local_ai_acceptance(uuid,uuid,jsonb) from public, anon;
revoke all on function public.get_phone_local_ai_acceptance_status(uuid,text) from public, anon, authenticated;
grant execute on function public.begin_phone_local_ai_acceptance(uuid,text) to authenticated;
grant execute on function public.capture_phone_local_ai_acceptance(uuid,uuid,jsonb) to authenticated;
grant execute on function public.get_phone_local_ai_acceptance_status(uuid,text) to service_role;
