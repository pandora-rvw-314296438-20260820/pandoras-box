-- Canonical post-fallback convergence patch for observable acceptance verification.
-- The original v5a verifier migration is version-aligned with live provider history and
-- therefore remains before the canonical 20260830225000 fallback migration. This patch
-- deterministically wires convergence v2 after that target exists. It is idempotent on
-- provider state where v5a was applied live after the fallback migration.

do $block$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='pandora_converge_static_site_build_v2_20260830';

  if v_def is null then
    raise exception 'STATIC_CONVERGENCE_V2_PATCH_TARGET_MISSING';
  elsif position('private.pandora_worker_e_verify_supabase_preview_v2_20260830' in v_def)>0 then
    null;
  elsif position('private.pandora_worker_e_verify_supabase_preview_20260830' in v_def)>0 then
    v_def:=replace(
      v_def,
      'private.pandora_worker_e_verify_supabase_preview_20260830',
      'private.pandora_worker_e_verify_supabase_preview_v2_20260830'
    );
    execute v_def;
  else
    raise exception 'STATIC_CONVERGENCE_V2_PATCH_TARGET_UNRECOGNIZED';
  end if;
end
$block$;
