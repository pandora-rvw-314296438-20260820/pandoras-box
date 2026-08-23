-- FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK.
--
-- Disable new final-review and owner-authorization capture without weakening
-- the release reader. Immutable review/owner receipts, nonce history, triggers,
-- and the gated reader definitions remain intact for reconciliation.

begin;

revoke all on function public.capture_canonical_release_owner_authorization(
  uuid,text,uuid,text,text,uuid,text,text,text,timestamptz
) from public, anon, authenticated, service_role, projectos_reviewer_ingest;

revoke all on function public.capture_canonical_release_review_receipt(
  uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated, service_role, projectos_reviewer_ingest;

-- Revoke both the fully gated reader and its internal pre-attestation wrapper
-- plus any later physical wrapper so this capability rollback cannot expose a
-- weaker release projection when it is executed standalone on the current head.
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

commit;
