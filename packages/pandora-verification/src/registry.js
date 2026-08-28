"use strict";

function check(id, category, failureClass, freshnessScope) {
  return Object.freeze({ id, category, failureClass, freshnessScope });
}
function profile(requiredChecks) {
  return Object.freeze({ requiredChecks: Object.freeze([...requiredChecks]) });
}

const CHECK_REGISTRY = Object.freeze({
  source_format: check("source_format", "SOURCE", "source", "exact_source"),
  source_lint: check("source_lint", "SOURCE", "source", "exact_source"),
  source_static_analysis: check("source_static_analysis", "SOURCE", "source", "exact_source"),
  source_typecheck: check("source_typecheck", "SOURCE", "source", "exact_source"),
  unit_tests: check("unit_tests", "TESTS", "unit_test", "exact_source"),
  integration_tests: check("integration_tests", "TESTS", "integration", "exact_source_and_environment"),
  browser_e2e: check("browser_e2e", "TESTS", "browser", "exact_deployment"),
  reproducible_build: check("reproducible_build", "BUILD", "build", "exact_source"),
  artifact_identity: check("artifact_identity", "BUILD", "build", "exact_artifact"),
  dependency_security: check("dependency_security", "SECURITY", "dependency", "exact_source"),
  secret_scan: check("secret_scan", "SECURITY", "security", "exact_source_and_artifact"),
  unsafe_configuration: check("unsafe_configuration", "SECURITY", "security", "exact_source_and_environment"),
  auth_security: check("auth_security", "SECURITY", "security", "exact_deployment"),
  permission_security: check("permission_security", "SECURITY", "security", "exact_deployment"),
  security_headers: check("security_headers", "SECURITY", "security", "exact_deployment"),
  accessibility_semantics: check("accessibility_semantics", "ACCESSIBILITY", "accessibility", "exact_deployment"),
  accessibility_keyboard: check("accessibility_keyboard", "ACCESSIBILITY", "accessibility", "exact_deployment"),
  accessibility_contrast: check("accessibility_contrast", "ACCESSIBILITY", "accessibility", "exact_deployment"),
  accessibility_scaling: check("accessibility_scaling", "ACCESSIBILITY", "accessibility", "exact_deployment"),
  accessibility_touch_targets: check("accessibility_touch_targets", "ACCESSIBILITY", "accessibility", "exact_deployment"),
  migration_preflight: check("migration_preflight", "DATABASE", "migration", "exact_migration_set"),
  migration_postflight: check("migration_postflight", "DATABASE", "migration", "exact_schema_state"),
  database_policy: check("database_policy", "DATABASE", "migration", "exact_schema_state"),
  visual_baseline: check("visual_baseline", "VISUAL", "visual", "exact_deployment"),
  visual_responsive: check("visual_responsive", "VISUAL", "visual", "exact_deployment"),
  runtime_health: check("runtime_health", "RUNTIME", "runtime", "exact_deployment"),
  runtime_core_routes: check("runtime_core_routes", "RUNTIME", "runtime", "exact_deployment"),
  runtime_auth_flow: check("runtime_auth_flow", "RUNTIME", "runtime", "exact_deployment"),
  acceptance_requirements: check("acceptance_requirements", "ACCEPTANCE", "acceptance", "exact_spec_and_deployment"),
  business_metric_readiness: check("business_metric_readiness", "ACCEPTANCE", "business_acceptance", "exact_spec_and_deployment"),
  production_exact_version: check("production_exact_version", "PRODUCTION", "runtime", "exact_production_deployment"),
  production_domain: check("production_domain", "PRODUCTION", "domain", "exact_production_deployment"),
  production_runtime: check("production_runtime", "PRODUCTION", "runtime", "exact_production_deployment"),
});

const PROFILES = Object.freeze({
  static_site: profile([
    "source_format", "source_lint", "secret_scan", "visual_responsive", "runtime_health", "acceptance_requirements",
  ]),
  web_application: profile([
    "source_format", "source_lint", "source_static_analysis", "source_typecheck", "unit_tests", "integration_tests",
    "browser_e2e", "artifact_identity", "dependency_security", "secret_scan", "unsafe_configuration", "auth_security",
    "accessibility_semantics", "accessibility_keyboard", "accessibility_contrast", "accessibility_scaling",
    "accessibility_touch_targets", "visual_responsive", "runtime_health", "runtime_core_routes", "acceptance_requirements",
  ]),
  mobile_application: profile([
    "source_format", "source_static_analysis", "unit_tests", "integration_tests", "artifact_identity", "dependency_security",
    "secret_scan", "accessibility_semantics", "accessibility_scaling", "accessibility_touch_targets", "visual_responsive",
    "acceptance_requirements",
  ]),
  backend_service: profile([
    "source_lint", "source_static_analysis", "source_typecheck", "unit_tests", "integration_tests", "artifact_identity",
    "dependency_security", "secret_scan", "unsafe_configuration", "auth_security", "permission_security", "runtime_health",
    "runtime_core_routes", "acceptance_requirements",
  ]),
  business_system: profile([
    "source_lint", "source_static_analysis", "source_typecheck", "unit_tests", "integration_tests", "browser_e2e",
    "artifact_identity", "dependency_security", "secret_scan", "auth_security", "permission_security",
    "accessibility_semantics", "accessibility_keyboard", "visual_responsive", "runtime_health", "runtime_core_routes",
    "acceptance_requirements", "business_metric_readiness",
  ]),
  automation: profile([
    "source_lint", "source_static_analysis", "unit_tests", "integration_tests", "dependency_security", "secret_scan",
    "permission_security", "acceptance_requirements",
  ]),
  database_change: profile(["migration_preflight", "database_policy", "migration_postflight"]),
  production_release: profile([
    "artifact_identity", "secret_scan", "runtime_health", "acceptance_requirements", "production_exact_version",
    "production_domain", "production_runtime",
  ]),
});

const DEFAULT_LIMITS = Object.freeze({
  maxCheckDurationMs: 15 * 60 * 1000,
  maxBrowserDurationMs: 10 * 60 * 1000,
  maxScreenshots: 50,
  maxLogBytes: 2 * 1024 * 1024,
  maxRetries: 2,
  maxEvidenceBytes: 50 * 1024 * 1024,
  maxNetworkRequests: 500,
});

function validateRegistry() {
  for (const [profileName, definition] of Object.entries(PROFILES)) {
    if (!definition.requiredChecks.length) throw new Error(`verification profile ${profileName} has no checks`);
    for (const checkId of definition.requiredChecks) {
      if (!CHECK_REGISTRY[checkId]) throw new Error(`verification profile ${profileName} references unknown check ${checkId}`);
    }
  }
  return true;
}

module.exports = { CHECK_REGISTRY, PROFILES, DEFAULT_LIMITS, validateRegistry };
