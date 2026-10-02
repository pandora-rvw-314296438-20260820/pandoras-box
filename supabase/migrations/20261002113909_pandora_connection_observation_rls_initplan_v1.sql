-- Keep Lane D observation reads tenant-scoped without per-row auth.uid() re-evaluation.

drop policy if exists pandora_connection_verification_observations_read_v1
  on public.pandora_connection_verification_observations_v1;

create policy pandora_connection_verification_observations_read_v1
on public.pandora_connection_verification_observations_v1
for select
to authenticated
using (
  exists (
    select 1
    from public.memberships m
    where m.organization_id =
      pandora_connection_verification_observations_v1.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'::public.membership_status
  )
);
