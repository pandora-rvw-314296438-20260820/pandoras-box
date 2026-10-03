-- Pandora Core owner mode: canonical projections and governed operations.
-- Additive, tenant-scoped and backwards compatible. No parallel user/provider/job stores.
begin;

create table private.pandora_core_config (
  singleton boolean primary key default true check (singleton),
  platform_organization_id uuid not null references public.organizations(id),
  created_at timestamptz not null default now()
);
create table private.pandora_operator_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  organization_id uuid references public.organizations(id),
  role text not null check (role in ('owner','operator','support','finance')),
  state text not null default 'active' check (state in ('active','revoked')),
  expires_at timestamptz,
  granted_by uuid not null references auth.users(id),
  reason text not null check (length(reason) between 3 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (user_id,organization_id)
);
create index pandora_operator_grants_org_idx on private.pandora_operator_grants(organization_id);
create index pandora_operator_grants_granter_idx on private.pandora_operator_grants(granted_by);

create function private.pandora_core_actor_role_v1(p_actor uuid,p_organization_id uuid default null)
returns text language sql stable security definer set search_path='' as $$
 select g.role from private.pandora_operator_grants g
 join private.pandora_core_config c on c.singleton
 join public.memberships m on m.organization_id=c.platform_organization_id and m.user_id=g.user_id
 join auth.users u on u.id=g.user_id
 join public.organizations platform on platform.id=c.platform_organization_id and platform.status='active'
 where g.user_id=p_actor and m.status='active' and not coalesce(u.is_anonymous,false)
   and (u.banned_until is null or u.banned_until<=now()) and u.deleted_at is null
   and g.state='active' and (g.expires_at is null or g.expires_at>now())
   and (g.organization_id is null or g.organization_id=p_organization_id)
 order by case g.role when 'owner' then 1 when 'operator' then 2 when 'finance' then 3 else 4 end
 limit 1;
$$;
create function private.pandora_core_role_v1(p_organization_id uuid default null)
returns text language sql stable security definer set search_path='' as $$
 select case when auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')<>'true'
 then private.pandora_core_actor_role_v1(auth.uid(),p_organization_id) else null end;
$$;
create function private.pandora_core_assert_v1(p_organization_id uuid,p_roles text[],p_step_up boolean default false)
returns text language plpgsql stable security definer set search_path='' as $$
declare v_role text:=private.pandora_core_role_v1(p_organization_id); v_session uuid;
begin
 if v_role is null or not(v_role=any(p_roles)) then
  raise exception 'ACCESS_DENIED' using errcode='42501';
 end if;
 if p_organization_id is not null and not exists(select 1 from public.organizations where id=p_organization_id) then
  raise exception 'ACCESS_DENIED' using errcode='42501';
 end if;
 if p_step_up then
  begin v_session:=(auth.jwt()->>'session_id')::uuid; exception when invalid_text_representation then v_session:=null; end;
  if auth.jwt()->>'aal' is distinct from 'aal2' or v_session is null or not exists(
   select 1 from auth.sessions s where s.id=v_session and s.user_id=auth.uid()
   and s.aal::text='aal2' and (s.not_after is null or s.not_after>now())
  ) then raise exception 'STEP_UP_REQUIRED' using errcode='42501'; end if;
 end if;
 return v_role;
end;
$$;

