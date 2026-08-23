-- FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK.
--
-- Stop new canonical provider receipt capture and canonical status reads while
-- retaining the immutable Supabase/Vercel receipt tables, rows, triggers, and
-- mutation guard. Historical release evidence remains available for incident
-- reconciliation and cannot silently become an operational status surface.

begin;

-- Revoke every reader that can exist at this migration point or at a later
-- head. Conditional lookup keeps this rollback safe both standalone and as
-- part of the ordered release-capability shutdown bundle.
do $readers$
begin
  if to_regprocedure('public.get_canonical_release_status(uuid,text,text)') is not null then
    execute 'revoke all on function public.get_canonical_release_status(uuid,text,text) from public, anon, authenticated, service_role';
  end if;
  if to_regprocedure('public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)') is not null then
    execute 'revoke all on function public.get_canonical_release_status_without_physical_android_authority(uuid,text,text) from public, anon, authenticated, service_role';
  end if;
  if to_regprocedure('public.get_canonical_release_status_without_final_attestations(uuid,text,text)') is not null then
    execute 'revoke all on function public.get_canonical_release_status_without_final_attestations(uuid,text,text) from public, anon, authenticated, service_role';
  end if;
end
$readers$;

revoke all on function public.capture_canonical_supabase_release_receipt(
  uuid,text,text,text,text,text,text,text,text
) from public, anon, authenticated, service_role;

revoke all on function public.capture_canonical_vercel_rehearsal_receipt(
  uuid,text,text,text,text,text,text
) from public, anon, authenticated, service_role;

commit;
