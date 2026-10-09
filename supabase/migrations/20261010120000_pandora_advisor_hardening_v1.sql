-- Migration: 20261010120000_pandora_advisor_hardening_v1.sql
-- Purpose: Harden production database against Supabase Security Advisor findings
--          with zero behavioural change.
--
-- Advisor findings addressed:
--   1. function_search_path_mutable:
--      Set search_path = pg_catalog for private.pandora_plp_billing_money(bigint).
--      Every referenced object (round, coalesce, numeric division operator) is
--      strictly resolvable from pg_catalog.
--   2. auth_rls_initplan:
--      Wrap auth.uid calls as (select auth.uid()) across 21 RLS policies to allow
--      PostgreSQL query planner to evaluate tenant authentication once via an InitPlan
--      subquery instead of re-evaluating per row.
--
-- Semantics:
--   Zero behavioural change. Authorization rules, permitted roles, commands,
--   and permissive flags are identical to existing production behavior.
--
-- Rollback note:
--   To revert the function search_path:
--     alter function private.pandora_plp_billing_money(bigint) reset search_path;
--   To revert policies:
--     Re-run alter policy statements on the 21 tables using the original expressions.

-- 1. Advisor function_search_path_mutable fix:
-- Confirmed function body in 20261008175248_pandora_plp_billing_paypal_api_v1.sql:
--   select round(coalesce(p_micros, 0) / 1000000.0, 2);
-- All referenced functions and operators reside in pg_catalog.
alter function private.pandora_plp_billing_money(bigint) set search_path = pg_catalog;

-- 2. Advisor auth_rls_initplan fixes (21 policies):

-- 1/21: enterprise_authority_policies_member_select on public.enterprise_authority_policies
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_authority_policies_member_select
  on public.enterprise_authority_policies
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_authority_policies.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 2/21: enterprise_entities_member_select on public.enterprise_entities
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_entities_member_select
  on public.enterprise_entities
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_entities.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 3/21: enterprise_entity_bindings_member_select on public.enterprise_entity_bindings
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_entity_bindings_member_select
  on public.enterprise_entity_bindings
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_entity_bindings.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 4/21: enterprise_field_provenance_member_select on public.enterprise_field_provenance
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_field_provenance_member_select
  on public.enterprise_field_provenance
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_field_provenance.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 5/21: enterprise_identity_resolutions_member_select on public.enterprise_identity_resolutions
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_identity_resolutions_member_select
  on public.enterprise_identity_resolutions
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_identity_resolutions.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 6/21: enterprise_identity_signals_member_select on public.enterprise_identity_signals
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_identity_signals_member_select
  on public.enterprise_identity_signals
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_identity_signals.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 7/21: enterprise_integration_connections_member_select on public.enterprise_integration_connections
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_integration_connections_member_select
  on public.enterprise_integration_connections
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_integration_connections.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 8/21: enterprise_people_member_select on public.enterprise_people
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_people_member_select
  on public.enterprise_people
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_people.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 9/21: enterprise_relationships_member_select on public.enterprise_relationships
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_relationships_member_select
  on public.enterprise_relationships
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_relationships.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 10/21: enterprise_source_records_member_select on public.enterprise_source_records
-- Latest definition in 20260930100000_pandora_universal_core_foundation_v1.sql matches TSV MEMBER_ENUM.
alter policy enterprise_source_records_member_select
  on public.enterprise_source_records
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_source_records.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 11/21: enterprise_realtime_signals_member_read on public.enterprise_realtime_signals
-- Latest definition in 20260921112000_plp_realtime_resort_updates_v1.sql matches TSV MEMBER_TEXT.
alter policy enterprise_realtime_signals_member_read
  on public.enterprise_realtime_signals
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = enterprise_realtime_signals.organization_id
        and m.user_id = (select auth.uid())
        and (m.status)::text = 'active'::text
    )
  );

-- 12/21: pandora_build_stream_sessions_member_read on public.pandora_build_stream_sessions
-- Latest definition in 20260901004825_pandora_live_code_stream_v1.sql matches TSV MEMBER_TEXT.
alter policy pandora_build_stream_sessions_member_read
  on public.pandora_build_stream_sessions
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = pandora_build_stream_sessions.organization_id
        and m.user_id = (select auth.uid())
        and (m.status)::text = 'active'::text
    )
  );

-- 13/21: pandora_change_impact_assessments_project_read on public.pandora_change_impact_assessments
-- Latest definition in 20260902004500_pandora_change_impact_assessment_v1.sql matches TSV MEMBER_TEXT.
alter policy pandora_change_impact_assessments_project_read
  on public.pandora_change_impact_assessments
  using (
    exists (
      select 1 from public.memberships m
      where m.organization_id = pandora_change_impact_assessments.organization_id
        and m.user_id = (select auth.uid())
        and (m.status)::text = 'active'::text
    )
  );

