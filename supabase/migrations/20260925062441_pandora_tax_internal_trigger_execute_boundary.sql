-- Internal trigger hardening only; no filing, rule-pack, or customer-data changes.
-- PostgreSQL invokes this routine through its existing triggers, not a client RPC.
do $guard$
declare v_oid oid;
begin
 v_oid:=to_regprocedure('public.pandora_tax_guard_rule_support_mutation_v1()');
 if v_oid is null then return; end if;
 if (select prorettype from pg_proc where oid=v_oid)<>'trigger'::regtype then
  raise exception 'Expected tax support guard to remain a trigger routine';
 end if;
 revoke all on function public.pandora_tax_guard_rule_support_mutation_v1() from public,anon,authenticated;
 grant execute on function public.pandora_tax_guard_rule_support_mutation_v1() to service_role;
 if has_function_privilege('anon',v_oid,'execute') or has_function_privilege('authenticated',v_oid,'execute') then
  raise exception 'Tax internal trigger remains directly executable by client roles';
 end if;
end; $guard$;
