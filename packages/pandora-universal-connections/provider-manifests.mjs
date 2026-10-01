import { validateProviderManifest } from "../pandora-provider-sdk/index.mjs";

const VERSION = "1.0.0";
const DOC = "docs/connections/PANDORA_UNIVERSAL_CONNECTIONS_LANE_B.md";

function cap(capabilityKey, operationMode = "read", evidenceModes = ["provider_readback"]) {
  return { capabilityKey, operationMode, evidenceModes };
}

function requiresPartnerActivation(definition) {
  return definition.requestActivation === true || definition.riskClass === "regulated";
}

const definitions = [
  {
    providerKey: "twilio", displayName: "Twilio", family: "communications", priority: "P1",
    authType: "api_key", authScheme: "api_key_or_oauth", riskClass: "high",
    readScopes: ["account.identity.read", "number.inventory.read"], writeScopes: ["message.send", "call.create"],
    identityFields: ["accountSid"], displayFields: ["accountSid"], safeProbe: "communications.account.read", webhook: true,
    capabilities: [cap("communications.account.read"), cap("communications.number.read"), cap("communications.message.send", "write", ["provider_receipt", "delivery_readback"])],
  },
  {
    providerKey: "vonage", displayName: "Vonage", family: "communications", priority: "P1",
    authType: "api_key", authScheme: "api_key_or_oauth", riskClass: "high",
    readScopes: ["account.identity.read", "number.inventory.read"], writeScopes: ["message.send", "call.create"],
    identityFields: ["accountId"], displayFields: ["accountId"], safeProbe: "communications.account.read", webhook: true,
    capabilities: [cap("communications.account.read"), cap("communications.number.read"), cap("communications.message.send", "write", ["provider_receipt", "delivery_readback"])],
  },
  {
    providerKey: "maya", displayName: "Maya", family: "money", priority: "P1",
    authType: "service_credential", authScheme: "merchant_api_credentials", riskClass: "regulated",
    readScopes: ["merchant.identity.read"], writeScopes: ["payment.create", "refund.create"],
    identityFields: ["merchantId"], displayFields: ["merchantId"], safeProbe: "money.merchant.read", webhook: true,
    capabilities: [cap("money.merchant.read"), cap("money.webhook.receive"), cap("money.payment.create", "write", ["provider_receipt", "signed_webhook_readback"])],
  },
  {
    providerKey: "shopify", displayName: "Shopify", family: "commerce", priority: "P1",
    authType: "oauth2", authScheme: "oauth2_app_install", riskClass: "high",
    readScopes: ["read_products", "read_orders"], writeScopes: ["write_orders"],
    identityFields: ["shopId"], displayFields: ["shopDomain"], safeProbe: "commerce.store.read", webhook: true,
    capabilities: [cap("commerce.store.read"), cap("commerce.product.read"), cap("commerce.order.read"), cap("commerce.order.write", "write", ["provider_receipt", "order_readback"])],
  },
  {
    providerKey: "woocommerce", displayName: "WooCommerce", family: "commerce", priority: "P1",
    authType: "api_key", authScheme: "rest_api_key_or_oauth", riskClass: "high",
    readScopes: ["store.read", "order.read"], writeScopes: ["order.write"],
    identityFields: ["storeId"], displayFields: ["storeUrl"], safeProbe: "commerce.store.read", webhook: true,
    capabilities: [cap("commerce.store.read"), cap("commerce.product.read"), cap("commerce.order.read"), cap("commerce.order.write", "write", ["provider_receipt", "order_readback"])],
  },
  {
    providerKey: "xero", displayName: "Xero", family: "money", priority: "P1",
    authType: "oauth2", authScheme: "oauth2", riskClass: "regulated",
    readScopes: ["accounting.settings", "accounting.transactions", "offline_access"], writeScopes: ["accounting.transactions.write_step_up"],
    identityFields: ["tenantId"], displayFields: ["tenantName"], safeProbe: "finance.tenant.read",
    capabilities: [cap("finance.tenant.read"), cap("finance.ledger.read"), cap("finance.invoice.write", "write", ["provider_receipt", "invoice_readback"])],
  },
  {
    providerKey: "quickbooks", displayName: "QuickBooks Online", family: "money", priority: "P1",
    authType: "oauth2", authScheme: "oauth2", riskClass: "regulated",
    readScopes: ["com.intuit.quickbooks.accounting"], writeScopes: ["transaction.write"],
    identityFields: ["realmId"], displayFields: ["companyName"], safeProbe: "finance.company.read",
    capabilities: [cap("finance.company.read"), cap("finance.ledger.read"), cap("finance.transaction.write", "write", ["provider_receipt", "transaction_readback"])],
  },
  {
    providerKey: "google-ads", displayName: "Google Ads", family: "marketing", priority: "P1",
    authType: "oauth2", authScheme: "oauth2", riskClass: "high",
    readScopes: ["https://www.googleapis.com/auth/adwords"], writeScopes: ["campaign.write"],
    identityFields: ["customerId"], displayFields: ["loginCustomerId"], safeProbe: "marketing.customer.read",
    capabilities: [cap("marketing.customer.read"), cap("marketing.campaign.read"), cap("marketing.campaign.write", "write", ["provider_receipt", "campaign_readback"])],
  },
  {
    providerKey: "voluum", displayName: "Voluum", family: "marketing", priority: "P1",
    authType: "oauth2", authScheme: "oauth2_or_mcp", riskClass: "medium",
    readScopes: ["workspace.read", "report.read"], writeScopes: [],
    identityFields: ["workspaceId"], displayFields: ["workspaceId"], safeProbe: "marketing.workspace.read",
    capabilities: [cap("marketing.workspace.read"), cap("marketing.report.read")],
  },
  {
    providerKey: "grab", displayName: "Grab", family: "logistics", priority: "P1",
    authType: "service_credential", authScheme: "partner_api_credentials", riskClass: "high", requestActivation: true,
    readScopes: ["partner.identity.read", "quote.read", "booking.status.read"], writeScopes: ["booking.dispatch"],
    identityFields: ["partnerId"], displayFields: ["market"], safeProbe: "logistics.quote.read",
    capabilities: [cap("logistics.account.read"), cap("logistics.quote.read"), cap("logistics.booking.dispatch", "write", ["provider_receipt", "booking_readback"])],
  },
  {
    providerKey: "lalamove", displayName: "Lalamove", family: "logistics", priority: "P1",
    authType: "api_key", authScheme: "api_key_partner_auth", riskClass: "high", requestActivation: true,
    readScopes: ["account.identity.read", "quote.read", "tracking.read"], writeScopes: ["delivery.dispatch"],
    identityFields: ["accountId"], displayFields: ["market"], safeProbe: "logistics.quote.read",
    capabilities: [cap("logistics.account.read"), cap("logistics.quote.read"), cap("logistics.delivery.dispatch", "write", ["provider_receipt", "tracking_readback"])],
  },
  {
    providerKey: "docusign", displayName: "DocuSign", family: "documents", priority: "P1",
    authType: "oauth2", authScheme: "oauth2", riskClass: "regulated",
    readScopes: ["signature"], writeScopes: ["envelope.send"],
    identityFields: ["accountId"], displayFields: ["baseUri"], safeProbe: "documents.account.read",
    capabilities: [cap("documents.account.read"), cap("documents.envelope.read"), cap("documents.envelope.send", "write", ["provider_receipt", "envelope_readback"])],
  },
  {
    providerKey: "google-maps", displayName: "Google Maps / Places / Routes", family: "location", priority: "P1",
    authType: "api_key", authScheme: "restricted_api_key", riskClass: "medium",
    readScopes: ["places.read", "routes.read"], writeScopes: [],
    identityFields: ["projectId"], displayFields: ["projectId"], safeProbe: "location.place.read",
    capabilities: [cap("location.project.read"), cap("location.place.read"), cap("location.route.read")],
  },
  {
    providerKey: "aws", displayName: "Amazon Web Services", family: "compute", priority: "P1",
    authType: "workload_identity", authScheme: "cross_account_role", riskClass: "high",
    readScopes: ["sts.identity.read", "resource.inventory.read"], writeScopes: ["resource.mutate"],
    identityFields: ["accountId", "roleArn"], displayFields: ["accountId", "roleArn"], safeProbe: "cloud.account.read", workloadIdentity: true,
    capabilities: [cap("cloud.account.read"), cap("cloud.resource.read"), cap("cloud.resource.write", "write", ["provider_receipt", "resource_readback"])],
  },
  {
    providerKey: "google-cloud", displayName: "Google Cloud", family: "compute", priority: "P1",
    authType: "workload_identity", authScheme: "workload_identity_federation", riskClass: "high",
    readScopes: ["project.identity.read", "resource.inventory.read"], writeScopes: ["resource.mutate"],
    identityFields: ["projectId", "principal"], displayFields: ["projectId", "principal"], safeProbe: "cloud.project.read", workloadIdentity: true,
    capabilities: [cap("cloud.project.read"), cap("cloud.resource.read"), cap("cloud.resource.write", "write", ["provider_receipt", "resource_readback"])],
  },
  {
    providerKey: "azure", displayName: "Microsoft Azure", family: "compute", priority: "P1",
    authType: "workload_identity", authScheme: "entra_oidc_workload_identity", riskClass: "high",
    readScopes: ["tenant.identity.read", "subscription.inventory.read"], writeScopes: ["resource.mutate"],
    identityFields: ["tenantId", "subscriptionId", "principalId"], displayFields: ["tenantId", "subscriptionId"], safeProbe: "cloud.subscription.read", workloadIdentity: true,
    capabilities: [cap("cloud.tenant.read"), cap("cloud.subscription.read"), cap("cloud.resource.write", "write", ["provider_receipt", "resource_readback"])],
  },
  {
    providerKey: "enterprise-idp", displayName: "Enterprise identity provider", family: "identity", priority: "P1",
    authType: "oidc", authScheme: "oidc_saml_scim_admin", authVariants: ["oidc", "saml", "scim"], riskClass: "regulated",
    readScopes: ["tenant.identity.read", "user.directory.read"], writeScopes: ["user.lifecycle.write"],
    identityFields: ["issuer", "tenantId"], displayFields: ["issuer", "tenantId"], safeProbe: "identity.tenant.read",
    capabilities: [cap("identity.tenant.read"), cap("identity.user.read"), cap("identity.lifecycle.write", "write", ["provider_receipt", "directory_readback"])],
  },
  {
    providerKey: "device-pairing", displayName: "Device pairing / QR", family: "devices", priority: "P1",
    authType: "device_pairing", authScheme: "one_time_pairing_attestation", riskClass: "high",
    readScopes: ["device.identity.read", "device.heartbeat.read"], writeScopes: ["device.command.write"],
    identityFields: ["deviceId", "attestationId"], displayFields: ["deviceId"], safeProbe: "device.heartbeat.read",
    capabilities: [cap("device.identity.read"), cap("device.heartbeat.read"), cap("device.command.write", "write", ["device_receipt", "heartbeat_readback"])],
  },
  {
    providerKey: "local-ai", displayName: "Local / on-device AI", family: "intelligence", priority: "P1",
    authType: "device_pairing", authScheme: "device_pairing_model_inventory", riskClass: "medium",
    readScopes: ["model.inventory.read", "inference.test"], writeScopes: [],
    identityFields: ["deviceId", "modelId", "modelDigest"], displayFields: ["deviceId", "modelId"], safeProbe: "intelligence.inference.test",
    capabilities: [cap("intelligence.model.read"), cap("intelligence.inference.test")],
  },
  {
    providerKey: "custom-openapi", displayName: "Custom OpenAPI connector", family: "custom", priority: "P1",
    authType: "service_credential", authScheme: "wizard_selected_server_auth", authVariants: ["oauth2", "api_key", "service_credential"], riskClass: "high",
    readScopes: ["schema.read", "sandbox.read"], writeScopes: ["classified.operation.write"],
    identityFields: ["connectorId", "baseUrlOrigin", "schemaDigest"], displayFields: ["baseUrlOrigin"], safeProbe: "custom.sandbox.read", sandbox: true,
    capabilities: [cap("custom.schema.read"), cap("custom.sandbox.read"), cap("custom.operation.write", "write", ["provider_receipt", "operation_readback"])],
  },
  {
    providerKey: "mcp", displayName: "MCP connector", family: "custom", priority: "P1",
    authType: "service_credential", authScheme: "mcp_authorization", authVariants: ["oauth2", "api_key", "service_credential"], riskClass: "high",
    readScopes: ["tool.catalog.read", "tool.safe.read"], writeScopes: ["tool.write"],
    identityFields: ["serverId", "serverOrigin", "toolCatalogDigest"], displayFields: ["serverOrigin"], safeProbe: "mcp.tool.read", sandbox: true,
    capabilities: [cap("mcp.catalog.read"), cap("mcp.tool.read"), cap("mcp.tool.write", "write", ["provider_receipt", "tool_readback"])],
  },
  {
    providerKey: "file-sftp-email", displayName: "File / SFTP / email ingestion", family: "data", priority: "P2",
    authType: "service_credential", authScheme: "source_specific_ingestion_auth", authVariants: ["file", "sftp", "email"], riskClass: "high",
    readScopes: ["source.identity.read", "sample.read"], writeScopes: ["ingestion.schedule.write"],
    identityFields: ["sourceId", "sourceType"], displayFields: ["sourceType", "sourceId"], safeProbe: "ingestion.sample.read", sandbox: true,
    capabilities: [cap("ingestion.source.read"), cap("ingestion.sample.read"), cap("ingestion.schedule.write", "write", ["import_receipt", "row_count_readback"])],
  },
  {
    providerKey: "pldt-enterprise", displayName: "PLDT Enterprise", family: "telecom", priority: "P1",
    authType: "partner_activation", authScheme: "partner_activation", riskClass: "regulated", requestActivation: true,
    readScopes: ["account.identity.read", "service.inventory.read"], writeScopes: [],
    identityFields: ["enterpriseAccountId"], displayFields: ["enterpriseAccountId"], safeProbe: "telecom.account.read",
    capabilities: [cap("telecom.account.read"), cap("telecom.service.read")],
  },
  {
    providerKey: "smart", displayName: "Smart", family: "telecom", priority: "P1",
    authType: "partner_activation", authScheme: "partner_activation", riskClass: "regulated", requestActivation: true,
    readScopes: ["account.identity.read", "service.inventory.read"], writeScopes: [],
    identityFields: ["enterpriseAccountId"], displayFields: ["enterpriseAccountId"], safeProbe: "telecom.account.read",
    capabilities: [cap("telecom.account.read"), cap("telecom.service.read")],
  },
  {
    providerKey: "globe", displayName: "Globe Telecom", family: "telecom", priority: "P1",
    authType: "partner_activation", authScheme: "partner_activation", riskClass: "regulated", requestActivation: true,
    readScopes: ["account.identity.read", "service.inventory.read"], writeScopes: [],
    identityFields: ["enterpriseAccountId"], displayFields: ["enterpriseAccountId"], safeProbe: "telecom.account.read",
    capabilities: [cap("telecom.account.read"), cap("telecom.service.read")],
  },
  {
    providerKey: "dito", displayName: "DITO", family: "telecom", priority: "P2",
    authType: "partner_activation", authScheme: "partner_activation", riskClass: "regulated", requestActivation: true,
    readScopes: ["account.identity.read", "service.inventory.read"], writeScopes: [],
    identityFields: ["enterpriseAccountId"], displayFields: ["enterpriseAccountId"], safeProbe: "telecom.account.read",
    capabilities: [cap("telecom.account.read"), cap("telecom.service.read")],
  },
  {
    providerKey: "ubivelox-philippines", displayName: "Ubivelox Philippines", family: "identity", priority: "P1",
    authType: "partner_activation", authScheme: "partner_activation", riskClass: "regulated", requestActivation: true,
    readScopes: ["enterprise.identity.read", "capability.inventory.read"], writeScopes: ["card.personalization.write"],
    identityFields: ["enterpriseAccountId"], displayFields: ["enterpriseAccountId"], safeProbe: "identity.enterprise.read",
    capabilities: [cap("identity.enterprise.read"), cap("identity.capability.read"), cap("identity.card.write", "write", ["provider_receipt", "personalization_readback"])],
  },
  {
    providerKey: "government-regulated", displayName: "Government / regulated system", family: "government", priority: "P1",
    authType: "partner_activation", authScheme: "authority_evidence_plus_partner_activation", riskClass: "regulated", requestActivation: true,
    readScopes: ["authority.identity.read", "authorized.record.read"], writeScopes: [],
    identityFields: ["agencyId", "authorityId"], displayFields: ["agencyId"], safeProbe: "government.authority.read",
    capabilities: [cap("government.authority.read"), cap("government.record.read")],
  },
];

