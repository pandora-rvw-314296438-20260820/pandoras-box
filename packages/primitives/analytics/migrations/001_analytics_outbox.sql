-- pandora-primitive: pandora-analytics@1.0.0
-- target: customer-app-runtime-only
DO $$ BEGIN
  IF to_regclass('public.project_specs') IS NOT NULL OR to_regclass('public.projectos_execution_plans') IS NOT NULL OR to_regclass('public.pandora_projects') IS NOT NULL THEN
    RAISE EXCEPTION 'pandora-analytics customer primitive refused on Pandora Control Plane-like schema';
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.primitive_analytics_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope_id uuid NOT NULL,
  event_name text NOT NULL CHECK (event_name ~ '^business\.[a-z][a-z0-9_.-]+$'),
  project_version_id text NOT NULL,
  environment text NOT NULL CHECK (environment IN ('development','test','preview','production')),
  aggregate_type text,
  aggregate_id text,
  actor_pseudonym text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload)='object'),
  idempotency_key text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed')),
  occurred_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(scope_id,idempotency_key)
);
ALTER TABLE public.primitive_analytics_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_analytics_outbox FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.primitive_analytics_outbox FROM anon, authenticated;
-- Analytics capture/outbox mutation remains server-only; client analytics credentials are never required.
