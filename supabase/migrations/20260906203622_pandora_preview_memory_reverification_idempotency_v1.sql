begin;

create or replace function private.enqueue_visible_preview_memory()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_version public.pandora_project_versions%rowtype;
  v_verification public.pandora_verification_runs%rowtype;
begin
  if new.environment <> 'preview' or new.verification_state <> 'live_verified'
     or (tg_op='UPDATE' and old.verification_state is not distinct from new.verification_state) then
    return new;
  end if;
  if new.source_sha256 !~ '^[0-9a-f]{64}$' or new.artifact_digest !~ '^[0-9a-f]{64}$' then
    return new;
  end if;

  -- A deployment is one visible preview evidence event. Transport
  -- re-certification creates a new verification run for the same deployment,
  -- but must preserve the original immutable memory evidence payload.
  if exists (
    select 1
    from private.execution_learning_outbox
    where event_key='visible:verified_preview:'||new.id::text
  ) then
    return new;
  end if;

  select * into v_version
  from public.pandora_project_versions
  where id=new.version_id
    and organization_id=new.organization_id
    and project_id=new.project_id;
  if v_version.id is null or v_version.verification_run_id is null then
    return new;
  end if;

  select * into v_verification
  from public.pandora_verification_runs
  where id=v_version.verification_run_id
    and organization_id=new.organization_id
    and project_id=new.project_id
    and project_version_id=new.version_id
    and status='PASS';
  if v_verification.id is null
     or v_verification.source_digest <> new.source_sha256
     or v_verification.artifact_digest <> new.artifact_digest then
    return new;
  end if;

  perform private.enqueue_visible_creation_memory_evidence(
    new.id,new.organization_id,new.project_id,'verified_preview','deployed',coalesce(new.ready_at,new.updated_at),
    new.version_id,null,v_verification.id,new.id,null,new.source_sha256,new.artifact_digest,null,null,null
  );
  return new;
end
$function$;

comment on function private.enqueue_visible_preview_memory() is
'Emits one immutable visible-preview memory evidence event per deployment. Later transport re-verification preserves the original event and remains represented by verification and audit evidence.';

commit;