function makeAdapterManifest(definition) {
  return validateProviderManifest({
    providerKey: definition.providerKey,
    manifestVersion: VERSION,
    displayName: definition.displayName,
    authScheme: definition.authScheme,
    regions: ["provider_supported_regions"],
    dataResidency: ["tenant_policy_selected", "provider_contract_verified"],
    dataHandling: {
      credentialStorage: "server_side_vault_reference_only",
      clientSecretExposure: "forbidden",
      rawProviderPayloadLogging: "forbidden",
      accountBinding: "required",
    },
    deprecationPolicy: { mode: "explicit_versioned_migration", silentCapabilityRemoval: false },
    runbookRef: requiresPartnerActivation(definition)
      ? `${DOC}#request-activation-providers`
      : `${DOC}#generic-self-service-manifests`,
    escalationRef: `${DOC}#activation-and-escalation`,
    capabilities: definition.capabilities.map((item) => ({
      capabilityKey: item.capabilityKey,
      capabilityVersion: VERSION,
      operationMode: item.operationMode,
      adapterVersion: VERSION,
      evidenceModes: item.evidenceModes,
      ...(item.operationMode === "write"
        ? { idempotencyStrategy: "pandora_request_id_plus_exact_target" }
        : {}),
    })),
  });
}

function makeMetadata(definition) {
  const hasWrite = definition.capabilities.some((item) => item.operationMode === "write");
  const requestActivation = requiresPartnerActivation(definition);
  return {
    family: definition.family,
    priority: definition.priority,
    connectionMode: requestActivation ? "request_activation" : "self_service",
    auth: {
      type: requestActivation ? "partner_activation" : definition.authType,
      ...(!requestActivation && ["oauth2", "oidc"].includes(definition.authType) ? {
        pkce: { required: true, method: "S256" },
        state: { required: true, ttlSeconds: 300 },
        nonce: { required: true },
      } : {}),
    },
    authVariants: definition.authVariants ?? [definition.authScheme],
    scopes: {
      strategy: "read_first",
      read: definition.readScopes,
      write: definition.writeScopes,
    },
    callback: {
      webPath: `/connections/callback/${definition.providerKey}`,
      mobile: { secureBrowser: "custom_tab", returnModes: ["app_link", "universal_link"] },
    },
    accountIdentity: {
      stableSubjectFields: definition.identityFields,
      displayFields: definition.displayFields,
      tenantSelector: true,
      auditRequired: true,
    },
    health: {
      authority: "live_connections_runtime",
      safeReadCapability: definition.safeProbe,
      maxAgeSeconds: 900,
      identityReadback: true,
      scopesReadback: true,
      noCredentialOnlyConnectedState: true,
    },
    readiness: requestActivation ? {
      defaultCatalogState: "request_activation",
      serverConfigurationAuthority: "partner_verified_runtime_handoff",
      connectEnabledByDefault: false,
      blockedReason: "partner_activation_required",
    } : {
      defaultCatalogState: "implemented_awaiting_credential",
      serverConfigurationAuthority: "server_runtime_config_registry",
      connectEnabledByDefault: false,
      blockedReason: "server_configuration_missing",
    },
    credential: {
      storage: "server_vault_reference",
      clientExposure: "forbidden",
      rotateSupported: !requestActivation,
      revokeSupported: !requestActivation,
    },
    dataResidency: {
      enforcement: "tenant_policy",
      allowedPolicies: definition.riskClass === "regulated"
        ? ["contract_verified", "tenant_selected"]
        : ["provider_managed", "tenant_selected"],
    },
    riskClass: definition.riskClass,
    ui: {
      surface: "generic_connections_center",
      customProviderUi: false,
      primaryAction: requestActivation ? "request_activation" : "connect",
      primaryLabel: requestActivation ? "Request activation" : "Connect",
      connectButtonVisible: !requestActivation,
    },
    writePolicy: {
      enabled: hasWrite,
      stepUpApprovalRequired: hasWrite,
      exactTargetPreviewRequired: hasWrite,
      providerReadbackRequired: hasWrite,
    },
    webhookPolicy: {
      enabled: Boolean(definition.webhook),
      signatureRequired: Boolean(definition.webhook),
      timestampWindowRequired: Boolean(definition.webhook),
      replayDefenseRequired: Boolean(definition.webhook),
      idempotencyKeyRequired: Boolean(definition.webhook),
    },
    workloadIdentity: {
      preferred: Boolean(definition.workloadIdentity),
      longLivedKeysAllowedByDefault: false,
    },
    sandboxPolicy: {
      required: Boolean(definition.sandbox),
      readOnlyFirst: Boolean(definition.sandbox),
      operationClassificationRequired: Boolean(definition.sandbox),
    },
    activation: requestActivation ? {
      mode: "partner_case",
      publicConnectAllowed: false,
      authorityEvidenceRequired: true,
      providerContractRequired: true,
      providerReadbackRequiredBeforeRuntimeHandoff: true,
    } : null,
  };
}

function deepFreeze(value) {
  if (value && typeof value === "object") {
    for (const item of Object.values(value)) deepFreeze(item);
    if (!Object.isFrozen(value)) Object.freeze(value);
  }
  return value;
}

export const providerEntries = deepFreeze(definitions.map((definition) => ({
  providerKey: definition.providerKey,
  adapterManifest: makeAdapterManifest(definition),
  metadata: makeMetadata(definition),
})));

export const providerAdapterManifests = deepFreeze(providerEntries.map((entry) => entry.adapterManifest));

const byKey = new Map(providerEntries.map((entry) => [entry.providerKey, entry]));

export function getProviderEntry(providerKey) {
  return byKey.get(providerKey) ?? null;
}

export function listProviderEntries({ family, priority, connectionMode } = {}) {
  return providerEntries.filter((entry) =>
    (!family || entry.metadata.family === family)
    && (!priority || entry.metadata.priority === priority)
    && (!connectionMode || entry.metadata.connectionMode === connectionMode));
}
