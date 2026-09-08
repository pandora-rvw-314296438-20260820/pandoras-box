export type ProjectRuntimePublicError = {
  responseCode: string;
  status: number;
  plainMessage: string;
  operation: "auth" | "create" | "project" | "preview" | "publish" | "domain" | "undo" | "rollback";
  phase: "request" | "authorization" | "reconcile" | "provider" | "verification";
  retryable: boolean;
  outcomeKnown: boolean;
  log: boolean;
};

const invalid = new Set([
  "INVALID_JSON",
  "BODY_TOO_LARGE",
  "INVALID_PROJECT_NAME",
  "INVALID_OBJECTIVE",
  "INVALID_BUILD_KIND",
  "IDEMPOTENCY_KEY_REQUIRED",
  "INVALID_DOMAIN",
  "VERSION_REQUIRED",
  "INVALID_PRODUCTION_PRECONDITION",
  "EXACT_VERSION_REQUIRED",
  "ARTIFACT_FILE_BASE64_INVALID",
  "ARTIFACT_FILE_BASE64_NON_CANONICAL",
  "ARTIFACT_FILE_PATH_INVALID",
  "ARTIFACT_BUNDLE_JSON_INVALID",
  "ARTIFACT_BUNDLE_SCHEMA_UNSUPPORTED",
  "ARTIFACT_BUNDLE_FILES_INVALID",
  "INVALID_DOMAIN_REQUEST",
  "INVALID_ROLLBACK_REQUEST",
  "INVALID_UNDO_REQUEST",
]);

const projectStateConflicts = new Set([
  "PREVIEW_REQUIRED",
  "PREVIEW_NOT_READY",
  "VERSION_SOURCE_INVALID",
  "VERSION_SOURCE_MISMATCH",
  "PRODUCTION_PRECONDITION_REQUIRED",
  "PRODUCTION_PRECONDITION_MISMATCH",
  "VERIFICATION_REQUIRED",
  "VERIFICATION_IDENTITY_MISMATCH",
  "VERIFICATION_STALE",
  "PROVIDER_LINEAGE_MISMATCH",
  "PRODUCTION_PROMOTION_NOT_CONFIRMED",
  "PRODUCTION_DEPLOYMENT_NOT_CONFIRMED",
  "VERCEL_CONFLICT",
  "VERCEL_DOMAIN_REJECTED",
  "VERCEL_PROJECT_NOT_FOUND",
  "VERCEL_PROJECT_IDENTITY_MISMATCH",
  "ARTIFACT_LINEAGE_INCOMPLETE",
  "ARTIFACT_NOT_FOUND",
  "ARTIFACT_DIGEST_MISMATCH",
  "ARTIFACT_STORAGE_INVALID",
  "ARTIFACT_STORAGE_READ_FAILED",
  "ARTIFACT_KIND_NOT_DEPLOYABLE",
  "ARTIFACT_PROVENANCE_MISMATCH",
  "ARTIFACT_BUNDLE_SIZE_INVALID",
  "ARTIFACT_BUNDLE_DIGEST_MISMATCH",
  "ARTIFACT_BUNDLE_LINEAGE_MISMATCH",
  "ARTIFACT_FILES_NOT_CANONICAL",
  "ARTIFACT_FILE_ENCODING_UNSUPPORTED",
  "ARTIFACT_FILE_TOO_LARGE",
  "ARTIFACT_FILES_TOTAL_TOO_LARGE",
  "ARTIFACT_FILE_DIGEST_MISMATCH",
  "ARTIFACT_FILE_SIZE_MISMATCH",
  "ARTIFACT_ENTRYPOINT_MISSING",
  "DOMAIN_DEPLOYMENT_REQUIRED",
  "DOMAIN_NOT_FOUND",
  "ROLLBACK_TARGET_NOT_ELIGIBLE",
  "ROLLBACK_TARGET_NOT_VERIFIED",
  "SUPABASE_FALLBACK_DOMAIN_UNAVAILABLE",
  "VERCEL_PREVIEW_REQUIRED",
  "VERCEL_PREVIEW_VERIFICATION_FAILED",
  "PRODUCTION_PROVIDER_UNSUPPORTED",
]);

function e(
  responseCode: string,
  status: number,
  plainMessage: string,
  operation: ProjectRuntimePublicError["operation"],
  phase: ProjectRuntimePublicError["phase"],
  retryable = false,
  outcomeKnown = true,
  log = false,
): ProjectRuntimePublicError {
  return {
    responseCode,
    status,
    plainMessage,
    operation,
    phase,
    retryable,
    outcomeKnown,
    log,
  };
}

