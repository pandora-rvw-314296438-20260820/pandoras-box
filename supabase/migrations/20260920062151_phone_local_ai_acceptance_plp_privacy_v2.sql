
alter table private.phone_local_ai_acceptance_challenges
  add column if not exists expected_package text,
  add column if not exists expected_model_sha256 text,
  add column if not exists acceptance_prompt_sha256 text;

update private.phone_local_ai_acceptance_challenges
set expected_package = coalesce(expected_package, 'com.banataosystems.pandora.plp'),
    expected_model_sha256 = coalesce(expected_model_sha256, '1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6'),
    acceptance_prompt_sha256 = coalesce(acceptance_prompt_sha256, 'f825a78c9dcfa953a987a905782db6b6b0b36143aa70eac6a4d2bad72ca59f46');

alter table private.phone_local_ai_acceptance_challenges
  alter column expected_package set not null,
  alter column expected_model_sha256 set not null,
  alter column acceptance_prompt_sha256 set not null;

alter table private.phone_local_ai_acceptance_challenges
  drop constraint if exists phone_local_ai_acceptance_challenges_expected_package_check,
  add constraint phone_local_ai_acceptance_challenges_expected_package_check
    check (expected_package = 'com.banataosystems.pandora.plp'),
  drop constraint if exists phone_local_ai_acceptance_challenges_expected_model_sha256_check,
  add constraint phone_local_ai_acceptance_challenges_expected_model_sha256_check
    check (expected_model_sha256 = '1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6'),
  drop constraint if exists phone_local_ai_acceptance_challenges_acceptance_prompt_sha256_check,
  add constraint phone_local_ai_acceptance_challenges_acceptance_prompt_sha256_check
    check (acceptance_prompt_sha256 = 'f825a78c9dcfa953a987a905782db6b6b0b36143aa70eac6a4d2bad72ca59f46');

alter table private.phone_local_ai_acceptance_receipts
  drop column if exists device_id_hash,
  add column if not exists acceptance_session_id text,
  add column if not exists package_name text,
  add column if not exists acceptance_prompt_sha256 text,
  add column if not exists acceptance_output_sha256 text,
  add column if not exists device_evidence_level text;

alter table private.phone_local_ai_acceptance_receipts
  alter column acceptance_session_id set not null,
  alter column package_name set not null,
  alter column acceptance_prompt_sha256 set not null,
  alter column acceptance_output_sha256 set not null,
  alter column device_evidence_level set not null;

alter table private.phone_local_ai_acceptance_receipts
  drop constraint if exists phone_local_ai_acceptance_receipts_acceptance_session_id_check,
  add constraint phone_local_ai_acceptance_receipts_acceptance_session_id_check
    check (acceptance_session_id ~ '^[0-9a-f]{64}$'),
  drop constraint if exists phone_local_ai_acceptance_receipts_package_name_check,
  add constraint phone_local_ai_acceptance_receipts_package_name_check
    check (package_name = 'com.banataosystems.pandora.plp'),
  drop constraint if exists phone_local_ai_acceptance_receipts_acceptance_prompt_sha256_check,
  add constraint phone_local_ai_acceptance_receipts_acceptance_prompt_sha256_check
    check (acceptance_prompt_sha256 = 'f825a78c9dcfa953a987a905782db6b6b0b36143aa70eac6a4d2bad72ca59f46'),
  drop constraint if exists phone_local_ai_acceptance_receipts_acceptance_output_sha256_check,
  add constraint phone_local_ai_acceptance_receipts_acceptance_output_sha256_check
    check (acceptance_output_sha256 = '8494f624333bf5613c6125789bd96a486236b9846dfc6e8a7dc4fdd7a5f1e2a7'),
  drop constraint if exists phone_local_ai_acceptance_receipts_device_evidence_level_check,
  add constraint phone_local_ai_acceptance_receipts_device_evidence_level_check
    check (device_evidence_level in ('heuristic','attested'));

