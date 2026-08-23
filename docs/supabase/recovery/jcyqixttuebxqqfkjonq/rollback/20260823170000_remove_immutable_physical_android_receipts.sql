-- FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK.
--
-- Stop all physical Android enrollment, lookup, capture, and release-status
-- capability. Preserve observer identities, one-shot JTI history, rate-limit
-- history, immutable Wi-Fi/mobile-data receipts, review bindings, triggers,
-- and reader definitions so prior evidence remains auditable and no weaker
-- pre-physical release projection can become authoritative.

begin;

revoke all on function public.register_physical_android_observer_identity(
  uuid,text,text,text[]
) from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function public.resolve_physical_android_observer_identity(uuid,text)
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function public.consume_physical_android_authority_rate_limit(uuid)
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function public.capture_canonical_physical_android_receipt(
  uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text[],uuid,uuid,text,uuid,uuid,text,text,text,text
) from public, anon, authenticated, service_role, projectos_physical_android_ingest;

revoke all on function public.get_canonical_physical_android_release_status(uuid,text,text)
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;

-- Revoke all possible canonical reader layers. Conditional lookup keeps this
-- rollback independently safe at its original migration point and at head.
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

revoke usage on schema public from projectos_physical_android_ingest;
revoke projectos_physical_android_ingest from authenticator;
alter role projectos_physical_android_ingest nologin noinherit;

-- Identity state is operational capability, not historical receipt evidence.
-- Drain it in place so every existing foreign-key and audit binding survives.
update private.physical_android_observer_identities
set status = 'draining',
    updated_at = clock_timestamp()
where status = 'active';

commit;
