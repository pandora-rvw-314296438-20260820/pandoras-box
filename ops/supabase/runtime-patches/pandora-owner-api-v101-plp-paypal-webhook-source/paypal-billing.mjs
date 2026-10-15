const BILLING_ERRORS = new Set([
  "INVALID_IDEMPOTENCY_KEY",
  "INVALID_RETURN_URL",
  "PLAN_NOT_FOUND",
  "PLAN_PROVIDER_LINK_REQUIRED",
  "PLAN_UNCHANGED",
  "SUBSCRIPTION_ALREADY_ACTIVE",
  "SUBSCRIPTION_NOT_ACTIVE",
  "RECONCILIATION_REQUIRED",
  "PAYPAL_CHECKOUT_FAILED",
  "PAYPAL_PLAN_CHANGE_FAILED",
  "PAYPAL_CANCEL_FAILED",
  "PAYPAL_NOT_CONFIGURED",
  "PAYPAL_AUTH_FAILED",
]);

function text(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function asRecord(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function billingError(error) {
  const message = text(error?.message || error, "BILLING_REQUEST_FAILED");
  const code = message.split(":")[0].trim();
  if (BILLING_ERRORS.has(code)) {
    const wrapped = new Error(code);
    throw wrapped;
  }
  if (message.includes("PAYPAL_NOT_CONFIGURED")) throw new Error("PAYPAL_NOT_CONFIGURED");
  if (message.includes("PAYPAL_AUTH_FAILED")) throw new Error("PAYPAL_AUTH_FAILED");
  throw new Error("BILLING_REQUEST_FAILED");
}

async function callBilling(admin, fn, args) {
  const { data, error } = await admin.rpc(fn, args);
  if (error) billingError(error);
  return asRecord(data);
}

export async function billingStatus(admin, organizationId) {
  const status = await callBilling(admin, "pandora_plp_billing_status_v1", {
    p_organization_id: organizationId,
  });
  return {
    provider: status.provider ?? { name: "paypal", configured: false, label: "Provider state unavailable" },
    subscription: status.subscription ?? null,
    plans: Array.isArray(status.plans) ? status.plans : [],
    pendingPlanChange: status.pendingPlanChange ?? null,
    checkout: status.checkout ?? null,
    activity: Array.isArray(status.activity) ? status.activity : [],
  };
}

export async function billingCheckout(admin, context, body) {
  const planCode = text(body.planCode);
  const idempotencyKey = text(body.idempotencyKey);
  const returnUrl = text(body.returnUrl);
  const cancelUrl = text(body.cancelUrl);
  if (!/^[a-z][a-z0-9_-]{1,63}$/.test(planCode)) throw new Error("PLAN_NOT_FOUND");
  return callBilling(admin, "pandora_plp_billing_checkout_v1", {
    p_organization_id: context.organizationId,
    p_actor: context.userId,
    p_plan_code: planCode,
    p_idempotency_key: idempotencyKey,
    p_return_url: returnUrl,
    p_cancel_url: cancelUrl,
  });
}

export async function billingChangePlan(admin, context, body) {
  const planCode = text(body.planCode);
  const idempotencyKey = text(body.idempotencyKey);
  if (!/^[a-z][a-z0-9_-]{1,63}$/.test(planCode)) throw new Error("PLAN_NOT_FOUND");
  return callBilling(admin, "pandora_plp_billing_change_plan_v1", {
    p_organization_id: context.organizationId,
    p_actor: context.userId,
    p_plan_code: planCode,
    p_idempotency_key: idempotencyKey,
  });
}

export async function billingReconcile(admin, context) {
  return callBilling(admin, "pandora_plp_billing_reconcile_v1", {
    p_organization_id: context.organizationId,
    p_actor: context.userId,
  });
}

export async function billingCancel(admin, context, body) {
  return callBilling(admin, "pandora_plp_billing_cancel_v1", {
    p_organization_id: context.organizationId,
    p_actor: context.userId,
    p_reason: text(body.reason, "Cancelled by PLP owner").slice(0, 128),
  });
}

export { BILLING_ERRORS };

// ---------------------------------------------------------------------------
// PayPal SANDBOX billing (explicit only).
//
// Everything above this line is the live path and is unchanged. Sandbox is
// selected per request ONLY by the header `x-pandora-billing-environment:
// sandbox`, with an explicit `x-organization-id`, and ONLY for organizations
// listed in the active server-side provider config
// `paypal.sandbox_organization_ids`. No header (or `live`) means live; any
// other value is rejected. Sandbox routes call the service-role-only
// `pandora_plp_billing_sandbox_*_v1` functions, which keep their own Vault
// secret names and `pandora_paypal_sandbox_*` tables. Nothing here reads,
// returns or logs a credential, token or Vault value.
//
// Gap: there is no `pandora_plp_billing_sandbox_change_plan_v1`, so sandbox
// plan changes are refused (SANDBOX_PLAN_CHANGE_UNAVAILABLE), never emulated.
// There is no sandbox status function either; sandbox status is a read-only
// select of the sandbox tables.
// ---------------------------------------------------------------------------
export const BILLING_ENVIRONMENT_HEADER = "x-pandora-billing-environment";

const SANDBOX_BILLING_ERROR_RESPONSES = new Map([
  ["BILLING_ENVIRONMENT_INVALID", [400, "That billing environment is not available."]],
  ["BILLING_ORGANIZATION_REQUIRED", [400, "Choose the organization whose sandbox billing you want to manage."]],
  ["BILLING_SANDBOX_NOT_ALLOWED", [403, "PayPal sandbox billing is not enabled for this organization."]],
  ["SANDBOX_PLAN_CHANGE_UNAVAILABLE", [409, "Plan changes are not available in PayPal sandbox. Nothing was sent to PayPal."]],
  ["SANDBOX_PLAN_NOT_FOUND", [400, "That plan is not available."]],
  ["SANDBOX_INVALID_IDEMPOTENCY_KEY", [400, "Please check that information and try again."]],
  ["PAYPAL_SANDBOX_NOT_CONFIGURED", [503, "PayPal sandbox is not configured."]],
  ["PAYPAL_SANDBOX_AUTH_FAILED", [503, "PayPal sandbox is unavailable right now. Pandora could not authenticate with PayPal."]],
  ["PAYPAL_SANDBOX_PRODUCT_FAILED", [502, "PayPal sandbox could not prepare the plan catalog. No checkout was started."]],
  ["PAYPAL_SANDBOX_PLAN_FAILED", [502, "PayPal sandbox could not prepare the plan catalog. No checkout was started."]],
  ["PAYPAL_SANDBOX_CHECKOUT_FAILED", [502, "PayPal sandbox could not start checkout."]],
  ["PAYPAL_SANDBOX_REQUEST_BLOCKED", [503, "Pandora blocked an unexpected PayPal sandbox request."]],
  ["SANDBOX_BILLING_STATE_READ_FAILED", [503, "Pandora could not read the sandbox billing state."]],
  ["SANDBOX_BILLING_REQUEST_FAILED", [502, "PayPal sandbox did not confirm this billing action."]],
]);

/** [httpStatus, plainMessage] for a sandbox billing error code, else null. */
export function sandboxBillingErrorResponse(code) {
  return SANDBOX_BILLING_ERROR_RESPONSES.get(code) ?? null;
}

const SANDBOX_RAISED_CODES = new Map([
  ["PLAN_NOT_FOUND", "SANDBOX_PLAN_NOT_FOUND"],
  ["INVALID_IDEMPOTENCY_KEY", "SANDBOX_INVALID_IDEMPOTENCY_KEY"],
  ["PAYPAL_SANDBOX_NOT_CONFIGURED", "PAYPAL_SANDBOX_NOT_CONFIGURED"],
  ["PAYPAL_SANDBOX_AUTH_FAILED", "PAYPAL_SANDBOX_AUTH_FAILED"],
  ["PAYPAL_SANDBOX_PRODUCT_FAILED", "PAYPAL_SANDBOX_PRODUCT_FAILED"],
  ["PAYPAL_SANDBOX_PLAN_FAILED", "PAYPAL_SANDBOX_PLAN_FAILED"],
  ["PAYPAL_SANDBOX_CHECKOUT_FAILED", "PAYPAL_SANDBOX_CHECKOUT_FAILED"],
  ["PAYPAL_PATH_NOT_ALLOWED", "PAYPAL_SANDBOX_REQUEST_BLOCKED"],
  ["PAYPAL_METHOD_NOT_ALLOWED", "PAYPAL_SANDBOX_REQUEST_BLOCKED"],
]);

function sandboxBillingError(error) {
  const message = text(error?.message || error, "");
  const code = message.split(":")[0].trim();
  throw new Error(SANDBOX_RAISED_CODES.get(code) ?? "SANDBOX_BILLING_REQUEST_FAILED");
}

async function callSandboxBilling(admin, fn, args) {
  const { data, error } = await admin.rpc(fn, args);
  if (error) sandboxBillingError(error);
  return asRecord(data);
}

/**
 * "live" (default) or "sandbox". Live never touches the sandbox config.
 * Sandbox is never implicit: it needs the header, an explicit organization
 * header, and the organization on the server-side sandbox allowlist.
 */
export async function billingEnvironment(admin, req, organizationId) {
  const requested = text(req.headers.get(BILLING_ENVIRONMENT_HEADER)).toLowerCase();
  if (!requested || requested === "live") return "live";
  if (requested !== "sandbox") throw new Error("BILLING_ENVIRONMENT_INVALID");
  if (!text(req.headers.get("x-organization-id"))) throw new Error("BILLING_ORGANIZATION_REQUIRED");
  const { data, error } = await admin
    .from("pandora_runtime_provider_configs")
    .select("config_value")
    .eq("provider", "paypal")
    .eq("config_key", "sandbox_organization_ids")
    .eq("active", true)
    .maybeSingle();
  if (error || !data) throw new Error("BILLING_SANDBOX_NOT_ALLOWED");
  const allowed = new Set(
    text(asRecord(data).config_value).split(",").map((value) => value.trim()).filter(Boolean),
  );
  if (!organizationId || !allowed.has(organizationId)) throw new Error("BILLING_SANDBOX_NOT_ALLOWED");
  return "sandbox";
}

function sandboxMoney(micros) {
  const value = Number(micros);
  return Number.isFinite(value) ? (value / 1000000).toFixed(2) : null;
}

function sandboxTrust(status) {
  if (status === "active" || status === "cancelled") return "provider";
  if (status === "approval_pending") return "pending_action";
  if (status === "failed") return "failed";
  return "local_request";
}

/** Read-only sandbox status, shaped like the live status. */
export async function sandboxBillingStatus(admin, organizationId) {
  const [subscription, checkout, plans, bindings] = await Promise.all([
    admin.from("pandora_paypal_sandbox_subscriptions")
      .select("plan_id,state,currency,monthly_fee_micros,starts_on,ends_on,renews_on,source_kind,provider_reference,provider_status,verified_at,updated_at")
      .eq("organization_id", organizationId).eq("environment", "sandbox").maybeSingle(),
    admin.from("pandora_paypal_sandbox_billing_sessions")
      .select("id,plan_code,status,paypal_subscription_id,approval_url,expires_at,created_at,updated_at")
      .eq("organization_id", organizationId).eq("environment", "sandbox")
      .order("created_at", { ascending: false }).limit(1).maybeSingle(),
    admin.from("pandora_service_plans")
      .select("id,code,name,currency,monthly_fee_micros").eq("state", "active"),
    admin.from("pandora_paypal_catalog_bindings")
      .select("plan_code,paypal_plan_id").eq("environment", "sandbox"),
  ]);
  if (subscription.error || checkout.error || plans.error || bindings.error) {
    throw new Error("SANDBOX_BILLING_STATE_READ_FAILED");
  }
  const planRows = Array.isArray(plans.data) ? plans.data.map(asRecord) : [];
  const linked = new Set(
    (Array.isArray(bindings.data) ? bindings.data.map(asRecord) : [])
      .filter((row) => text(row.paypal_plan_id)).map((row) => text(row.plan_code)),
  );
  const sub = subscription.data ? asRecord(subscription.data) : null;
  const subPlan = sub ? planRows.find((plan) => String(plan.id) === String(sub.plan_id)) : null;
  const session = checkout.data ? asRecord(checkout.data) : null;
  return {
    environment: "sandbox",
    provider: { name: "paypal", environment: "sandbox", label: "PayPal sandbox" },
    subscription: sub ? {
      plan_id: sub.plan_id,
      plan_code: subPlan ? subPlan.code : null,
      plan_name: subPlan ? subPlan.name : null,
      state: sub.state,
      currency: sub.currency,
      monthly_fee: sandboxMoney(sub.monthly_fee_micros),
      monthly_fee_micros: sub.monthly_fee_micros,
      starts_on: sub.starts_on ?? null,
      ends_on: sub.ends_on ?? null,
      renews_on: sub.renews_on ?? null,
      source_kind: sub.source_kind,
      provider_reference: sub.provider_reference ?? null,
      provider_status: sub.provider_status ?? null,
      verified_at: sub.verified_at ?? null,
      updated_at: sub.updated_at ?? null,
      verification_label: sub.source_kind === "provider_verified" && sub.verified_at
        ? "Verified"
        : "Awaiting provider confirmation",
    } : null,
    plans: planRows
      .sort((a, b) => Number(a.monthly_fee_micros ?? Infinity) - Number(b.monthly_fee_micros ?? Infinity))
      .map((plan) => ({
        plan_id: plan.id,
        code: plan.code,
        name: plan.name,
        currency: plan.currency,
        monthly_fee: sandboxMoney(plan.monthly_fee_micros),
        monthly_fee_micros: plan.monthly_fee_micros,
        provider_linked: linked.has(text(plan.code)),
      })),
    pendingPlanChange: null,
    checkout: session ? {
      id: session.id,
      plan_code: session.plan_code,
      status: session.status,
      provider_reference: session.paypal_subscription_id ?? null,
      approval_url: session.approval_url ?? null,
      expires_at: session.expires_at ?? null,
      created_at: session.created_at,
      updated_at: session.updated_at,
      trust: sandboxTrust(text(session.status)),
    } : null,
    activity: [],
  };
}

export async function sandboxBillingCheckout(admin, context, body) {
  const planCode = text(body.planCode);
  const idempotencyKey = text(body.idempotencyKey);
  if (!/^[a-z][a-z0-9_-]{1,63}$/.test(planCode)) throw new Error("SANDBOX_PLAN_NOT_FOUND");
  return callSandboxBilling(admin, "pandora_plp_billing_sandbox_checkout_v1", {
    p_organization_id: context.organizationId,
    p_actor: context.userId,
    p_plan_code: planCode,
    p_idempotency_key: idempotencyKey,
  });
}

export async function sandboxBillingReconcile(admin, context) {
  return callSandboxBilling(admin, "pandora_plp_billing_sandbox_reconcile_v1", {
    p_organization_id: context.organizationId,
    p_actor: context.userId,
  });
}

/**
 * The sandbox cancel function reads PayPal first and returns its decision
 * (e.g. reason AWAITING_BUYER_APPROVAL with no POST /cancel while the buyer
 * has not approved). The reason is passed through unchanged.
 */
export async function sandboxBillingCancel(admin, context, body) {
  return callSandboxBilling(admin, "pandora_plp_billing_sandbox_cancel_v1", {
    p_organization_id: context.organizationId,
    p_actor: context.userId,
    p_reason: text(body.reason, "Cancelled by PLP owner").slice(0, 128),
  });
}

export function sandboxBillingChangePlan() {
  throw new Error("SANDBOX_PLAN_CHANGE_UNAVAILABLE");
}
