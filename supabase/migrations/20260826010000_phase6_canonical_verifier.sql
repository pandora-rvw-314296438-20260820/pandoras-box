-- Phase 6 Recovery Migration: Commit Canonical Verifier Literals
-- This migration commits canonical verifier literals for overall recovery completion.

CREATE TABLE IF NOT EXISTS public.phase6_canonical_verifiers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  verifier_name TEXT NOT NULL,
  verifier_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'committed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.phase6_canonical_verifiers (verifier_name, verifier_hash)
VALUES ('canonical_recovery_verifier', '4eb3f86e3f0eaee913db2d5ffcff8fbfac1ee6986e7efecfa2c842faae48b6ef');
