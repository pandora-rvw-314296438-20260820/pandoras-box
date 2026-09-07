begin;

create or replace function private.pandora_static_preview_acceptance_v4(
  p_runtime_body text,
  p_project_name text,
  p_business_summary text,
  p_acceptance_scope jsonb
)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_body text:=coalesce(p_runtime_body,'');
  v_body_lower text:=lower(coalesce(p_runtime_body,''));
  v_body_words text;
  v_identity text;
  v_title text;
  v_h1 text;
  v_title_text text;
  v_h1_text text;
  v_generic boolean:=false;
  v_token text;
  v_token_count integer:=0;
  v_link text;
  v_fn text;
begin
  if length(v_body)<128
     or position('<html' in v_body_lower)=0
     or position('<body' in v_body_lower)=0
     or jsonb_typeof(p_acceptance_scope->'functional')<>'array'
     or jsonb_array_length(p_acceptance_scope->'functional')=0 then
    return false;
  end if;

  if v_body_lower ~ '(404[[:space:]]+not[[:space:]]+found|application[[:space:]]+error|internal[[:space:]]+server[[:space:]]+error|service[[:space:]]+unavailable)' then
    return false;
  end if;

  v_body_words:=' '||regexp_replace(v_body_lower,'[^a-z0-9-]+',' ','g')||' ';
  v_identity:=lower(trim(regexp_replace(
    coalesce(p_project_name,''),
    '[[:space:]]+(landing[[:space:]]+page|landing|website|web[[:space:]]*site|site|page|app|application|project|guide)[[:space:]]*$',
    '',
    'i'
  )));

  v_generic :=
    length(v_identity)<3
    or v_identity in (
      'decoration','decor','design','redesign','ui','ux','frontend','front end',
      'homepage','home page','website','site','page','landing','landing page',
      'app','application','project','guide','fix','repair','update','improvement','enhancement'
    );

  if not v_generic and position(v_identity in v_body_lower)=0 then
    for v_token in
      select distinct m[1]
      from regexp_matches(
        lower(coalesce(p_project_name,'')),
        '([a-z0-9][a-z0-9-]{2,})',
        'g'
      ) m
      where m[1] not in (
        'landing','page','homepage','website','web','site','app','application',
        'project','guide','design','redesign','frontend','update','improvement',
        'enhancement','showcase'
      )
    loop
      v_token_count:=v_token_count+1;
      if position(' '||v_token||' ' in v_body_words)=0 then
        return false;
      end if;
    end loop;
    if v_token_count=0 then
      v_generic:=true;
    end if;
  end if;

  if v_generic then
    v_title:=substring(v_body from '(?is)<title[^>]*>(.*?)</title>');
    v_h1:=substring(v_body from '(?is)<h1[^>]*>(.*?)</h1>');
    v_title_text:=trim(regexp_replace(coalesce(v_title,''),'<[^>]+>',' ','g'));
    v_h1_text:=trim(regexp_replace(coalesce(v_h1,''),'<[^>]+>',' ','g'));
    if length(regexp_replace(v_title_text,'[[:space:]]+','','g'))<3
       and length(regexp_replace(v_h1_text,'[[:space:]]+','','g'))<3 then
      return false;
    end if;
  end if;

  for v_link in
    select distinct m[1]
    from regexp_matches(v_body,'href=["'']#([^"'']+)["'']','g') m
  loop
    if nullif(v_link,'') is not null
       and position('id="'||v_link||'"' in v_body)=0
       and position('id='''||v_link||'''' in v_body)=0 then
      return false;
    end if;
  end loop;

  for v_fn in
    select distinct m[1]
    from regexp_matches(v_body,'onclick=["''][[:space:]]*([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*\(','g') m
  loop
    if lower(v_fn) in ('window','document','location','history','console','alert','confirm','prompt','settimeout','setinterval') then
      continue;
    end if;
    if position('function '||lower(v_fn)||'(' in v_body_lower)=0
       and position('function '||lower(v_fn)||' (' in v_body_lower)=0
       and position('const '||lower(v_fn)||'=' in replace(v_body_lower,' ',''))=0
       and position('let '||lower(v_fn)||'=' in replace(v_body_lower,' ',''))=0
       and position('var '||lower(v_fn)||'=' in replace(v_body_lower,' ',''))=0 then
      return false;
    end if;
  end loop;

  return true;
end
$function$;

do $migration$
declare
  v_scope jsonb:=jsonb_build_object('functional',jsonb_build_array('renders'));
  v_good text:='<!DOCTYPE html><html><head><title>The Majestic Chow Chow | Comprehensive Breed Guide & Showcase</title></head><body><h1>The Majestic Chow Chow</h1><p>Chow Chow breed history, temperament, grooming, exercise, and care guidance for owners.</p></body></html>';
  v_wrong text:='<!DOCTYPE html><html><head><title>Golden Retriever Guide</title></head><body><h1>Golden Retriever</h1><p>Friendly family dog care and grooming guidance with enough substantive content for this fixture.</p></body></html>';
begin
  if not private.pandora_static_preview_acceptance_v4(
    v_good,
    'Chow Chow Breed Guide',
    'Create a dedicated information and showcase page for Chow Chow dogs.',
    v_scope
  ) then
    raise exception 'ACCEPTANCE_V4_GUIDE_IDENTITY_FALSE_NEGATIVE' using errcode='23514';
  end if;

  if private.pandora_static_preview_acceptance_v4(
    v_wrong,
    'Chow Chow Breed Guide',
    'Create a dedicated information and showcase page for Chow Chow dogs.',
    v_scope
  ) then
    raise exception 'ACCEPTANCE_V4_GUIDE_IDENTITY_FALSE_POSITIVE' using errcode='23514';
  end if;
end
$migration$;

comment on function private.pandora_static_preview_acceptance_v4(text,text,text,jsonb) is
'Observable static-page acceptance v4. Exact project identity is preferred; when display phrasing differs, all substantive project-name tokens must remain visible while generic guide/page terms are ignored. Structure, internal links, and click handlers remain fail-closed.';

commit;
