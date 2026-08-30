
begin;

create table if not exists public.pandora_primitive_verification_runs (
  id uuid primary key default gen_random_uuid(),
  primitive_name text not null,
  primitive_version text not null,
  source_commit text not null,
  source_manifest_path text not null,
  source_digest text not null,
  manifest_sha256 text,
  evidence_sha256 text,
  status text not null check (status in ('PASS','FAIL','BLOCKED')),
  verifier_identity text not null default 'worker-e-primitive-static-v1',
  checks jsonb not null default '[]'::jsonb,
  failure_summary text,
  created_at timestamptz not null default now(),
  completed_at timestamptz not null default now()
);

create index if not exists pandora_primitive_verification_runs_identity_idx
  on public.pandora_primitive_verification_runs (primitive_name, primitive_version, created_at desc);

alter table public.pandora_primitive_verification_runs enable row level security;
alter table public.pandora_primitive_verification_runs force row level security;
revoke all on public.pandora_primitive_verification_runs from public, anon, authenticated, service_role;

drop trigger if exists pandora_guard_primitive_trust_promotion on public.pandora_primitive_catalog_entries;
drop function if exists private.pandora_guard_primitive_trust_promotion_20260831();

create or replace function private.pandora_guard_primitive_trust_promotion_20260831()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $fn$
declare
  v_run public.pandora_primitive_verification_runs%rowtype;
begin
  if new.trust_state = 'TRUSTED' and old.trust_state is distinct from 'TRUSTED' then
    if nullif(new.worker_e_evidence_ref, '') is null
       or new.worker_e_evidence_ref !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'TRUSTED primitive promotion requires persisted Worker E evidence' using errcode='23514';
    end if;

    select * into v_run
    from public.pandora_primitive_verification_runs
    where id = new.worker_e_evidence_ref::uuid;

    if not found
       or v_run.status <> 'PASS'
       or v_run.verifier_identity <> 'worker-e-primitive-static-v1'
       or v_run.primitive_name <> new.primitive_name
       or v_run.primitive_version <> new.primitive_version
       or v_run.source_commit <> new.source_commit
       or v_run.source_manifest_path <> new.source_manifest_path
       or v_run.source_digest <> new.source_digest
       or v_run.evidence_sha256 is null then
      raise exception 'TRUSTED primitive promotion evidence does not match immutable primitive identity' using errcode='23514';
    end if;
  end if;
  return new;
end;
$fn$;

create trigger pandora_guard_primitive_trust_promotion
before update of trust_state, worker_e_evidence_ref, source_commit, source_manifest_path, source_digest
on public.pandora_primitive_catalog_entries
for each row execute function private.pandora_guard_primitive_trust_promotion_20260831();

