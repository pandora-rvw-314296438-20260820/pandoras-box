-- Align active canonical release functions with the authoritative production origin.
-- Secondary aliases remain valid network aliases; release authority binds mcpmaster.vercel.app.

do $migration$
declare
  v_reg regprocedure;
  v_definition text;
  v_function_name text;
  v_legacy_origin constant text := 'pandoras-box-system.vercel.app';
  v_canonical_origin constant text := 'mcpmaster.vercel.app';
begin
  foreach v_function_name in array array[
    'public.capture_canonical_physical_android_receipt(uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text[],uuid,uuid,text,uuid,uuid,text,text,text,text)',
    'public.capture_canonical_vercel_rehearsal_receipt(uuid,text,text,text,text,text,text)',
    'public.get_canonical_release_status_without_final_attestations(uuid,text,text)'
  ]
  loop
    v_reg := to_regprocedure(v_function_name);
    if v_reg is null then
      raise notice '% is absent in this replay state; skipping production-origin alignment', v_function_name;
      continue;
    end if;

    select pg_get_functiondef(v_reg::oid) into v_definition;

    if position(v_legacy_origin in v_definition) > 0 then
      v_definition := replace(v_definition, v_legacy_origin, v_canonical_origin);
      execute v_definition;
    end if;

    select pg_get_functiondef(to_regprocedure(v_function_name)::oid) into v_definition;

    if position(v_legacy_origin in v_definition) > 0 then
      raise exception 'legacy production origin remains in %', v_function_name;
    end if;
    if position(v_canonical_origin in v_definition) = 0 then
      raise exception 'canonical production origin missing from %', v_function_name;
    end if;
  end loop;
end
$migration$;