create table public.pandora_enterprise_accounts (
 organization_id uuid primary key references public.organizations(id),
 industry text not null check (industry in ('hospitality','trade','legal','restaurant','retail','custom')),
 workspace_type text not null check (workspace_type in ('plp','eurofish','batalla','bok','generic')),
 property_id uuid,
 lifecycle_state text not null default 'onboarding' check (lifecycle_state in ('prospect','contracting','onboarding','active','attention','suspended','offboarding','archived')),
 primary_contact_name text check (length(primary_contact_name)<=160),
 primary_contact_email text check (length(primary_contact_email)<=320 and primary_contact_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
 account_owner_user_id uuid references auth.users(id),
 brand_asset_url text check (brand_asset_url is null or (length(brand_asset_url)<=1000 and brand_asset_url ~ '^https://[^?#@]+$')),
 notes text not null default '' check (length(notes)<=2000),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(property_id,organization_id) references public.enterprise_properties(id,organization_id)
);
create index pandora_enterprise_accounts_property_idx on public.pandora_enterprise_accounts(property_id,organization_id);
create index pandora_enterprise_accounts_owner_idx on public.pandora_enterprise_accounts(account_owner_user_id);
create index pandora_enterprise_accounts_creator_idx on public.pandora_enterprise_accounts(created_by);
create index pandora_enterprise_accounts_lifecycle_idx on public.pandora_enterprise_accounts(lifecycle_state,created_at);

create table public.pandora_service_plans (
 id uuid primary key default gen_random_uuid(),code text unique not null check(code~'^[a-z][a-z0-9_-]{1,63}$'),
 name text not null check(length(name) between 1 and 160),
 state text not null default 'draft' check(state in ('draft','active','retired')),
 currency text not null check(currency~'^[A-Z]{3}$'),
 monthly_fee_micros bigint check(monthly_fee_micros between 0 and 100000000000000),
 included_allowance_micros bigint check(included_allowance_micros between 0 and 100000000000000),
 entitlements jsonb not null default '[]' check(jsonb_typeof(entitlements)='array' and jsonb_array_length(entitlements)<=100),
 limits jsonb not null default '{}' check(jsonb_typeof(limits)='object' and octet_length(limits::text)<=4096),
 overage_policy text not null default 'approval_required' check(overage_policy in ('blocked','approval_required','contracted')),
 support_tier text not null default 'standard' check(support_tier in ('standard','priority','dedicated')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index pandora_service_plans_creator_idx on public.pandora_service_plans(created_by);
create table public.pandora_customer_subscriptions (
 organization_id uuid primary key references public.pandora_enterprise_accounts(organization_id),
 plan_id uuid not null references public.pandora_service_plans(id),
 state text not null default 'draft' check(state in ('draft','trial','active','past_due','suspended','cancelled')),
 currency text not null check(currency~'^[A-Z]{3}$'),
 monthly_fee_micros bigint check(monthly_fee_micros between 0 and 100000000000000),
 setup_fee_micros bigint check(setup_fee_micros between 0 and 100000000000000),
 discount_micros bigint not null default 0 check(discount_micros>=0),
 starts_on date,ends_on date,renews_on date,
 source_kind text not null default 'manual' check(source_kind in ('manual','provider_verified')),
 provider_reference text check(length(provider_reference)<=240),verified_at timestamptz,
 notes text not null default '' check(length(notes)<=2000),
 updated_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(ends_on is null or starts_on is null or ends_on>=starts_on),
 check(discount_micros<=coalesce(monthly_fee_micros,0)),
 check(source_kind<>'provider_verified' or (provider_reference is not null and verified_at is not null))
);
create index pandora_customer_subscriptions_plan_idx on public.pandora_customer_subscriptions(plan_id);
create index pandora_customer_subscriptions_actor_idx on public.pandora_customer_subscriptions(updated_by);
create index pandora_customer_subscriptions_renewal_idx on public.pandora_customer_subscriptions(renews_on) where state='active';
create table public.pandora_customer_onboarding_steps (
 organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
 step text not null check(step in ('identity','administrator','capabilities','connections','routing','limits','billing','verification','go_live')),
 state text not null default 'pending' check(state in ('pending','blocked','verified','not_required')),
 source_kind text not null default 'derived' check(source_kind in ('derived','owner_attested','provider_verified')),
 note text not null default '' check(length(note)<=500),
 evidence_ref text check(length(evidence_ref)<=500),updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 primary key(organization_id,step)
);
create index pandora_customer_onboarding_actor_idx on public.pandora_customer_onboarding_steps(updated_by);

create table public.pandora_customer_invoices (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
 invoice_number text not null check(length(invoice_number) between 1 and 100),currency text not null check(currency~'^[A-Z]{3}$'),
 amount_micros bigint not null check(amount_micros between 0 and 100000000000000),
 state text not null default 'draft' check(state in ('draft','issued','void')),
 issued_on date,due_on date,source_kind text not null default 'manual' check(source_kind in ('manual','provider_verified')),
 provider_reference text check(length(provider_reference)<=240),verified_at timestamptz,
 notes text not null default '' check(length(notes)<=1000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(organization_id,invoice_number),unique(id,organization_id),
 check(due_on is null or issued_on is null or due_on>=issued_on),
 check(source_kind<>'provider_verified' or (provider_reference is not null and verified_at is not null))
);
create index pandora_customer_invoices_creator_idx on public.pandora_customer_invoices(created_by);
create index pandora_customer_invoices_due_idx on public.pandora_customer_invoices(due_on) where state='issued';
create table public.pandora_customer_payments (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
 invoice_id uuid not null,currency text not null check(currency~'^[A-Z]{3}$'),
 amount_micros bigint not null check(amount_micros between 1 and 100000000000000),
 payment_kind text not null default 'payment' check(payment_kind in ('payment','credit','refund','adjustment')),
 reference text not null check(length(reference) between 1 and 240),
 occurred_on date not null,source_kind text not null default 'manual' check(source_kind in ('manual','provider_verified')),
 verified_at timestamptz,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(organization_id,reference),foreign key(invoice_id,organization_id) references public.pandora_customer_invoices(id,organization_id),
 check(source_kind<>'provider_verified' or verified_at is not null)
);
create index pandora_customer_payments_invoice_idx on public.pandora_customer_payments(invoice_id,organization_id);
create index pandora_customer_payments_creator_idx on public.pandora_customer_payments(created_by);

create table public.pandora_sales_opportunities (
 id uuid primary key default gen_random_uuid(),company_name text not null check(length(company_name) between 1 and 160),
 contact_name text check(length(contact_name)<=160),contact_email text check(length(contact_email)<=320),
 industry text not null default 'custom' check(length(industry)<=80),source text check(length(source)<=160),
 stage text not null default 'prospect' check(stage in ('prospect','qualified','demo','proposal','contracting','won','lost')),
 currency text check(currency~'^[A-Z]{3}$'),estimated_value_micros bigint check(estimated_value_micros between 0 and 100000000000000),
 next_action text check(length(next_action)<=500),follow_up_at timestamptz,decision_on date,
 converted_organization_id uuid references public.pandora_enterprise_accounts(organization_id),
 notes text not null default '' check(length(notes)<=2000),
 owner_user_id uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(stage<>'won' or converted_organization_id is not null)
);
create index pandora_sales_opportunities_owner_idx on public.pandora_sales_opportunities(owner_user_id);
create index pandora_sales_opportunities_client_idx on public.pandora_sales_opportunities(converted_organization_id);
create index pandora_sales_opportunities_followup_idx on public.pandora_sales_opportunities(follow_up_at) where stage not in ('won','lost');

-- Support specializes the existing tenant task, so ownership/state/evidence stay canonical.
create table public.pandora_customer_cases (
 task_entity_id uuid primary key,organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
 kind text not null check(kind in ('issue','request','feature','onboarding','training','access')),
 subject text not null check(length(subject) between 1 and 160),
 priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
 needs_owner boolean not null default false,assigned_user_id uuid references auth.users(id),
 description text not null default '' check(length(description)<=2000),resolution text not null default '' check(length(resolution)<=2000),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(task_entity_id,organization_id) references public.enterprise_tasks(entity_id,organization_id)
);
create index pandora_customer_cases_org_idx on public.pandora_customer_cases(organization_id,updated_at desc);
create index pandora_customer_cases_assignee_idx on public.pandora_customer_cases(assigned_user_id);
create index pandora_customer_cases_creator_idx on public.pandora_customer_cases(created_by);

-- Commercial contract specializes an existing platform-owned enterprise contract.
-- The legal document stays in its connected document system; only safe linkage lives here.
create table public.pandora_customer_contracts (
 contract_entity_id uuid primary key,organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
 contract_organization_id uuid not null references public.organizations(id),
 title text not null check(length(title) between 1 and 160),
 document_url text check(document_url is null or (length(document_url)<=1000 and document_url ~ '^https://[^?#@]+$')),
 document_sha256 text check(document_sha256~'^[a-f0-9]{64}$'),
 renewal_on date,currency text check(currency~'^[A-Z]{3}$'),value_micros bigint check(value_micros between 0 and 100000000000000),
 source_kind text not null default 'manual' check(source_kind in ('manual','provider_verified')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(contract_entity_id,contract_organization_id) references public.enterprise_contracts(entity_id,organization_id)
);
create index pandora_customer_contracts_org_idx on public.pandora_customer_contracts(organization_id,renewal_on);
create index pandora_customer_contracts_entity_org_idx on public.pandora_customer_contracts(contract_entity_id,contract_organization_id);
create index pandora_customer_contracts_contract_org_idx on public.pandora_customer_contracts(contract_organization_id);
create index pandora_customer_contracts_creator_idx on public.pandora_customer_contracts(created_by);

create table public.pandora_platform_incidents (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 title text not null check(length(title) between 1 and 160),severity text not null check(severity in ('low','medium','high','critical')),
 state text not null default 'investigating' check(state in ('investigating','identified','recovering','resolved')),
 impact text not null check(length(impact) between 1 and 1000),diagnosis text not null default '' check(length(diagnosis)<=2000),
 resolution text not null default '' check(length(resolution)<=2000),verification_ref text check(length(verification_ref)<=500),
 started_at timestamptz not null default now(),resolved_at timestamptz,
 owner_user_id uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 check(state<>'resolved' or (resolved_at is not null and verification_ref is not null and length(resolution)>0))
);
create index pandora_platform_incidents_org_idx on public.pandora_platform_incidents(organization_id,state,started_at desc);
create index pandora_platform_incidents_owner_idx on public.pandora_platform_incidents(owner_user_id);
create table public.pandora_business_partners (
 id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 1 and 160),
 kind text not null check(kind in ('vendor','partner')),state text not null default 'active' check(state in ('prospect','active','inactive')),
 service text check(length(service)<=240),contact text check(length(contact)<=320),
 recurring_cost_micros bigint check(recurring_cost_micros between 0 and 100000000000000),currency text check(currency~'^[A-Z]{3}$'),
 next_review_on date,notes text not null default '' check(length(notes)<=2000),
 updated_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(recurring_cost_micros is null or currency is not null)
);
create index pandora_business_partners_actor_idx on public.pandora_business_partners(updated_by);

create table private.pandora_core_operation_receipts (
 id uuid primary key default gen_random_uuid(),actor_user_id uuid not null references auth.users(id),
 idempotency_key uuid not null,organization_id uuid references public.organizations(id),
 operation text not null,payload_hash text not null check(payload_hash~'^[a-f0-9]{64}$'),
 result jsonb not null default '{}',created_at timestamptz not null default now(),
 unique(actor_user_id,idempotency_key)
);
create index pandora_core_operation_receipts_actor_time_idx on private.pandora_core_operation_receipts(actor_user_id,created_at desc);
create index pandora_core_operation_receipts_org_idx on private.pandora_core_operation_receipts(organization_id,created_at desc);
create table private.pandora_client_entry_sessions (
 id uuid primary key default gen_random_uuid(),actor_user_id uuid not null references auth.users(id),
 auth_session_id uuid not null references auth.sessions(id),organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
 reason text not null check(length(reason) between 3 and 500),started_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '1 hour',ended_at timestamptz,
 check(expires_at>started_at)
);
create index pandora_client_entry_sessions_actor_idx on private.pandora_client_entry_sessions(actor_user_id,organization_id,expires_at desc);
create index pandora_client_entry_sessions_auth_idx on private.pandora_client_entry_sessions(auth_session_id);
create index pandora_client_entry_sessions_org_idx on private.pandora_client_entry_sessions(organization_id);

-- No operator bypass of has_org_role / is_org_member: existing business RLS stays tenant-bound.
-- New private tables are defense-in-depth RLS, accessible only through bounded definers.
alter table private.pandora_core_config enable row level security;
alter table private.pandora_operator_grants enable row level security;
alter table private.pandora_core_operation_receipts enable row level security;
alter table private.pandora_client_entry_sessions enable row level security;
revoke all on private.pandora_core_config,private.pandora_operator_grants,private.pandora_core_operation_receipts,private.pandora_client_entry_sessions from public,anon,authenticated;

do $$
declare t text;
begin
 foreach t in array array['pandora_enterprise_accounts','pandora_customer_onboarding_steps','pandora_customer_cases','pandora_platform_incidents'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy core_operator_read on public.%I for select to authenticated using (private.pandora_core_role_v1(organization_id) is not null)',t);
 end loop;
 foreach t in array array['pandora_customer_subscriptions','pandora_customer_invoices','pandora_customer_payments','pandora_customer_contracts'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy core_commercial_read on public.%I for select to authenticated using (private.pandora_core_role_v1(organization_id) in (''owner'',''operator'',''finance''))',t);
 end loop;
 foreach t in array array['pandora_service_plans','pandora_sales_opportunities','pandora_business_partners'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy core_business_read on public.%I for select to authenticated using ((select private.pandora_core_role_v1(null)) in (''owner'',''operator'',''finance''))',t);
 end loop;
end;
$$;
-- The former direct UPDATE policy allowed lowering an existing owner's role.
-- Preserve SELECT and the audited service-role user-admin broker.
revoke insert,update,delete on public.memberships from authenticated;

-- Bootstrap only inspected canonical identities. Missing installations remain unconfigured.
-- Never rename an existing organization or turn historical demo properties into customers.
insert into private.pandora_core_config(platform_organization_id)
select id from public.organizations where slug='mcpmaster-staging'
on conflict(singleton) do nothing;
insert into private.pandora_operator_grants(user_id,role,granted_by,reason)
select m.user_id,'owner',m.user_id,'Owner instruction 2026-10-03; verified current canonical platform owner'
from public.memberships m join private.pandora_core_config c on m.organization_id=c.platform_organization_id
where m.user_id='a0d6f184-3039-4735-8d11-63ce403636e2'::uuid and m.role='owner' and m.status='active'
on conflict(user_id,organization_id) do nothing;
insert into public.pandora_enterprise_accounts(organization_id,industry,workspace_type,property_id,created_by)
select o.id,'hospitality','plp',p.id,g.user_id from public.organizations o
join public.enterprise_properties p on p.organization_id=o.id and p.slug='plp-boracay'
cross join private.pandora_operator_grants g
where o.slug='plp-boracay' and g.role='owner' and g.organization_id is null and g.state='active'
on conflict(organization_id) do nothing;
-- Other named customers are registered by the same governed flow after migration,
-- with onboarding state only. This keeps generated IDs out of data migrations.

create function private.pandora_core_connections_v1(p_organization_id uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x order by x->>'client_name',x->>'provider'),'[]') from (
 select jsonb_build_object('id',c.id,'organization_id',c.organization_id,'client_name',o.name,
  'provider',c.provider_key,'name',c.account_label,'status',c.status,
  'health',case when c.revoked_at is not null then 'revoked'
   when c.status<>'connected' then case when c.status='needs_attention' then 'unhealthy' else c.status end
   when c.health_state not in ('healthy','ok') then c.health_state
   when c.credential_expires_at<=now() then 'expired'
   when c.last_verified_at is null or c.last_verified_at<now()-interval '24 hours' then 'stale'
   else 'healthy' end,
  'last_verified_at',c.last_verified_at,'failure_code',c.failure_code,
  'capabilities',c.granted_capabilities,'scopes',c.granted_scopes,
  'verification_source','connection_broker','evidence_hash',c.provider_readback_hash) x
 from private.pandora_connection_accounts_v1 c join public.organizations o on o.id=c.organization_id
 where (p_organization_id is null or c.organization_id=p_organization_id)
 and private.pandora_core_role_v1(c.organization_id) is not null
 order by c.updated_at desc limit 200
 ) q;
$$;
create function private.pandora_core_clients_v1(p_organization_id uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x order by x->>'display_name'),'[]') from (
 select jsonb_build_object('organization_id',a.organization_id,'display_name',o.name,'slug',o.slug,
  'industry',a.industry,'workspace_type',a.workspace_type,'lifecycle_state',a.lifecycle_state,
  'onboarding_state',case when exists(select 1 from public.pandora_customer_onboarding_steps s where s.organization_id=a.organization_id and s.step='go_live' and s.state='verified') then 'complete'
   when exists(select 1 from public.pandora_customer_onboarding_steps s where s.organization_id=a.organization_id and s.state='blocked') then 'blocked' else 'in_progress' end,
  'property_id',a.property_id,'primary_contact_name',a.primary_contact_name,'primary_contact_email',a.primary_contact_email,
  'brand_asset_url',a.brand_asset_url,'notes',a.notes,'created_at',a.created_at,
  'users',(select count(*) from public.memberships m where m.organization_id=a.organization_id and m.status='active'),
  'admins',(select count(*) from public.memberships m where m.organization_id=a.organization_id and m.status='active' and m.role in ('owner','admin')),
  'connections',(select count(*) from private.pandora_connection_accounts_v1 c where c.organization_id=a.organization_id and c.revoked_at is null),
  'connections_healthy',(select count(*) from private.pandora_connection_accounts_v1 c where c.organization_id=a.organization_id and c.status='connected' and c.health_state='healthy' and c.last_verified_at>=now()-interval '24 hours' and (c.credential_expires_at is null or c.credential_expires_at>now()) and c.revoked_at is null),
  'devices',(select count(*) from public.enterprise_devices d where d.organization_id=a.organization_id and d.trust_state<>'revoked'),
  'health',case when a.lifecycle_state in ('suspended','offboarding','archived') then a.lifecycle_state
   when exists(select 1 from public.pandora_platform_incidents i where i.organization_id=a.organization_id and i.state<>'resolved' and i.severity in ('high','critical')) then 'attention'
   when exists(select 1 from private.pandora_connection_accounts_v1 c where c.organization_id=a.organization_id and c.revoked_at is null and (c.status='needs_attention' or c.health_state='unhealthy')) then 'attention'
   when a.lifecycle_state in ('prospect','contracting','onboarding') then 'onboarding' else 'unverified' end,
  'last_active',(select max(u.last_sign_in_at) from public.memberships m join auth.users u on u.id=m.user_id where m.organization_id=a.organization_id and m.status='active'),
  'can_enter',exists(select 1 from public.memberships m where m.organization_id=a.organization_id and m.user_id=auth.uid() and m.status='active')
    and a.lifecycle_state not in ('suspended','offboarding','archived')
    and a.workspace_type='plp' and o.slug='plp-boracay' and a.property_id is not null,
  'entry_requires','active_target_membership_and_aal2',
  'plan',(select p.name from public.pandora_customer_subscriptions s join public.pandora_service_plans p on p.id=s.plan_id where s.organization_id=a.organization_id)) x
 from public.pandora_enterprise_accounts a join public.organizations o on o.id=a.organization_id
 where (p_organization_id is null or a.organization_id=p_organization_id)
 and private.pandora_core_role_v1(a.organization_id) is not null limit 200
 ) q;
$$;
create function private.pandora_core_usage_v1(p_organization_id uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(q) order by q.estimated_cost_micros desc nulls last),'[]') from (
 select r.organization_id,o.name client_name,r.provider provider,r.model model,
  count(*) requests,count(*) filter(where r.status='succeeded') succeeded,
  sum(r.input_tokens) input_tokens,sum(r.output_tokens) output_tokens,sum(r.total_tokens) tokens,
  sum(r.estimated_cost_micros) filter(where r.cost_estimate_status='estimated') estimated_cost_micros,
  sum(r.billed_cost_micros) filter(where r.billing_reconciliation_status='matched') billed_cost_micros,
  count(*) filter(where r.cost_estimate_status='estimated') requests_with_cost,
  price.currency,
  max(r.created_at) last_observed_at,'recorded_model_runs_only' coverage,
  null::numeric local_share,null::bigint local_savings_micros,
  'No cross-phase local/cloud denominator or billed counterfactual is recorded' local_evidence_note
 from public.pandora_model_runs r join public.organizations o on o.id=r.organization_id
 left join lateral (select p.currency from public.pandora_model_pricing_versions p where p.provider=r.provider and p.model=r.model and p.pricing_version=r.pricing_version and p.verification_status='verified' order by p.effective_at desc limit 1) price on true
 where r.created_at>=date_trunc('month',now()) and r.created_at<date_trunc('month',now())+interval '1 month'
 and (p_organization_id is null or r.organization_id=p_organization_id)
 and private.pandora_core_role_v1(r.organization_id) in ('owner','operator','finance')
 group by r.organization_id,o.name,r.provider,r.model,price.currency limit 200
 ) q;
$$;

create function public.pandora_core_snapshot_v1(p_section text default 'home',p_organization_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_role text;v_platform uuid;v_clients jsonb;v_connections jsonb;v_usage jsonb;v_plans jsonb;
 v_result jsonb;v_needs jsonb;v_business jsonb;v_commercial boolean;
begin
 if p_section not in ('home','clients','client','business','platform','administration') or (p_section='client' and p_organization_id is null) then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 v_role:=private.pandora_core_assert_v1(p_organization_id,array['owner','operator','support','finance'],false);
 if p_organization_id is not null and not exists(select 1 from public.pandora_enterprise_accounts where organization_id=p_organization_id) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_section='business' and v_role not in ('owner','operator','finance') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_section='administration' and (p_organization_id is not null or private.pandora_core_role_v1(null) not in ('owner','operator')) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select platform_organization_id into v_platform from private.pandora_core_config where singleton;
 v_commercial:=v_role in ('owner','operator','finance');
 v_clients:=private.pandora_core_clients_v1(p_organization_id);
 v_connections:=private.pandora_core_connections_v1(p_organization_id);
 v_usage:=case when v_commercial then private.pandora_core_usage_v1(p_organization_id) else '[]'::jsonb end;
 select coalesce(jsonb_agg(to_jsonb(p)-'created_by'),'[]') into v_plans from public.pandora_service_plans p where v_commercial and p.state<>'retired';
 select coalesce(jsonb_agg(x order by x->>'deadline' nulls last),'[]') into v_needs from (
  select jsonb_build_object('id','case:'||c.task_entity_id,'kind','support','organization_id',c.organization_id,'client_name',o.name,'title',c.subject,'why',case when c.kind='access' then 'Customer workspace access requires a decision' else 'Support escalation needs an owner decision' end,'risk',c.priority,'action','open_case','deadline',t.due_at,'evidence',c.task_entity_id) x
  from public.pandora_customer_cases c join public.enterprise_tasks t on t.entity_id=c.task_entity_id and t.organization_id=c.organization_id join public.organizations o on o.id=c.organization_id
  where c.needs_owner and t.task_state not in ('completed','cancelled') and (p_organization_id is null or c.organization_id=p_organization_id) and private.pandora_core_role_v1(c.organization_id) is not null
  union all select jsonb_build_object('id','incident:'||i.id,'kind','incident','organization_id',i.organization_id,'client_name',o.name,'title',i.title,'why',i.impact,'risk',i.severity,'action','open_incident','evidence',i.verification_ref)
  from public.pandora_platform_incidents i join public.organizations o on o.id=i.organization_id where i.state<>'resolved' and i.severity in ('high','critical') and (p_organization_id is null or i.organization_id=p_organization_id) and private.pandora_core_role_v1(i.organization_id) is not null
  union all select jsonb_build_object('id','connection:'||(c->>'id'),'kind','connection','organization_id',c->>'organization_id','client_name',c->>'client_name','title',(c->>'provider')||' needs attention','why','The current connection cannot be verified as usable','risk','medium','action','open_connections','evidence',c->>'evidence_hash') from jsonb_array_elements(v_connections) c where c->>'status'='needs_attention'
  union all select jsonb_build_object('id','onboarding:'||s.organization_id||':'||s.step,'kind','onboarding','organization_id',s.organization_id,'client_name',o.name,'title',initcap(replace(s.step,'_',' '))||' blocked','why',s.note,'risk','medium','action','open_onboarding','evidence',s.evidence_ref)
  from public.pandora_customer_onboarding_steps s join public.organizations o on o.id=s.organization_id where s.state='blocked' and (p_organization_id is null or s.organization_id=p_organization_id) and private.pandora_core_role_v1(s.organization_id) is not null
  union all select jsonb_build_object('id',a.id,'kind','approval','organization_id',a.organization_id,'client_name',o.name,'title','Approval required','why',coalesce(nullif(a.request_reason,''),'A consequential action requires your decision'),'risk','review_required','action','open_approvals','deadline',a.expires_at,'evidence',a.action_hash)
  from public.approvals a join public.organizations o on o.id=a.organization_id
  where a.decision='pending' and a.expires_at>now() and (a.assigned_to is null or a.assigned_to=auth.uid())
   and (p_organization_id is null or a.organization_id=p_organization_id)
   and private.pandora_core_role_v1(a.organization_id) is not null
   and private.has_org_role(a.organization_id,array['owner','admin']::public.member_role[])
  union all select jsonb_build_object('id','gate:'||g.task_key||':'||g.gate_kind,'kind','operations_gate','organization_id',g.organization_id,'title',initcap(replace(g.gate_kind,'_',' ')),'why','Operations Room is waiting for a human decision','risk','medium','action','open_operations','evidence',g.evidence_ref)
  from private.pandora_ops_human_gates g where g.state='blocked' and g.updated_at>now()-interval '7 days' and (p_organization_id is null or g.organization_id=p_organization_id) and private.pandora_core_role_v1(g.organization_id) is not null
  limit 50
 ) q;
 select jsonb_build_object(
  'subscriptions',(select count(*) from public.pandora_customer_subscriptions s where s.state='active' and (p_organization_id is null or s.organization_id=p_organization_id) and private.pandora_core_role_v1(s.organization_id) in ('owner','operator','finance')),
  'invoices',(select count(*) from public.pandora_customer_invoices i where i.state='issued' and (p_organization_id is null or i.organization_id=p_organization_id) and private.pandora_core_role_v1(i.organization_id) in ('owner','operator','finance')),
  'pipeline',(select count(*) from public.pandora_sales_opportunities where stage not in ('won','lost') and p_organization_id is null and v_commercial),
  'usage',v_usage,'coverage','Recorded commercial terms and usage only; missing records are unknown',
  'currencies',coalesce((select jsonb_agg(to_jsonb(x)) from (
   select s.currency,sum(s.monthly_fee_micros-s.discount_micros) mrr_micros,
    12*sum(s.monthly_fee_micros-s.discount_micros) arr_micros,count(*) recorded_subscriptions,
    count(*) filter(where s.source_kind='provider_verified') provider_verified_subscriptions,
    case when bool_and(s.source_kind='provider_verified') then 'provider_verified' else 'manual_or_mixed' end source_kind
   from public.pandora_customer_subscriptions s where v_commercial and s.state='active' and (p_organization_id is null or s.organization_id=p_organization_id) and private.pandora_core_role_v1(s.organization_id) in ('owner','operator','finance')
   group by s.currency
  ) x),'[]'::jsonb)) into v_business;
 v_result:=jsonb_build_object('schema_version','1','generated_at',now(),'section',p_section,
  'operator',jsonb_build_object('role',v_role,'platform_organization_id',v_platform),
  'clients',v_clients,'plans',v_plans,'needs_you',v_needs,'business',v_business,
  'health',jsonb_build_object('clients',jsonb_array_length(v_clients),
   'active_clients',(select count(*) from jsonb_array_elements(v_clients) c where c->>'lifecycle_state'='active'),
   'attention_clients',(select count(*) from jsonb_array_elements(v_clients) c where c->>'health'='attention' or c->>'onboarding_state'='blocked'),
   'connections',jsonb_array_length(v_connections),'connections_healthy',(select count(*) from jsonb_array_elements(v_connections) c where c->>'health'='healthy'),
   'devices',(select coalesce(sum((c->>'devices')::integer),0) from jsonb_array_elements(v_clients) c),
   'incidents',(select count(*) from public.pandora_platform_incidents i where i.state<>'resolved' and (p_organization_id is null or i.organization_id=p_organization_id) and private.pandora_core_role_v1(i.organization_id) is not null),
   'state',case when jsonb_array_length(v_needs)>0 then 'needs_attention' else 'unverified' end),
  'handling',coalesce((select jsonb_agg(to_jsonb(q)) from (
   select j.id,j.organization_id,'Pandora task' title,j.execution_state state,j.updated_at
   from public.pandora_activity_jobs j where j.terminal_state is null and j.execution_state in ('queued','running','claimed','waiting') and j.expires_at>now() and j.updated_at>now()-interval '1 hour'
   and (p_organization_id is null or j.organization_id=p_organization_id) and private.pandora_core_role_v1(j.organization_id) is not null order by j.updated_at desc limit 12
  ) q),'[]'::jsonb),
  'outcomes',coalesce((select jsonb_agg(to_jsonb(q)) from (
   select a.id,a.organization_id,initcap(replace(a.event_type,'core.','')) title,a.created_at occurred_at,'recorded' outcome
   from public.audit_events a where a.event_type like 'core.%' and (p_organization_id is null or a.organization_id=p_organization_id) and private.pandora_core_role_v1(a.organization_id) is not null order by a.created_at desc limit 12
  ) q),'[]'::jsonb));
 if p_section='client' then
  v_result:=v_result||jsonb_build_object('client',v_clients->0,
   'available_capability_packs',coalesce((select jsonb_agg(jsonb_build_object('key',p.pack_key,'version',p.pack_version,'name',p.display_name)) from public.pandora_industry_packs p where p.lifecycle_state='active'),'[]'::jsonb),
   'onboarding',coalesce((select jsonb_agg(jsonb_build_object('key',s.step,'title',initcap(replace(s.step,'_',' ')),'state',s.state,'reason',s.note,'action',case when s.step='administrator' then 'open_users' when s.step='connections' then 'open_connections' else 'verify' end,'source_kind',s.source_kind,'evidence_ref',s.evidence_ref) order by array_position(array['identity','administrator','capabilities','connections','routing','limits','billing','verification','go_live'],s.step)) from public.pandora_customer_onboarding_steps s where s.organization_id=p_organization_id),'[]'::jsonb),
   'members',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'name',coalesce(nullif(u.raw_user_meta_data->>'full_name',''),split_part(u.email,'@',1)),'role',m.role,'status',m.status,'last_active',u.last_sign_in_at)) from public.memberships m join auth.users u on u.id=m.user_id where m.organization_id=p_organization_id),'[]'::jsonb),
   'capabilities',coalesce((select jsonb_agg(jsonb_build_object('key',p.pack_key,'version',p.pack_version,'state',p.activation_state)) from public.pandora_workspace_industry_packs p where p.organization_id=p_organization_id),'[]'::jsonb),
   'sources',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.display_name,'status',s.status,'last_success',s.last_success_at)) from public.enterprise_source_connections s where s.organization_id=p_organization_id),'[]'::jsonb));
 end if;
 if p_section in ('client','platform') then
  v_result:=v_result||jsonb_build_object('connections',v_connections,'usage',v_usage,
   'devices',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select d.entity_id id,d.organization_id,o.name client_name,d.model,d.trust_state,d.capabilities,d.updated_at,'unknown' enrollment_state
    from public.enterprise_devices d join public.organizations o on o.id=d.organization_id where (p_organization_id is null or d.organization_id=p_organization_id) and private.pandora_core_role_v1(d.organization_id) is not null limit 100
   ) q),'[]'::jsonb),
   'deployments',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select d.id,d.organization_id,d.provider,d.environment,d.provider_deployment_id,d.source_commit_sha,d.status,d.verification_state,d.provider_state,d.last_provider_check_at,
     case when d.source_commit_sha is null then 'source_unbound' when d.last_provider_check_at<now()-interval '24 hours' then 'stale' else 'provider_evidence_only' end evidence_state
    from public.pandora_project_deployments d where (p_organization_id is null or d.organization_id=p_organization_id) and private.pandora_core_role_v1(d.organization_id) is not null order by d.last_provider_check_at desc nulls last limit 30
   ) q),'[]'::jsonb));
 end if;
 if p_section in ('client','business') and v_commercial then
  v_result:=v_result||jsonb_build_object('usage',v_usage,
   'subscriptions',coalesce((select jsonb_agg(to_jsonb(s)-'updated_by') from public.pandora_customer_subscriptions s where (p_organization_id is null or s.organization_id=p_organization_id) and private.pandora_core_role_v1(s.organization_id) in ('owner','operator','finance')),'[]'::jsonb),
   'subscription',(select to_jsonb(s)-'updated_by' from public.pandora_customer_subscriptions s where s.organization_id=p_organization_id),
   'invoices',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select i.id,i.organization_id,o.name client_name,i.invoice_number,i.currency,i.amount_micros,i.state,i.due_on,i.source_kind,
     i.amount_micros-coalesce((select sum(case when p.payment_kind='refund' then -p.amount_micros else p.amount_micros end) from public.pandora_customer_payments p where p.invoice_id=i.id),0) remaining_micros
    from public.pandora_customer_invoices i join public.organizations o on o.id=i.organization_id where (p_organization_id is null or i.organization_id=p_organization_id) and private.pandora_core_role_v1(i.organization_id) in ('owner','operator','finance') order by i.created_at desc limit 100
   ) q),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p)-'created_by') from public.pandora_customer_payments p where (p_organization_id is null or p.organization_id=p_organization_id) and private.pandora_core_role_v1(p.organization_id) in ('owner','operator','finance')),'[]'::jsonb),
   'contracts',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('state',e.contract_state,'starts_on',e.effective_from,'ends_on',e.effective_to)) from public.pandora_customer_contracts c join public.enterprise_contracts e on e.entity_id=c.contract_entity_id and e.organization_id=c.contract_organization_id where (p_organization_id is null or c.organization_id=p_organization_id) and private.pandora_core_role_v1(c.organization_id) in ('owner','operator','finance')),'[]'::jsonb),
   'pipeline',coalesce((select jsonb_agg(to_jsonb(s)) from public.pandora_sales_opportunities s where p_organization_id is null),'[]'::jsonb),
   'vendors',coalesce((select jsonb_agg(to_jsonb(s)-'updated_by') from public.pandora_business_partners s where p_organization_id is null),'[]'::jsonb));
 end if;
 if p_section in ('client','clients','administration') then
  v_result:=v_result||jsonb_build_object('cases',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('id',c.task_entity_id,'state',t.task_state,'due_at',t.due_at)) from public.pandora_customer_cases c join public.enterprise_tasks t on t.entity_id=c.task_entity_id where (p_organization_id is null or c.organization_id=p_organization_id) and private.pandora_core_role_v1(c.organization_id) is not null),'[]'::jsonb));
 end if;

 if p_section in ('home','client','business','platform') and v_commercial then
  v_result:=v_result||jsonb_build_object('usage_allowances',coalesce((select jsonb_agg(to_jsonb(q)) from (
   select s.organization_id,o.name client_name,s.currency,s.state subscription_state,
    (p.limits->>'monthly_requests')::bigint request_limit,(p.limits->>'monthly_tokens')::bigint token_limit,
    (p.limits->>'budget_micros')::bigint budget_micros,p.included_allowance_micros,
    (select count(*) from public.pandora_model_runs r where r.organization_id=s.organization_id and r.created_at>=date_trunc('month',now())) requests_recorded,
    (select sum(r.total_tokens) from public.pandora_model_runs r where r.organization_id=s.organization_id and r.created_at>=date_trunc('month',now())) tokens_recorded,
    'recorded_model_runs_only' coverage,
    'Configured allowances require matching execution admission; missing usage is not zero' evidence_note
   from public.pandora_customer_subscriptions s join public.pandora_service_plans p on p.id=s.plan_id join public.organizations o on o.id=s.organization_id
   where s.state in ('trial','active','past_due') and (p_organization_id is null or s.organization_id=p_organization_id) and private.pandora_core_role_v1(s.organization_id) in ('owner','operator','finance')
  ) q),'[]'::jsonb));
 end if;
 if p_section='platform' then
  v_result:=v_result||jsonb_build_object(
   'providers',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select a.organization_id,a.provider_key provider,a.activation_state,a.health_state activation_health,a.last_verified_at,'activation_metadata_only' evidence_state
    from public.pandora_provider_activations a where (p_organization_id is null or a.organization_id=p_organization_id) and private.pandora_core_role_v1(a.organization_id) is not null limit 100
   ) q),'[]'::jsonb),
   'models',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select m.organization_id,m.provider_key provider,m.capability_key capability,m.region,m.verified_success_count success_count,m.verified_failure_count failure_count,m.p95_latency_ms,m.observed_at,
     case when m.observed_at<now()-interval '24 hours' then 'stale' else 'measured' end evidence_state
    from public.pandora_provider_capability_metrics m where (p_organization_id is null or m.organization_id=p_organization_id) and private.pandora_core_role_v1(m.organization_id) is not null order by m.observed_at desc limit 50
   ) q),'[]'::jsonb),
   'automations',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select t.organization_id,t.task_key name,t.status state,t.attempts,t.queued_at,t.head_sha
    from private.pandora_ops_tasks t where (p_organization_id is null or t.organization_id=p_organization_id) and private.pandora_core_role_v1(t.organization_id) is not null order by t.queued_at desc limit 30
   ) q),'[]'::jsonb),
   'memory',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select m.id,m.organization_id,m.learning_kind kind,m.learning_summary summary,m.state,m.promotion_basis,m.created_at,m.delivered_at,m.memory_review_item_id review_item_id
    from public.pandora_verified_learning_outbox m where (p_organization_id is null or m.organization_id=p_organization_id) and private.pandora_core_role_v1(m.organization_id) is not null order by m.created_at desc limit 20
   ) q),'[]'::jsonb),
   'evidence',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select e.id,e.organization_id,e.evidence_type kind,e.content_sha256,e.created_at
    from public.pandora_verification_evidence e where (p_organization_id is null or e.organization_id=p_organization_id) and private.pandora_core_role_v1(e.organization_id) is not null order by e.created_at desc limit 30
   ) q),'[]'::jsonb));
 end if;
 if p_section='administration' then
  v_result:=v_result||jsonb_build_object(
   'team',coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'name',coalesce(nullif(u.raw_user_meta_data->>'full_name',''),split_part(u.email,'@',1)),'role',m.role,'status',m.status)) from public.memberships m join auth.users u on u.id=m.user_id where m.organization_id=v_platform),'[]'::jsonb),
   'operators',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'user_id',g.user_id,'organization_id',g.organization_id,'role',g.role,'state',g.state,'expires_at',g.expires_at)) from private.pandora_operator_grants g where p_organization_id is null or g.organization_id=p_organization_id),'[]'::jsonb),
   'incidents',coalesce((select jsonb_agg(to_jsonb(i)) from public.pandora_platform_incidents i where (p_organization_id is null or i.organization_id=p_organization_id) and private.pandora_core_role_v1(i.organization_id) is not null),'[]'::jsonb),
   'audit',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select a.id,a.organization_id,a.actor_user_id,a.event_type,a.created_at,a.event_hash
    from public.audit_events a where a.event_type like 'core.%' and (p_organization_id is null or a.organization_id=p_organization_id) and private.pandora_core_role_v1(a.organization_id) is not null order by a.created_at desc limit 100
   ) q),'[]'::jsonb),
   'policies',jsonb_build_array(
    jsonb_build_object('name','Operator authority','state','enforced','detail','Explicit grant and active internal membership'),
    jsonb_build_object('name','Client entry','state','enforced','detail','Target membership, live MFA session and audit'),
    jsonb_build_object('name','Financial writes','state','enforced','detail','Owner or finance role, live MFA and idempotency'),
    jsonb_build_object('name','Connection health','state','evidence_based','detail','Runtime verification expires after 24 hours'),
    jsonb_build_object('name','Routing','state','auto','detail','Existing routing policies; no dashboard model probes')));
 end if;
 return v_result;
