-- Pandora Base44 read bridge identity mapping.
create table if not exists private.pandora_base44_identity_links (
  id uuid primary key default gen_random_uuid(),
  base44_origin text not null,
  base44_app_id text not null,
  base44_user_id text not null,
  pandora_user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  enabled boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint pandora_base44_identity_links_origin_https_check check (base44_origin ~ '^https://[a-z0-9][a-z0-9-]*\.base44\.app$'),
  constraint pandora_base44_identity_links_exact_tuple_key unique (base44_origin, base44_app_id, base44_user_id, project_id)
);
revoke all on private.pandora_base44_identity_links from public, anon, authenticated;
grant select on private.pandora_base44_identity_links to service_role;

create or replace function public.pandora_base44_resolve_identity_v1(p_origin text,p_app_id text,p_base44_user_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  select jsonb_build_object('pandoraUserId',l.pandora_user_id,'organizationId',l.organization_id,'projectId',l.project_id)
  from private.pandora_base44_identity_links l
  join public.memberships m on m.organization_id=l.organization_id and m.user_id=l.pandora_user_id and m.status='active'
  join public.projectos_projects p on p.id=l.project_id and p.organization_id=l.organization_id
  where l.enabled=true and l.base44_origin=p_origin and l.base44_app_id=p_app_id and l.base44_user_id=p_base44_user_id
  order by l.updated_at desc limit 1
$fn$;
revoke all on function public.pandora_base44_resolve_identity_v1(text,text,text) from public, anon, authenticated;
grant execute on function public.pandora_base44_resolve_identity_v1(text,text,text) to service_role;

insert into private.pandora_base44_identity_links(base44_origin,base44_app_id,base44_user_id,pandora_user_id,organization_id,project_id,enabled)
values ('https://build-with-pandora.base44.app','6a94ecfadf75736cd4ebf7e1','6a94ecfadf75736cd4ebf7e2','f17558e4-e1b2-4b8d-a215-b96775b1a470'::uuid,'076a9306-5c4e-4d9d-98d3-e3a6fea968fb'::uuid,'db007811-fe55-42b4-b0be-3a11324dcfff'::uuid,true)
on conflict (base44_origin,base44_app_id,base44_user_id,project_id)
do update set pandora_user_id=excluded.pandora_user_id,organization_id=excluded.organization_id,enabled=true,updated_at=timezone('utc',now());

comment on table private.pandora_base44_identity_links is 'Service-only mapping used after Base44 bearer validation; Base44 remains presentation/authentication input, not Pandora authority.';
comment on function public.pandora_base44_resolve_identity_v1(text,text,text) is 'Service-role-only resolver for an externally validated Base44 user ID with active Pandora membership and exact project/org binding.';