export function classifyProjectRuntimeError(
  code: string,
): ProjectRuntimePublicError {
  if (code === "SIGN_IN_REQUIRED") {
    return e(code, 401, "Please sign in again.", "auth", "authorization");
  }
  if ([
    "ORGANIZATION_ACCESS_REQUIRED",
    "OWNER_ROLE_REQUIRED",
    "ROLLBACK_OWNER_REQUIRED",
    "ROLLBACK_AUTHORIZATION_FAILED",
  ].includes(code)) {
    return e(
      code,
      403,
      "You do not have permission to perform that project action.",
      "auth",
      "authorization",
    );
  }
  if (code === "ORGANIZATION_SELECTION_REQUIRED") {
    return e(code, 409, "Choose which organization you want to use.", "auth", "request");
  }
  if (code === "EXTERNAL_EXPERIENCE_WRITE_DISABLED") {
    return e(
      code,
      403,
      "That external app is not enabled for this project action.",
      "project",
      "authorization",
    );
  }
  if (code === "RATE_LIMITED") {
    return e(code, 429, "Please wait a moment before trying again.", "project", "request", true);
  }
  if (code === "PROJECT_CREATE_IDEMPOTENCY_COLLISION") {
    return e(
      code,
      409,
      "That retry does not match the original project request. Start a new request instead.",
      "create",
      "reconcile",
    );
  }
  if (invalid.has(code)) {
    return e(code, 400, "Check that project information and try again.", "project", "request");
  }
  if (code === "PROJECT_NOT_FOUND") {
    return e(code, 404, "Pandora could not find that project.", "project", "request");
  }
  if (code === "VERCEL_DEPLOYMENT_QUOTA_EXHAUSTED") {
    return e(
      code,
      503,
      "Preview capacity is temporarily full. Pandora can retry when provider capacity resets.",
      "preview",
      "provider",
      true,
    );
  }
  if (code === "DOMAIN_IN_PROGRESS") {
    return e(code, 409, "Pandora is already attaching that domain.", "domain", "provider", true);
  }
  if (code === "DOMAIN_RECONCILIATION_REQUIRED") {
    return e(
      code,
      409,
      "Pandora is confirming the domain. Do not attach it again yet.",
      "domain",
      "reconcile",
      true,
      false,
    );
  }
  if (code === "UNDO_REQUIRES_ROLLBACK") {
    return e(
      code,
      409,
      "That version is already live. Use the governed rollback action instead of Undo.",
      "undo",
      "verification",
    );
  }
  if ([
    "UNDO_NOT_AVAILABLE",
    "UNDO_PRECONDITION_MISMATCH",
    "UNDO_PARENT_NOT_VERIFIED",
    "UNDO_PARENT_PREVIEW_UNAVAILABLE",
  ].includes(code)) {
    return e(
      code,
      409,
      "That change cannot be undone from the current project state.",
      "undo",
      "verification",
    );
  }
  if (code === "ROLLBACK_APPROVAL_REQUIRED") {
    return e(
      code,
      409,
      "This production rollback needs your approval in Needs You before Pandora can continue.",
      "rollback",
      "authorization",
    );
  }
  if (code === "ROLLBACK_DENIED") {
    return e(code, 409, "This production rollback was not approved.", "rollback", "authorization");
  }
  if (code === "ROLLBACK_IN_PROGRESS") {
    return e(code, 409, "Pandora is already rolling back this project.", "rollback", "provider", true);
  }
  if (code === "ROLLBACK_RECONCILIATION_REQUIRED") {
    return e(
      code,
      409,
      "Pandora is confirming the production rollback. Do not roll back again yet.",
      "rollback",
      "reconcile",
      true,
      false,
    );
  }
  if (code === "ROLLBACK_AUTHORIZATION_COLLISION") {
    return e(
      code,
      409,
      "That rollback request conflicts with an earlier authorization. Create a new rollback request.",
      "rollback",
      "authorization",
    );
  }
  if (code === "ROLLBACK_PROVIDER_UNSUPPORTED") {
    return e(
      code,
      409,
      "This production provider does not support governed rollback yet.",
      "rollback",
      "provider",
    );
  }
  if (code === "ROLLBACK_VERIFICATION_FAILED") {
    return e(
      code,
      409,
      "Pandora refused to make the rollback live because independent verification failed.",
      "rollback",
      "verification",
    );
  }
  if (code === "PREVIEW_IN_PROGRESS") {
    return e(code, 409, "Pandora is already creating this exact preview.", "preview", "provider", true);
  }
  if (code === "PREVIEW_RECONCILIATION_REQUIRED") {
    return e(
      code,
      409,
      "Pandora is confirming whether that preview was created. Do not create it again yet.",
      "preview",
      "reconcile",
      true,
      false,
    );
  }
  if (code === "PUBLISH_IN_PROGRESS") {
    return e(code, 409, "Pandora is already publishing this version.", "publish", "provider", true);
  }
  if (code === "PUBLISH_RECONCILIATION_REQUIRED") {
    return e(
      code,
      409,
      "Pandora is confirming whether that publish completed. Do not publish again yet.",
      "publish",
      "reconcile",
      true,
      false,
    );
  }
  if (projectStateConflicts.has(code)) {
    return e(
      code,
      409,
      "The project is not ready for that action yet.",
      "project",
      "verification",
    );
  }
  if ([
    "RUNTIME_BROKER_NOT_CONFIGURED",
    "VERCEL_NOT_CONFIGURED",
    "PUBLISH_CLAIM_FAILED",
    "PREVIEW_CLAIM_FAILED",
    "DOMAIN_CLAIM_FAILED",
    "ROLLBACK_CLAIM_FAILED",
    "ROLLBACK_EXECUTION_FAILED",
    "SUPABASE_PRODUCTION_FALLBACK_FAILED",
  ].includes(code)) {
    return e(
      code,
      503,
      "The project runtime is temporarily unavailable.",
      "project",
      "provider",
      true,
    );
  }

  return e(
    "PROJECT_RUNTIME_UNAVAILABLE",
    503,
    "Pandora cannot reach the project runtime right now.",
    "project",
    "provider",
    true,
    true,
    true,
  );
}
