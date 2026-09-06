-- Align active canonical release verification with the current GitHub owner.
-- Historical recovery migrations remain immutable; this is a forward-only operational identity repair.

do $migration$
declare
  v_reg regprocedure;
  v_definition text;
  v_old_owner constant text := '''banataosystems''';
  v_current_owner constant text := '''pandora-rvw-314296438-20260820''';
  v_function_name text;
begin
  foreach v_function_name in array array[
    'public.get_canonical_release_status_without_final_attestations(uuid,text,text)',
    'public.capture_canonical_vercel_rehearsal_receipt(uuid,text,text,text,text,text,text)'
  ]
  loop
    v_reg := to_regprocedure(v_function_name);
    if v_reg is null then
      raise notice '% is absent in this replay state; skipping identity alignment', v_function_name;
      continue;
    end if;

    select pg_get_functiondef(v_reg::oid) into v_definition;

    if position(v_old_owner in v_definition) > 0 then
      v_definition := replace(v_definition, v_old_owner, v_current_owner);
      execute v_definition;
    end if;

    select pg_get_functiondef(to_regprocedure(v_function_name)::oid) into v_definition;

    if position(v_old_owner in v_definition) > 0 then
      raise exception 'legacy GitHub owner remains in %', v_function_name;
    end if;
    if position(v_current_owner in v_definition) = 0 then
      raise exception 'current GitHub owner missing from %', v_function_name;
    end if;
  end loop;
end
$migration$;
