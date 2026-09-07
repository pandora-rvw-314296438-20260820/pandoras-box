-- Capacity recovery for provider-retired Pandora Edge helpers.
-- Source classification authority: ec9c02fe13095d34c3c7433d1db743ac5a57e14e (#459).
-- This broker can delete only the 30 exact project/slug/version tuples classified
-- RETIRE_CANDIDATE_SELF_RETIRED. It re-proves provider identity before mutation
-- and proves absence afterwards. Provider credentials stay in Supabase Vault.

create table if not exists private.pandora_edge_function_retirement_receipts (
  project_ref text not null,
  slug text not null,
  expected_version integer not null check (expected_version > 0),
  classification_source_sha text not null
    check (classification_source_sha ~ '^[0-9a-f]{40}$'),
  delete_status integer not null,
  verification_status integer not null,
  deleted_at timestamptz not null default now(),
  primary key (project_ref, slug)
);

revoke all on table private.pandora_edge_function_retirement_receipts
  from public, anon, authenticated;
grant select on table private.pandora_edge_function_retirement_receipts
  to service_role;

create or replace function private.pandora_retire_self_retired_edge_function_20260907(
  p_project_ref text,
  p_slug text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'private', 'vault', 'extensions', 'public'
as $function$
declare
  v_expected_version integer;
  v_classification_sha constant text :=
    'ec9c02fe13095d34c3c7433d1db743ac5a57e14e';
  v_token text;
  v_project_probe extensions.http_response;
  v_preflight extensions.http_response;
  v_delete extensions.http_response;
  v_verify extensions.http_response;
  v_metadata jsonb;
  v_receipt private.pandora_edge_function_retirement_receipts%rowtype;
begin
  if p_project_ref is null or p_slug is null then
    raise exception 'project ref and function slug are required' using errcode='22023';
  end if;

  case p_project_ref || ':' || p_slug
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b1-format-probe-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b1-artifact-probe-20260901' then v_expected_version := 3;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b1-final-repair-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b1-rebase-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b1-unused-candidate-fix-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b1-format-space-fix-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b1-green-merge-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b2-create-branch-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b2-focus-write-20260901' then v_expected_version := 4;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b2-sync-main-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b2-controller-write-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b2-open-pr-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b2-sync-fix-import-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-b2-merge-pr201-20260901' then v_expected_version := 3;
    when 'jcyqixttuebxqqfkjonq:pandora-evo-task28-github-supabase-write-20260901' then v_expected_version := 4;
    when 'jcyqixttuebxqqfkjonq:pandora-github-vault-retry-probe-20260901' then v_expected_version := 32;
    when 'jcyqixttuebxqqfkjonq:pandora-memory-prod-retrigger-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-exact-android-artifact-transfer-20260901' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-exact-android-apk-20260901' then v_expected_version := 6;
    when 'jcyqixttuebxqqfkjonq:pandora-publish-exact-apk-release-20260901' then v_expected_version := 5;
    when 'jcyqixttuebxqqfkjonq:pandora-source-convergence-worker-phase3-canary' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-task118-paid-source-e2e-20260903' then v_expected_version := 7;
    when 'jcyqixttuebxqqfkjonq:pandora-task118-source-e2e-once-20260903' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-task118-launcher-20260903' then v_expected_version := 5;
    when 'jcyqixttuebxqqfkjonq:pandora-task118-authenticated-probe-20260903' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-p1-memory-proof-rebind-20260903' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-p1-merge-pr326-20260903' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-p1-sync-pr326-20260903' then v_expected_version := 2;
    when 'jcyqixttuebxqqfkjonq:pandora-p1-merge-pr326-v2-20260903' then v_expected_version := 4;
    when 'ivmvufhcsezyhczzondn:pandora-evo-task28-closure-write-20260901' then v_expected_version := 2;
    else
      raise exception 'Edge function is outside the reviewed retirement allowlist'
        using errcode='22023';
  end case;

  for v_token in
    select decrypted_secret
    from vault.decrypted_secrets
    where name in (
      'mcpmaster_supabase_account_1_pat',
      'mcpmaster_supabase_account_2_pat'
    )
    order by case name
      when 'mcpmaster_supabase_account_1_pat' then 1
      else 2
    end
  loop
    select * into v_project_probe
    from extensions.http((
      'GET'::extensions.http_method,
      ('https://api.supabase.com/v1/projects/' || p_project_ref)::varchar,
      array[
        extensions.http_header('authorization', 'Bearer ' || v_token),
        extensions.http_header('accept', 'application/json'),
        extensions.http_header('user-agent', 'Pandora-Edge-Retirement/1.0')
      ]::extensions.http_header[],
      null::varchar,
      null::varchar
    )::extensions.http_request);
    exit when v_project_probe.status = 200;
  end loop;

  if v_project_probe.status is distinct from 200 or nullif(v_token, '') is null then
    v_token := null;
    raise exception 'Supabase management credential unavailable for target project'
      using errcode='55000';
  end if;

  select * into v_preflight
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.supabase.com/v1/projects/' || p_project_ref ||
      '/functions/' || p_slug)::varchar,
    array[
      extensions.http_header('authorization', 'Bearer ' || v_token),
      extensions.http_header('accept', 'application/json'),
      extensions.http_header('user-agent', 'Pandora-Edge-Retirement/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  if v_preflight.status = 404 then
    select * into v_receipt
    from private.pandora_edge_function_retirement_receipts
    where project_ref = p_project_ref and slug = p_slug;

    v_token := null;
    if v_receipt.project_ref is not null then
      return jsonb_build_object(
        'deleted', true,
        'alreadyVerified', true,
        'projectRef', p_project_ref,
        'slug', p_slug,
        'expectedVersion', v_receipt.expected_version,
        'classificationSourceSha', v_receipt.classification_source_sha,
        'deletedAt', v_receipt.deleted_at
      );
    end if;
    raise exception 'retirement candidate is absent without a Pandora retirement receipt'
      using errcode='55000';
  end if;

  if v_preflight.status <> 200 then
    v_token := null;
    raise exception 'Edge retirement preflight failed with status %', v_preflight.status
      using errcode='55000';
  end if;

  begin
    v_metadata := nullif(v_preflight.content, '')::jsonb;
  exception when others then
    v_token := null;
    raise exception 'Edge retirement preflight returned invalid metadata'
      using errcode='55000';
  end;

  if coalesce((v_metadata->>'version')::integer, -1) <> v_expected_version
     or v_metadata->>'slug' is distinct from p_slug
     or v_metadata->>'status' is distinct from 'ACTIVE' then
    v_token := null;
    raise exception 'Edge retirement candidate changed after classification'
      using errcode='55000';
  end if;

  select * into v_delete
  from extensions.http((
    'DELETE'::extensions.http_method,
    ('https://api.supabase.com/v1/projects/' || p_project_ref ||
      '/functions/' || p_slug)::varchar,
    array[
      extensions.http_header('authorization', 'Bearer ' || v_token),
      extensions.http_header('accept', 'application/json'),
      extensions.http_header('user-agent', 'Pandora-Edge-Retirement/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  if v_delete.status <> 200 then
    v_token := null;
    raise exception 'Supabase Edge retirement failed with status %', v_delete.status
      using errcode='55000';
  end if;

  select * into v_verify
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.supabase.com/v1/projects/' || p_project_ref ||
      '/functions/' || p_slug)::varchar,
    array[
      extensions.http_header('authorization', 'Bearer ' || v_token),
      extensions.http_header('accept', 'application/json'),
      extensions.http_header('user-agent', 'Pandora-Edge-Retirement/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  v_token := null;

  if v_verify.status <> 404 then
    raise exception 'Supabase Edge retirement could not prove provider absence'
      using errcode='55000';
  end if;

  insert into private.pandora_edge_function_retirement_receipts (
    project_ref,
    slug,
    expected_version,
    classification_source_sha,
    delete_status,
    verification_status
  )
  values (
    p_project_ref,
    p_slug,
    v_expected_version,
    v_classification_sha,
    v_delete.status,
    v_verify.status
  )
  on conflict (project_ref, slug) do update
  set expected_version = excluded.expected_version,
      classification_source_sha = excluded.classification_source_sha,
      delete_status = excluded.delete_status,
      verification_status = excluded.verification_status,
      deleted_at = now()
  returning * into v_receipt;

  return jsonb_build_object(
    'deleted', true,
    'alreadyVerified', false,
    'projectRef', p_project_ref,
    'slug', p_slug,
    'expectedVersion', v_expected_version,
    'classificationSourceSha', v_classification_sha,
    'deleteStatus', v_delete.status,
    'verificationStatus', v_verify.status,
    'deletedAt', v_receipt.deleted_at
  );
end;
$function$;

revoke all on function private.pandora_retire_self_retired_edge_function_20260907(text,text)
  from public, anon, authenticated;
grant execute on function private.pandora_retire_self_retired_edge_function_20260907(text,text)
  to service_role;