end;
$$;

-- The owner's named customers are identity records, not demo activity or active subscriptions.
do $$
declare v_owner uuid;v_org uuid;r record;
begin
 select user_id into v_owner from private.pandora_operator_grants where role='owner' and organization_id is null and state='active' order by created_at limit 1;
 if v_owner is not null then
  for r in select * from (values
   ('1064 Euro-Fish Traders','1064-euro-fish-traders','trade','eurofish'),
   ('Batalla & Associates','batalla-associates','legal','batalla'),
   ('BOK','bok','restaurant','bok')) x(name,slug,industry,workspace_type)
  loop
   insert into public.organizations(name,slug,created_by) values(r.name,r.slug,v_owner)
    on conflict(slug) do nothing returning id into v_org;
   if v_org is not null then
    insert into public.pandora_enterprise_accounts(organization_id,industry,workspace_type,created_by)
     values(v_org,r.industry,r.workspace_type,v_owner);
    perform private.append_audit_event(v_org,null,null,'system'::public.audit_actor_type,null,
     'core.client.registered',jsonb_build_object('source','owner_instruction_2026_10_03','migration','20261003044349','lifecycle_state','onboarding'));
   end if;
  end loop;
  insert into public.pandora_customer_onboarding_steps(organization_id,step,state,note,updated_by)
  select a.organization_id,s.step,case when s.step='identity' then 'verified' else 'pending' end,
   case when s.step='identity' then 'Canonical organization registered from owner instruction' else 'Verification required' end,v_owner
  from public.pandora_enterprise_accounts a cross join unnest(array['identity','administrator','capabilities','connections','routing','limits','billing','verification','go_live']) s(step)
  on conflict(organization_id,step) do nothing;
 end if;