create or replace function public.begin_phone_local_ai_acceptance(
  p_organization_id uuid,
  p_source_sha text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  build public.pandora_local_ai_build_receipts%rowtype;
  challenge private.phone_local_ai_acceptance_challenges%rowtype;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if p_source_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'invalid source sha' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=uid
      and m.status::text='active'
  ) then
    raise exception 'active organization membership required' using errcode='42501';
  end if;

  select * into build
  from public.pandora_local_ai_build_receipts b
  where b.source_sha=p_source_sha
    and b.status in ('passed','success','ready')
    and b.apk_sha256 ~ '^[0-9a-f]{64}$'
    and b.apk_size_bytes > 0
  order by b.updated_at desc, b.build_id desc
  limit 1;

  if build.build_id is null then
    raise exception 'verified exact-source APK build required' using errcode='55000';
  end if;

  insert into private.phone_local_ai_acceptance_challenges(
    organization_id,user_id,source_sha,expected_apk_sha256,
    expected_package,expected_model_sha256,acceptance_prompt_sha256
  ) values (
    p_organization_id,uid,p_source_sha,build.apk_sha256,
    'com.banataosystems.pandora.plp',
    '1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6',
    'f825a78c9dcfa953a987a905782db6b6b0b36143aa70eac6a4d2bad72ca59f46'
  ) returning * into challenge;

  return jsonb_build_object(
    'challengeId',challenge.id,
    'nonce',challenge.nonce,
    'sourceSha',challenge.source_sha,
    'expectedApkSha256',challenge.expected_apk_sha256,
    'expectedPackage',challenge.expected_package,
    'expectedModelSha256',challenge.expected_model_sha256,
    'acceptancePromptSha256',challenge.acceptance_prompt_sha256,
    'expiresAt',challenge.expires_at
  );
end;
$$;

