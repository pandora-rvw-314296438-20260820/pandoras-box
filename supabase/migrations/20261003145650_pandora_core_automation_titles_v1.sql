-- Display existing Operations task titles and scope in Pandora Core Automations.
-- Read-only projection: no execution state, history, authority or catalog changes.
begin;

do $patch$
declare v_definition text;v_body_sha text;v_old text;v_new text;
begin
 select pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
 into v_definition,v_body_sha from pg_proc p
 where p.oid='public.pandora_core_snapshot_v1(text,uuid)'::regprocedure;
 if v_body_sha is distinct from '54d09f1103c1471ffe5fb963e10916f119b1cde44330917c52811d7264d6d238' then
  raise exception 'CORE_AUTOMATION_SOURCE_DRIFT';
 end if;
 v_old:=$old$   'automations',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select t.organization_id,t.task_key name,t.status state,t.attempts,t.queued_at,t.head_sha
    from private.pandora_ops_tasks t where (p_organization_id is null or t.organization_id=p_organization_id) and private.pandora_core_role_v1(t.organization_id) is not null order by t.queued_at desc limit 30
   ) q),'[]'::jsonb),$old$;
 v_new:=$new$   'automations',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select t.organization_id,t.project_id,t.task_key,
     case when jsonb_typeof(t.spec->'title')='string' and nullif(btrim(t.spec->>'title'),'') is not null
      then left(btrim(t.spec->>'title'),200) else null end name,
     case when jsonb_typeof(t.spec->'title')='string' and nullif(btrim(t.spec->>'title'),'') is not null
      then 'recorded' else 'missing' end title_state,
     case when t.organization_id=v_platform then 'Pandora' else o.name end client_name,
     t.status state,t.attempts,t.queued_at,t.head_sha
    from private.pandora_ops_tasks t join public.organizations o on o.id=t.organization_id
    where (p_organization_id is null or t.organization_id=p_organization_id) and private.pandora_core_role_v1(t.organization_id) is not null order by t.queued_at desc limit 30
   ) q),'[]'::jsonb),$new$;
 if strpos(v_definition,v_old)=0 or (length(v_definition)-length(replace(v_definition,v_old,'')))/length(v_old)<>1 then
  raise exception 'CORE_AUTOMATION_PATCH_NOT_FOUND';
 end if;
 execute replace(v_definition,v_old,v_new);
end;
$patch$;

-- CREATE OR REPLACE preserves the existing function owner, ACL and search path.
commit;
