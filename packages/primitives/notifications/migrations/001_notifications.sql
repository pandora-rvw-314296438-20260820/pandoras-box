-- pandora-primitive: pandora-notifications@1.0.0
-- target: customer-app-runtime-only
DO $$ BEGIN
  IF to_regclass('public.project_specs') IS NOT NULL OR to_regclass('public.projectos_execution_plans') IS NOT NULL OR to_regclass('public.pandora_projects') IS NOT NULL THEN
    RAISE EXCEPTION 'pandora-notifications customer primitive refused on Pandora Control Plane-like schema';
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.primitive_notification_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope_id uuid NOT NULL,
  idempotency_key text NOT NULL CHECK (char_length(idempotency_key) BETWEEN 1 AND 200),
  channel text NOT NULL CHECK (channel IN ('email','sms','in_app')),
  template_key text NOT NULL CHECK (template_key ~ '^[a-z][a-z0-9_.-]{0,127}$'),
  recipient_digest text NOT NULL CHECK (recipient_digest ~ '^sha256:[a-f0-9]{64}$'),
  status text NOT NULL CHECK (status IN ('claimed','sent','failed')),
  provider_delivery_id text,
  error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(scope_id,idempotency_key)
);
ALTER TABLE public.primitive_notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.primitive_notification_deliveries FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.primitive_notification_deliveries FROM anon, authenticated;
-- Delivery claims and provider receipts are server-only. No client grants are installed.
