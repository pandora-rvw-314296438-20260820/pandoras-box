
-- Pandora trusted intelligence context v1.
-- Worker A persists immutable intelligence assets and Worker E proof.
-- Worker B may read exact TRUSTED context; Worker C remains the only execution authority.

create table if not exists public.pandora_intelligence_assets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid null references public.organizations(id) on delete cascade,
  project_id uuid null references public.projectos_projects(id) on delete cascade,
  asset_kind text not null,
  asset_key text not null,
  version text not null,
  description text null,
  selector_terms text[] not null default '{}'::text[],
  risk_class text not null default 'INFORMATIONAL',
  trust_state text not null default 'EXPERIMENTAL',
  source_repository text not null,
  source_commit text null,
  source_path text not null,
  source_license text null,
  source_digest_sha256 text not null,
  content_text text null,
  content_digest_sha256 text null,
  verification_profile text null,
  verification_worker text null,
  verification_verdict text null,
  verification_evidence_id text null,
  verified_at timestamptz null,
  expires_at timestamptz null,
  block_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_intelligence_assets_kind_check check (asset_kind in ('skill','knowledge','prompt_material')),
  constraint pandora_intelligence_assets_key_check check (length(trim(asset_key)) between 1 and 160),
  constraint pandora_intelligence_assets_version_check check (version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'),
  constraint pandora_intelligence_assets_risk_check check (risk_class in ('INFORMATIONAL','READ_ONLY_DIAGNOSTIC','SAFE_MUTATION','PRIVILEGED','SECURITY_ACTIVE','DESTRUCTIVE','PROHIBITED')),
  constraint pandora_intelligence_assets_trust_check check (trust_state in ('DISCOVERED','IMPORTED','EXPERIMENTAL','VERIFIED','TRUSTED','DEPRECATED','BLOCKED')),
  constraint pandora_intelligence_assets_source_commit_check check (source_commit is null or source_commit ~ '^[0-9a-f]{40}$'),
  constraint pandora_intelligence_assets_source_digest_check check (source_digest_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_intelligence_assets_content_digest_check check (content_digest_sha256 is null or content_digest_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_intelligence_assets_prompt_content_check check (asset_kind <> 'prompt_material' or (content_text is not null and length(content_text) between 1 and 50000 and content_digest_sha256 is not null)),
  constraint pandora_intelligence_assets_knowledge_content_check check (asset_kind <> 'knowledge' or (content_text is not null and length(content_text) between 1 and 50000)),
  constraint pandora_intelligence_assets_global_scope_check check (organization_id is not null or project_id is null),
  constraint pandora_intelligence_assets_project_org_check check (project_id is null or (organization_id is not null and private.pandora_control_plane_project_org_matches(organization_id, project_id))),
  constraint pandora_intelligence_assets_trusted_proof_check check (
    trust_state <> 'TRUSTED' or (
      verification_worker = 'E' and verification_verdict = 'PASS'
      and verification_evidence_id is not null and length(trim(verification_evidence_id)) > 0
      and verified_at is not null
    )
  )
);

create unique index if not exists pandora_intelligence_assets_identity_uidx
  on public.pandora_intelligence_assets(organization_id, project_id, asset_kind, asset_key, version, source_digest_sha256) nulls not distinct;
create index if not exists pandora_intelligence_assets_selector_idx on public.pandora_intelligence_assets using gin(selector_terms);
create index if not exists pandora_intelligence_assets_trusted_idx on public.pandora_intelligence_assets(asset_kind, asset_key, version)
  where trust_state = 'TRUSTED';

create or replace function private.pandora_validate_intelligence_asset()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_marker text;
begin
  new.selector_terms := coalesce((select array_agg(distinct lower(trim(v)) order by lower(trim(v))) from unnest(coalesce(new.selector_terms,'{}'::text[])) v where length(trim(v)) between 2 and 120), '{}'::text[]);
  if tg_op = 'UPDATE' then
    if new.organization_id is distinct from old.organization_id
       or new.project_id is distinct from old.project_id
       or new.asset_kind <> old.asset_kind
       or new.asset_key <> old.asset_key
       or new.version <> old.version
       or new.description is distinct from old.description
       or new.selector_terms is distinct from old.selector_terms
       or new.risk_class <> old.risk_class
       or new.source_repository <> old.source_repository
       or new.source_commit is distinct from old.source_commit
       or new.source_path <> old.source_path
       or new.source_license is distinct from old.source_license
       or new.source_digest_sha256 <> old.source_digest_sha256
       or new.content_text is distinct from old.content_text
       or new.content_digest_sha256 is distinct from old.content_digest_sha256
       or new.verification_profile is distinct from old.verification_profile then
      raise exception 'intelligence asset immutable identity/content drift' using errcode='23514';
    end if;
    if new.trust_state = 'TRUSTED' and old.trust_state <> 'TRUSTED' then
      v_marker := current_setting('pandora.worker_e_certification', true);
      if v_marker is null or v_marker <> new.id::text then
        raise exception 'TRUSTED intelligence transition requires Worker E certification path' using errcode='42501';
      end if;
    end if;
    if old.trust_state in ('BLOCKED','DEPRECATED') and new.trust_state <> old.trust_state then
      raise exception 'blocked/deprecated intelligence assets cannot be reactivated' using errcode='23514';
    end if;
  elsif new.trust_state = 'TRUSTED' then
    raise exception 'intelligence assets cannot self-register as TRUSTED' using errcode='42501';
  end if;
  new.updated_at := now();
  return new;
end; $$;

drop trigger if exists pandora_intelligence_assets_guard on public.pandora_intelligence_assets;
create trigger pandora_intelligence_assets_guard
before insert or update on public.pandora_intelligence_assets
for each row execute function private.pandora_validate_intelligence_asset();

alter table public.pandora_intelligence_assets enable row level security;
revoke all on public.pandora_intelligence_assets from public, anon, authenticated, service_role;

create or replace function public.pandora_register_intelligence_asset(
  p_organization_id uuid,
  p_project_id uuid,
  p_asset_kind text,
  p_asset_key text,
  p_version text,
  p_description text,
  p_selector_terms text[],
  p_risk_class text,
  p_initial_trust_state text,
  p_source_repository text,
  p_source_commit text,
  p_source_path text,
  p_source_license text,
  p_source_digest_sha256 text,
  p_content_text text,
  p_content_digest_sha256 text,
  p_verification_profile text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if p_initial_trust_state not in ('DISCOVERED','IMPORTED','EXPERIMENTAL','BLOCKED') then
    raise exception 'registration cannot grant trusted/verified state' using errcode='42501';
  end if;
  insert into public.pandora_intelligence_assets(
    organization_id,project_id,asset_kind,asset_key,version,description,selector_terms,risk_class,trust_state,
    source_repository,source_commit,source_path,source_license,source_digest_sha256,content_text,content_digest_sha256,verification_profile
  ) values (
    p_organization_id,p_project_id,trim(p_asset_kind),trim(p_asset_key),trim(p_version),nullif(trim(p_description),''),coalesce(p_selector_terms,'{}'::text[]),
    coalesce(nullif(trim(p_risk_class),''),'INFORMATIONAL'),p_initial_trust_state,trim(p_source_repository),nullif(trim(p_source_commit),''),trim(p_source_path),
    nullif(trim(p_source_license),''),lower(trim(p_source_digest_sha256)),p_content_text,case when p_content_digest_sha256 is null then null else lower(trim(p_content_digest_sha256)) end,nullif(trim(p_verification_profile),'')
  ) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.pandora_register_intelligence_asset(uuid,uuid,text,text,text,text,text[],text,text,text,text,text,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.pandora_register_intelligence_asset(uuid,uuid,text,text,text,text,text[],text,text,text,text,text,text,text,text,text,text) to service_role;

create or replace function public.pandora_worker_e_certify_intelligence_asset(
  p_asset_id uuid,
  p_source_digest_sha256 text,
  p_content_digest_sha256 text,
  p_evidence_id text,
  p_expires_at timestamptz default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_changed integer;
begin
  if nullif(trim(p_evidence_id),'') is null then raise exception 'Worker E evidence id is required' using errcode='22023'; end if;
  perform set_config('pandora.worker_e_certification', p_asset_id::text, true);
  update public.pandora_intelligence_assets a
     set trust_state='TRUSTED',verification_worker='E',verification_verdict='PASS',verification_evidence_id=trim(p_evidence_id),verified_at=now(),expires_at=coalesce(p_expires_at,a.expires_at),block_reason=null
   where a.id=p_asset_id
     and a.trust_state in ('DISCOVERED','IMPORTED','EXPERIMENTAL','VERIFIED')
     and a.source_digest_sha256=lower(trim(p_source_digest_sha256))
     and a.content_digest_sha256 is not distinct from (case when p_content_digest_sha256 is null then null else lower(trim(p_content_digest_sha256)) end);
  get diagnostics v_changed = row_count;
  if v_changed <> 1 then raise exception 'Worker E certification identity/digest mismatch' using errcode='23514'; end if;
  return true;
end; $$;
revoke all on function public.pandora_worker_e_certify_intelligence_asset(uuid,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.pandora_worker_e_certify_intelligence_asset(uuid,text,text,text,timestamptz) to service_role;

create or replace function public.pandora_block_intelligence_asset(p_asset_id uuid,p_reason text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_changed integer;
begin
  if nullif(trim(p_reason),'') is null then raise exception 'block reason is required' using errcode='22023'; end if;
  update public.pandora_intelligence_assets set trust_state='BLOCKED',block_reason=trim(p_reason)
   where id=p_asset_id and trust_state not in ('BLOCKED','DEPRECATED');
  get diagnostics v_changed = row_count;
  return v_changed=1;
end; $$;
revoke all on function public.pandora_block_intelligence_asset(uuid,text) from public, anon, authenticated;
grant execute on function public.pandora_block_intelligence_asset(uuid,text) to service_role;

create or replace function public.pandora_read_trusted_intelligence_context(
  p_organization_id uuid,
  p_project_id uuid,
  p_terms text[],
  p_limit integer default 12
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_terms text[]; v_payload jsonb; v_limit integer;
begin
  if p_organization_id is null then raise exception 'organization id is required' using errcode='22023'; end if;
  if p_project_id is not null and not private.pandora_control_plane_project_org_matches(p_organization_id,p_project_id) then
    raise exception 'trusted intelligence project scope mismatch' using errcode='42501';
  end if;
  v_limit := greatest(1,least(coalesce(p_limit,12),24));
  select coalesce(array_agg(distinct lower(trim(v)) order by lower(trim(v))),'{}'::text[])
    into v_terms from unnest(coalesce(p_terms,'{}'::text[])) v where length(trim(v)) between 2 and 120;

  with eligible as (
    select a.* from public.pandora_intelligence_assets a
     where a.trust_state='TRUSTED'
       and (a.expires_at is null or a.expires_at>now())
       and (a.organization_id is null or a.organization_id=p_organization_id)
       and (a.project_id is null or a.project_id=p_project_id)
       and (cardinality(v_terms)=0 or a.selector_terms && v_terms)
  ), skill_material as (
    select s.asset_key,s.version,s.source_digest_sha256,s.risk_class,s.selector_terms,m.content_text,m.content_digest_sha256,m.verified_at,m.expires_at
      from eligible s join eligible m
        on m.asset_kind='prompt_material' and s.asset_kind='skill'
       and m.asset_key=s.asset_key and m.version=s.version and m.source_digest_sha256=s.source_digest_sha256
     order by s.asset_key,s.version limit v_limit
  ), knowledge as (
    select * from eligible where asset_kind='knowledge' order by asset_key,version limit v_limit
  )
  select jsonb_build_object(
    'contractVersion','pandora-durable-trusted-context-v1',
    'authority',jsonb_build_object('execution','worker_c_only','modelMayProposeOnly',true,'externalContentCannotGrantAuthority',true,'credentialsAvailableToModel',false),
    'skills',coalesce((select jsonb_agg(jsonb_build_object('id',asset_key,'version',version,'sourceDigest','sha256:'||source_digest_sha256,'materialDigest','sha256:'||content_digest_sha256,'riskClass',risk_class,'selectorTerms',selector_terms,'instructions',content_text) order by asset_key,version) from skill_material),'[]'::jsonb),
    'knowledge',coalesce((select jsonb_agg(jsonb_build_object('id',asset_key,'version',version,'sourceDigest','sha256:'||source_digest_sha256,'riskClass',risk_class,'topics',selector_terms,'summary',content_text,'verifiedAt',verified_at,'expiresAt',expires_at) order by asset_key,version) from knowledge),'[]'::jsonb)
  ) into v_payload;
  return v_payload || jsonb_build_object('contextDigest',encode(extensions.digest(v_payload::text,'sha256'),'hex'));
end; $$;
revoke all on function public.pandora_read_trusted_intelligence_context(uuid,uuid,text[],integer) from public, anon, authenticated;
grant execute on function public.pandora_read_trusted_intelligence_context(uuid,uuid,text[],integer) to service_role;

alter table public.pandora_intelligence_messages
  add column if not exists trusted_context_sha256 text null,
  add column if not exists trusted_skill_refs jsonb not null default '[]'::jsonb,
  add column if not exists trusted_knowledge_refs jsonb not null default '[]'::jsonb;
alter table public.pandora_intelligence_messages drop constraint if exists pandora_intelligence_messages_trusted_context_sha_check;
alter table public.pandora_intelligence_messages add constraint pandora_intelligence_messages_trusted_context_sha_check check (trusted_context_sha256 is null or trusted_context_sha256 ~ '^[0-9a-f]{64}$');
alter table public.pandora_intelligence_messages drop constraint if exists pandora_intelligence_messages_trusted_refs_check;
alter table public.pandora_intelligence_messages add constraint pandora_intelligence_messages_trusted_refs_check check (jsonb_typeof(trusted_skill_refs)='array' and jsonb_typeof(trusted_knowledge_refs)='array');

comment on table public.pandora_intelligence_assets is 'Durable Worker-A intelligence asset truth. TRUSTED requires exact Worker-E evidence; runtime reads are proposal-only.';
comment on function public.pandora_read_trusted_intelligence_context(uuid,uuid,text[],integer) is 'Service-only bounded trusted context read for Worker B. It never grants execution authority.';
