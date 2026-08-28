-- pandora-primitive: pandora-booking@1.0.0
-- target: customer-app-runtime-only
DO $$ BEGIN
  IF to_regclass('public.project_specs') IS NOT NULL OR to_regclass('public.projectos_execution_plans') IS NOT NULL OR to_regclass('public.pandora_projects') IS NOT NULL THEN RAISE EXCEPTION 'pandora-booking customer primitive refused on Pandora Control Plane-like schema'; END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.primitive_booking_scope_access (
 scope_id uuid NOT NULL, user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(scope_id,user_id)
);
CREATE TABLE IF NOT EXISTS public.primitive_booking_resources (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), scope_id uuid NOT NULL, name text NOT NULL CHECK(char_length(name)<=200), active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(id,scope_id)
);
CREATE TABLE IF NOT EXISTS public.primitive_booking_slots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), scope_id uuid NOT NULL, resource_id uuid NOT NULL, starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
 capacity integer NOT NULL CHECK(capacity>0), reserved_count integer NOT NULL DEFAULT 0 CHECK(reserved_count>=0 AND reserved_count<=capacity), created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(starts_at<ends_at), FOREIGN KEY(resource_id,scope_id) REFERENCES public.primitive_booking_resources(id,scope_id) ON DELETE CASCADE, UNIQUE(scope_id,resource_id,starts_at,ends_at), UNIQUE(id,scope_id)
);
CREATE TABLE IF NOT EXISTS public.primitive_booking_reservations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), scope_id uuid NOT NULL, slot_id uuid NOT NULL, customer_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 guest jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(guest)='object'), status text NOT NULL CHECK(status IN('confirmed','cancelled')), idempotency_key text NOT NULL CHECK(char_length(idempotency_key)<=200),
 created_at timestamptz NOT NULL DEFAULT now(), cancelled_at timestamptz, FOREIGN KEY(slot_id,scope_id) REFERENCES public.primitive_booking_slots(id,scope_id) ON DELETE RESTRICT, UNIQUE(scope_id,idempotency_key)
);
ALTER TABLE public.primitive_booking_scope_access ENABLE ROW LEVEL SECURITY; ALTER TABLE public.primitive_booking_scope_access FORCE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_booking_resources ENABLE ROW LEVEL SECURITY; ALTER TABLE public.primitive_booking_resources FORCE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_booking_slots ENABLE ROW LEVEL SECURITY; ALTER TABLE public.primitive_booking_slots FORCE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_booking_reservations ENABLE ROW LEVEL SECURITY; ALTER TABLE public.primitive_booking_reservations FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.primitive_booking_scope_access, public.primitive_booking_resources, public.primitive_booking_slots, public.primitive_booking_reservations FROM anon, authenticated;
GRANT SELECT ON public.primitive_booking_scope_access, public.primitive_booking_resources, public.primitive_booking_slots, public.primitive_booking_reservations TO authenticated;
CREATE POLICY primitive_booking_scope_access_own_read ON public.primitive_booking_scope_access FOR SELECT TO authenticated USING(user_id=(SELECT auth.uid()));
CREATE POLICY primitive_booking_resources_read ON public.primitive_booking_resources FOR SELECT TO authenticated USING(EXISTS (SELECT 1 FROM public.primitive_booking_scope_access a WHERE a.scope_id=primitive_booking_resources.scope_id AND a.user_id=(SELECT auth.uid())));
CREATE POLICY primitive_booking_slots_read ON public.primitive_booking_slots FOR SELECT TO authenticated USING(EXISTS (SELECT 1 FROM public.primitive_booking_scope_access a WHERE a.scope_id=primitive_booking_slots.scope_id AND a.user_id=(SELECT auth.uid())));
CREATE POLICY primitive_booking_reservations_own_read ON public.primitive_booking_reservations FOR SELECT TO authenticated USING(customer_user_id=(SELECT auth.uid()));
CREATE OR REPLACE FUNCTION public.primitive_booking_create_reservation(p_scope_id uuid,p_slot_id uuid,p_guest jsonb,p_idempotency_key text)
RETURNS public.primitive_booking_reservations LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $$
DECLARE v_existing public.primitive_booking_reservations; v_slot public.primitive_booking_slots; v_result public.primitive_booking_reservations; v_user uuid;
BEGIN
 v_user:=auth.uid(); IF v_user IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.primitive_booking_scope_access a WHERE a.scope_id=p_scope_id AND a.user_id=v_user) THEN RAISE EXCEPTION 'booking scope access denied'; END IF;
 SELECT * INTO v_existing FROM public.primitive_booking_reservations WHERE scope_id=p_scope_id AND idempotency_key=p_idempotency_key;
 IF FOUND THEN IF v_existing.customer_user_id<>v_user THEN RAISE EXCEPTION 'idempotency ownership mismatch'; END IF; RETURN v_existing; END IF;
 UPDATE public.primitive_booking_slots SET reserved_count=reserved_count+1 WHERE id=p_slot_id AND scope_id=p_scope_id AND reserved_count<capacity AND starts_at>now() RETURNING * INTO v_slot;
 IF NOT FOUND THEN RAISE EXCEPTION 'booking slot unavailable'; END IF;
 INSERT INTO public.primitive_booking_reservations(scope_id,slot_id,customer_user_id,guest,status,idempotency_key) VALUES(p_scope_id,p_slot_id,v_user,COALESCE(p_guest,'{}'::jsonb),'confirmed',p_idempotency_key) RETURNING * INTO v_result;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.primitive_booking_create_reservation(uuid,uuid,jsonb,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.primitive_booking_create_reservation(uuid,uuid,jsonb,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.primitive_booking_cancel_reservation(p_scope_id uuid,p_reservation_id uuid)
RETURNS public.primitive_booking_reservations LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $$
DECLARE v_result public.primitive_booking_reservations; v_user uuid;
BEGIN
 v_user:=auth.uid(); IF v_user IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
 SELECT * INTO v_result FROM public.primitive_booking_reservations WHERE id=p_reservation_id AND scope_id=p_scope_id AND customer_user_id=v_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'reservation not found'; END IF; IF v_result.status='cancelled' THEN RETURN v_result; END IF;
 UPDATE public.primitive_booking_reservations SET status='cancelled',cancelled_at=now() WHERE id=v_result.id RETURNING * INTO v_result;
 UPDATE public.primitive_booking_slots SET reserved_count=reserved_count-1 WHERE id=v_result.id slot_id AND scope_id=p_scope_id AND reserved_count>0;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.primitive_booking_cancel_reservation(uuid,uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.primitive_booking_cancel_reservation(uuid,uuid) TO authenticated;
