-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

alter function public.projectos_accept_intake(uuid,uuid,text,text,text,text,text,text,text)
  set search_path = public, private, auth, extensions, pg_temp;

alter function public.projectos_record_outcome(uuid,text,text,boolean,jsonb,jsonb,numeric,integer,integer,text,jsonb,jsonb,jsonb)
  set search_path = public, private, auth, extensions, pg_temp;
