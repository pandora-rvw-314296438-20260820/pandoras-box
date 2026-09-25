\set ON_ERROR_STOP on
-- Simulate a tenant-controlled project row using a mixed-case canonical repo.
INSERT INTO public.pandora_projects VALUES
 ('30000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','lookalike','Pandora-Rvw-314296438-20260820/Pandoras-Box','active'),
 ('30000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000003','customer','Customer/Allowed-Repo','active');
DO $test$
DECLARE denied boolean;
BEGIN
 PERFORM set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
 PERFORM private.pandora_require_provider_resource_v1('10000000-0000-4000-8000-000000000001','github',' PANDORA-RVW-314296438-20260820/PANDORAS-BOX ',false);
 PERFORM set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
 denied:=false;
 BEGIN
  PERFORM private.pandora_require_provider_resource_v1('10000000-0000-4000-8000-000000000003','github','Pandora-Rvw-314296438-20260820/Pandoras-Box',false);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Case variant bypassed canonical resource exclusion'; END IF;
 PERFORM private.pandora_require_provider_resource_v1('10000000-0000-4000-8000-000000000003','github',' customer/allowed-repo ',false);
 IF position('private.pandora_is_active_org_admin_v1(p_organization_id)' in pg_get_functiondef('public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid)'::regprocedure))=0 THEN RAISE EXCEPTION 'Late dispatcher lost membership guard'; END IF;
 IF position('private.pandora_require_provider_resource_v1' in pg_get_functiondef('public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid)'::regprocedure))=0 THEN RAISE EXCEPTION 'Late dispatcher lost tenant guard'; END IF;
END; $test$;
SET ROLE authenticated;
DO $test$
DECLARE denied boolean:=false;
BEGIN
 PERFORM set_config('request.jwt.claims','{"sub":"20000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
 BEGIN
  PERFORM public.pandora_chat_capability_dispatch_native_v1('10000000-0000-4000-8000-000000000001','check github',NULL,NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Replayed native dispatcher admitted a nonmember'; END IF;
END; $test$;
RESET ROLE;
SELECT 'PASS: canonical case normalization, approved customer fallback, late native dispatcher reassertion' AS result;
