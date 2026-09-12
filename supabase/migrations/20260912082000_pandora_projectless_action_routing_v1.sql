-- Pandora projectless action routing v1
-- Explicit provider targets are actionable without creating a new user Project.

create or replace function public.pandora_chat_universal_dispatch_v6(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_message text := trim(coalesce(p_message,''));
  v_repository text;
  v_routed_message text;
  v_result jsonb;
  v_thread_id uuid;
begin
  if auth.uid() is null then
    raise exception 'pandora_chat_sign_in_required' using errcode='42501';
  end if;
  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  v_repository := substring(v_message from '(?i)github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)');
  if v_repository is null then
    v_repository := substring(v_message from '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)');
  end if;

  if v_repository is not null
     and (
       v_message ~* '\m(audit|inspect|review|check|read|show|open|scan|analy[sz]e|debug|fix|change|update|repair|edit|merge|branch|commit|deploy|publish)\M'
       or v_repository in ('pandora-rvw-314296438-20260820/pandoras-box','pandora-rvw-314296438-20260820/pandoras-box-memory')
       or exists (
         select 1 from public.projectos_projects p
         where p.organization_id=p_organization_id
           and lower(coalesce(p.repository,''))=lower(v_repository)
           and p.status <> 'archived'
       )
     ) then
    v_routed_message := 'GitHub: ' || v_message;
    v_result := public.pandora_chat_universal_dispatch_v5(
      p_organization_id,
      v_routed_message,
      p_thread_id,
      p_project_id
    );

    if coalesce((v_result->>'handled')::boolean,false) then
      v_thread_id := nullif(v_result->>'threadId','')::uuid;
      if v_thread_id is not null then
        with latest_user as (
          select id
          from public.pandora_intelligence_messages
          where thread_id=v_thread_id
            and organization_id=p_organization_id
            and author_role='user'
            and content=v_routed_message
          order by created_at desc,id desc
          limit 1
        )
        update public.pandora_intelligence_messages m
        set content=v_message
        from latest_user l
        where m.id=l.id;
      end if;

      if jsonb_typeof(v_result->'capabilityResult')='object' then
        v_result := jsonb_set(v_result,'{capabilityResult,projectRequired}','false'::jsonb,true);
      end if;
      if v_result #>> '{handoff,required}'='true' then
        v_result := jsonb_set(v_result,'{handoff,request}',to_jsonb(v_message),true);
      end if;
      v_result := jsonb_set(v_result,'{projectRequired}','false'::jsonb,true);
      return v_result;
    end if;
  end if;

  return public.pandora_chat_universal_dispatch_v5(
    p_organization_id,
    p_message,
    p_thread_id,
    p_project_id
  );
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v6(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v6(uuid,text,uuid,uuid) to authenticated;

comment on function public.pandora_chat_universal_dispatch_v6(uuid,text,uuid,uuid)
is 'Universal Chat dispatch that treats explicit existing provider targets such as owner/repo as actionable without creating a new user Project; ProjectOS governance remains mandatory for consequential execution.';