create or replace function public.capture_phone_local_ai_acceptance(
  p_challenge_id uuid,
  p_nonce uuid,
  p_evidence jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  c private.phone_local_ai_acceptance_challenges%rowtype;
  r private.phone_local_ai_acceptance_receipts%rowtype;
  basis text;
  digest_hex text;
  apk_sha text := lower(coalesce(p_evidence->>'apkSha256',''));
  model_sha text := lower(coalesce(p_evidence->>'modelSha256',''));
  backend text := lower(coalesce(p_evidence->>'runtimeBackend',''));
  model_name text := nullif(trim(coalesce(p_evidence->>'modelName','')),'');
  network_state text := lower(coalesce(p_evidence->>'networkState',''));
  run_nonce uuid;
  session_id text;
  prompt_sha text := lower(coalesce(p_evidence->>'acceptancePromptSha256',''));
  output_sha text := lower(coalesce(p_evidence->>'acceptanceOutputSha256',''));
  device_level text := lower(coalesce(p_evidence->>'deviceEvidenceLevel','heuristic'));
  ttft bigint;
  generation bigint;
  token_events integer;
  token_rate double precision;
  load_ms bigint;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select * into c
  from private.phone_local_ai_acceptance_challenges
  where id=p_challenge_id
  for update;

  if c.id is null
     or c.user_id<>uid
     or c.nonce<>p_nonce
     or c.consumed_at is not null
     or c.expires_at < clock_timestamp() then
    raise exception 'invalid or expired acceptance challenge' using errcode='42501';
  end if;

  begin
    run_nonce := (p_evidence->>'runNonce')::uuid;
  exception when others then
    raise exception 'invalid acceptance run nonce' using errcode='22023';
  end;

  session_id := encode(
    extensions.digest(
      convert_to(c.nonce::text || '|' || run_nonce::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if p_evidence->>'sourceSha' <> c.source_sha
     or p_evidence->>'challengeNonce' <> c.nonce::text
     or p_evidence->>'packageName' <> c.expected_package
     or p_evidence->>'nativeRuntime' <> 'llama.cpp'
     or p_evidence->>'runtimeNativeAbi' <> 'arm64-v8a'
     or apk_sha <> c.expected_apk_sha256
     or apk_sha !~ '^[0-9a-f]{64}$'
     or model_sha <> c.expected_model_sha256
     or model_name <> 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf'
     or backend <> 'cpu'
     or network_state <> 'offline'
     or prompt_sha <> c.acceptance_prompt_sha256
     or output_sha <> '8494f624333bf5613c6125789bd96a486236b9846dfc6e8a7dc4fdd7a5f1e2a7'
     or coalesce((p_evidence->>'acceptanceOutputMatched')::boolean,false) is not true
     or device_level not in ('heuristic','attested')
     or coalesce((p_evidence->>'localOnlyPathVerified')::boolean,false) is not true
     or coalesce((p_evidence->>'cloudUsed')::boolean,true) is not false
     or coalesce((p_evidence->>'physicalDevice')::boolean,false) is not true
     or coalesce((p_evidence->>'emulatorDetected')::boolean,true) is not false
     or coalesce((p_evidence->>'cancellationVerified')::boolean,false) is not true
     or coalesce((p_evidence->>'unloadReloadVerified')::boolean,false) is not true
     or coalesce((p_evidence->>'gpuAccelerationUsed')::boolean,true) is not false
     or coalesce((p_evidence->>'npuAccelerationUsed')::boolean,true) is not false
     or coalesce((p_evidence->>'nnapiAccelerationUsed')::boolean,true) is not false
     or coalesce((p_evidence->>'acceleratorVerified')::boolean,true) is not false then
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

  basis := concat_ws('|',
    'pandora-phone-local-ai-acceptance-v2',
    c.organization_id::text,c.user_id::text,c.id::text,c.nonce::text,
    c.source_sha,c.expected_apk_sha256,c.expected_package,c.expected_model_sha256,
    session_id,prompt_sha,output_sha,device_level,
    model_name,model_sha,backend,network_state,
    ttft::text,generation::text,token_events::text,token_rate::text,
    coalesce(load_ms::text,'')
  );
  digest_hex := encode(extensions.digest(convert_to(basis,'UTF8'),'sha256'),'hex');

  update private.phone_local_ai_acceptance_challenges
  set consumed_at=clock_timestamp()
  where id=c.id;

  insert into private.phone_local_ai_acceptance_receipts(
    organization_id,user_id,challenge_id,source_sha,apk_sha256,
    model_name,model_sha256,runtime_backend,network_state,
    local_only_path_verified,cloud_used,physical_device,emulator_detected,
    cancellation_verified,unload_reload_verified,model_load_ms,
    time_to_first_token_ms,generation_ms,generated_token_events,
    token_events_per_second,evidence,receipt_sha256,
    acceptance_session_id,package_name,acceptance_prompt_sha256,
    acceptance_output_sha256,device_evidence_level
  ) values (
    c.organization_id,uid,c.id,c.source_sha,apk_sha,
    model_name,model_sha,backend,network_state,
    true,false,true,false,true,true,load_ms,
    ttft,generation,token_events,token_rate,
    p_evidence - 'generatedOutput' - 'prompt' - 'deviceIdHash',
    digest_hex,
    session_id,c.expected_package,prompt_sha,output_sha,device_level
  ) returning * into r;

  return jsonb_build_object(
    'verified',true,
    'authority','PHONE_LOCAL_AI_ACCEPTANCE_V2',
    'receiptId',r.id,
    'receiptSha256',r.receipt_sha256,
    'sourceSha',r.source_sha,
    'apkSha256',r.apk_sha256,
    'modelSha256',r.model_sha256,
    'acceptanceSessionId',r.acceptance_session_id,
    'packageName',r.package_name,
    'deviceEvidenceLevel',r.device_evidence_level,
    'runtimeBackend',r.runtime_backend,
    'capturedAt',r.captured_at
  );
end;
$$;

create or replace function public.get_phone_local_ai_acceptance_status(
  p_organization_id uuid,
  p_source_sha text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r private.phone_local_ai_acceptance_receipts%rowtype;
begin
  perform private.assert_control_service_role();
  select * into r
  from private.phone_local_ai_acceptance_receipts
  where organization_id=p_organization_id and source_sha=p_source_sha
  order by captured_at desc
  limit 1;
  if r.id is null then return null; end if;
  return jsonb_build_object(
    'verified',true,
    'authority','PHONE_LOCAL_AI_ACCEPTANCE_V2',
    'receiptId',r.id,
    'receiptSha256',r.receipt_sha256,
    'sourceSha',r.source_sha,
    'apkSha256',r.apk_sha256,
    'modelName',r.model_name,
    'modelSha256',r.model_sha256,
    'acceptanceSessionId',r.acceptance_session_id,
    'packageName',r.package_name,
    'deviceEvidenceLevel',r.device_evidence_level,
    'runtimeBackend',r.runtime_backend,
    'networkState',r.network_state,
    'modelLoadMs',r.model_load_ms,
    'timeToFirstTokenMs',r.time_to_first_token_ms,
    'generationMs',r.generation_ms,
    'generatedTokenEvents',r.generated_token_events,
    'tokenEventsPerSecond',r.token_events_per_second,
    'capturedAt',r.captured_at
  );
end;
$$;

revoke all on function public.begin_phone_local_ai_acceptance(uuid,text) from public, anon;
revoke all on function public.capture_phone_local_ai_acceptance(uuid,uuid,jsonb) from public, anon;
revoke all on function public.get_phone_local_ai_acceptance_status(uuid,text) from public, anon, authenticated;
grant execute on function public.begin_phone_local_ai_acceptance(uuid,text) to authenticated;
grant execute on function public.capture_phone_local_ai_acceptance(uuid,uuid,jsonb) to authenticated;
grant execute on function public.get_phone_local_ai_acceptance_status(uuid,text) to service_role;