-- 14/21: pandora_build_stream_events_member_live_read on public.pandora_build_stream_events
-- Latest definition in 20260901004825_pandora_live_code_stream_v1.sql matches TSV (expires_at > now()) AND MEMBER_TEXT.
alter policy pandora_build_stream_events_member_live_read
  on public.pandora_build_stream_events
  using (
    (expires_at > now()) and exists (
      select 1 from public.memberships m
      where m.organization_id = pandora_build_stream_events.organization_id
        and m.user_id = (select auth.uid())
        and (m.status)::text = 'active'::text
    )
  );

-- 15/21: pandora_activity_jobs_owner_read on public.pandora_activity_jobs
-- Latest definition in 20260914100000_pandora_activity_realtime_transport_v1.sql matches TSV (requested_by = ...) AND MEMBER_ENUM.
alter policy pandora_activity_jobs_owner_read
  on public.pandora_activity_jobs
  using (
    (requested_by = (select auth.uid())) and exists (
      select 1 from public.memberships m
      where m.organization_id = pandora_activity_jobs.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 16/21: pandora_intelligence_threads_owner_select on public.pandora_intelligence_threads
-- Latest definition in 20260830104500_pandora_intelligence_chat_v1.sql matches TSV (created_by = ...) AND MEMBER_ENUM.
alter policy pandora_intelligence_threads_owner_select
  on public.pandora_intelligence_threads
  using (
    (created_by = (select auth.uid())) and exists (
      select 1 from public.memberships m
      where m.organization_id = pandora_intelligence_threads.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 17/21: pandora_phone_local_ai_turns_owner_read on public.pandora_phone_local_ai_turns
-- Latest definition in 20260920180430_phone_local_ai_turn_telemetry_v1.sql matches TSV (user_id = ...) AND MEMBER_TEXT.
alter policy pandora_phone_local_ai_turns_owner_read
  on public.pandora_phone_local_ai_turns
  using (
    (user_id = (select auth.uid())) and exists (
      select 1 from public.memberships m
      where m.organization_id = pandora_phone_local_ai_turns.organization_id
        and m.user_id = (select auth.uid())
        and (m.status)::text = 'active'::text
    )
  );

-- 18/21: pandora_intelligence_messages_owner_select on public.pandora_intelligence_messages
-- Latest definition in 20260830104500_pandora_intelligence_chat_v1.sql matches TSV private.pandora_intelligence_thread_matches_org(...) AND MEMBER_ENUM.
alter policy pandora_intelligence_messages_owner_select
  on public.pandora_intelligence_messages
  using (
    private.pandora_intelligence_thread_matches_org(thread_id, organization_id, (select auth.uid())) and exists (
      select 1 from public.memberships m
      where m.organization_id = pandora_intelligence_messages.organization_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 19/21: pandora_activity_events_owner_read on public.pandora_activity_events
-- Latest definition in 20260914100000_pandora_activity_realtime_transport_v1.sql matches TSV EXISTS(...).
alter policy pandora_activity_events_owner_read
  on public.pandora_activity_events
  using (
    exists (
      select 1 from public.pandora_activity_jobs j
      join public.memberships m on m.organization_id = j.organization_id
      where j.id = pandora_activity_events.job_id
        and j.organization_id = pandora_activity_events.organization_id
        and j.requested_by = (select auth.uid())
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 20/21: pandora_activity_controls_owner_read on public.pandora_activity_controls
-- Latest definition in 20260915001000_pandora_activity_controls_v1.sql matches TSV (requested_by = ...) AND EXISTS(...).
alter policy pandora_activity_controls_owner_read
  on public.pandora_activity_controls
  using (
    (requested_by = (select auth.uid())) and exists (
      select 1 from public.pandora_activity_jobs j
      join public.memberships m on m.organization_id = j.organization_id
      where j.id = pandora_activity_controls.job_id
        and j.organization_id = pandora_activity_controls.organization_id
        and j.requested_by = (select auth.uid())
        and m.user_id = (select auth.uid())
        and m.status = 'active'::public.membership_status
    )
  );

-- 21/21: pandora_project_intents_member_insert on public.pandora_project_intents
-- Latest definition in 20260828153500_pandora_project_spec_control_plane_v1.sql matches TSV WITH CHECK.
alter policy pandora_project_intents_member_insert
  on public.pandora_project_intents
  with check (
    private.is_org_member(organization_id)
    and (requester_id = (select auth.uid()))
    and (source = 'customer'::text)
  );