create or replace function private.pandora_worker_e_verify_primitive_20260831(
  p_primitive_name text,
  p_primitive_version text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, public, extensions
as $fn$
declare
  v_catalog public.pandora_primitive_catalog_entries%rowtype;
  v_manifest_response jsonb;
  v_file_response jsonb;
  v_manifest_text text;
  v_manifest jsonb;
  v_file jsonb;
  v_file_text text;
  v_path text;
  v_expected_sha text;
  v_actual_sha text;
  v_manifest_sha text;
  v_evidence_sha text;
  v_evidence_chain text := '';
  v_checks jsonb;
  v_run_id uuid := gen_random_uuid();
  v_file_count integer := 0;
  v_failure text;
begin
  if nullif(trim(p_primitive_name),'') is null
     or p_primitive_name !~ '^pandora-[a-z0-9-]+$'
     or nullif(trim(p_primitive_version),'') is null
     or p_primitive_version !~ '^[0-9]+[.][0-9]+[.][0-9]+$' then
    raise exception 'invalid primitive identity' using errcode='22023';
  end if;

  select * into strict v_catalog
  from public.pandora_primitive_catalog_entries
  where primitive_name = p_primitive_name
    and primitive_version = p_primitive_version
  for update;

  if v_catalog.source_commit !~ '^[0-9a-f]{40}$'
     or v_catalog.source_digest !~ '^sha256:[0-9a-f]{64}$'
     or v_catalog.source_manifest_path !~ '^packages/primitives/[A-Za-z0-9._/-]+/SOURCE_MANIFEST[.]json$'
     or v_catalog.source_manifest_path like '%..%' then
    raise exception 'primitive catalog source identity is not immutable/bounded' using errcode='23514';
  end if;

  begin
    v_manifest_response := private.pandora_integration_github_api_20260825(
      'GET',
      '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/' || v_catalog.source_manifest_path || '?ref=' || v_catalog.source_commit,
      null
    );
    if coalesce((v_manifest_response->>'status')::integer,0) <> 200 then
      raise exception 'exact primitive source manifest unavailable';
    end if;

    v_manifest_text := convert_from(
      decode(replace(v_manifest_response->'body'->>'content', E'\n', ''), 'base64'),
      'utf8'
    );
    if nullif(v_manifest_text,'') is null or octet_length(v_manifest_text) > 131072 then
      raise exception 'primitive source manifest is empty or exceeds bound';
    end if;
    v_manifest := v_manifest_text::jsonb;

    if v_manifest->>'primitive' <> p_primitive_name || '@' || p_primitive_version then
      raise exception 'primitive source manifest identity mismatch';
    end if;
    if v_manifest->>'bundleDigest' <> v_catalog.source_digest then
      raise exception 'primitive source manifest bundle digest mismatch';
    end if;
    if jsonb_typeof(v_manifest->'files') <> 'array'
       or jsonb_array_length(v_manifest->'files') < 1
       or jsonb_array_length(v_manifest->'files') > 64 then
      raise exception 'primitive source manifest file list is invalid';
    end if;

    v_manifest_sha := encode(extensions.digest(convert_to(v_manifest_text,'utf8'),'sha256'),'hex');

    for v_file in select value from jsonb_array_elements(v_manifest->'files')
    loop
      v_file_count := v_file_count + 1;
      v_path := v_file->>'path';
      v_expected_sha := v_file->>'sha256';
      if nullif(v_path,'') is null
         or v_path like '%..%'
         or v_path like '/%'
         or v_path !~ '^[A-Za-z0-9._/-]+$'
         or v_expected_sha !~ '^[0-9a-f]{64}$' then
        raise exception 'primitive source manifest contains invalid file identity';
      end if;

      v_file_response := private.pandora_integration_github_api_20260825(
        'GET',
        '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/packages/primitives/' || v_path || '?ref=' || v_catalog.source_commit,
        null
      );
      if coalesce((v_file_response->>'status')::integer,0) <> 200 then
        raise exception 'exact primitive source file unavailable: %', v_path;
      end if;

      v_file_text := convert_from(
        decode(replace(v_file_response->'body'->>'content', E'\n', ''), 'base64'),
        'utf8'
      );
      if octet_length(v_file_text) > 524288 then
        raise exception 'primitive source file exceeds verifier bound: %', v_path;
      end if;
      v_actual_sha := encode(extensions.digest(convert_to(v_file_text,'utf8'),'sha256'),'hex');
      if v_actual_sha <> v_expected_sha then
        raise exception 'primitive source file digest mismatch: %', v_path;
      end if;

      if v_file_text ~* '-----BEGIN[[:space:]]+(RSA|EC|OPENSSH|DSA)?[[:space:]]*PRIVATE[[:space:]]+KEY-----'
         or v_file_text ~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
         or v_file_text ~ 'PANDORA_FAKE_SECRET_CANARY'
         or v_file_text ~* 'DISABLE[[:space:]]+ROW[[:space:]]+LEVEL[[:space:]]+SECURITY' then
        raise exception 'primitive source failed bounded security scan: %', v_path;
      end if;

      v_evidence_chain := v_evidence_chain || v_path || E'\t' || v_actual_sha || E'\n';
    end loop;

    v_evidence_sha := encode(
      extensions.digest(
        convert_to(v_catalog.source_commit || E'\n' || v_catalog.source_digest || E'\n' || v_manifest_sha || E'\n' || v_evidence_chain,'utf8'),
        'sha256'
      ),
      'hex'
    );

    v_checks := jsonb_build_array(
      jsonb_build_object('check_id','primitive.manifest_identity','status','PASS','authoritative_issuer','pandora-verification-engine','evidence_refs',jsonb_build_array('sha256:'||v_manifest_sha)),
      jsonb_build_object('check_id','primitive.file_hashes','status','PASS','authoritative_issuer','pandora-verification-engine','evidence_refs',jsonb_build_array('sha256:'||v_evidence_sha),'file_count',v_file_count),
      jsonb_build_object('check_id','security.secret_scan','status','PASS','authoritative_issuer','pandora-verification-engine','evidence_refs',jsonb_build_array('sha256:'||v_evidence_sha)),
      jsonb_build_object('check_id','security.static_policy','status','PASS','authoritative_issuer','pandora-verification-engine','evidence_refs',jsonb_build_array('sha256:'||v_evidence_sha))
    );

    insert into public.pandora_primitive_verification_runs(
      id,primitive_name,primitive_version,source_commit,source_manifest_path,source_digest,
      manifest_sha256,evidence_sha256,status,verifier_identity,checks,completed_at
    ) values (
      v_run_id,p_primitive_name,p_primitive_version,v_catalog.source_commit,v_catalog.source_manifest_path,v_catalog.source_digest,
      v_manifest_sha,v_evidence_sha,'PASS','worker-e-primitive-static-v1',v_checks,now()
    );

    update public.pandora_primitive_catalog_entries
    set trust_state='TRUSTED', worker_e_evidence_ref=v_run_id::text
    where primitive_name=p_primitive_name and primitive_version=p_primitive_version;

    return jsonb_build_object(
      'status','PASS','primitive',p_primitive_name,'version',p_primitive_version,
      'sourceCommit',v_catalog.source_commit,'sourceDigest',v_catalog.source_digest,
      'manifestSha256','sha256:'||v_manifest_sha,'evidenceSha256','sha256:'||v_evidence_sha,
      'evidenceId',v_run_id,'fileCount',v_file_count,'verifier','worker-e-primitive-static-v1'
    );
  exception when others then
    v_failure := left(sqlerrm,500);
    insert into public.pandora_primitive_verification_runs(
      id,primitive_name,primitive_version,source_commit,source_manifest_path,source_digest,
      status,verifier_identity,checks,failure_summary,completed_at
    ) values (
      v_run_id,p_primitive_name,p_primitive_version,v_catalog.source_commit,v_catalog.source_manifest_path,v_catalog.source_digest,
      'FAIL','worker-e-primitive-static-v1','[]'::jsonb,v_failure,now()
    );
    return jsonb_build_object(
      'status','FAIL','primitive',p_primitive_name,'version',p_primitive_version,
      'evidenceId',v_run_id,'failure',v_failure
    );
  end;
end;
$fn$;

create or replace function public.pandora_worker_e_verify_primitive_20260831(
  p_primitive_name text,
  p_primitive_version text
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, private, public
as $fn$
  select private.pandora_worker_e_verify_primitive_20260831(p_primitive_name,p_primitive_version)
$fn$;

revoke all on function public.pandora_worker_e_verify_primitive_20260831(text,text) from public, anon, authenticated;
grant execute on function public.pandora_worker_e_verify_primitive_20260831(text,text) to service_role;

commit;