end;
$$;

create function private.pandora_core_payload_v1(p_payload jsonb,p_allowed text[])
returns void language plpgsql immutable set search_path='' as $$
begin
 if p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>16384
  or exists(select 1 from jsonb_object_keys(p_payload) k where not(k=any(p_allowed)))
  or p_payload::text ~* '(-----BEGIN [A-Z ]*PRIVATE KEY|Bearer[[:space:]]+[A-Za-z0-9._-]{16,}|sb_secret_[A-Za-z0-9]+|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,})'
 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
end;
$$;

create function private.pandora_core_onboarding_verify_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s record;v_ok boolean;v_reason text;v_account public.pandora_enterprise_accounts%rowtype;v_pending integer;
begin
 select * into strict v_account from public.pandora_enterprise_accounts where organization_id=p_organization_id;
 for s in select * from public.pandora_customer_onboarding_steps where organization_id=p_organization_id and step not in ('verification','go_live') loop
  v_ok:=false;v_reason:='Verification required';
  case s.step
   when 'identity' then v_ok:=true;v_reason:='Canonical organization registered';
   when 'administrator' then
    select exists(select 1 from public.memberships where organization_id=p_organization_id and role in ('owner','admin') and status='active') into v_ok;
    v_reason:=case when v_ok then 'Active customer administrator recorded' else 'Invite and verify a customer administrator' end;
   when 'capabilities' then
    select exists(select 1 from public.pandora_workspace_industry_packs where organization_id=p_organization_id and activation_state='active') into v_ok;
    v_reason:=case when v_ok then 'Workspace capability pack is active' else 'Select an available workspace capability pack' end;
   when 'connections' then
    select exists(select 1 from private.pandora_connection_accounts_v1 where organization_id=p_organization_id and status='connected' and health_state='healthy' and last_verified_at>now()-interval '24 hours' and revoked_at is null and (credential_expires_at is null or credential_expires_at>now())) into v_ok;
    v_reason:=case when v_ok then 'Current connection readback exists' else 'Connect and verify required providers, or attest that no connection is required' end;
   when 'routing' then
    v_ok:=s.state='verified' and s.source_kind='owner_attested';v_reason:=case when v_ok then s.note else 'Review the existing Auto routing policy for this workspace' end;
   when 'limits' then
    select exists(select 1 from public.pandora_customer_subscriptions cs join public.pandora_service_plans p on p.id=cs.plan_id where cs.organization_id=p_organization_id and p.limits<>'{}'::jsonb and cs.state not in ('cancelled','suspended')) into v_ok;
    v_reason:=case when v_ok then 'Server-side plan limits are recorded; execution enforcement is separate' else 'Record plan limits and confirm enforcement before go-live' end;
   when 'billing' then
    select exists(select 1 from public.pandora_customer_subscriptions where organization_id=p_organization_id and state in ('trial','active')) into v_ok;
    v_reason:=case when v_ok then 'Commercial state recorded; provider billing evidence remains separate' else 'Record approved commercial terms or an explicitly approved non-billable arrangement' end;
   else null;
  end case;
  if s.state='not_required' and s.source_kind='owner_attested' and s.step in ('connections','billing') then continue;end if;
  update public.pandora_customer_onboarding_steps set state=case when v_ok then 'verified' else 'pending' end,note=v_reason,
   source_kind=case when s.step='routing' and v_ok then 'owner_attested' else 'derived' end,updated_by=auth.uid(),updated_at=now()
  where organization_id=p_organization_id and step=s.step;
 end loop;
 select count(*) into v_pending from public.pandora_customer_onboarding_steps where organization_id=p_organization_id and step not in ('verification','go_live') and state not in ('verified','not_required');
 -- A checklist pass is not deployed user-flow verification. Preserve real evidence separately.
 return jsonb_build_object('pending_steps',v_pending,'ready_for_runtime_verification',v_pending=0,'go_live',false);
