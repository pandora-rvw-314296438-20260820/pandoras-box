begin;
-- Keep verified connection data and routing evidence in the structured receipt.
-- Ordinary capability questions use Pandora's conversational voice.
do $migration$
declare definition text; old_copy text := 'I checked Pandora''''s live capability registry. The connection state below is runtime evidence, not a model assumption.';
begin
 select pg_get_functiondef('public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid)'::regprocedure) into definition;
 if position(old_copy in definition)=0 then raise exception 'PANDORA_CAPABILITY_COPY_SOURCE_DRIFT'; end if;
 definition:=replace(definition,old_copy,'I can help with research, writing, planning, files, and connected work. Here is what is available right now.');
 execute definition;
end;
$migration$;
commit;
