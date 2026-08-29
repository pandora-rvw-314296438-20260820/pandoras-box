-- pandora-primitive: pandora-audit@1.0.0
-- target: customer-app-runtime-only
DO $$ BEGIN
  IF to_regclass('public.project_specs') IS NOT NULL OR to_regclass('public.projectos_execution_plans') IS NOT NULL OR to_regclass('public.pandora_projects') IS NOT NULL THEN
    RAISE EXCEPTION 'pandora-audit customer primitive refused on Pandora Control Plane-like schema';
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.primitive_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  event_name text NOT NULL CHECK (event_name ~ '^[a-z][a-z0-9_.-]{2,127}$'), resource_type text NOT NULL,
  resource_id text NOT NULL, mutation_id text NOT NULL, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  change_digest text, occurred_at timestamptz NOT NULL DEFAULT now(), UNIQUE (tenant_id, mutation_id)
);
CREATE INDEX IF NOT EXISTS primitive_audit_log_tenant_occurred_idx ON public.primitive_audit_log(tenant_id, occurred_at DESC);
ALTER TABLE public.primitive_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_audit_log FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.primitive_audit_log FROM anon, authenticated;
GRANT SELECT ON public.primitive_audit_log TO authenticated;
DROP POLICY IF EXISTS primitive_audit_member_read ON public.primitive_audit_log;
CREATE POLICY primitive_audit_member_read ON public.primitive_audit_log FOR SELECT TO authenticated
USING (public.primitive_has_permission(tenant_id, 'audit.read'));
-- Writes intentionally remain service-only. Customer applications never expose direct authenticated INSERT/UPDATE/DELETE grants.
