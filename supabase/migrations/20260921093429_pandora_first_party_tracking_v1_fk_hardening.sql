alter table public.pandora_tracking_events
  drop constraint if exists pandora_tracking_events_click_fk;

alter table public.pandora_tracking_events
  add constraint pandora_tracking_events_click_fk
  foreign key (tenant_id, click_id)
  references public.pandora_tracking_clicks(tenant_id, click_id)
  on delete restrict;

update public.pandora_tracking_releases
set notes = coalesce(notes,'') || ' Attribution click FK hardened to RESTRICT deletion so conversion lineage cannot be orphaned.',
    deployed_at = now()
where version = '1.0.0-provider';
