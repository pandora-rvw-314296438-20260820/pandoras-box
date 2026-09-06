begin;

-- The Supabase shared functions domain rewrites HTML to text/plain and applies
-- a non-renderable sandbox. Keep Supabase as the capability/storage authority,
-- but serve the exact bytes through Pandora's Vercel origin where HTML MIME and
-- an isolated script-capable sandbox can be enforced.

do $migration$
declare
  v_def text;
  v_old text := 'v_url:=''https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-preview-host/''||v_token||''/index.html'';';
  v_new text := 'v_url:=''https://mcpmaster.vercel.app/preview/''||v_token||''/index.html'';';
begin
  select pg_get_functiondef(
    'private.pandora_create_supabase_preview_fallback_20260830(uuid,uuid,uuid,text)'::regprocedure
  ) into v_def;
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_PROXY_CREATE_ANCHOR_MISSING' using errcode='55000';
    end if;
    execute replace(v_def,v_old,v_new);
  end if;
end
$migration$;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid)'::regprocedure
  ) into v_def;

  if position('v_runtime_content_type text' in v_def)=0 then
    v_old := '  v_runtime extensions.http_response;'||chr(10)||'  v_runtime_ok boolean:=false;';
    v_new := '  v_runtime extensions.http_response;'||chr(10)||
             '  v_runtime_content_type text:='''''';'||chr(10)||
             '  v_runtime_csp text:='''''';'||chr(10)||
             '  v_runtime_ok boolean:=false;';
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_VERIFY_DECLARATION_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := '^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/';
  v_new := '^https://mcpmaster[.]vercel[.]app/preview/';
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_VERIFY_TOKEN_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := '      v_runtime_ok:=v_runtime.status between 200 and 399;'||chr(10)||
           '      v_runtime_body:=left(coalesce(v_runtime.content,''''),1048576);';
  v_new := '      select lower(coalesce((h).value,'''')) into v_runtime_content_type'||chr(10)||
           '      from unnest(v_runtime.headers) h where lower((h).field)=''content-type'' limit 1;'||chr(10)||
           '      select lower(coalesce((h).value,'''')) into v_runtime_csp'||chr(10)||
           '      from unnest(v_runtime.headers) h where lower((h).field)=''content-security-policy'' limit 1;'||chr(10)||
           '      v_runtime_ok:=v_runtime.status between 200 and 399'||chr(10)||
           '        and v_runtime_content_type like ''text/html%'''||chr(10)||
           '        and position(''sandbox'' in v_runtime_csp)>0'||chr(10)||
           '        and position(''allow-scripts'' in v_runtime_csp)>0'||chr(10)||
           '        and position(''allow-same-origin'' in v_runtime_csp)=0;'||chr(10)||
           '      v_runtime_body:=left(coalesce(v_runtime.content,''''),1048576);';
  if position('v_runtime_content_type like ''text/html%''' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_VERIFY_RUNTIME_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := 'concat_ws(''|'',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,''static_site'',v_ver.source_sha256';
  v_new := 'concat_ws(''|'',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,''static_site_renderable_v2'',v_dep.url,v_ver.source_sha256';
  if position('static_site_renderable_v2' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_VERIFY_IDENTITY_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := 'jsonb_build_object(''httpStatus'',v_runtime.status,''runtimeBodySha256'',v_runtime_digest,''previewProvider'',''supabase_preview'')';
  v_new := 'jsonb_build_object(''httpStatus'',v_runtime.status,''runtimeBodySha256'',v_runtime_digest,''previewProvider'',''supabase_preview'',''contentType'',v_runtime_content_type,''contentSecurityPolicy'',v_runtime_csp)';
  if position('''contentType'',v_runtime_content_type' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_VERIFY_EVIDENCE_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  execute v_def;
end
$migration$;

do $migration$
declare
  v_def text;
  v_start integer;
  v_stop integer;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_worker_e_verify_supabase_preview_v2_20260830(uuid,uuid)'::regprocedure
  ) into v_def;

  if position('SUPABASE_PREVIEW_BASE_VERIFICATION_MISSING' in v_def)=0 then
    v_start:=position('  select * into v_old' in v_def);
    v_stop:=position('  if upper(coalesce(v_old.status' in v_def);
    if v_start=0 or v_stop<=v_start then
      raise exception 'PREVIEW_VERIFY_V2_REPLAY_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_new :=
      '  v_base:=private.pandora_worker_e_verify_supabase_preview_20260830(p_deployment_id,p_requested_by);'||chr(10)||
      '  select * into v_old from public.pandora_verification_runs where id=(v_base->>''verificationRunId'')::uuid;'||chr(10)||
      '  if not found then raise exception ''SUPABASE_PREVIEW_BASE_VERIFICATION_MISSING'' using errcode=''55000''; end if;'||chr(10)||chr(10);
    v_def:=overlay(v_def placing v_new from v_start for v_stop-v_start);
    execute v_def;
  end if;
end
$migration$;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_evaluate_supabase_preview_acceptance_v2_20260830(uuid)'::regprocedure
  ) into v_def;

  v_old := 'v_dep.url !~ ''^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/[0-9a-f]{64}/index[.]html$''';
  v_new := 'v_dep.url !~ ''^https://mcpmaster[.]vercel[.]app/preview/[0-9a-f]{64}/index[.]html$''';
  if position('mcpmaster[.]vercel[.]app/preview' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_ACCEPTANCE_URL_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  if position('v_runtime_content_type text' in v_def)=0 then
    v_old := '  v_runtime extensions.http_response;'||chr(10)||'  v_body text := '''';';
    v_new := '  v_runtime extensions.http_response;'||chr(10)||
             '  v_runtime_content_type text := '''';'||chr(10)||
             '  v_runtime_csp text := '''';'||chr(10)||
             '  v_body text := '''';';
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_ACCEPTANCE_DECLARATION_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := '  v_body:=left(coalesce(v_runtime.content,''''),1048576);';
  v_new := '  select lower(coalesce((h).value,'''')) into v_runtime_content_type'||chr(10)||
           '  from unnest(v_runtime.headers) h where lower((h).field)=''content-type'' limit 1;'||chr(10)||
           '  select lower(coalesce((h).value,'''')) into v_runtime_csp'||chr(10)||
           '  from unnest(v_runtime.headers) h where lower((h).field)=''content-security-policy'' limit 1;'||chr(10)||
           '  if v_runtime_content_type not like ''text/html%'''||chr(10)||
           '     or position(''sandbox'' in v_runtime_csp)=0'||chr(10)||
           '     or position(''allow-scripts'' in v_runtime_csp)=0'||chr(10)||
           '     or position(''allow-same-origin'' in v_runtime_csp)>0 then'||chr(10)||
           '    return jsonb_build_object(''ok'',false,''reason'',''runtime_not_renderable'',''httpStatus'',v_runtime.status,''contentType'',v_runtime_content_type);'||chr(10)||
           '  end if;'||chr(10)||
           '  v_body:=left(coalesce(v_runtime.content,''''),1048576);';
  if position('runtime_not_renderable' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_ACCEPTANCE_RUNTIME_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  execute v_def;
end
$migration$;

do $migration$
declare
  v_def text;
  v_old text := 'v_url:=''https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-preview-host/''||v_token||''/index.html'';';
  v_new text := 'v_url:=''https://mcpmaster.vercel.app/preview/''||v_token||''/index.html'';';
begin
  select pg_get_functiondef(
    'private.pandora_publish_supabase_fallback_20260831(uuid,uuid,uuid,uuid)'::regprocedure
  ) into v_def;
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PRODUCTION_PROXY_CREATE_ANCHOR_MISSING' using errcode='55000';
    end if;
    execute replace(v_def,v_old,v_new);
  end if;
end
$migration$;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_worker_e_verify_supabase_production_20260831(uuid,uuid)'::regprocedure
  ) into v_def;

  v_old := '^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/';
  v_new := '^https://mcpmaster[.]vercel[.]app/preview/';
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PRODUCTION_VERIFY_URL_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  if position('v_runtime_content_type text' in v_def)=0 then
    v_old := '  v_runtime extensions.http_response;'||chr(10)||'  v_runtime_body text := '''';';
    v_new := '  v_runtime extensions.http_response;'||chr(10)||
             '  v_runtime_content_type text := '''';'||chr(10)||
             '  v_runtime_csp text := '''';'||chr(10)||
             '  v_runtime_body text := '''';';
    if position(v_old in v_def)=0 then
      raise exception 'PRODUCTION_VERIFY_DECLARATION_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := '    v_runtime_ok:=v_runtime.status between 200 and 399;'||chr(10)||
           '    v_runtime_body:=left(coalesce(v_runtime.content,''''),1048576);';
  v_new := '    select lower(coalesce((h).value,'''')) into v_runtime_content_type'||chr(10)||
           '    from unnest(v_runtime.headers) h where lower((h).field)=''content-type'' limit 1;'||chr(10)||
           '    select lower(coalesce((h).value,'''')) into v_runtime_csp'||chr(10)||
           '    from unnest(v_runtime.headers) h where lower((h).field)=''content-security-policy'' limit 1;'||chr(10)||
           '    v_runtime_ok:=v_runtime.status between 200 and 399'||chr(10)||
           '      and v_runtime_content_type like ''text/html%'''||chr(10)||
           '      and position(''sandbox'' in v_runtime_csp)>0'||chr(10)||
           '      and position(''allow-scripts'' in v_runtime_csp)>0'||chr(10)||
           '      and position(''allow-same-origin'' in v_runtime_csp)=0;'||chr(10)||
           '    v_runtime_body:=left(coalesce(v_runtime.content,''''),1048576);';
  if position('v_runtime_content_type like ''text/html%''' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PRODUCTION_VERIFY_RUNTIME_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := 'concat_ws(''|'',''supabase-static-production-v2'',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,v_ver.source_sha256';
  v_new := 'concat_ws(''|'',''supabase-static-production-renderable-v3'',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,v_dep.url,v_ver.source_sha256';
  if position('supabase-static-production-renderable-v3' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PRODUCTION_VERIFY_IDENTITY_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  execute v_def;
end
$migration$;

-- Translate existing capability URLs to the renderable proxy without changing
-- their opaque capability token. Verification is deliberately invalidated so
-- the new MIME/CSP contract must pass before the UI can call them verified.
with translated as (
  select
    id,
    'https://mcpmaster.vercel.app/preview/'||
      split_part(regexp_replace(url,'^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/',''), '/', 1)||
      '/index.html' as new_url
  from public.pandora_project_deployments
  where url ~ '^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/[0-9a-f]{64}/index[.]html$'
)
update public.pandora_project_deployments d
set
  url=t.new_url,
  immutable_url=t.new_url,
  stable_url=case when d.environment='preview' then t.new_url else d.stable_url end,
  status='ready_for_verification',
  verification_state='ready_for_verification',
  updated_at=clock_timestamp()
from translated t
where d.id=t.id;

update public.pandora_runtime_environments e
set
  verification_state='ready_for_verification',
  updated_at=clock_timestamp(),
  last_reconciled_at=clock_timestamp()
from public.pandora_project_deployments d
where d.id=e.current_deployment_id
  and d.url ~ '^https://mcpmaster[.]vercel[.]app/preview/[0-9a-f]{64}/index[.]html$';

update public.projectos_projects p
set config=jsonb_set(
  coalesce(p.config,'{}'::jsonb),
  '{customerJourney}',
  coalesce(p.config->'customerJourney','{}'::jsonb) ||
    case
      when coalesce(p.config->'customerJourney'->>'previewUrl','') ~ '^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/[0-9a-f]{64}/index[.]html$'
      then jsonb_build_object(
        'previewUrl',
        'https://mcpmaster.vercel.app/preview/'||
          split_part(regexp_replace(p.config->'customerJourney'->>'previewUrl','^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/',''), '/', 1)||
          '/index.html',
        'previewVerificationState','ready_for_verification',
        'runtimeStatus','verifying'
      )
      else '{}'::jsonb
    end ||
    case
      when coalesce(p.config->'customerJourney'->>'liveUrl','') ~ '^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/[0-9a-f]{64}/index[.]html$'
      then jsonb_build_object(
        'liveUrl',
        'https://mcpmaster.vercel.app/preview/'||
          split_part(regexp_replace(p.config->'customerJourney'->>'liveUrl','^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/',''), '/', 1)||
          '/index.html',
        'productionVerificationState','ready_for_verification',
        'runtimeStatus','verifying'
      )
      else '{}'::jsonb
    end,
  true
),
updated_at=clock_timestamp()
where
  coalesce(p.config->'customerJourney'->>'previewUrl','') like 'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-preview-host/%'
  or coalesce(p.config->'customerJourney'->>'liveUrl','') like 'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-preview-host/%';

comment on function private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid) is
'Worker E preview verification requires renderable HTML MIME plus an isolated script-capable sandbox and binds verification identity to the exact render transport.';
comment on function private.pandora_worker_e_verify_supabase_production_20260831(uuid,uuid) is
'Worker E Supabase fallback production verification requires the renderable Vercel proxy transport, HTML MIME, isolated script-capable sandbox, and exact response identity.';

commit;