end;
$$;

create function public.pandora_core_operate_v1(p_operation text,p_organization_id uuid,p_payload jsonb,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();v_role text;v_platform uuid;v_org uuid:=p_organization_id;v_id uuid;v_hash text;v_result jsonb;v_before jsonb;
 v_receipt private.pandora_core_operation_receipts%rowtype;v_plan public.pandora_service_plans%rowtype;
 v_invoice public.pandora_customer_invoices%rowtype;v_high boolean;v_allowed text[];v_step text;v_state text;v_due timestamptz;
 v_existing_role text;v_target uuid;v_amount bigint;v_net bigint;v_count integer;
begin
 if p_idempotency_key is null or p_operation is null or length(p_operation)>80 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 select platform_organization_id into v_platform from private.pandora_core_config where singleton;
 v_high:=p_operation in ('plan.save','subscription.save','invoice.save','payment.record','contract.save','partner.save','device.revoke','operator.grant','onboarding.attest','client.go_live')
  or (p_operation='client.update' and p_payload ? 'lifecycle_state');
 v_role:=private.pandora_core_assert_v1(v_org,
  case when p_operation='operator.grant' then array['owner']
   when p_operation in ('plan.save','subscription.save','invoice.save','payment.record','contract.save','partner.save') then array['owner','finance']
   when p_operation in ('case.save','access.request','incident.save') then array['owner','operator','support']
   else array['owner','operator'] end,v_high);
 if v_org is not null and not exists(select 1 from public.pandora_enterprise_accounts where organization_id=v_org) and not(p_operation='incident.save' and v_org=v_platform) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_operation in ('client.register','plan.save','prospect.save','partner.save','operator.grant') and v_org is not null then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 if p_operation not in ('client.register','plan.save','prospect.save','partner.save','operator.grant','incident.save') and v_org is null then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 v_allowed:=case p_operation
  when 'client.register' then array['name','slug','industry','workspace_type','primary_contact_name','primary_contact_email','plan_id']
  when 'client.update' then array['lifecycle_state','primary_contact_name','primary_contact_email','notes']
  when 'onboarding.checkpoint' then array['step','state','note']
  when 'onboarding.attest' then array['step','state','note','evidence_ref']
  when 'onboarding.verify' then array[]::text[]
  when 'client.go_live' then array['evidence_ref']
  when 'capability.activate' then array['pack_key','pack_version']
  when 'plan.save' then array['id','code','name','state','currency','monthly_fee_micros','included_allowance_micros','entitlements','limits','overage_policy','support_tier']
  when 'subscription.save' then array['plan_id','state','currency','monthly_fee_micros','setup_fee_micros','discount_micros','starts_on','ends_on','renews_on','notes']
  when 'invoice.save' then array['id','invoice_number','currency','amount_micros','state','issued_on','due_on','notes']
  when 'payment.record' then array['invoice_id','currency','amount_micros','payment_kind','reference','occurred_on']
  when 'case.save' then array['id','kind','subject','priority','needs_owner','assigned_user_id','description','resolution','state','due_at']
  when 'access.request' then array['reason']
  when 'prospect.save' then array['id','company_name','contact_name','contact_email','industry','source','stage','currency','estimated_value_micros','next_action','follow_up_at','decision_on','converted_organization_id','notes']
  when 'contract.save' then array['id','title','contract_type','state','starts_on','ends_on','renewal_on','currency','value_micros','document_url','document_sha256']
  when 'incident.save' then array['id','title','severity','state','impact','diagnosis','resolution','verification_ref']
  when 'device.revoke' then array['id','reason']
  when 'partner.save' then array['id','name','kind','state','service','contact','recurring_cost_micros','currency','next_review_on','notes']
  when 'operator.grant' then array['user_id','role','scope_organization_id','state','expires_at','reason']
  else null end;
 if v_allowed is null then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 perform private.pandora_core_payload_v1(p_payload,v_allowed);
 v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('operation',p_operation,'organization_id',v_org,'payload',p_payload)::text,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pandora-core:'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_receipt from private.pandora_core_operation_receipts where actor_user_id=v_actor and idempotency_key=p_idempotency_key;
 if found then
  if v_receipt.payload_hash<>v_hash then raise exception 'CONFLICT' using errcode='23505';end if;
  return v_receipt.result||jsonb_build_object('replayed',true);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pandora-core-actor:'||v_actor::text,0));
 if (select count(*) from private.pandora_core_operation_receipts where actor_user_id=v_actor and created_at>now()-interval '1 minute')>=30 then raise exception 'RATE_LIMITED' using errcode='P0001';end if;
 -- Per-tenant serialization protects lifecycle, billing and payment totals across different keys.
 perform pg_advisory_xact_lock(hashtextextended('pandora-core-org:'||coalesce(v_org,v_platform)::text,0));
 -- Authority may have been revoked while waiting for another operation.
 perform private.pandora_core_assert_v1(v_org,array[v_role],v_high);
 insert into private.pandora_core_operation_receipts(actor_user_id,idempotency_key,organization_id,operation,payload_hash)
 values(v_actor,p_idempotency_key,v_org,p_operation,v_hash) returning * into v_receipt;
 case p_operation
 when 'client.register' then
  if p_payload->>'name' is null or p_payload->>'slug' is null then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  insert into public.organizations(name,slug,created_by) values(trim(p_payload->>'name'),lower(trim(p_payload->>'slug')),v_actor) returning id into v_org;
  insert into public.pandora_enterprise_accounts(organization_id,industry,workspace_type,primary_contact_name,primary_contact_email,created_by)
  values(v_org,coalesce(p_payload->>'industry','custom'),coalesce(p_payload->>'workspace_type','generic'),nullif(trim(p_payload->>'primary_contact_name'),''),nullif(lower(trim(p_payload->>'primary_contact_email')),''),v_actor);
  insert into public.pandora_customer_onboarding_steps(organization_id,step,state,note,updated_by)
  select v_org,s,case when s='identity' then 'verified' else 'pending' end,case when s='identity' then 'Canonical organization registered' else 'Verification required' end,v_actor
  from unnest(array['identity','administrator','capabilities','connections','routing','limits','billing','verification','go_live']) s;
  -- A selected draft plan records intent only and never creates a billable subscription.
  if nullif(p_payload->>'plan_id','') is not null then
   select * into strict v_plan from public.pandora_service_plans where id=(p_payload->>'plan_id')::uuid and state='active';
   insert into public.pandora_customer_subscriptions(organization_id,plan_id,state,currency,monthly_fee_micros,updated_by)
   values(v_org,v_plan.id,'draft',v_plan.currency,v_plan.monthly_fee_micros,v_actor);
  end if;
  v_result:=jsonb_build_object('status','registered','organization_id',v_org,'lifecycle_state','onboarding','next_action','Invite and verify the customer administrator');
 when 'client.update' then
  if p_payload->>'lifecycle_state'='active' then raise exception 'GO_LIVE_VERIFICATION_REQUIRED' using errcode='22023';end if;
  select to_jsonb(a) into v_before from public.pandora_enterprise_accounts a where organization_id=v_org;
  update public.pandora_enterprise_accounts set
   lifecycle_state=coalesce(p_payload->>'lifecycle_state',lifecycle_state),
   primary_contact_name=case when p_payload?'primary_contact_name' then nullif(trim(p_payload->>'primary_contact_name'),'') else primary_contact_name end,
   primary_contact_email=case when p_payload?'primary_contact_email' then nullif(lower(trim(p_payload->>'primary_contact_email')),'') else primary_contact_email end,
   notes=coalesce(p_payload->>'notes',notes),updated_at=now() where organization_id=v_org;
  -- Suspending commercial access also suspends the canonical organization, enforced on Core entry.
  if p_payload->>'lifecycle_state' in ('suspended','archived','offboarding') then
   update public.organizations set status='suspended',updated_at=now() where id=v_org;
   update private.pandora_client_entry_sessions set ended_at=now() where organization_id=v_org and ended_at is null;
  end if;
  v_result:=jsonb_build_object('status','saved','organization_id',v_org);
 when 'onboarding.checkpoint' then
  if p_payload->>'state' not in ('pending','blocked') or length(coalesce(p_payload->>'note',''))<3 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  update public.pandora_customer_onboarding_steps set state=p_payload->>'state',note=p_payload->>'note',source_kind='owner_attested',evidence_ref=null,updated_by=v_actor,updated_at=now()
  where organization_id=v_org and step=p_payload->>'step' and step not in ('identity','go_live');
  if not found then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  v_result:=jsonb_build_object('status','saved','organization_id',v_org,'next_action','Resolve the recorded prerequisite');
 when 'onboarding.attest' then
  v_step:=p_payload->>'step';v_state:=p_payload->>'state';
  if (v_step not in ('routing','verification','connections','billing')) or
   (v_state<>'verified' and not(v_state='not_required' and v_step in ('connections','billing')))
   or length(coalesce(p_payload->>'note',''))<10 or length(coalesce(p_payload->>'evidence_ref',''))<3 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  -- Attestation is labelled human evidence, never provider verification.
  update public.pandora_customer_onboarding_steps set state=v_state,note=p_payload->>'note',evidence_ref=p_payload->>'evidence_ref',source_kind='owner_attested',updated_by=v_actor,updated_at=now()
  where organization_id=v_org and step=v_step;
  v_result:=jsonb_build_object('status','attested','organization_id',v_org,'source_kind','owner_attested');
 when 'onboarding.verify' then
  v_result:=private.pandora_core_onboarding_verify_v1(v_org)||jsonb_build_object('status','checked','organization_id',v_org);
 when 'client.go_live' then
  if not exists(select 1 from public.pandora_enterprise_accounts a join public.organizations o on o.id=a.organization_id where a.organization_id=v_org and a.workspace_type='plp' and o.slug='plp-boracay' and a.property_id is not null) then raise exception 'WORKSPACE_NOT_VERIFIED' using errcode='22023';end if;
  perform private.pandora_core_onboarding_verify_v1(v_org);
  if exists(select 1 from public.pandora_customer_onboarding_steps where organization_id=v_org and step<>'go_live' and state not in ('verified','not_required'))
   or length(coalesce(p_payload->>'evidence_ref',''))<3 then raise exception 'GO_LIVE_VERIFICATION_REQUIRED' using errcode='22023';end if;
  update public.pandora_enterprise_accounts set lifecycle_state='active',updated_at=now() where organization_id=v_org;
  update public.organizations set status='active',updated_at=now() where id=v_org;
  update public.pandora_customer_onboarding_steps set state='verified',source_kind='owner_attested',note='Owner approved go-live after recorded verification',evidence_ref=p_payload->>'evidence_ref',updated_by=v_actor,updated_at=now() where organization_id=v_org and step='go_live';
  v_result:=jsonb_build_object('status','active','organization_id',v_org,'verification_kind','owner_attested');
 when 'capability.activate' then
  if not exists(select 1 from public.pandora_industry_packs where pack_key=p_payload->>'pack_key' and pack_version=p_payload->>'pack_version' and lifecycle_state='active') then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  insert into public.pandora_workspace_industry_packs(organization_id,pack_key,pack_version,activation_state)
  values(v_org,p_payload->>'pack_key',p_payload->>'pack_version','active')
  on conflict(organization_id,pack_key) do update set pack_version=excluded.pack_version,activation_state='active',updated_at=now();
  v_result:=jsonb_build_object('status','configured','organization_id',v_org,'next_action','Check commercial entitlement and provider authorization separately');
 when 'plan.save' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from public.pandora_customer_subscriptions where plan_id=v_id and state in ('active','trial','past_due')) then raise exception 'PLAN_IN_USE_CREATE_NEW_VERSION' using errcode='23505';end if;
  if jsonb_typeof(coalesce(p_payload->'limits','{}'))<>'object' or exists(select 1 from jsonb_each(coalesce(p_payload->'limits','{}')) kv where kv.key not in ('users','devices','monthly_requests','monthly_tokens','budget_micros','storage_bytes') or jsonb_typeof(kv.value)<>'number' or (kv.value::text)::numeric<0 or (kv.value::text)::numeric<>trunc((kv.value::text)::numeric)) then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_payload->'entitlements','[]')) e where jsonb_typeof(e)<>'string' or trim(both '"' from e::text)!~'^[a-z][a-z0-9_.-]{1,100}$') then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  insert into public.pandora_service_plans(id,code,name,state,currency,monthly_fee_micros,included_allowance_micros,entitlements,limits,overage_policy,support_tier,created_by)
  values(v_id,p_payload->>'code',p_payload->>'name',coalesce(p_payload->>'state','draft'),p_payload->>'currency',nullif(p_payload->>'monthly_fee_micros','')::bigint,nullif(p_payload->>'included_allowance_micros','')::bigint,coalesce(p_payload->'entitlements','[]'),coalesce(p_payload->'limits','{}'),coalesce(p_payload->>'overage_policy','approval_required'),coalesce(p_payload->>'support_tier','standard'),v_actor)
  on conflict(id) do update set code=excluded.code,name=excluded.name,state=excluded.state,currency=excluded.currency,monthly_fee_micros=excluded.monthly_fee_micros,included_allowance_micros=excluded.included_allowance_micros,entitlements=excluded.entitlements,limits=excluded.limits,overage_policy=excluded.overage_policy,support_tier=excluded.support_tier,updated_at=now();
  v_result:=jsonb_build_object('status','saved','id',v_id,'source_kind','manual');
 when 'subscription.save' then
  select * into strict v_plan from public.pandora_service_plans where id=(p_payload->>'plan_id')::uuid and state='active';
  if p_payload?'currency' and p_payload->>'currency'<>v_plan.currency then raise exception 'CURRENCY_MISMATCH' using errcode='22023';end if;
  select to_jsonb(s) into v_before from public.pandora_customer_subscriptions s where organization_id=v_org;
  insert into public.pandora_customer_subscriptions(organization_id,plan_id,state,currency,monthly_fee_micros,setup_fee_micros,discount_micros,starts_on,ends_on,renews_on,notes,updated_by)
  values(v_org,v_plan.id,coalesce(p_payload->>'state','draft'),v_plan.currency,coalesce(nullif(p_payload->>'monthly_fee_micros','')::bigint,v_plan.monthly_fee_micros),nullif(p_payload->>'setup_fee_micros','')::bigint,coalesce(nullif(p_payload->>'discount_micros','')::bigint,0),nullif(p_payload->>'starts_on','')::date,nullif(p_payload->>'ends_on','')::date,nullif(p_payload->>'renews_on','')::date,coalesce(p_payload->>'notes',''),v_actor)
  on conflict(organization_id) do update set plan_id=excluded.plan_id,state=excluded.state,currency=excluded.currency,monthly_fee_micros=excluded.monthly_fee_micros,setup_fee_micros=excluded.setup_fee_micros,discount_micros=excluded.discount_micros,starts_on=excluded.starts_on,ends_on=excluded.ends_on,renews_on=excluded.renews_on,notes=excluded.notes,source_kind='manual',provider_reference=null,verified_at=null,updated_by=v_actor,updated_at=now();
  v_result:=jsonb_build_object('status','saved','organization_id',v_org,'source_kind','manual');
 when 'invoice.save' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  select * into v_invoice from public.pandora_customer_invoices where id=v_id;
  if found and (v_invoice.organization_id<>v_org or v_invoice.state<>'draft') then raise exception 'CONFLICT' using errcode='23505';end if;
  insert into public.pandora_customer_invoices(id,organization_id,invoice_number,currency,amount_micros,state,issued_on,due_on,notes,created_by)
  values(v_id,v_org,p_payload->>'invoice_number',p_payload->>'currency',(p_payload->>'amount_micros')::bigint,coalesce(p_payload->>'state','draft'),nullif(p_payload->>'issued_on','')::date,nullif(p_payload->>'due_on','')::date,coalesce(p_payload->>'notes',''),v_actor)
  on conflict(id) do update set invoice_number=excluded.invoice_number,currency=excluded.currency,amount_micros=excluded.amount_micros,state=excluded.state,issued_on=excluded.issued_on,due_on=excluded.due_on,notes=excluded.notes,updated_at=now();
  v_result:=jsonb_build_object('status','saved','organization_id',v_org,'id',v_id,'source_kind','manual');
 when 'payment.record' then
  select * into strict v_invoice from public.pandora_customer_invoices where id=(p_payload->>'invoice_id')::uuid and organization_id=v_org for update;
  if v_invoice.currency<>p_payload->>'currency' then raise exception 'CURRENCY_MISMATCH' using errcode='22023';end if;
  if v_invoice.state<>'issued' then raise exception 'ISSUED_INVOICE_REQUIRED' using errcode='22023';end if;
  v_amount:=(p_payload->>'amount_micros')::bigint;
  select coalesce(sum(case when payment_kind='refund' then -amount_micros else amount_micros end),0) into v_net from public.pandora_customer_payments where invoice_id=v_invoice.id;
  if (coalesce(p_payload->>'payment_kind','payment')='refund' and v_amount>v_net) or (coalesce(p_payload->>'payment_kind','payment')<>'refund' and v_amount+v_net>v_invoice.amount_micros) then raise exception 'AMOUNT_EXCEEDS_BALANCE' using errcode='22023';end if;
  insert into public.pandora_customer_payments(organization_id,invoice_id,currency,amount_micros,payment_kind,reference,occurred_on,created_by)
  values(v_org,v_invoice.id,v_invoice.currency,v_amount,coalesce(p_payload->>'payment_kind','payment'),p_payload->>'reference',(p_payload->>'occurred_on')::date,v_actor) returning id into v_id;
  v_result:=jsonb_build_object('status','recorded','organization_id',v_org,'id',v_id,'source_kind','manual');
 when 'case.save','access.request' then
  if nullif(p_payload->>'assigned_user_id','') is not null and not exists(select 1 from public.memberships where user_id=(p_payload->>'assigned_user_id')::uuid and organization_id in (v_org,v_platform) and status='active') then raise exception 'ASSIGNEE_NOT_AUTHORIZED' using errcode='22023';end if;
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from public.pandora_customer_cases where task_entity_id=v_id and organization_id<>v_org) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  if p_operation='access.request' then
   if length(coalesce(p_payload->>'reason',''))<3 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
   -- Repeated access requests reuse the open request; they never grant access.
   select c.task_entity_id into v_target from public.pandora_customer_cases c join public.enterprise_tasks t on t.entity_id=c.task_entity_id where c.organization_id=v_org and c.kind='access' and c.created_by=v_actor and t.task_state not in ('completed','cancelled') limit 1;
   if v_target is not null then v_result:=jsonb_build_object('status','pending','organization_id',v_org,'id',v_target);end if;
  end if;
  if v_result is null then
   if not exists(select 1 from public.pandora_customer_cases where task_entity_id=v_id) then
    insert into public.enterprise_entities(id,organization_id,entity_kind) values(v_id,v_org,'task');
    insert into public.enterprise_tasks(entity_id,organization_id,task_type,task_state,evidence_required) values(v_id,v_org,'customer_support','open',true);
   end if;
   v_state:=coalesce(p_payload->>'state','open');
   if v_state='completed' and length(coalesce(p_payload->>'resolution',''))<3 then raise exception 'RESOLUTION_REQUIRED' using errcode='22023';end if;
   insert into public.pandora_customer_cases(task_entity_id,organization_id,kind,subject,priority,needs_owner,assigned_user_id,description,resolution,created_by)
   values(v_id,v_org,case when p_operation='access.request' then 'access' else coalesce(p_payload->>'kind','issue') end,
    case when p_operation='access.request' then 'Customer workspace access request' else p_payload->>'subject' end,
    coalesce(p_payload->>'priority','normal'),case when p_operation='access.request' then true else coalesce((p_payload->>'needs_owner')::boolean,false) end,
    nullif(p_payload->>'assigned_user_id','')::uuid,coalesce(p_payload->>'description',p_payload->>'reason',''),coalesce(p_payload->>'resolution',''),v_actor)
   on conflict(task_entity_id) do update set subject=excluded.subject,kind=excluded.kind,priority=excluded.priority,needs_owner=excluded.needs_owner,assigned_user_id=excluded.assigned_user_id,description=excluded.description,resolution=excluded.resolution,updated_at=now();
   update public.enterprise_tasks set task_state=v_state,due_at=nullif(p_payload->>'due_at','')::timestamptz,completed_at=case when v_state='completed' then now() else null end,updated_at=now() where entity_id=v_id and organization_id=v_org;
   v_result:=jsonb_build_object('status','saved','organization_id',v_org,'id',v_id);
  end if;
 when 'prospect.save' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  insert into public.pandora_sales_opportunities(id,company_name,contact_name,contact_email,industry,source,stage,currency,estimated_value_micros,next_action,follow_up_at,decision_on,converted_organization_id,notes,owner_user_id)
  values(v_id,p_payload->>'company_name',p_payload->>'contact_name',p_payload->>'contact_email',coalesce(p_payload->>'industry','custom'),p_payload->>'source',coalesce(p_payload->>'stage','prospect'),nullif(p_payload->>'currency',''),nullif(p_payload->>'estimated_value_micros','')::bigint,p_payload->>'next_action',nullif(p_payload->>'follow_up_at','')::timestamptz,nullif(p_payload->>'decision_on','')::date,nullif(p_payload->>'converted_organization_id','')::uuid,coalesce(p_payload->>'notes',''),v_actor)
  on conflict(id) do update set company_name=excluded.company_name,contact_name=excluded.contact_name,contact_email=excluded.contact_email,industry=excluded.industry,source=excluded.source,stage=excluded.stage,currency=excluded.currency,estimated_value_micros=excluded.estimated_value_micros,next_action=excluded.next_action,follow_up_at=excluded.follow_up_at,decision_on=excluded.decision_on,converted_organization_id=excluded.converted_organization_id,notes=excluded.notes,updated_at=now();
  v_result:=jsonb_build_object('status','saved','id',v_id);
 when 'contract.save' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from public.pandora_customer_contracts where contract_entity_id=v_id and organization_id<>v_org) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  if not exists(select 1 from public.pandora_customer_contracts where contract_entity_id=v_id) then
   insert into public.enterprise_entities(id,organization_id,entity_kind) values(v_id,v_platform,'contract');
   insert into public.enterprise_contracts(entity_id,organization_id,contract_type) values(v_id,v_platform,coalesce(p_payload->>'contract_type','service_agreement'));
  end if;
  update public.enterprise_contracts set contract_state=coalesce(p_payload->>'state','draft'),effective_from=nullif(p_payload->>'starts_on','')::timestamptz,effective_to=nullif(p_payload->>'ends_on','')::timestamptz,updated_at=now() where entity_id=v_id and organization_id=v_platform;
  insert into public.pandora_customer_contracts(contract_entity_id,organization_id,contract_organization_id,title,document_url,document_sha256,renewal_on,currency,value_micros,created_by)
  values(v_id,v_org,v_platform,p_payload->>'title',nullif(p_payload->>'document_url',''),nullif(p_payload->>'document_sha256',''),nullif(p_payload->>'renewal_on','')::date,nullif(p_payload->>'currency',''),nullif(p_payload->>'value_micros','')::bigint,v_actor)
  on conflict(contract_entity_id) do update set title=excluded.title,document_url=excluded.document_url,document_sha256=excluded.document_sha256,renewal_on=excluded.renewal_on,currency=excluded.currency,value_micros=excluded.value_micros,updated_at=now();
  v_result:=jsonb_build_object('status','saved','organization_id',v_org,'id',v_id,'source_kind','manual');
 when 'incident.save' then
  v_org:=coalesce(v_org,v_platform);v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from public.pandora_platform_incidents where id=v_id and organization_id<>v_org) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  insert into public.pandora_platform_incidents(id,organization_id,title,severity,state,impact,diagnosis,resolution,verification_ref,resolved_at,owner_user_id)
  values(v_id,v_org,p_payload->>'title',coalesce(p_payload->>'severity','medium'),coalesce(p_payload->>'state','investigating'),p_payload->>'impact',coalesce(p_payload->>'diagnosis',''),coalesce(p_payload->>'resolution',''),nullif(p_payload->>'verification_ref',''),case when p_payload->>'state'='resolved' then now() else null end,v_actor)
  on conflict(id) do update set title=excluded.title,severity=excluded.severity,state=excluded.state,impact=excluded.impact,diagnosis=excluded.diagnosis,resolution=excluded.resolution,verification_ref=excluded.verification_ref,resolved_at=excluded.resolved_at,updated_at=now();
  v_result:=jsonb_build_object('status','saved','organization_id',v_org,'id',v_id);
 when 'device.revoke' then
  if length(coalesce(p_payload->>'reason',''))<3 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  update public.enterprise_devices set trust_state='revoked',updated_at=now() where entity_id=(p_payload->>'id')::uuid and organization_id=v_org;
  if not found then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  v_result:=jsonb_build_object('status','revoked','organization_id',v_org,'id',p_payload->>'id','verification','server_trust_revoked_device_acknowledgment_pending');
 when 'partner.save' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  insert into public.pandora_business_partners(id,name,kind,state,service,contact,recurring_cost_micros,currency,next_review_on,notes,updated_by)
  values(v_id,p_payload->>'name',p_payload->>'kind',coalesce(p_payload->>'state','active'),p_payload->>'service',p_payload->>'contact',nullif(p_payload->>'recurring_cost_micros','')::bigint,nullif(p_payload->>'currency',''),nullif(p_payload->>'next_review_on','')::date,coalesce(p_payload->>'notes',''),v_actor)
  on conflict(id) do update set name=excluded.name,kind=excluded.kind,state=excluded.state,service=excluded.service,contact=excluded.contact,recurring_cost_micros=excluded.recurring_cost_micros,currency=excluded.currency,next_review_on=excluded.next_review_on,notes=excluded.notes,updated_by=v_actor,updated_at=now();
  v_result:=jsonb_build_object('status','saved','id',v_id,'source_kind','manual');
 when 'operator.grant' then
  v_target:=(p_payload->>'user_id')::uuid;
  if v_target=v_actor then raise exception 'SELF_CHANGE_DENIED' using errcode='42501';end if;
  if not exists(select 1 from public.memberships where organization_id=v_platform and user_id=v_target and status='active') then raise exception 'INTERNAL_MEMBERSHIP_REQUIRED' using errcode='22023';end if;
  if nullif(p_payload->>'scope_organization_id','') is not null and not exists(select 1 from public.pandora_enterprise_accounts where organization_id=(p_payload->>'scope_organization_id')::uuid) then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  if p_payload->>'role'='owner' and nullif(p_payload->>'scope_organization_id','') is not null then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  if nullif(p_payload->>'expires_at','') is not null and (p_payload->>'expires_at')::timestamptz<=now() and coalesce(p_payload->>'state','active')='active' then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  insert into private.pandora_operator_grants(user_id,organization_id,role,state,expires_at,granted_by,reason)
  values(v_target,nullif(p_payload->>'scope_organization_id','')::uuid,p_payload->>'role',coalesce(p_payload->>'state','active'),nullif(p_payload->>'expires_at','')::timestamptz,v_actor,p_payload->>'reason')
  on conflict(user_id,organization_id) do update set role=excluded.role,state=excluded.state,expires_at=excluded.expires_at,granted_by=v_actor,reason=excluded.reason,updated_at=now() returning id into v_id;
  v_result:=jsonb_build_object('status','saved','id',v_id,'next_action','Client business access still requires a separate target membership');
 else raise exception 'INVALID_REQUEST' using errcode='22023';
 end case;
 v_result:=v_result||jsonb_build_object('receipt_id',v_receipt.id,'replayed',false);
 update private.pandora_core_operation_receipts set organization_id=v_org,result=v_result where id=v_receipt.id;
 perform private.append_audit_event(coalesce(v_org,v_platform),null,null,'human'::public.audit_actor_type,v_actor,
  'core.'||p_operation,jsonb_build_object('receipt_id',v_receipt.id,'operation',p_operation,'target',coalesce(v_id::text,v_org::text),'authorization',v_role,
  'payload_sha256',v_hash,'changed_fields',(select jsonb_agg(k) from jsonb_object_keys(p_payload) k),
  'before_sha256',case when v_before is not null then encode(extensions.digest(convert_to(v_before::text,'UTF8'),'sha256'),'hex') else null end,
  'commercial_before',case when p_operation='subscription.save' then v_before-'notes'-'provider_reference'-'updated_by' else null end,
  'commercial_after',case when p_operation='subscription.save' then (select to_jsonb(s)-'notes'-'provider_reference'-'updated_by' from public.pandora_customer_subscriptions s where s.organization_id=v_org) else null end,
  'result',v_result,'source','pandora-core-v1'));
 return v_result;
