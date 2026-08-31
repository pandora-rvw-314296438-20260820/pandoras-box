-- Align the active Vercel connector account identity after project/team transfer.
-- Configuration was already rebound; this removes the stale external account id
-- while preserving the installation row and audit lineage.

do $align$
declare
  changed integer;
begin
  update public.connector_installations
     set external_account_id = 'vercel-team:team_3yw1CN59ce4pj5SwyQGCAqN3',
         updated_at = now()
   where provider = 'vercel'
     and status = 'active'
     and external_account_id = 'vercel-team:team_IcdJUnzLi5wUN1GD8ALHyjF7'
     and configuration->>'team_id' = 'team_3yw1CN59ce4pj5SwyQGCAqN3'
     and configuration->>'team_slug' = 'mbanatao';

  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'expected exactly one transferred active Vercel connector, changed %', changed
      using errcode = '55000';
  end if;

  if exists (
    select 1 from public.connector_installations
     where provider = 'vercel'
       and status = 'active'
       and (
         external_account_id <> 'vercel-team:team_3yw1CN59ce4pj5SwyQGCAqN3'
         or configuration->>'team_id' <> 'team_3yw1CN59ce4pj5SwyQGCAqN3'
         or configuration->>'team_slug' <> 'mbanatao'
       )
  ) then
    raise exception 'active Vercel connector identity remains inconsistent after transfer'
      using errcode = '55000';
  end if;
end;
$align$;
