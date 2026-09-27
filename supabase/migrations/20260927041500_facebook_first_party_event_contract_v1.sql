-- FB-017: extend the existing first-party tracking event ledger.
-- Existing rows receive fail-safe defaults; no competing ledger is created.

alter table public.pandora_tracking_events
  add column if not exists schema_version smallint not null default 1,
  add column if not exists consent jsonb not null default '{"analytics":false,"marketing":false}'::jsonb,
  add column if not exists is_test boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.pandora_tracking_events'::regclass
      and conname='pandora_tracking_events_schema_version_check'
  ) then
    alter table public.pandora_tracking_events
      add constraint pandora_tracking_events_schema_version_check
      check (schema_version = 1);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.pandora_tracking_events'::regclass
      and conname='pandora_tracking_events_consent_check'
  ) then
    alter table public.pandora_tracking_events
      add constraint pandora_tracking_events_consent_check
      check (
        jsonb_typeof(consent)='object'
        and jsonb_typeof(consent->'analytics')='boolean'
        and jsonb_typeof(consent->'marketing')='boolean'
        and consent - array['analytics','marketing']::text[] = '{}'::jsonb
      );
  end if;
end
$$;

comment on column public.pandora_tracking_events.schema_version is
  'FB-017 first-party event contract version. Version 1 is the only accepted version.';
comment on column public.pandora_tracking_events.consent is
  'Closed-schema analytics/marketing consent flags. Missing input defaults false/false.';
comment on column public.pandora_tracking_events.is_test is
  'Explicit test marker so test events remain distinguishable from production measurement.';
