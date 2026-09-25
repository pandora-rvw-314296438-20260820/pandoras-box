-- Runs only after the disposable fixture and exact committed migrations.
\set ON_ERROR_STOP on
SET ROLE authenticated;
DO $test$
DECLARE c record; denied boolean; result jsonb; passed integer:=0;
BEGIN
 FOR c IN SELECT * FROM (VALUES
  ('nonmember','20000000-0000-4000-8000-000000000099','10000000-0000-4000-8000-000000000001'),
  ('wrong-tenant-owner','20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003'),
  ('other-org-id','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002'),
  ('revoked','20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001'),
  ('staff','20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000001'),
  ('invited','20000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000001'),
  ('suspended','20000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000001'),
  ('missing-subject',NULL,'10000000-0000-4000-8000-000000000001'),
  ('missing-org','20000000-0000-4000-8000-000000000001',NULL)
 ) x(label,uid,org)
 LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',c.uid,'role','authenticated')::text,false);
  denied:=false;
  BEGIN
   PERFORM public.pandora_enterprise_direct_github_v1(c.org::uuid,'GET','/repos/pandora-rvw-314296438-20260820/plp',NULL);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Expected denial: %',c.label; END IF;
  passed:=passed+1;
 END LOOP;
 RAISE NOTICE 'Negative authorization cases passed: %',passed;
END; $test$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM private.audit_provider_calls) THEN RAISE EXCEPTION 'Denied call reached provider'; END IF;
END; $$;
SET ROLE authenticated;
DO $test$
DECLARE c record; result jsonb;
BEGIN
 FOR c IN SELECT * FROM (VALUES
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002'),
  ('20000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000001')
 ) x(uid,org)
 LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',c.uid,'role','authenticated')::text,false);
  result:=public.pandora_enterprise_direct_github_v1(c.org::uuid,'GET','/repos/pandora-rvw-314296438-20260820/plp',NULL);
  IF result->>'status'<>'200' THEN RAISE EXCEPTION 'Valid owner/admin denied'; END IF;
 END LOOP;
END; $test$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM private.audit_provider_calls)<>3 THEN RAISE EXCEPTION 'Unexpected provider call count'; END IF;
 IF has_function_privilege('anon','public.pandora_enterprise_direct_github_v1(uuid,text,text,jsonb)','execute') THEN RAISE EXCEPTION 'Anonymous RPC execute granted'; END IF;
 IF has_table_privilege('authenticated','private.pandora_provider_resource_grants','select') THEN RAISE EXCEPTION 'Private grants exposed'; END IF;
 IF has_function_privilege('authenticated','private.pandora_is_active_org_admin_v1(uuid)','execute') THEN RAISE EXCEPTION 'Internal predicate exposed'; END IF;
END; $$;
SELECT 'PASS: 9 denial cases, 3 authorized cases, zero unauthorized provider calls, private grant boundary' AS result;
