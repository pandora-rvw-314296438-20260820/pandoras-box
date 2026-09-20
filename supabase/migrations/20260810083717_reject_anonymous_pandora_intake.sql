-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function public.projectos_accept_intake(
  p_organization_id uuid,
  p_requester_id uuid,
  p_request_text text,
  p_project_key text default null,
  p_project_name text default null,
  p_repository text default null,
  p_request_type text default 'work',
  p_source text default 'operator',
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'private', 'auth', 'extensions', 'pg_temp'
as $$
declare
  v_project public.projectos_projects%rowtype;
  v_intake public.projectos_intake_requests%rowtype;
  v_key text;
  v_policy public.projectos_policies%rowtype;
begin
  if auth.role() <> 'service_role'
     and coalesce(auth.jwt() ->> 'is_anonymous', 'false') = 'true' then
    raise exception 'projectos_permanent_account_required' using errcode = '42501';
  end if;

  if auth.role() <> 'service_role' and not private.is_org_member(p_organization_id) then
    raise exception 'projectos_forbidden';
  end if;
  if p_requester_id is not null and auth.role() <> 'service_role' and p_requester_id <> auth.uid() then
    raise exception 'projectos_requester_mismatch';
  end if;

  select * into v_policy from public.projectos_policies where organization_id = p_organization_id;
  if found and v_policy.allow_untracked_work then raise exception 'invalid_projectos_policy'; end if;

  if p_project_key is not null and trim(p_project_key) <> '' then
    v_key := lower(trim(p_project_key));
  elsif p_repository is not null and trim(p_repository) <> '' then
    v_key := lower(regexp_replace(split_part(p_repository, '/', 2), '[^a-zA-Z0-9._-]+', '-', 'g'));
  elsif p_project_name is not null and trim(p_project_name) <> '' then
    v_key := lower(regexp_replace(trim(p_project_name), '[^a-zA-Z0-9._-]+', '-', 'g'));
  else
    v_key := 'projectos-inbox';
  end if;

  select * into v_project
  from public.projectos_projects
  where organization_id = p_organization_id
    and (project_key = v_key or (p_repository is not null and repository = p_repository))
  order by case when project_key = v_key then 0 else 1 end
  limit 1;

  if not found then
    perform public.projectos_register_project(
      p_organization_id,
      v_key,
      coalesce(nullif(trim(p_project_name), ''), initcap(replace(v_key, '-', ' '))),
      p_repository,
      'Automatically created by mandatory ProjectOS intake.',
      p_requester_id
    );
    select * into v_project from public.projectos_projects
      where organization_id = p_organization_id and project_key = v_key;
  end if;

  insert into public.projectos_intake_requests (
    organization_id, project_id, requester_id, source, request_type, request_text,
    project_hint, repository_hint, idempotency_key, status, analysis
  ) values (
    p_organization_id, v_project.id, p_requester_id, p_source, p_request_type,
    p_request_text, v_key, p_repository,
    coalesce(nullif(p_idempotency_key, ''), encode(digest(p_organization_id::text || ':' || p_request_text, 'sha256'), 'hex')),
    'accepted',
    jsonb_build_object(
      'workspacePath', v_project.workspace_path,
      'mandatoryControlLayer', true,
      'nextAction', 'analyze_current_state'
    )
  )
  on conflict (organization_id, idempotency_key) do update set
    project_id = excluded.project_id
  returning * into v_intake;

  return jsonb_build_object('intake', to_jsonb(v_intake), 'project', to_jsonb(v_project));
end;
$$;

comment on function public.projectos_accept_intake(uuid, uuid, text, text, text, text, text, text, text)
is 'Accepts governed ProjectOS intake for permanent organization members or the service role; anonymous sessions are rejected.';
