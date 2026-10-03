create schema auth;
create schema private;
create role anon;
create role authenticated;
create role service_role bypassrls;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select (auth.jwt()->>'sub')::uuid $$;
create function auth.role() returns text language sql stable as $$ select auth.jwt()->>'role' $$;
grant usage on schema auth,public to anon,authenticated,service_role;
grant execute on all functions in schema auth to anon,authenticated,service_role;
create table auth.users(id uuid primary key);
create table public.organizations(id uuid primary key);
create table public.memberships(organization_id uuid not null,user_id uuid not null,role text not null,status text not null);
grant select on public.memberships to authenticated;
create table public.pandora_intelligence_threads(id uuid primary key default gen_random_uuid(),organization_id uuid not null,project_id uuid,created_by uuid not null,title text,status text not null default 'active',last_message_at timestamptz not null default now(),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.pandora_intelligence_messages(id uuid primary key default gen_random_uuid(),thread_id uuid not null references public.pandora_intelligence_threads(id),organization_id uuid not null,project_id uuid,author_role text not null,content text not null,attachment_manifest jsonb not null default '[]',structured_response jsonb,provider text,model text,request_sha256 text,response_sha256 text,input_tokens bigint not null default 0,output_tokens bigint not null default 0,total_tokens bigint not null default 0,created_at timestamptz not null default now(),trusted_context_sha256 text,trusted_skill_refs jsonb not null default '[]',trusted_knowledge_refs jsonb not null default '[]');
create table public.pandora_model_runs(id uuid primary key default gen_random_uuid());
create table public.pandora_activity_jobs(id uuid primary key default gen_random_uuid(),organization_id uuid not null,requested_by uuid not null,thread_id uuid,project_id uuid,request_id text not null,writer_epoch bigint not null default 1,writer_id text not null default 'pandora-intelligence-chat',last_sequence bigint not null default 0,terminal_state text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '30 days',controls_sealed_at timestamptz,unique(organization_id,requested_by,request_id));
create table public.pandora_activity_controls(id uuid primary key default gen_random_uuid(),job_id uuid not null,organization_id uuid not null,requested_by uuid not null,request_id text not null,control_type text not null,instruction text,status text not null default 'requested');
create function public.pandora_enterprise_chat_authority_v1(p_org uuid,p_entry uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.memberships where organization_id=p_org and user_id=auth.uid() and status='active' and role in('owner','admin')) then raise exception 'ACCESS_REQUIRED';end if;return '{}';end;$$;
create function public.pandora_core_activity_begin_v1(p_org uuid,p_request text,p_thread uuid default null,p_project uuid default null,p_entry uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$declare j uuid;begin
 perform public.pandora_enterprise_chat_authority_v1(p_org,p_entry);
 if not exists(select 1 from public.pandora_intelligence_threads where id=p_thread and organization_id=p_org and created_by=auth.uid() and status='active') then raise exception 'THREAD_NOT_AVAILABLE';end if;
 insert into public.pandora_activity_jobs(organization_id,requested_by,thread_id,project_id,request_id) values(p_org,auth.uid(),p_thread,p_project,p_request) on conflict(organization_id,requested_by,request_id)do update set updated_at=now() returning id into j;
 return jsonb_build_object('jobId',j);end;$$;
create function public.pandora_activity_control_request_v1(p_org uuid,p_job uuid,p_request text,p_type text,p_instruction text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.pandora_activity_jobs where id=p_job and organization_id=p_org and requested_by=auth.uid()) then raise exception 'ACCESS_REQUIRED';end if;
 insert into public.pandora_activity_controls(job_id,organization_id,requested_by,request_id,control_type,instruction) values(p_job,p_org,auth.uid(),p_request,p_type,p_instruction);return '{}';end;$$;
-- Synthetic deterministic capability uses the same legacy persistence contract:
-- user insert without RETURNING, then assistant insert and a structured result.
create function public.pandora_chat_universal_dispatch_v9(p_org uuid,p_message text,p_thread uuid default null,p_project uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_message='unhandled' then return jsonb_build_object('handled',false);end if;
 insert into public.pandora_intelligence_messages(thread_id,organization_id,author_role,content)values(p_thread,p_org,'user',p_message);
 insert into public.pandora_intelligence_messages(thread_id,organization_id,author_role,content,structured_response,provider,model)values(p_thread,p_org,'assistant','Fixture result','{"verified":true}','fixture','deterministic-fixture');
 return jsonb_build_object('handled',true,'threadId',p_thread,'reply','Fixture result','providerReadback',jsonb_build_object('verified',true));end;$$;
revoke all on all tables in schema public from anon,authenticated;
grant select on public.memberships to authenticated;
grant all on all tables in schema public to service_role;