end;
$$;

create function public.pandora_core_enter_client_v1(p_organization_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_role text;v_entry uuid;v_session uuid;v_client record;v_expiry timestamptz:=now()+interval '1 hour';
begin
 v_role:=private.pandora_core_assert_v1(p_organization_id,array['owner','operator','support'],true);
 if length(coalesce(trim(p_reason),'')) not between 3 and 500 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 select a.*,o.name,o.slug into v_client from public.pandora_enterprise_accounts a join public.organizations o on o.id=a.organization_id
 where a.organization_id=p_organization_id and o.status='active' and a.lifecycle_state not in ('suspended','offboarding','archived');
 if not found or not private.is_org_member(p_organization_id) then raise exception 'CLIENT_MEMBERSHIP_REQUIRED' using errcode='42501';end if;
 -- Existing PLP adapter is bound to the actual PLP organization/property pair.
 -- Other workspaces remain onboarding until their runtime adapter proves exact scope.
 if v_client.workspace_type<>'plp' or v_client.slug<>'plp-boracay' or v_client.property_id is null then raise exception 'WORKSPACE_NOT_VERIFIED' using errcode='22023';end if;
 v_session:=(auth.jwt()->>'session_id')::uuid;
 update private.pandora_client_entry_sessions set ended_at=now() where actor_user_id=auth.uid() and auth_session_id=v_session and ended_at is null;
 insert into private.pandora_client_entry_sessions(actor_user_id,auth_session_id,organization_id,reason,expires_at)
 values(auth.uid(),v_session,p_organization_id,trim(p_reason),v_expiry) returning id into v_entry;
 perform private.append_audit_event(p_organization_id,null,null,'human'::public.audit_actor_type,auth.uid(),'core.client.enter',
  jsonb_build_object('entry_id',v_entry,'authorization',v_role,'reason',trim(p_reason),'expires_at',v_expiry,'source','pandora-core-v1'));
 return jsonb_build_object('entry_id',v_entry,'organization_id',p_organization_id,'property_id',v_client.property_id,
  'workspace_type',v_client.workspace_type,'display_name',v_client.name,'expires_at',v_expiry);
end;
$$;
create function public.pandora_core_leave_client_v1(p_entry_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_org uuid;
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 update private.pandora_client_entry_sessions set ended_at=coalesce(ended_at,now())
 where id=p_entry_id and actor_user_id=auth.uid() and auth_session_id=(auth.jwt()->>'session_id')::uuid
 returning organization_id into v_org;
 if not found then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 perform private.append_audit_event(v_org,null,null,'human'::public.audit_actor_type,auth.uid(),'core.client.leave',jsonb_build_object('entry_id',p_entry_id));
 return jsonb_build_object('status','closed');
end;
$$;
create function public.pandora_core_validate_entry_v1(p_entry_id uuid,p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select private.pandora_core_role_v1(p_organization_id) in ('owner','operator','support') and private.is_org_member(p_organization_id)
 and exists(select 1 from private.pandora_client_entry_sessions e join auth.sessions s on s.id=e.auth_session_id
  join public.organizations o on o.id=e.organization_id
  join public.pandora_enterprise_accounts a on a.organization_id=e.organization_id
  where e.id=p_entry_id and e.organization_id=p_organization_id and e.actor_user_id=auth.uid()
  and e.auth_session_id=(auth.jwt()->>'session_id')::uuid and e.ended_at is null and e.expires_at>now()
  and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()) and s.aal::text='aal2'
  and auth.jwt()->>'aal'='aal2' and o.status='active' and a.lifecycle_state not in ('suspended','offboarding','archived'));
$$;
create function public.pandora_core_authorize_user_admin_v1(p_organization_id uuid,p_write boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_role text;
begin
 if not exists(select 1 from public.pandora_enterprise_accounts where organization_id=p_organization_id) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 v_role:=private.pandora_core_assert_v1(p_organization_id,array['owner','operator'],p_write);
 return jsonb_build_object('organization_id',p_organization_id,'role',case when v_role='owner' then 'owner' else 'admin' end,'authority','explicit_operator_grant');
end;
$$;

-- New privileges are closed by default, including private SECURITY DEFINER helpers.
revoke all on function private.pandora_core_actor_role_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function private.pandora_core_role_v1(uuid) from public,anon,authenticated;
grant execute on function private.pandora_core_role_v1(uuid) to authenticated;
revoke all on function private.pandora_core_assert_v1(uuid,text[],boolean),private.pandora_core_connections_v1(uuid),private.pandora_core_clients_v1(uuid),private.pandora_core_usage_v1(uuid),private.pandora_core_payload_v1(jsonb,text[]),private.pandora_core_onboarding_verify_v1(uuid) from public,anon,authenticated;
revoke all on function public.pandora_core_snapshot_v1(text,uuid),public.pandora_core_operate_v1(text,uuid,jsonb,uuid),public.pandora_core_enter_client_v1(uuid,text),public.pandora_core_leave_client_v1(uuid),public.pandora_core_validate_entry_v1(uuid,uuid),public.pandora_core_authorize_user_admin_v1(uuid,boolean) from public,anon;
grant execute on function public.pandora_core_snapshot_v1(text,uuid),public.pandora_core_operate_v1(text,uuid,jsonb,uuid),public.pandora_core_enter_client_v1(uuid,text),public.pandora_core_leave_client_v1(uuid),public.pandora_core_validate_entry_v1(uuid,uuid),public.pandora_core_authorize_user_admin_v1(uuid,boolean) to authenticated;

comment on function public.pandora_core_snapshot_v1(text,uuid) is 'Bounded explicit-operator projection over canonical owner and tenant truth. Client members have no ambient access.';
comment on function public.pandora_core_operate_v1(text,uuid,jsonb,uuid) is 'Atomic payload-bound idempotent owner operation. Financial/access mutations require live AAL2; no external side effects or provider-verification fabrication.';
comment on table public.pandora_enterprise_accounts is 'Pandora commercial/operator relationship to canonical organizations, not a second tenant directory.';
comment on table private.pandora_client_entry_sessions is 'Audited temporary operator context. Does not grant membership or bypass tenant RLS.';

-- Extend the existing user-admin brokers; never introduce a parallel user store.
CREATE OR REPLACE FUNCTION public.pandora_admin_add_organization_member(p_actor_user_id uuid, p_organization_id uuid, p_target_user_id uuid, p_role member_role)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_user_id uuid := p_actor_user_id;
  actor_role public.member_role;
  target_confirmed boolean;
  target_anonymous boolean;
  existing_membership public.memberships%rowtype;
  desired_status public.membership_status;
  changed_at timestamptz := clock_timestamp();
  audit_event_type text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service-role broker required'
      using errcode = '42501';
  end if;

  if actor_user_id is null
     or not exists (
       select 1
       from auth.users caller
       where caller.id = actor_user_id
         and coalesce(caller.is_anonymous, false) = false
     ) then
    raise exception 'existing non-anonymous administrator required'
      using errcode = '22023';
  end if;

  if p_organization_id is null or p_target_user_id is null or p_role is null then
    raise exception 'organization, target user, and role are required'
      using errcode = '22023';
  end if;

  if p_target_user_id = actor_user_id then
    raise exception 'cannot change your own membership through the add-user workflow'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pandora-membership-org:' || p_organization_id::text,0));

  select membership.role
    into actor_role
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = actor_user_id
    and membership.status = 'active'::public.membership_status;

  -- The broker remains service-role-only. The Edge gateway first validates the
  -- caller's actual JWT and live AAL2 through pandora_core_authorize_user_admin_v1.
  -- Re-check the server-controlled operator grant at mutation time.
  if actor_role is null or actor_role not in ('owner'::public.member_role,'admin'::public.member_role) then
    actor_role := case private.pandora_core_actor_role_v1(actor_user_id,p_organization_id)
      when 'owner' then 'owner'::public.member_role
      when 'operator' then 'admin'::public.member_role else null end;
  end if;
  if not exists(select 1 from public.organizations where id=p_organization_id and status='active') then
    raise exception 'active organization required' using errcode='42501';
  end if;

  if actor_role is null or actor_role not in (
    'owner'::public.member_role,
    'admin'::public.member_role
  ) then
    raise exception 'active owner or administrator membership required'
      using errcode = '42501';
  end if;

  if actor_role = 'admin'::public.member_role
     and p_role not in (
       'operator'::public.member_role,
       'member'::public.member_role,
       'viewer'::public.member_role
     ) then
    raise exception 'administrators cannot grant owner or admin roles'
      using errcode = '42501';
  end if;

  select account.email_confirmed_at is not null,
         coalesce(account.is_anonymous, false)
    into target_confirmed, target_anonymous
  from auth.users account
  where account.id = p_target_user_id;

  if not found or target_anonymous then
    raise exception 'target must be an existing non-anonymous auth user'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('pandora-membership-org:' || p_organization_id::text, 0)
  );

  select membership.*
    into existing_membership
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_target_user_id
  for update;

  desired_status := case
    when target_confirmed then 'active'::public.membership_status
    else 'invited'::public.membership_status
  end;

  if found then
    if existing_membership.status in (
      'active'::public.membership_status,
      'invited'::public.membership_status
    ) then
      if existing_membership.role <> p_role then
        raise exception 'membership already exists with another role'
          using errcode = '23505';
      end if;

      if existing_membership.status = 'active'::public.membership_status
         or existing_membership.status = desired_status then
        return jsonb_build_object(
          'userId', existing_membership.user_id,
          'organizationId', existing_membership.organization_id,
          'role', existing_membership.role,
          'status', existing_membership.status,
          'created', false,
          'restored', false,
          'idempotent', true
        );
      end if;

      update public.memberships
      set status = 'active'::public.membership_status,
          joined_at = coalesce(joined_at, changed_at),
          invited_by = coalesce(invited_by, actor_user_id),
          updated_at = changed_at
      where organization_id = p_organization_id
        and user_id = p_target_user_id;

      desired_status := 'active'::public.membership_status;
      audit_event_type := 'organization.member.activated';
    else
      update public.memberships
      set role = p_role,
          status = desired_status,
          invited_by = actor_user_id,
          joined_at = case when desired_status = 'active' then changed_at else null end,
          updated_at = changed_at
      where organization_id = p_organization_id
        and user_id = p_target_user_id;

      audit_event_type := 'organization.member.restored';
    end if;
  else
    insert into public.memberships (
      organization_id,
      user_id,
      role,
      status,
      invited_by,
      joined_at,
      created_at,
      updated_at
    ) values (
      p_organization_id,
      p_target_user_id,
      p_role,
      desired_status,
      actor_user_id,
      case when desired_status = 'active' then changed_at else null end,
      changed_at,
      changed_at
    );

    audit_event_type := case
      when desired_status = 'active' then 'organization.member.added'
      else 'organization.member.invited'
    end;
  end if;

  perform private.append_audit_event(
    p_organization_id,
    null,
    null,
    'human'::public.audit_actor_type,
    actor_user_id,
    audit_event_type,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'role', p_role,
      'status', desired_status,
      'source', 'pandora-user-admin'
    )
  );

  return jsonb_build_object(
    'userId', p_target_user_id,
    'organizationId', p_organization_id,
    'role', p_role,
    'status', desired_status,
    'created', existing_membership.organization_id is null,
    'restored', existing_membership.organization_id is not null,
    'idempotent', false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.pandora_admin_update_organization_member(p_actor_user_id uuid, p_organization_id uuid, p_target_user_id uuid, p_role member_role DEFAULT NULL::member_role, p_status membership_status DEFAULT NULL::membership_status)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_role public.member_role;
  current_membership public.memberships%rowtype;
  next_role public.member_role;
  next_status public.membership_status;
  changed_at timestamptz := clock_timestamp();
  remaining_active_owners integer;
  event_type text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service-role broker required'
      using errcode = '42501';
  end if;

  if p_actor_user_id is null
     or not exists (
       select 1
       from auth.users caller
       where caller.id = p_actor_user_id
         and coalesce(caller.is_anonymous, false) = false
     ) then
    raise exception 'existing non-anonymous administrator required'
      using errcode = '22023';
  end if;

  if p_organization_id is null or p_target_user_id is null then
    raise exception 'organization and target user are required'
      using errcode = '22023';
  end if;

  if p_role is null and p_status is null then
    raise exception 'role or status change required'
      using errcode = '22023';
  end if;

  if p_target_user_id = p_actor_user_id then
    raise exception 'cannot change your own membership through the user-admin workflow'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pandora-membership-org:' || p_organization_id::text,0));

  select membership.role
    into actor_role
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_actor_user_id
    and membership.status = 'active'::public.membership_status;

  -- The broker remains service-role-only. The Edge gateway first validates the
  -- caller's actual JWT and live AAL2 through pandora_core_authorize_user_admin_v1.
  -- Re-check the server-controlled operator grant at mutation time.
  if actor_role is null or actor_role not in ('owner'::public.member_role,'admin'::public.member_role) then
    actor_role := case private.pandora_core_actor_role_v1(p_actor_user_id,p_organization_id)
      when 'owner' then 'owner'::public.member_role
      when 'operator' then 'admin'::public.member_role else null end;
  end if;
  if not exists(select 1 from public.organizations where id=p_organization_id and status='active') then
    raise exception 'active organization required' using errcode='42501';
  end if;

  if actor_role is null or actor_role not in (
    'owner'::public.member_role,
    'admin'::public.member_role
  ) then
    raise exception 'active owner or administrator membership required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('pandora-membership-org:' || p_organization_id::text, 0)
  );

  select membership.*
    into current_membership
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_target_user_id
  for update;

  if not found then
    raise exception 'target membership not found'
      using errcode = 'P0002';
  end if;

  next_role := coalesce(p_role, current_membership.role);
  next_status := coalesce(p_status, current_membership.status);

  if next_status = 'invited'::public.membership_status then
    raise exception 'use invitation workflow for invited membership'
      using errcode = '22023';
  end if;

  if actor_role = 'admin'::public.member_role then
    if current_membership.role in (
      'owner'::public.member_role,
      'admin'::public.member_role
    ) then
      raise exception 'administrators cannot modify owner or admin memberships'
        using errcode = '42501';
    end if;
    if next_role in (
      'owner'::public.member_role,
      'admin'::public.member_role
    ) then
      raise exception 'administrators cannot grant owner or admin roles'
        using errcode = '42501';
    end if;
  end if;

  if current_membership.role = 'owner'::public.member_role
     and current_membership.status = 'active'::public.membership_status
     and (
       next_role <> 'owner'::public.member_role
       or next_status <> 'active'::public.membership_status
     ) then
    select count(*)
      into remaining_active_owners
    from public.memberships membership
    where membership.organization_id = p_organization_id
      and membership.user_id <> p_target_user_id
      and membership.role = 'owner'::public.member_role
      and membership.status = 'active'::public.membership_status;

    if remaining_active_owners < 1 then
      raise exception 'cannot remove the last active owner'
        using errcode = '42501';
    end if;
  end if;

  if current_membership.role = next_role
     and current_membership.status = next_status then
    return jsonb_build_object(
      'userId', current_membership.user_id,
      'organizationId', current_membership.organization_id,
      'previousRole', current_membership.role,
      'role', current_membership.role,
      'previousStatus', current_membership.status,
      'status', current_membership.status,
      'changed', false,
      'idempotent', true
    );
  end if;

  update public.memberships
  set role = next_role,
      status = next_status,
      joined_at = case
        when next_status = 'active'::public.membership_status
          then coalesce(joined_at, changed_at)
        else joined_at
      end,
      updated_at = changed_at
  where organization_id = p_organization_id
    and user_id = p_target_user_id;

  event_type := case
    when next_status = 'revoked'::public.membership_status
      then 'organization.member.revoked'
    when next_status = 'suspended'::public.membership_status
      then 'organization.member.suspended'
    when current_membership.status <> 'active'::public.membership_status
         and next_status = 'active'::public.membership_status
      then 'organization.member.activated'
    when current_membership.role <> next_role
      then 'organization.member.role_changed'
    else 'organization.member.updated'
  end;

  perform private.append_audit_event(
    p_organization_id,
    null,
    null,
    'human'::public.audit_actor_type,
    p_actor_user_id,
    event_type,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'previous_role', current_membership.role,
      'role', next_role,
      'previous_status', current_membership.status,
      'status', next_status,
      'source', 'pandora-user-admin'
    )
  );

  return jsonb_build_object(
    'userId', p_target_user_id,
    'organizationId', p_organization_id,
    'previousRole', current_membership.role,
    'role', next_role,
    'previousStatus', current_membership.status,
    'status', next_status,
    'changed', true,
    'idempotent', false
  );
end;
$function$;

-- Account suspension is enforced by the existing tenant RLS helpers. This only
-- narrows existing membership authority; operator grants never bypass these checks.
create or replace function private.is_org_member(target_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')<>'true'
 and exists(select 1 from public.memberships m
  join public.organizations o on o.id=m.organization_id and o.status='active'
  join auth.users u on u.id=m.user_id and not coalesce(u.is_anonymous,false)
  where m.organization_id=target_organization_id and m.user_id=auth.uid() and m.status='active'
  and (u.banned_until is null or u.banned_until<=now()) and u.deleted_at is null);
$$;
create or replace function private.has_org_role(target_organization_id uuid,allowed_roles public.member_role[])
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')<>'true'
 and exists(select 1 from public.memberships m
  join public.organizations o on o.id=m.organization_id and o.status='active'
  join auth.users u on u.id=m.user_id and not coalesce(u.is_anonymous,false)
  where m.organization_id=target_organization_id and m.user_id=auth.uid() and m.status='active' and m.role=any(allowed_roles)
  and (u.banned_until is null or u.banned_until<=now()) and u.deleted_at is null);
$$;

commit;
