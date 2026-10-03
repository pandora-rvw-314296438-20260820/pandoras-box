begin;

-- Add native conversation roles and opt-in provider streaming. Legacy parts
-- tickets remain valid during the compatible server/client rollout.
create or replace function public.pandora_issue_bedrock_chat_ticket_v1(
  p_model text,
  p_body jsonb
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions','pg_temp'
as $$
declare
  v_role text;
  v_target text;
  v_provider text;
  v_token text;
  v_token_sha text;
  v_expires_at timestamptz;
  v_max_tokens integer;
  v_messages boolean;
  v_images boolean;
  v_stream boolean;
  v_item jsonb;
  v_part jsonb;
  v_previous_role text;
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in('postgres','service_role','supabase_admin') and v_role<>'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  if coalesce(p_model,'')!~'^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$'
     or p_body is null or coalesce(jsonb_typeof(p_body),'')<>'object' then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end if;
  v_messages:=p_body?'messages';
  if v_messages=(p_body?'parts') or exists(select 1 from jsonb_object_keys(p_body) k
    where k not in('system','parts','messages','maxTokens','stream'))
    or (p_body?'system' and coalesce(jsonb_typeof(p_body->'system'),'')<>'string')
    or (p_body?'stream' and coalesce(jsonb_typeof(p_body->'stream'),'')<>'boolean') then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end if;
  v_stream:=coalesce((p_body->>'stream')::boolean,false);
  v_images:=false;
  if v_messages then
    if coalesce(jsonb_typeof(p_body->'messages'),'')<>'array' or jsonb_array_length(p_body->'messages') not between 1 and 64 then
      raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
    end if;
    for v_item in select value from jsonb_array_elements(p_body->'messages') loop
      if coalesce(jsonb_typeof(v_item),'')<>'object' or coalesce(v_item->>'role','') not in('user','assistant')
        or (v_previous_role is null and v_item->>'role'<>'user') or v_previous_role=v_item->>'role'
        or coalesce(jsonb_typeof(v_item->'content'),'')<>'array' or jsonb_array_length(v_item->'content') not between 1 and 64
        or exists(select 1 from jsonb_object_keys(v_item) k where k not in('role','content')) then
        raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
      end if;
      v_previous_role:=v_item->>'role';
      for v_part in select value from jsonb_array_elements(v_item->'content') loop
        if coalesce(jsonb_typeof(v_part),'')<>'object' or (v_part?'text')=(v_part?'image')
          or exists(select 1 from jsonb_object_keys(v_part) k where k not in('text','image')) then
          raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
        end if;
        if v_part?'text' then
          if coalesce(jsonb_typeof(v_part->'text'),'')<>'string' or length(trim(v_part->>'text'))=0 then
            raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
          end if;
        else
          v_images:=true;
          if v_previous_role<>'user' or coalesce(v_part->'image'->>'format','') not in('png','jpeg','webp')
            or coalesce(v_part->'image'->'source'->>'bytes','')!~'^[A-Za-z0-9+/=]+$' then
            raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
          end if;
        end if;
      end loop;
    end loop;
    if v_previous_role<>'user' then raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023'; end if;
  else
    if coalesce(jsonb_typeof(p_body->'parts'),'')<>'array' or jsonb_array_length(p_body->'parts') not between 1 and 64 then
      raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
    end if;
    select exists(select 1 from jsonb_array_elements(p_body->'parts') p where p->>'type'='image') into v_images;
  end if;
  begin
    v_max_tokens:=coalesce(nullif(p_body->>'maxTokens','')::integer,4096);
  exception when others then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end;
  if v_max_tokens not between 1 and 8192 or octet_length(p_body::text)>1048576 then
    raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';
  end if;

  select c.invocation_target,c.provider_name
  into v_target,v_provider
  from private.pandora_bedrock_reasoning_catalog c
  where c.model_id=p_model
    and c.routable=true
    and c.conversational=true
    and c.present_in_latest_sync=true
    and c.runtime_verification_status='passed'
    and c.lifecycle_status='ACTIVE'
    and nullif(c.invocation_target,'') is not null
    and (not v_images or 'IMAGE'=any(c.input_modalities))
    and (not v_stream or c.response_streaming_supported=true)
  limit 1;
  if v_target is null then
    raise exception 'BEDROCK_CHAT_MODEL_UNAVAILABLE' using errcode='55000';
  end if;

  delete from private.pandora_bedrock_chat_tickets
  where expires_at<=clock_timestamp();

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_token_sha:=encode(extensions.digest(v_token,'sha256'),'hex');
  v_expires_at:=clock_timestamp()+interval '2 minutes';

  insert into private.pandora_bedrock_chat_tickets(
    token_sha256,model_id,invocation_target,provider_name,request_body,expires_at
  ) values(
    v_token_sha,p_model,v_target,v_provider,
    p_body||jsonb_build_object('maxTokens',v_max_tokens),v_expires_at
  );

  return jsonb_build_object('ticket',v_token,'expiresAt',v_expires_at);
end;
$$;

revoke all on function public.pandora_issue_bedrock_chat_ticket_v1(text,jsonb)
from public,anon,authenticated;
grant execute on function public.pandora_issue_bedrock_chat_ticket_v1(text,jsonb)
to service_role;

comment on function public.pandora_issue_bedrock_chat_ticket_v1(text,jsonb)
is 'Service-role-only one-time Bedrock chat ticket issuer. The issuing RPC commits before the caller sends the opaque ticket to the Vercel OIDC signer.';

-- Preserve streamMode for older Edge versions. New clients negotiate streaming
-- explicitly and only for catalog models reporting the real capability.
create or replace function public.pandora_bedrock_chat_routing_config_v1()
returns jsonb language plpgsql security definer set search_path='' as $$
declare models jsonb; images jsonb; streams jsonb; selected text;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
 select coalesce(jsonb_agg(c.model_id order by c.provider_name,c.model_name,c.model_id),'[]'),
   coalesce(jsonb_agg(c.model_id order by c.provider_name,c.model_name,c.model_id) filter(where 'IMAGE'=any(c.input_modalities)),'[]'),
   coalesce(jsonb_agg(c.model_id order by c.provider_name,c.model_name,c.model_id) filter(where c.response_streaming_supported=true),'[]'),
   (array_agg(c.model_id order by c.provider_name,c.model_name,c.model_id))[1]
 into models,images,streams,selected from private.pandora_bedrock_reasoning_catalog c
 where c.routable and c.conversational and c.present_in_latest_sync and c.runtime_verification_status='passed'
   and c.lifecycle_status='ACTIVE' and nullif(c.invocation_target,'') is not null;
 return jsonb_build_object('enabled',selected is not null,'routingEligible',selected is not null,'fallbackEnabled',true,
   'model',selected,'allowedModels',models,'imageModels',images,'streamingModels',streams,'nativeMessages',true,
   'policyVersion','bedrock-live-catalog-chat-v2','streamMode','buffered_v1');
end; $$;
revoke all on function public.pandora_bedrock_chat_routing_config_v1() from public,anon,authenticated;
grant execute on function public.pandora_bedrock_chat_routing_config_v1() to service_role;
commit;
