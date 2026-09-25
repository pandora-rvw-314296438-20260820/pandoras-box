\set ON_ERROR_STOP on
DO $$ BEGIN
 IF has_function_privilege('anon','public.pandora_tax_guard_rule_support_mutation_v1()','execute')
 OR has_function_privilege('authenticated','public.pandora_tax_guard_rule_support_mutation_v1()','execute') THEN
  RAISE EXCEPTION 'Trigger routine directly exposed';
 END IF;
END; $$;
SET ROLE authenticated;
INSERT INTO public.tax_rule_sources VALUES(1,'90000000-0000-4000-8000-000000000001');
UPDATE public.tax_rule_sources SET id=3 WHERE id=1;
DELETE FROM public.tax_rule_sources WHERE id=3;
DO $test$
DECLARE q text; blocked boolean; passed integer:=0;
BEGIN
 FOREACH q IN ARRAY ARRAY[
  'insert into public.tax_rule_sources values(4,''90000000-0000-4000-8000-000000000002'')',
  'update public.tax_rule_sources set id=5 where id=2',
  'delete from public.tax_rule_sources where id=2'
 ] LOOP
  blocked:=false;
  BEGIN EXECUTE q; EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM<>'pandora_tax_rule_support_immutable' THEN RAISE; END IF;
   blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Approved evidence was mutable'; END IF;
  passed:=passed+1;
 END LOOP;
 RAISE NOTICE 'PASS: % approved-rule evidence mutations rejected by actual trigger after direct execute revocation',passed;
END; $test$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.tax_rule_sources WHERE id=2) THEN RAISE EXCEPTION 'Protected fixture evidence changed'; END IF;
END; $$;
SELECT 'PASS: direct execute revoked, normal trigger operation retained, reviewed evidence immutable' AS result;
