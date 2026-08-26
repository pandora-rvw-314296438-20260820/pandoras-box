-- Pandora PostHog Phase 1: privacy-safe lifecycle contracts only.
-- All new Pandora lifecycle contracts remain inactive. This migration does not enable PostHog capture,
-- replay, autocapture, network payload capture, flags, experiments, or production use.

DO $migration$
DECLARE
  v_organization_id uuid := '2270b266-59da-4c39-bfd9-9f8d08352af0';
  v_allowed_properties text[] := ARRAY[
    'environment',
    'source_sha',
    'release_sha',
    'release_id',
    'deployment_id',
    'rollback_of_deployment_id',
    'schema_version',
    'event_schema_version',
    'privacy_mode',
    'proof_stage',
    'organization_key',
    'project_key',
    'execution_id',
    'failure_class',
    'tool_class',
    'model_provider',
    'model_name',
    'outcome_type',
    'result',
    'duration_ms',
    'latency_ms',
    'retry_count',
    'input_tokens',
    'output_tokens',
    'total_cost_usd',
    'evaluation_score',
    'evidence_count'
  ];
BEGIN
  INSERT INTO private.projectos_product_registry (
    organization_id,
    product_key,
    title,
    repo_full_name,
    posthog_project_id,
    posthog_dashboard_id,
    posthog_dashboard_url,
    supabase_project_ref,
    status,
    data_classification
  ) VALUES (
    v_organization_id,
    'pandoras_box',
    'Pandoras-Box / ProjectOS',
    'pandora-rvw-314296438-20260820/pandoras-box',
    526760,
    1934160,
    'https://us.posthog.com/project/526760/dashboard/1934160',
    'jcyqixttuebxqqfkjonq',
    'active',
    'aggregate_only'
  )
  ON CONFLICT (organization_id, product_key) DO NOTHING;

  IF NOT EXISTS (
    SELECT 1
    FROM private.projectos_product_registry
    WHERE organization_id = v_organization_id
      AND product_key = 'pandoras_box'
  ) THEN
    RAISE EXCEPTION 'pandora_product_registry_missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM private.projectos_product_registry
    WHERE organization_id = v_organization_id
      AND product_key = 'pandoras_box'
      AND (
        repo_full_name IS DISTINCT FROM 'mbanatao/mcpmaster'
        AND repo_full_name IS DISTINCT FROM 'banataosystems/Pandoras-box'
        AND repo_full_name IS DISTINCT FROM 'pandora-rvw-314296438-20260820/pandoras-box'
        OR posthog_project_id IS DISTINCT FROM 526760
        OR supabase_project_ref IS DISTINCT FROM 'jcyqixttuebxqqfkjonq'
      )
  ) THEN
    RAISE EXCEPTION 'pandora_product_registry_identity_conflict';
  END IF;

  UPDATE private.projectos_product_registry
  SET repo_full_name = 'pandora-rvw-314296438-20260820/pandoras-box',
      updated_at = now()
  WHERE organization_id = v_organization_id
    AND product_key = 'pandoras_box'
    AND repo_full_name IS DISTINCT FROM 'pandora-rvw-314296438-20260820/pandoras-box';

  INSERT INTO private.projectos_event_contracts (
    organization_id,
    product_key,
    event_name,
    purpose,
    privacy_tier,
    allowed_properties,
    retention_days,
    active
  )
  SELECT
    v_organization_id,
    'pandoras_box',
    lifecycle.event_name,
    lifecycle.purpose,
    'pseudonymous_product',
    v_allowed_properties,
    400,
    false
  FROM (VALUES
    ('pandora_intent_received', 'Record that a governed customer intent entered Pandora without retaining the intent text.'),
    ('pandora_plan_accepted', 'Record acceptance of a governed execution plan without retaining plan content.'),
    ('pandora_execution_started', 'Record the start of a governed execution using metadata-only identifiers.'),
    ('pandora_build_succeeded', 'Record a successful build proof without source code or build logs.'),
    ('pandora_tests_passed', 'Record that defined automated proof gates passed without test payloads.'),
    ('pandora_deployment_created', 'Record creation of a deployment candidate without deployment secrets.'),
    ('pandora_production_verified', 'Record completed production verification only after the separate release gate.'),
    ('pandora_outcome_accepted', 'Record customer acceptance of a verified outcome without customer messages.'),
    ('pandora_execution_failed', 'Record a sanitized execution failure class without arguments, results, or stack payloads.'),
    ('pandora_rollback_completed', 'Record completion of rollback proof using metadata-only deployment references.')
  ) AS lifecycle(event_name, purpose)
  ON CONFLICT (organization_id, product_key, event_name)
  DO UPDATE SET
    purpose = EXCLUDED.purpose,
    privacy_tier = EXCLUDED.privacy_tier,
    allowed_properties = EXCLUDED.allowed_properties,
    retention_days = EXCLUDED.retention_days,
    active = false,
    updated_at = now();
END;
$migration$;

COMMENT ON TABLE private.projectos_event_contracts IS
  'Allowlisted product-signal contracts. Pandora lifecycle contracts added by Phase 1 remain inactive until isolation, privacy, CI, non-production readback, rollback, independent-review, and owner-production gates pass.';
