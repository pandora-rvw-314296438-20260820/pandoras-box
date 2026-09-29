-- R-005: enforce the source-side tracking minimization contract for future writes.
-- NOT VALID preserves historical rows without a table scan or history rewrite.
-- These checks still reject nonconforming INSERT and UPDATE rows.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.pandora_tracking_clicks'::regclass
      and conname='pandora_tracking_clicks_minimized_v1_check'
  ) then
    alter table public.pandora_tracking_clicks
      add constraint pandora_tracking_clicks_minimized_v1_check
      check (
        referrer is null
        and user_agent is null
        and ip_hash is null
        and visitor_hash is null
        and platform_click_ids = '{}'::jsonb
        and query_params = '{}'::jsonb
        and metadata in ('{}'::jsonb, '{"collector":"vercel"}'::jsonb)
        and (
          landing_url is null
          or (
            landing_url ~ '^https://'
            and position('?' in landing_url) = 0
            and position('#' in landing_url) = 0
            and position('@' in split_part(landing_url, '/', 3)) = 0
          )
        )
      ) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.pandora_tracking_events'::regclass
      and conname='pandora_tracking_events_empty_metadata_v1_check'
  ) then
    alter table public.pandora_tracking_events
      add constraint pandora_tracking_events_empty_metadata_v1_check
      check (metadata = '{}'::jsonb) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.pandora_tracking_costs'::regclass
      and conname='pandora_tracking_costs_empty_metadata_v1_check'
  ) then
    alter table public.pandora_tracking_costs
      add constraint pandora_tracking_costs_empty_metadata_v1_check
      check (metadata = '{}'::jsonb) not valid;
  end if;
end
$$;

comment on constraint pandora_tracking_clicks_minimized_v1_check
  on public.pandora_tracking_clicks is
  'R-005 future-write minimization: no referrer, user agent, linkable hashes, incoming query or platform IDs; configured landing query is not copied to the ledger.';
comment on constraint pandora_tracking_events_empty_metadata_v1_check
  on public.pandora_tracking_events is
  'R-005 future writes reject caller-defined event metadata; FB-017 typed fields remain authoritative.';
comment on constraint pandora_tracking_costs_empty_metadata_v1_check
  on public.pandora_tracking_costs is
  'R-005 future writes reject caller-defined cost metadata.';
