-- Pandora exactly-once customer project creation v1.
-- A client retry with the same idempotency key and same normalized request
-- replays the original project identity. A reused key with different input
-- fails closed. External runtime provisioning is intentionally outside this
-- transaction.

begin;

create table if not exists public.pandora_project_creation_requests (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  requester_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  request_sha256 text not null,
  project_id uuid references public.projectos_projects(id) on delete restrict,
  state text not null default 'claimed',
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (organization_id, requester_id, idempotency_key),
  constraint pandora_project_creation_idempotency_key_check
    check (length(btrim(idempotency_key)) between 8 and 200),
  constraint pandora_project_creation_request_sha_check
    check (request_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_project_creation_state_check
    check (state in ('claimed','completed')),
  constraint pandora_project_creation_completion_check
    check ((state = 'completed') = (project_id is not null and completed_at is not null))
);

alter table public.pandora_project_creation_requests enable row level security;
revoke all on table public.pandora_project_creation_requests from public, anon, authenticated;
grant all on table public.pandora_project_creation_requests to service_role;

create index if not exists pandora_project_creation_project_idx
  on public.pandora_project_creation_requests(project_id)
  where project_id is not null;

create or replace function public.pandora_create_customer_project_v1(
  p_organization_id uuid,
  p_requester_id uuid,
  p_idempotency_key text,
  p_request_sha256 text,
  p_name text,
  p_objective text,
  p_build_kind text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.pandora_project_creation_requests%rowtype;
  v_project public.projectos_projects%rowtype;
  v_project_id uuid;
  v_project_key text;
  v_slug text;
  v_now timestamptz := clock_timestamp();
  v_config jsonb;
  v_replayed boolean := false;
begin
  if p_organization_id is null
     or p_requester_id is null
     or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 200
     or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or length(btrim(coalesce(p_name,''))) not between 2 and 100
     or length(btrim(coalesce(p_objective,''))) not between 10 and 50000
     or p_build_kind not in (
       'website','web_app','mobile_app','internal_tool',
       'automation','api_backend','full_system','help_me_decide'
     ) then
    raise exception 'PROJECT_CREATE_INVALID_REQUEST' using errcode='22023';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = p_requester_id
      and m.status::text = 'active'
      and m.role::text in ('owner','admin')
  ) then
    raise exception 'PROJECT_CREATE_NOT_ALLOWED' using errcode='42501';
  end if;

  insert into public.pandora_project_creation_requests(
    organization_id, requester_id, idempotency_key, request_sha256
  ) values (
    p_organization_id, p_requester_id, btrim(p_idempotency_key), p_request_sha256
  )
  on conflict (organization_id, requester_id, idempotency_key) do nothing;

  select *
    into strict v_request
  from public.pandora_project_creation_requests
  where organization_id = p_organization_id
    and requester_id = p_requester_id
    and idempotency_key = btrim(p_idempotency_key)
  for update;

  if v_request.request_sha256 <> p_request_sha256 then
    raise exception 'PROJECT_CREATE_IDEMPOTENCY_COLLISION' using errcode='23505';
  end if;

  if v_request.project_id is not null then
    select *
      into strict v_project
    from public.projectos_projects
    where id = v_request.project_id
      and organization_id = p_organization_id;

    return jsonb_build_object(
      'project', to_jsonb(v_project),
      'replayed', true
    );
  end if;

  v_project_id := gen_random_uuid();
  v_slug := left(
    trim(both '-' from regexp_replace(lower(btrim(p_name)), '[^a-z0-9]+', '-', 'g')),
    42
  );
  if v_slug = '' then v_slug := 'project'; end if;
  v_project_key := v_slug || '-' || substr(replace(v_project_id::text,'-',''),1,8);

  v_config := jsonb_build_object(
    'customerJourney', jsonb_build_object(
      'buildKind', p_build_kind,
      'stage', 'understanding',
      'runtimeStatus', 'not_configured',
      'createdFrom', 'simple_mode',
      'updatedAt', v_now
    )
  );

  insert into public.projectos_projects(
    id, organization_id, project_key, name, workspace_path, status,
    objective, roadmap_version, config, created_by, created_at, updated_at
  ) values (
    v_project_id, p_organization_id, v_project_key, btrim(p_name),
    'projectos/projects/' || v_project_key, 'active',
    btrim(p_objective), '2.0.0', v_config, p_requester_id, v_now, v_now
  )
  returning * into v_project;

  update public.pandora_project_creation_requests
  set project_id = v_project_id,
      state = 'completed',
      completed_at = v_now
  where organization_id = p_organization_id
    and requester_id = p_requester_id
    and idempotency_key = btrim(p_idempotency_key);

  return jsonb_build_object(
    'project', to_jsonb(v_project),
    'replayed', v_replayed
  );
end
$function$;

revoke all on function public.pandora_create_customer_project_v1(
  uuid,uuid,text,text,text,text,text
) from public, anon, authenticated;
grant execute on function public.pandora_create_customer_project_v1(
  uuid,uuid,text,text,text,text,text
) to service_role;

commit;
