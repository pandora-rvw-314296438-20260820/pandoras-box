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
     or p_evidence->>'challengeNonce' <> c.nonce::text
     or p_evidence->>'packageName' <> 'com.banataosystems.pandora_mobile'
     or p_evidence->>'nativeRuntime' <> 'llama.cpp'
     or p_evidence->>'runtimeNativeAbi' <> 'arm64-v8a'
     or apk_sha <> c.expected_apk_sha256 or apk_sha !~ '^[0-9a-f]{64}$'
     or model_sha !~ '^[0-9a-f]{64}$' or device_hash !~ '^[0-9a-f]{64}$'
     or model_name is null or backend <> 'cpu' or network_state <> 'offline'
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
revoke all on function public.capture_phone_local_ai_acceptance(uuid,uuid,jsonb) from public, anon;
grant execute on function public.capture_phone_local_ai_acceptance(uuid,uuid,jsonb) to authenticated;
