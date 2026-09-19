-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create table if not exists private.project_resource_bindings (
  repo_full_name text primary key,
  github_access text not null default 'read_write'
    check (github_access in ('read_only','read_write')),
  supabase_project_ref text,
  supabase_project_name text,
  database_binding_state text not null
    check (database_binding_state in ('verified_schema','project_empty','not_identified','not_required','quarantined')),
  vercel_team_id text,
  vercel_project_id text,
  vercel_project_name text,
  vercel_binding_state text not null
    check (vercel_binding_state in ('verified','deployment_error','not_identified','not_required')),
  canonical_domain text,
  notes text not null default '',
  verified_at timestamptz,
  updated_at timestamptz not null default now(),
  check (supabase_project_ref is null or supabase_project_ref ~ '^[a-z0-9]{20}$'),
  check (repo_full_name ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
);

comment on table private.project_resource_bindings is
  'Canonical ProjectOS registry binding each GitHub repository to its verified Supabase and Vercel resources. Null or not_identified bindings must never be guessed.';

revoke all on table private.project_resource_bindings from public, anon, authenticated, service_role;

insert into private.project_resource_bindings (
  repo_full_name, github_access, supabase_project_ref, supabase_project_name,
  database_binding_state, vercel_team_id, vercel_project_id, vercel_project_name,
  vercel_binding_state, canonical_domain, notes, verified_at, updated_at
) values
('mbanatao/Battle','read_write','ydyzokdndnhwjpibrsvu','Battle','verified_schema','team_IcdJUnzLi5wUN1GD8ALHyjF7','prj_ldIscDQj8s3ONbz4f0F7FScLMGnK','battle','verified','battletested.vercel.app','Canonical paid-team deployment and repository-backed Supabase schema.',now(),now()),
('mbanatao/callgate-platform','read_write','czsjwmasypvgcnewrlcf','callgate-platform','project_empty','team_IcdJUnzLi5wUN1GD8ALHyjF7','prj_Zk2uzBX1A834793yxpGY8oOX8l6W','callgate-platform','deployment_error',null,'Dedicated project exists but public schema is empty; latest production deployment is in error. Do not use legacy xkkimmqzplzdmaszkzmr as canonical.',now(),now()),
('mbanatao/codebase-memory-mcp','read_write',null,null,'not_identified',null,null,null,'not_identified',null,'No dedicated Supabase or Vercel project verified.',now(),now()),
('mbanatao/e-mango','read_write',null,null,'not_identified','team_IcdJUnzLi5wUN1GD8ALHyjF7','prj_GSeJbamdnnylbk2BlGBsNEpVpbYT','e-mango','verified',null,'Vercel project verified; no repository-backed Supabase binding identified.',now(),now()),
('mbanatao/evelas','read_write',null,null,'not_identified',null,null,null,'not_identified',null,'No dedicated Supabase or Vercel project verified.',now(),now()),
('mbanatao/fong','read_write','jhygppdcfrmejbzyozud','fxpass','verified_schema','team_IcdJUnzLi5wUN1GD8ALHyjF7','prj_t9cl0GiY9APSTw2NUNJLtRg6auwZ','fxpass','verified','fxpass.vercel.app','Canonical FXPass repository, production database, and paid-team deployment.',now(),now()),
('mbanatao/Hatid-ph','read_write',null,null,'not_identified',null,null,null,'not_identified',null,'No dedicated Supabase or Vercel project verified.',now(),now()),
('mbanatao/lakeview','read_write',null,null,'not_identified',null,null,null,'not_identified',null,'No dedicated Supabase or Vercel project verified.',now(),now()),
('mbanatao/launchos','read_write','qjarspsifemjubmzsdgy','Launchos','project_empty',null,null,null,'not_identified',null,'Dedicated Supabase project exists but public schema is empty; no Vercel project verified.',now(),now()),
('mbanatao/legacy','read_write',null,null,'not_identified','team_3yw1CN59ce4pj5SwyQGCAqN3','prj_kuNkaautToz57Szq5RhysB7ZsAkb','legacy','verified',null,'Vercel project verified; no dedicated Supabase binding identified.',now(),now()),
('mbanatao/mcpmaster','read_write','jcyqixttuebxqqfkjonq','MCPMaster Meta Staging','verified_schema','team_3yw1CN59ce4pj5SwyQGCAqN3','prj_aG8ekiHMsCEYn6dbIK5Mk4HeNuZ8','mcpmaster','verified','mcpmasterz.vercel.app','ProjectOS control plane; production-targeted Vercel project and live control database.',now(),now()),
('mbanatao/Memory','read_write','ivmvufhcsezyhczzondn','Memory','verified_schema','team_3yw1CN59ce4pj5SwyQGCAqN3','prj_Sav0aQAgZxEs3J4pplcgp6dsFZhp','memory','verified','memory-psi-steel.vercel.app','Dedicated database verified with 67 public tables and production-targeted Vercel deployment.',now(),now()),
('mbanatao/pandorasbox','read_write',null,null,'not_identified',null,null,null,'not_identified',null,'No dedicated Supabase or Vercel project verified.',now(),now()),
('mbanatao/realmatch','read_write','ijqivgnlqndddftgazxc','realmatch','verified_schema','team_3yw1CN59ce4pj5SwyQGCAqN3','prj_Zuyr4F6cpULzBwfNpAiKAHw4DlBx','realmatch','verified','realmatch-one.vercel.app','Canonical repository provisioning record; database restored to ACTIVE_HEALTHY. Duplicate rkthpfdzzisudaxxqvgn is quarantined.',now(),now())
on conflict (repo_full_name) do update set
  github_access=excluded.github_access,
  supabase_project_ref=excluded.supabase_project_ref,
  supabase_project_name=excluded.supabase_project_name,
  database_binding_state=excluded.database_binding_state,
  vercel_team_id=excluded.vercel_team_id,
  vercel_project_id=excluded.vercel_project_id,
  vercel_project_name=excluded.vercel_project_name,
  vercel_binding_state=excluded.vercel_binding_state,
  canonical_domain=excluded.canonical_domain,
  notes=excluded.notes,
  verified_at=excluded.verified_at,
  updated_at=now();
