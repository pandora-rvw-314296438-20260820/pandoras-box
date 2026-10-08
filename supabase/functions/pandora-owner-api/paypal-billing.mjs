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
