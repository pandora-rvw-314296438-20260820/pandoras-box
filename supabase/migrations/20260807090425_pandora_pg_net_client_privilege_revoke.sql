-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

begin;

revoke usage on schema net from public;
revoke usage on schema net from anon;
revoke usage on schema net from authenticated;

revoke all privileges on all tables in schema net from public;
revoke all privileges on all tables in schema net from anon;
revoke all privileges on all tables in schema net from authenticated;

revoke all privileges on all sequences in schema net from public;
revoke all privileges on all sequences in schema net from anon;
revoke all privileges on all sequences in schema net from authenticated;

revoke all privileges on all functions in schema net from public;
revoke all privileges on all functions in schema net from anon;
revoke all privileges on all functions in schema net from authenticated;

commit;
