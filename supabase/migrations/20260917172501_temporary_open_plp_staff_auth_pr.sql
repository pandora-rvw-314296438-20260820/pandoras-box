create or replace function private.open_plp_staff_auth_pr_20260918()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare
  v_token text; v_response extensions.http_response; v_body jsonb;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='Github_supabase' limit 1;
  if v_token is null then return jsonb_build_object('ok',false,'stage','credential'); end if;
  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/pulls'::varchar,
    array[
      extensions.http_header('Accept','application/vnd.github+json'),
      extensions.http_header('Authorization','Bearer '||v_token),
      extensions.http_header('X-GitHub-Api-Version','2022-11-28'),
      extensions.http_header('Content-Type','application/json'),
      extensions.http_header('User-Agent','Pandora-PLP-StaffAuth/1.0')
    ]::extensions.http_header[],
    'application/json'::varchar,
    jsonb_build_object(
      'title','feat(plp): replace shared staff code with role-based auth',
      'head','feature/plp-staff-auth-20260917',
      'base','main',
      'body','Replaces legacy shared staff-code authentication with Supabase Auth sessions, HttpOnly/Secure/SameSite=Strict cookie handling, and server-side PLP roles. Exact head a4ce39b98ab56beded0e4d100c1a7522ab74d8cf. Local gates: 101/101 tests pass; production build passes; legacy staff-code identifiers are absent from api/ and public/. Production remains untouched pending CI and authenticated preview acceptance.'
    )::text::varchar
  )::extensions.http_request);
  v_token:=null;
  begin v_body:=coalesce(nullif(v_response.content,'')::jsonb,'{}'::jsonb); exception when others then v_body:='{}'::jsonb; end;
  return jsonb_build_object('ok',v_response.status in (201,422),'status',v_response.status,'number',v_body->>'number','htmlUrl',v_body->>'html_url','headSha',v_body#>>'{head,sha}','baseSha',v_body#>>'{base,sha}','message',coalesce(v_body->>'message',''));
end $fn$;
revoke all on function private.open_plp_staff_auth_pr_20260918() from public,anon,authenticated;
