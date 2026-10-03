/**
 * Read-only owner commands over the authenticated Core projection.
 * A navigation context is a selector, never a grant. This module has no service
 * client, model adapter, outbound provider call, or business mutation path.
 */
type Row = Record<string, unknown>;
export type CoreRpcClient = {
  rpc(name: string, parameters: Record<string, unknown>): PromiseLike<{
    data: unknown;
    error: unknown;
  }>;
};

export type CoreChatScope = {
  context: Row | null;
  kind: "none" | "owner" | "client";
  targetOrganizationId: string | null;
  snapshot: Row | null;
};

type Navigation = {
  required: true;
  kind: "core_navigation";
  source: "core_navigation";
  request: string;
  label: string;
  section: "clients" | "business" | "platform" | "administration" | "home";
  action: "create_client" | "manage_users" | "prepare_proposal" | "inspect" | "return_owner";
  organizationId: string | null;
};

export type CoreOwnerReply = {
  reply: string;
  intent: "chat" | "act";
  confidence: number;
  needsClarification: false;
  clarifyingQuestion: null;
  conversationLane: "core_owner";
  handoff: Navigation | null;
  providerReadback: Row;
};

const row = (value: unknown): Row =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Row : {};
const text = (value: unknown): string => typeof value === "string" ? value.trim() : "";
const uuid = (value: string): boolean => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const sensitive = /(?:Bearer\s+\S+|Basic\s+[A-Za-z0-9+/=]{12,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]{20,}|sb_secret_[A-Za-z0-9_-]+|AIza[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|postgres(?:ql)?:\/\/|(?:authorization|api[_ -]?key|secret|password)\s*[:=])/i;
const label = (value: unknown, fallback: string): string => {
  const candidate = text(value);
  if (!candidate || sensitive.test(candidate)) return fallback;
  return candidate.replace(/[\r\n\t\u0000-\u001f\u007f]/g, " ").replace(/[\[\]<>`\\]/g, "").slice(0, 120);
};
const rows = (snapshot: Row, field: string): Row[] => {
  const values = snapshot[field];
  if (!Array.isArray(values) || values.length > 1000 || values.some((value) => value === null || typeof value !== "object" || Array.isArray(value))) {
    throw new Error("CORE_CONTEXT_UNAVAILABLE");
  }
  return values.map(row);
};

async function readSnapshot(user: CoreRpcClient, organizationId: string, section: string, target: string | null): Promise<Row> {
  let result;
  try {
    result = await user.rpc("pandora_core_snapshot_v1", { p_section: section, p_organization_id: target });
  } catch {
    throw new Error("CORE_CONTEXT_UNAVAILABLE");
  }
  if (result.error) {
    throw new Error(text(row(result.error).code) === "42501" ? "CORE_ACCESS_DENIED" : "CORE_CONTEXT_UNAVAILABLE");
  }
  const snapshot = row(result.data), operator = row(snapshot.operator);
  if (snapshot.schema_version !== "1" || !["owner", "operator", "support", "finance"].includes(text(operator.role)) ||
    !Number.isFinite(Date.parse(text(snapshot.generated_at))) || !uuid(text(operator.platform_organization_id))) {
    throw new Error("CORE_CONTEXT_UNAVAILABLE");
  }
  // Owner results must be persisted in an owner-scoped conversation, including
  // when the operator also happens to hold membership in a customer workspace.
  if (operator.platform_organization_id !== organizationId) throw new Error("CORE_SCOPE_MISMATCH");
  const clients = rows(snapshot, "clients");
  if (target && (clients.length !== 1 || clients[0].organization_id !== target)) throw new Error("CORE_ACCESS_DENIED");
  return snapshot;
}

export async function validateCoreChatScope(user: CoreRpcClient, organizationId: string, value: unknown): Promise<CoreChatScope> {
  const context = value == null ? null : row(value), selected = row(context?.selectedObject);
  const target = text(selected.organizationId) || null, entryId = text(selected.entryId);
  if ((target && !uuid(target)) || (entryId && !uuid(entryId))) throw new Error("CORE_SCOPE_MISMATCH");
  if (selected.coreMode === "owner") {
    if (entryId || context?.identityScope !== "pandora_organization" || !text(context?.route).startsWith("/enterprise/core/") ||
      !["home", "clients", "client", "business", "platform", "administration"].includes(text(selected.coreSection))) {
      throw new Error("CORE_SCOPE_MISMATCH");
    }
    const snapshot = await readSnapshot(user, organizationId, target ? "client" : "home", target);
    return { context, kind: "owner", targetOrganizationId: target, snapshot };
  }
  if (target && target !== organizationId) throw new Error("CORE_SCOPE_MISMATCH");
  if (entryId) {
    if (!target) throw new Error("CORE_SCOPE_MISMATCH");
    let result;
    try {
      result = await user.rpc("pandora_core_validate_entry_v1", { p_entry_id: entryId, p_organization_id: organizationId });
    } catch {
      throw new Error("CORE_CONTEXT_UNAVAILABLE");
    }
    if (result.error || result.data !== true) throw new Error("CORE_ENTRY_REQUIRED");
    return { context, kind: "client", targetOrganizationId: organizationId, snapshot: null };
  }
  return { context, kind: "none", targetOrganizationId: target, snapshot: null };
}

type Intent = "attention" | "onboarding" | "clients" | "connections" | "costs" | "local" | "deployments" | "providers" | "limits" | "create" | "proposal" | "team" | null;
function commandIntent(message: string): Intent {
  const m = message.toLowerCase();
  if (/\b(add|invite|give|grant|change|make|promote|demote|suspend|revoke|remove|restore)\b/.test(m) &&
    (/\b(admin(?:istrator)?s?|owners?|users?|members?|staff|access|roles?)\b/.test(m) || /\binvite\b/.test(m))) return "team";
  if (/\b(create|add|onboard|provision|register)\b/.test(m) && /\b(?:enterprise\s+)?(?:client|customer)\b/.test(m)) return "create";
  if (/\b(prepare|draft|create|write)\b/.test(m) && /\bproposal\b/.test(m)) return "proposal";
  if (/\b(client|customer|tenant)s?\b/.test(m) && /\b(onboard\w*|go[ -]?live)\b/.test(m)) return "onboarding";
  if (/\b(client|customer|tenant)s?\b/.test(m) && /\b(attention|blocked|unhealthy|needs?\s+(?:me|help))\b/.test(m)) return "attention";
  if (/\b(connection|integration)s?\b/.test(m) && /\b(fail\w*|broken|disconnect\w*|unhealthy|attention|reauthoriz\w*)\b/.test(m)) return "connections";
  if (/\b(local(?:ly)?|on[ -]device)\b/.test(m) && /\b(inference|ai|model|saving|savings)\b/.test(m)) return "local";
  if (/\b(provider|model)s?\b/.test(m) && /\b(expensive|costly|stop|reliability|outcomes?|better)\b/.test(m)) return "providers";
  if (/\b(allowance|budget|limits?)\b/.test(m) && /\b(client|customer|tenant|nearing|remaining|exceed\w*)s?\b/.test(m)) return "limits";
  if (/\b(cost|costs|spend|spent|usage|tokens?)\b/.test(m) && /\b(client|customer|tenant|ai|inference|model|month)s?\b/.test(m)) return "costs";
  if (/\b(deploy\w*|release|running)\b/.test(m) && /\b(what|which|show|why|version|sha|failed|production)\b/.test(m)) return "deployments";
  if (/\b(client|customer|tenant)s?\b/.test(m) && /\b(which|show|list|how|status|healthy)\b/.test(m)) return "clients";
  return null;
}

function navigation(section: Navigation["section"], action: Navigation["action"], caption: string, organizationId: string | null = null): Navigation {
  return { required: true, kind: "core_navigation", source: "core_navigation", request: caption, label: caption, section, action, organizationId };
}

function reply(content: string, snapshot: Row | null, handoff: Navigation | null = null): CoreOwnerReply {
  return {
    reply: content,
    intent: handoff ? "act" : "chat",
    confidence: 1,
    needsClarification: false,
    clarifyingQuestion: null,
    conversationLane: "core_owner",
    handoff,
    providerReadback: {
      source: "pandora_core_snapshot_v1",
      state: snapshot ? "authenticated_read" : "not_read",
      snapshotVerified: snapshot !== null,
      observedAt: snapshot ? text(snapshot.generated_at) : null,
      actionExecuted: false,
      ...(handoff ? { actionState: "awaiting_governed_ui" } : {}),
    },
  };
}

function clientMatch(message: string, clients: Row[]): Row[] {
  const normalized = ` ${message.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()} `;
  return clients.filter((client) => {
    const name = text(client.display_name).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
    const slug = text(client.slug).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
    const words = name.split(" ").filter(Boolean);
    const distinct = words.filter((word) => word.length >= 3 && !["the", "company", "group", "pandora", "enterprise"].includes(word));
    const word = distinct.find((value) => !/^\d+$/.test(value));
    const pair = word ? words.slice(words.indexOf(word), words.indexOf(word) + 2).join("") : "";
    const aliases = [name, slug, distinct[0], word, pair].filter((alias): alias is string => !!alias);
    return aliases.some((alias) => normalized.includes(` ${alias} `));
  });
}

function clientList(snapshot: Row, intent: Intent): string {
  const clients = rows(snapshot, "clients");
  const selected = clients.filter((client) => intent === "attention"
    ? client.health === "attention" || client.onboarding_state === "blocked" || client.lifecycle_state === "attention"
    : intent === "onboarding" ? client.onboarding_state !== "complete" && !["archived", "offboarding"].includes(text(client.lifecycle_state)) : true);
  if (!selected.length) return intent === "attention"
    ? "No client is currently flagged for owner attention in the recorded account state. Platform health remains dependent on current verification."
    : intent === "onboarding" ? "No incomplete client onboarding is recorded in this view." : "No Enterprise clients are registered in this view.";
  const heading = intent === "attention" ? "Clients needing attention" : intent === "onboarding" ? "Incomplete onboarding" : "Enterprise clients";
  return `${heading}: ${selected.length}.\n\n${selected.slice(0, 12).map((client) => {
    const state = intent === "onboarding" ? client.onboarding_state : intent === "attention" && client.onboarding_state === "blocked" ? "onboarding blocked" : client.health;
    return `• ${label(client.display_name, "Client")} — ${label(state, "unverified").replace(/_/g, " ")}; account ${label(client.lifecycle_state, "unverified")}.`;
  }).join("\n")}${selected.length > 12 ? "\nOpen Clients for the remaining records." : ""}`;
}

function failingConnections(snapshot: Row): string {
  const connections = rows(snapshot, "connections");
  const failed = connections.filter((connection) => connection.status === "needs_attention" ||
    ["unhealthy", "failed", "expired", "disconnected", "revoked"].includes(text(connection.health)));
  const unverified = connections.filter((connection) => !failed.includes(connection) && (connection.health !== "healthy" || connection.status !== "connected"));
  if (!connections.length) return "No live connection accounts are recorded in this view. Provider catalog entries do not establish a connection.";
  const heading = failed.length ? `${failed.length} connection${failed.length === 1 ? " needs" : "s need"} attention:` : "No failing connection is recorded in this view.";
  return `${heading}${failed.length ? `\n\n${failed.slice(0, 12).map((connection) => `• ${label(connection.client_name, "Account")} · ${label(connection.provider, "Provider")} — ${label(connection.health, "needs attention").replace(/_/g, " ")}.`).join("\n")}` : ""}${unverified.length ? `\n\n${unverified.length} other connection${unverified.length === 1 ? " is" : "s are"} awaiting current verification.` : ""}${failed.length > 12 ? "\nOpen Platform → Connections for the remaining records." : ""}`;
}

const integer = (value: unknown): bigint | null => {
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) return BigInt(value);
  if (typeof value === "string" && /^\d{1,25}$/.test(value)) return BigInt(value);
  return null;
};
const money = (micros: bigint, currency: string): string => {
  const fraction = (micros % 1000000n).toString().padStart(6, "0").replace(/0+$/, "").padEnd(2, "0");
  return `${currency} ${micros / 1000000n}.${fraction}`;
};
function usageRows(snapshot: Row): Row[] {
  return snapshot.usage !== undefined ? rows(snapshot, "usage") : rows(row(snapshot.business), "usage");
}
function costSummary(snapshot: Row): string {
  const clients = new Map(rows(snapshot, "clients").map((client) => [text(client.organization_id), label(client.display_name, "Client")]));
  const usage = usageRows(snapshot).filter((record) => clients.has(text(record.organization_id)));
  if (!usage.length) return "No customer AI usage is recorded for this month. This is an evidence gap, not a verified zero bill.";
  const groups = new Map<string, { name: string; currency: string; estimated: bigint | null; billed: bigint | null; requests: bigint; priced: bigint }>();
  for (const record of usage) {
    const currency = /^[A-Z]{3}$/.test(text(record.currency)) ? text(record.currency) : "";
    const key = `${record.organization_id}:${currency}`;
    const group = groups.get(key) ?? { name: clients.get(text(record.organization_id))!, currency, estimated: null, billed: null, requests: 0n, priced: 0n };
    const estimated = integer(record.estimated_cost_micros), billed = integer(record.billed_cost_micros);
    const requests = integer(record.requests), priced = integer(record.requests_with_cost);
    if (requests === null || priced === null || priced > requests) throw new Error("CORE_CONTEXT_UNAVAILABLE");
    if (estimated !== null && currency) group.estimated = (group.estimated ?? 0n) + estimated;
    if (billed !== null && currency) group.billed = (group.billed ?? 0n) + billed;
    group.requests += requests;
    group.priced += priced;
    groups.set(key, group);
  }
  const ordered = [...groups.values()].sort((a, b) => a.currency.localeCompare(b.currency) ||
    ((a.estimated ?? -1n) === (b.estimated ?? -1n) ? a.name.localeCompare(b.name) : (a.estimated ?? -1n) > (b.estimated ?? -1n) ? -1 : 1));
  return `Recorded customer AI usage this month:\n\n${ordered.slice(0, 12).map((group) => {
    const estimate = group.estimated === null ? "estimate unavailable" : `${money(group.estimated, group.currency)} estimated${group.priced < group.requests ? " (partial coverage)" : ""}`;
    const billed = group.billed === null ? "billed cost unverified" : `${money(group.billed, group.currency)} reconciled billed cost`;
    return `• ${group.name} — ${estimate}; ${billed}; ${group.requests} recorded requests.`;
  }).join("\n")}\n\nCurrencies are kept separate. Recorded runs may not cover all provider charges.${ordered.length > 12 ? " Open Business → Usage & Costs for the remaining records." : ""}`;
}

function deploymentSummary(snapshot: Row, message: string): string {
  const deployments = rows(snapshot, "deployments");
  if (!deployments.length) return "No deployment evidence is recorded in this view. The running source version is unverified.";
  const failedQuestion = /\b(why|cause)\b/i.test(message);
  const lines = deployments.slice(0, 8).map((deployment) => {
    const commit = /^[0-9a-f]{40}$/i.test(text(deployment.source_commit_sha)) ? text(deployment.source_commit_sha).slice(0, 12) : "source unknown";
    const state = deployment.evidence_state === "stale" ? "stale provider evidence" : deployment.evidence_state === "source_unbound" ? "source not linked" : "provider evidence only";
    return `• ${label(deployment.provider, "Provider")} · ${label(deployment.environment, "environment unknown")} — ${label(deployment.status, "unknown")}; ${commit}; ${state}.`;
  });
  return `${failedQuestion ? "These records do not establish a verified cause for the failure.\n\n" : ""}Recorded deployments:\n\n${lines.join("\n")}\n\nA recorded build or merge does not prove which version is serving customers. Open Platform → Deployments for verification evidence.`;
}

function providerSummary(snapshot: Row): string {
  const metrics = rows(snapshot, "models"), measured = metrics.filter((metric) => metric.evidence_state === "measured");
  const detail = measured.length ? `\n\nRecent recorded outcomes:\n${measured.slice(0, 6).map((metric) => `• ${label(metric.provider, "Provider")} · ${label(metric.capability, "capability")} — ${integer(metric.success_count)?.toString() ?? "unknown"} verified successes; ${integer(metric.failure_count)?.toString() ?? "unknown"} verified failures.`).join("\n")}` : " Recent comparable outcome evidence is unavailable or stale.";
  return `I cannot support a stop-or-switch recommendation from cost alone. This view does not yet link comparable outcomes with reconciled provider costs.${detail}\n\nAuto routing remains unchanged. No paid model probe was run.`;
}

function allowanceSummary(snapshot: Row): string {
  if (snapshot.usage_allowances === undefined) return "Remaining allowance is not yet reconciled with recorded usage in this view. Open Business to review configured limits and recorded costs.";
  const allowances = rows(snapshot, "usage_allowances");
  const approaching: string[] = [];
  let comparable = 0;
  for (const allowance of allowances) {
    if (allowance.subscription_state !== "active") continue;
    for (const [measure, limitField, recordedField] of [["requests", "request_limit", "requests_recorded"], ["tokens", "token_limit", "tokens_recorded"]]) {
      const limit = integer(allowance[limitField]), recorded = integer(allowance[recordedField]);
      if (limit === null || recorded === null) continue;
      comparable += 1;
      // Eighty percent is an explicit display threshold, not an execution quota.
      if ((limit > 0n && recorded * 100n >= limit * 80n) || (limit === 0n && recorded > 0n)) {
        approaching.push(`• ${label(allowance.client_name, "Client")} — ${recorded} of ${limit} ${measure} recorded${limit > 0n ? ` (${recorded * 100n / limit}%)` : "; configured limit is zero"}.`);
      }
    }
  }
  if (!comparable) return "No active customer allowance can be compared with recorded usage yet. Open Business to configure terms and inspect the available usage evidence.";
  return `${approaching.length ? `Recorded usage at or above 80% of a configured limit:\n\n${approaching.slice(0, 12).join("\n")}` : "No recorded request or token total reaches 80% of its configured limit in this view."}\n\nOnly recorded model runs are included. Missing telemetry can understate consumption; this does not establish remaining billed allowance or an enforced execution quota.`;
}

/** Returns null only when the normal chat/team lanes should handle the request. */
export async function tryCoreOwnerCommand(user: CoreRpcClient, organizationId: string, message: string, scope: CoreChatScope): Promise<CoreOwnerReply | null> {
  const intent = commandIntent(message);
  if (!intent) return null;
  if (scope.kind === "client") {
    return reply("Return to Pandora to manage Enterprise accounts. This conversation is scoped to the client workspace.", null,
      navigation("home", "return_owner", "Return to Pandora"));
  }
  const clientAccessWording = /\b(client|customer|tenant|enterprise)\b|\b(?:another|additional|new)\s+admin(?:istrator)?\b|\b(?:to|for|in)\s+(?!(?:the\s+)?(?:team|organization|workspace|owner|admin|operator|member|viewer)\b)[A-Za-z0-9]/i.test(message);
  const section = ["connections", "costs", "local", "deployments", "providers", "limits"].includes(intent) ? "platform" : intent === "proposal" ? "business" : "clients";
  let snapshot: Row;
  try {
    snapshot = scope.snapshot && ["clients", "team", "create", "attention", "onboarding"].includes(intent)
      ? scope.snapshot : await readSnapshot(user, organizationId, section, scope.kind === "owner" ? scope.targetOrganizationId : null);
  } catch (error) {
    // Preserve ordinary member administration in an independently authenticated
    // tenant, but never let client-targeted wording fall into the current org's
    // pending invitation flow when owner authority cannot be established.
    if (intent === "team" && scope.kind === "none" && !clientAccessWording && /\b(?:this|current|our|my)\s+(?:team|workspace|organization)\b/i.test(message)) return null;
    if (error instanceof Error && error.message === "CORE_ACCESS_DENIED") {
      return reply("Pandora operator access is required for that owner view. Open your authorized workspace to continue.", null);
    }
    if (error instanceof Error && error.message === "CORE_SCOPE_MISMATCH") {
      return reply("Return to Pandora before opening owner controls. The current conversation belongs to a client workspace.", null,
        navigation("home", "return_owner", "Return to Pandora"));
    }
    return reply("Pandora could not load the owner records. Please retry from the relevant Core screen; no account changes were made.", null);
  }
  const target = scope.kind === "owner" ? scope.targetOrganizationId : null;
  if (["costs", "limits", "proposal"].includes(intent) && !["owner", "operator", "finance"].includes(text(row(snapshot.operator).role))) {
    return reply("Commercial access is required to inspect customer costs, limits or proposals.", null);
  }
  if (intent === "create") return reply("Open Clients → Add Enterprise Client to register the business and resume its verified onboarding steps.", snapshot,
    navigation("clients", "create_client", "Add Enterprise Client"));
  if (intent === "proposal") return reply("Open Business → Pipeline to select the prospect and prepare the proposal with its commercial records. Nothing has been sent.", snapshot,
    navigation("business", "prepare_proposal", "Prepare proposal", target));
  if (intent === "team") {
    const matches = clientMatch(message, rows(snapshot, "clients"));
    if (matches.length > 1) return reply("Select the client in Clients before changing access. This request matches more than one customer.", snapshot,
      navigation("clients", "inspect", "Choose client"));
    const client = matches[0] ?? (target ? rows(snapshot, "clients")[0] : null);
    if (target && matches[0] && matches[0].organization_id !== target) throw new Error("CORE_SCOPE_MISMATCH");
    if (client) return reply(`Open ${label(client.display_name, "the client")} → Manage Client → Users to review the person, role and authorization. No access has changed.`, snapshot,
      navigation("clients", "manage_users", "Manage client users", text(client.organization_id)));
    if (clientAccessWording) return reply("Choose the client in Clients, then open Manage Client → Users. No access has changed.", snapshot,
      navigation("clients", "inspect", "Choose client"));
    if (scope.kind !== "owner") return null;
    return reply("Open Administration → Team & Access to review and change Pandora team access.", snapshot,
      navigation("administration", "manage_users", "Manage Pandora team"));
  }
  if (["attention", "onboarding", "clients"].includes(intent)) return reply(clientList(snapshot, intent), snapshot,
    navigation("clients", "inspect", "Open Clients", target));
  if (intent === "connections") return reply(failingConnections(snapshot), snapshot,
    navigation("platform", "inspect", "Inspect connections", target));
  if (intent === "costs") return reply(costSummary(snapshot), snapshot,
    navigation("business", "inspect", "Usage & Costs", target));
  if (intent === "local") return reply("A verified local-versus-cloud inference share and billed savings are not available in these records. Device phase events alone cannot establish that comparison.", snapshot,
    navigation("platform", "inspect", "Inspect usage evidence", target));
  if (intent === "deployments") return reply(deploymentSummary(snapshot, message), snapshot,
    navigation("platform", "inspect", "Inspect deployments", target));
  if (intent === "providers") return reply(providerSummary(snapshot), snapshot,
    navigation("platform", "inspect", "Inspect models & routing", target));
  return reply(allowanceSummary(snapshot), snapshot,
    navigation("business", "inspect", "Review limits", target));
}
