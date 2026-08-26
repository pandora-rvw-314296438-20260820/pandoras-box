-- Phase 7 Recovery Migration: Final Release Sign-Off and Coordinated Rotation
-- This migration records the final release sign-off and coordinated secret rotation completion.

CREATE TABLE IF NOT EXISTS public.phase7_release_signoffs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signoff_stage TEXT NOT NULL DEFAULT 'final_recovery_complete',
  status TEXT NOT NULL DEFAULT 'approved',
  signed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.phase7_release_signoffs (signoff_stage, status)
VALUES ('final_recovery_complete', 'approved');
