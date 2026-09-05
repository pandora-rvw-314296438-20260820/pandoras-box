do $migration$
declare
  v_response jsonb;
  v_sql text;
begin
  v_response := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/supabase/migrations/20260902094000_pandora_build_model_cost_guard_v1.sql?ref=e167349bbfb61867a9961c8ea0085b9e82e5d97f',
    null
  );
  if coalesce((v_response->>'status')::int,0) <> 200 then
    raise exception 'Unable to fetch exact Task108 migration source';
  end if;
  v_sql := convert_from(decode(replace(v_response->'body'->>'content', E'\n', ''), 'base64'), 'utf8');
  if position('pandora_source_model_budget_reservations' in v_sql) = 0
     or position('gemini-3.5-flash-lite-usd-2026-09-02' in v_sql) = 0 then
    raise exception 'Exact Task108 migration identity check failed';
  end if;
  v_sql := regexp_replace(v_sql, E'(^|\\n)[[:space:]]*begin;[[:space:]]*(\\n|$)', E'\\1\\2', 'i');
  v_sql := regexp_replace(v_sql, E'(^|\\n)[[:space:]]*commit;[[:space:]]*$', E'\\1', 'i');
  if v_sql ~* E'(^|\\n)[[:space:]]*(begin|commit);' then
    raise exception 'Outer transaction wrapper removal failed';
  end if;
  execute v_sql;
end
$migration$;