const RISK = {
  read: { label: "READ", className: "read" },
  write: { label: "WRITE", className: "write" },
  destructive: { label: "DESTRUCTIVE", className: "destructive" },
};

const TOOL_ROWS = [
  ["github.get-repository", "read", false, "repository", "repositories:read", "", false, "Get repository", "Get a GitHub repository by owner and name"],
  ["github.list-repositories", "read", false, "account", "repositories:read", "", false, "List repositories", "List GitHub repositories filtered to the allowlist"],
  ["github.get-issue", "read", false, "repository", "issues:read", "", false, "Get issue", "Get a GitHub issue by number"],
  ["github.list-issues", "read", false, "repository", "issues:read", "", false, "List issues", "List GitHub issues"],
  ["github.create-issue", "write", true, "repository", "issues:write", "", false, "Create issue", "Create a new GitHub issue"],
  ["github.update-issue", "write", true, "repository", "issues:write", "", false, "Update issue", "Update a GitHub issue"],
  ["github.get-pull-request", "read", false, "repository", "pull_requests:read", "", false, "Get pull request", "Get a GitHub pull request by number"],
  ["github.list-pull-requests", "read", false, "repository", "pull_requests:read", "", false, "List pull requests", "List GitHub pull requests"],
  ["github.create-pull-request", "write", true, "repository", "pull_requests:write", "", false, "Create pull request", "Create a new GitHub pull request"],
  ["github.merge-pull-request", "destructive", true, "repository", "pull_requests:write", "", false, "Merge pull request", "Merge a GitHub pull request"],
  ["github.list-workflow-runs", "read", false, "repository", "workflows:read", "", false, "List workflow runs", "List GitHub Actions workflow runs"],
  ["github.get-workflow-run", "read", false, "repository", "workflows:read", "", false, "Get workflow run", "Get one GitHub Actions workflow run by ID"],
  ["github.search-repositories", "read", false, "account", "repositories:read", "", false, "Search repositories", "Search GitHub repositories"],
  ["github.search-issues", "read", false, "account", "issues:read,pull_requests:read", "", false, "Search issues", "Search GitHub issues"],
  ["github.get-me", "read", false, "account", "identity:read", "", false, "Get connected identity", "Get current GitHub user information"],
  ["github.read-repository-api", "read", false, "repository", "repositories:read", "github-repository-api", false, "Repository API read", "Call any GET or HEAD GitHub REST endpoint under one allowlisted repository"],
  ["github.write-repository-api", "write", true, "repository", "repositories:write", "github-repository-api", true, "Repository API write", "Call any POST, PUT, or PATCH GitHub REST endpoint under one allowlisted repository"],
  ["github.delete-repository-api", "destructive", true, "repository", "repositories:write", "github-repository-api", true, "Repository API delete", "Call any DELETE GitHub REST endpoint under one allowlisted repository"],
  ["supabase.list-accounts", "read", false, "account", "", "", false, "List connections", "List configured Supabase account connections without exposing credentials"],
  ["supabase.list-organizations", "read", false, "account", "organizations:read", "", false, "List organizations", "List organizations visible to one configured Supabase account"],
  ["supabase.list-projects", "read", false, "organization", "projects:read", "", false, "List projects", "List projects visible to one configured Supabase account"],
  ["supabase.get-project", "read", false, "project", "projects:read", "", false, "Get project", "Get one exact Supabase project through a selected account"],
  ["supabase.get-auth-security-config", "read", false, "project", "auth:read", "", false, "Check leaked-password protection", "Read only whether leaked-password protection is enabled for one allowlisted project"],
  ["supabase.enable-leaked-password-protection", "write", true, "project", "auth:read,auth:write", "", false, "Enable leaked-password protection", "Reject known leaked passwords for one allowlisted Supabase project"],
  ["supabase.pause-project", "destructive", true, "project", "projects:write", "", false, "Pause project", "Pause one exact Supabase project"],
  ["supabase.restore-project", "write", true, "project", "projects:write", "", false, "Restore project", "Restore one exact paused Supabase project"],
  ["supabase.read-project-api", "read", false, "project", "projects:read", "supabase-project-api", false, "Project API read", "Call any GET or HEAD Management API endpoint under one allowlisted project"],
  ["supabase.write-project-api", "write", true, "project", "projects:write", "supabase-project-api", true, "Project API write", "Call any POST, PUT, or PATCH Management API endpoint under one allowlisted project"],
  ["supabase.delete-project-api", "destructive", true, "project", "projects:write", "supabase-project-api", true, "Project API delete", "Call any DELETE Management API endpoint under one allowlisted project"],
  ["supabase.read-organization-api", "read", false, "organization", "organizations:read", "supabase-organization-api", false, "Organization API read", "Call any GET or HEAD Management API endpoint under one allowlisted organization"],
  ["supabase.write-organization-api", "write", true, "organization", "organizations:write", "supabase-organization-api", true, "Organization API write", "Call any POST, PUT, or PATCH Management API endpoint under one allowlisted organization"],
  ["supabase.delete-organization-api", "destructive", true, "organization", "organizations:write", "supabase-organization-api", true, "Organization API delete", "Call any DELETE Management API endpoint under one allowlisted organization"],
  ["supabase.read-branch-api", "read", false, "branch", "projects:read", "supabase-branch-api", false, "Branch API read", "Call any GET or HEAD Management API endpoint under a verified branch"],
  ["supabase.write-branch-api", "write", true, "branch", "projects:write", "supabase-branch-api", false, "Branch API write", "Call any POST, PUT, or PATCH Management API endpoint under a verified branch"],
  ["supabase.delete-branch-api", "destructive", true, "branch", "projects:write", "supabase-branch-api", false, "Branch API delete", "Call any DELETE Management API endpoint under a verified branch"],
];

const TOOLS = TOOL_ROWS.map(([name, risk, mutation, scope, scopes, confirmationKind, highImpact, label, description]) => ({
  name, risk, mutation, scope, scopes: scopes ? scopes.split(",") : [], confirmationKind, highImpact, label, description,
  provider: name.split(".")[0],
}));

const CONNECTIONS = [];

const PLANS = [];
const AUDIT = [];

const state = {
  route: "home",
  theme: localStorage.getItem("mcpmaster-theme") || "dark",
  density: localStorage.getItem("mcpmaster-density") || "comfortable",
  mode: "connecting",
  apiBase: "/api/operator",
  query: "",
  filters: { provider: "", risk: "", availability: "" },
  planFilter: "all",
  auditQuery: "",
  sheet: null,
  toast: null,
  live: { projectos: null, health: null, metrics: null, tools: null, connections: null, plans: null, logs: null, chain: null, error: null },
  builder: { step: 0, tool: null, connectionKey: "", target: "", owner: "", repo: "", projectRef: "", organizationSlug: "", branchIdOrRef: "", method: "PATCH", pathSegments: "", title: "", body: "", pullNumber: "", mergeMethod: "squash", hash: "", result: null },
};

const ROUTES = {
  home: ["ProjectOS", "Portfolio roadmap and autonomous continuation"],
  actions: ["Manual Actions", "Emergency and operator-initiated provider operations"],
  builder: ["Action Builder", "Plan → approve → execute once"],
  plans: ["Plans", "Durable execution lifecycle"],
  approvals: ["Approval Center", "Owner/admin review and exact confirmation"],
  connections: ["Connections", "Vault-backed accounts, scopes and allowlists"],
  audit: ["Audit Trail", "Tamper-evident execution history"],
  security: ["Security Center", "Identity, policy and boundary state"],
  operations: ["Operations", "Production runtime and recovery"],
  settings: ["Settings", "Display and control-plane connection"],
  more: ["More", "Governance and operator tools"],
};

const app = document.querySelector("#app");
document.documentElement.dataset.theme = state.theme;
document.documentElement.dataset.density = state.density;

function esc(value) {
  return String(value ?? "").replace(/[&<>'"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
}

function short(value, length = 12) {
  const string = String(value || "");
  return string.length > length ? `${string.slice(0, Math.max(4, length - 5))}…${string.slice(-4)}` : string;
}

function timeAgo(timestamp) {
  const seconds = Math.max(0, Math.round((Date.now() - timestamp) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  return `${Math.floor(seconds / 3600)}h ago`;
}

function expiry(plan) {
  const ms = plan.expiresAt - Date.now();
  if (!["pending_approval", "approved"].includes(plan.status)) return "closed";
  if (ms <= 0) return "expired — recreate";
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.floor((ms % 60000) / 1000);
  return `expires in ${minutes}m ${String(seconds).padStart(2, "0")}s`;
}

function badge(label, className = "neutral") {
  return `<span class="badge ${className}">${esc(label)}</span>`;
}

function track(name, properties = {}) {
  console.info(JSON.stringify({ event: "product_event", name, route: state.route, ...properties }));
}

function toast(title, detail, kind = "healthy") {
  state.toast = { title, detail, kind };
  render();
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { state.toast = null; render(); }, 4200);
}

function setRoute(route) {
  state.route = route;
  state.sheet = null;
  track(route === "home" ? "command_center_viewed" : "route_viewed", { destination: route });
  window.scrollTo({ top: 0, behavior: "smooth" });
  render();
}

function scopedConnections(tool) {
  return CONNECTIONS.filter((connection) => (
    connection.provider === tool.provider
    && tool.scopes.every((scope) => connection.scopes.includes(scope))
  ));
}

function eligibleConnections(tool) {
  return scopedConnections(tool).filter((connection) => !tool.mutation || connection.mutations);
}

function executableConnections(tool) {
  return eligibleConnections(tool).filter((connection) => connectionTargets(connection, tool).length > 0);
}

function connectionFor(tool) {
  return executableConnections(tool)[0];
}

function connectionTargets(connection, tool) {
  if (!connection || !tool) return [];
  if (tool.provider === "github") {
    return tool.scope === "account" ? connection.targets.accounts : connection.targets.repositories;
  }
  if (tool.scope === "organization") return connection.targets.organizations;
  if (tool.scope === "project" || tool.scope === "branch") return connection.targets.projects;
  return connection.targets.accounts;
}

function allConnectionTargets(connection) {
  return [...new Set(Object.values(connection?.targets || {}).flat())];
}

function connectionKey(connection) {
  return connection ? `${connection.provider}:${connection.id}` : "";
}

function connectionByKey(key) {
  return CONNECTIONS.find((connection) => connectionKey(connection) === key);
}

function toolAvailability(tool) {
  const connection = connectionFor(tool);
  const scoped = scopedConnections(tool);
  const eligible = eligibleConnections(tool);
  if (!connection && tool.mutation && scoped.length > 0 && eligible.length === 0) {
    return { available: false, reason: "The provider mutation switch is disabled on every scoped connection." };
  }
  if (!connection && eligible.length > 0) {
    return { available: false, reason: "No scoped connection has an allowlisted target for this action." };
  }
  if (!connection) return { available: false, reason: `No ${tool.provider} connection grants ${tool.scopes.join(", ") || "the required account access"}.` };
  return { available: true, reason: "Available through an allowlisted connection." };
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => [key, stable(item)]));
  return value;
}

async function payloadHash(tool, args) {
  const canonical = JSON.stringify({ tool, args: stable(args) });
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function builderArgs() {
  const b = state.builder;
  const tool = b.tool;
  if (!tool) return {};
  const args = {};
  if (tool.provider === "github") {
    const [ownerFromTarget, repoFromTarget] = (b.target || "").split("/");
    if (ownerFromTarget) args.owner = ownerFromTarget;
    if (repoFromTarget) args.repo = repoFromTarget;
  }
  if (tool.provider === "supabase") {
    const connection = connectionByKey(b.connectionKey);
    if (tool.name !== "supabase.list-accounts" && connection) args.accountId = connection.account;
    if (tool.scope === "organization") args.organizationSlug = b.organizationSlug || b.target;
    if (tool.scope === "project" || tool.scope === "branch") args.projectRef = b.projectRef || b.target;
    if (tool.scope === "branch") args.branchIdOrRef = b.branchIdOrRef;
  }
  if (tool.confirmationKind) {
    args.method = tool.risk === "destructive" ? "DELETE" : b.method;
    args.pathSegments = b.pathSegments.split("/").map((part) => part.trim()).filter(Boolean);
  }
  if (tool.name === "github.create-issue") { args.title = b.title; if (b.body) args.body = b.body; }
  if (tool.name === "github.merge-pull-request") { args.pullNumber = Number(b.pullNumber); args.mergeMethod = b.mergeMethod; }
  if (tool.name === "supabase.pause-project") args.confirmation = `PAUSE ${args.projectRef}`;
  if (tool.name === "supabase.restore-project") args.confirmation = `RESTORE ${args.projectRef}`;
  if (tool.name === "supabase.enable-leaked-password-protection") {
    args.enabled = true;
    args.confirmation = `ENABLE LEAKED PASSWORD PROTECTION ${args.projectRef}`;
  }
  return Object.fromEntries(Object.entries(args).filter(([, value]) => value !== "" && value !== undefined && !(Number.isNaN(value))));
}

function expectedConfirmation(tool, args) {
  if (!tool) return "";
  if (tool.name === "supabase.pause-project") return `PAUSE ${args.projectRef || ""}`.trim();
  if (tool.name === "supabase.restore-project") return `RESTORE ${args.projectRef || ""}`.trim();
  if (tool.name === "supabase.enable-leaked-password-protection") return `ENABLE LEAKED PASSWORD PROTECTION ${args.projectRef || ""}`.trim();
  if (!tool.confirmationKind || !tool.mutation) return "";
  const method = tool.risk === "destructive" ? "DELETE" : args.method;
  const suffix = args.pathSegments?.length ? `/${args.pathSegments.join("/")}` : "";
  if (tool.confirmationKind === "github-repository-api") return method && args.owner && args.repo ? `${method} ${args.owner}/${args.repo}${suffix}` : "";
  if (tool.confirmationKind === "supabase-project-api") return method && args.projectRef ? `${method} PROJECT ${args.projectRef}${suffix}` : "";
  if (tool.confirmationKind === "supabase-organization-api") return method && args.organizationSlug ? `${method} ORGANIZATION ${args.organizationSlug}${suffix}` : "";
  if (tool.confirmationKind === "supabase-branch-api") return method && args.projectRef && args.branchIdOrRef ? `${method} BRANCH ${args.projectRef}:${args.branchIdOrRef}${suffix}` : "";
  return "";
}

function highImpactReason(tool, args) {
  if (!tool?.highImpact || !tool.mutation) return "";
  const segments = (args.pathSegments || []).map((value) => String(value).toLowerCase());
  const path = segments.join("/");
  if (tool.provider === "github") {
    if (tool.risk === "destructive" && segments.length === 0) return "repository deletion";
    if (segments[0] === "transfer") return "repository transfer";
    if (path.startsWith("actions/permissions")) return "GitHub Actions permission changes";
    if (segments.includes("secrets")) return "repository or environment secret changes";
    if (path.endsWith("/protection") && tool.risk === "destructive") return "branch-protection removal";
  } else {
    if (tool.scope === "project" && tool.risk === "destructive" && segments.length === 0) return "Supabase project deletion";
    if (tool.scope === "organization" && tool.risk === "destructive" && segments.length === 0) return "Supabase organization deletion";
    if (segments.some((value) => ["secrets", "api-keys", "password"].includes(value))) return "Supabase credential or secret changes";
    if (path.includes("network-restrictions") || path.includes("ssl-enforcement")) return "Supabase network-security changes";
  }
  return "";
}

function targetForPlan(tool, args = {}) {
  if (tool?.provider === "github") {
    const repository = [args.owner, args.repo].filter(Boolean).join("/");
    return args.pullNumber ? `${repository}#${args.pullNumber}` : repository || "GitHub account";
  }
  if (tool?.scope === "organization") return args.organizationSlug || "Supabase organization";
  if (tool?.scope === "branch") return [args.projectRef, args.branchIdOrRef].filter(Boolean).join(":") || "Supabase branch";
  return args.projectRef || "Supabase account";
}

function replaceConnectionsFromLive(payload) {
  const connections = Array.isArray(payload?.connections) ? payload.connections : [];
  CONNECTIONS.splice(0, CONNECTIONS.length, ...connections.map((connection) => ({
    id: String(connection.id || ""),
    provider: connection.provider === "github" ? "github" : "supabase",
    label: String(connection.label || connection.id || "Provider connection"),
    account: String(connection.account || connection.id || ""),
    healthy: true,
    mutations: connection.mutations === true,
    lastSuccess: "Live catalog",
    installation: "Vault-backed control catalog",
    scopes: Array.isArray(connection.scopes) ? connection.scopes.map(String) : [],
    targets: {
      accounts: Array.isArray(connection.targets?.accounts) ? connection.targets.accounts.map(String) : [],
      repositories: Array.isArray(connection.targets?.repositories) ? connection.targets.repositories.map(String) : [],
      organizations: Array.isArray(connection.targets?.organizations) ? connection.targets.organizations.map(String) : [],
      projects: Array.isArray(connection.targets?.projects) ? connection.targets.projects.map(String) : [],
    },
  })).filter((connection) => connection.id && connection.account));
}

function replacePlansFromLive(payload) {
  const plans = Array.isArray(payload?.plans) ? payload.plans : [];
  PLANS.splice(0, PLANS.length, ...plans.map((remote) => {
    const tool = TOOLS.find((item) => item.name === remote.tool);
    const args = remote.args && typeof remote.args === "object" ? remote.args : {};
    return {
      id: remote.planId,
      requestId: remote.requestId,
      tool: remote.tool,
      risk: remote.risk,
      status: remote.status,
      target: targetForPlan(tool, args),
      args,
      createdAt: Date.parse(remote.createdAt || "") || Date.now(),
      expiresAt: Date.parse(remote.expiresAt || "") || Date.now(),
      payloadHash: remote.payloadHash,
      terminalOutcome: remote.terminalOutcome && typeof remote.terminalOutcome === "object"
        ? remote.terminalOutcome
        : null,
      reversible: remote.risk !== "destructive",
      confirmation: expectedConfirmation(tool, args),
    };
  }));
}

function auditDetail(event) {
  const details = event?.details && typeof event.details === "object" ? event.details : {};
  if (typeof details.error === "string") return details.error;
  if (typeof details.reason === "string") return details.reason;
  if (typeof details.approvedBy === "string") return `Approved by ${details.approvedBy}.`;
  if (typeof details.expiresAt === "string") return `Durable plan expires ${details.expiresAt}.`;
  if (event?.planId) return `Durable plan ${short(event.planId)} changed state.`;
  return "Sanitized control-plane event recorded.";
}

function replaceAuditFromLive(payload) {
  const events = Array.isArray(payload?.events) ? payload.events : [];
  AUDIT.splice(0, AUDIT.length, ...events.map((event, index) => ({
    seq: event.sequence ?? events.length - index,
    event: event.eventType || "runtime_event",
    status: event.status || "completed",
    tool: event.tool || "runtime",
    risk: event.risk || "read",
    detail: auditDetail(event),
    at: Date.parse(event.occurredAt || "") || Date.now(),
  })));
}

function addAudit(event) {
  const seq = AUDIT.reduce((highest, item) => Math.max(highest, Number(item.seq) || 0), 0) + 1;
  AUDIT.unshift({ seq, ...event });
}

async function callApi(method, path, body) {
  try {
    const response = await fetch(`${state.apiBase}${path}`, {
      method,
      credentials: "same-origin",
      cache: "no-store",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const code = payload?.error?.code || `HTTP_${response.status}`;
      throw Object.assign(new Error(payload?.error?.message || "Control-plane request failed"), { code, status: response.status });
    }
    return payload;
  } catch (error) {
    state.live.error = { code: error.code || "NETWORK", message: error.message || "Control plane unreachable" };
    return null;
  }
}

function liveReadiness(candidate = state.live) {
  return Boolean(
    candidate
    && candidate.error === null
    && candidate.projectos
    && candidate.projectos.authoritative === true
    && candidate.projectos.status === "current"
    && Number.isFinite(Date.parse(candidate.projectos.expiresAt || ""))
    && Date.parse(candidate.projectos.expiresAt) > Date.now()
    && candidate.health?.status === "healthy"
    && candidate.health.protectedRoutesConfigured === true
    && candidate.health.durableLedgerConfigured === true
    && candidate.health.distributedRateLimitConfigured === true
    && Array.isArray(candidate.tools?.tools)
    && Array.isArray(candidate.connections?.connections)
    && candidate.metrics && typeof candidate.metrics === "object"
    && Array.isArray(candidate.plans?.plans)
    && Array.isArray(candidate.logs?.events)
    && candidate.chain?.valid === true
  );
}

function clearLiveReadiness(projectos = state.live.projectos, error = state.live.error) {
  state.live = {
    projectos,
    health: null,
    metrics: null,
    tools: null,
    connections: null,
    plans: null,
    logs: null,
    chain: null,
    error,
  };
  CONNECTIONS.splice(0, CONNECTIONS.length);
  PLANS.splice(0, PLANS.length);
  AUDIT.splice(0, AUDIT.length);
}

function updateModeFromReadiness() {
  state.mode = liveReadiness() ? "live" : state.live.error ? "degraded" : "status";
}

async function loadProjectOSProjection() {
  try {
    const response = await fetch("/api/operator/status", {
      method: "GET",
      credentials: "same-origin",
      cache: "no-store",
      headers: { accept: "application/json" },
    });
    const projection = await response.json().catch(() => null);
    if (
      ![200, 503].includes(response.status)
      || !projection
      || projection.schemaVersion !== "1.0.0"
      || !projection.progress
      || !Array.isArray(projection.phases)
      || !Array.isArray(projection.tasks)
    ) {
      throw new Error("The canonical status pack is unavailable or invalid");
    }
    return projection;
  } catch (error) {
    state.live.error = {
      code: "PROJECTOS_STATUS_UNAVAILABLE",
      message: error.message || "The canonical ProjectOS projection is unavailable",
    };
    return null;
  }
}

async function refreshProjectOS() {
  if (state.live.error?.code === "PROJECTOS_STATUS_UNAVAILABLE") {
    state.live.error = null;
  }
  const projectos = await loadProjectOSProjection();
  if (!projectos) {
    clearLiveReadiness(null, state.live.error);
    state.mode = "degraded";
    render();
    return;
  }
  state.live.projectos = projectos;
  updateModeFromReadiness();
  render();
}

async function refreshLive() {
  state.mode = "connecting";
  clearLiveReadiness(state.live.projectos, null);
  render();
  const [projectos, health] = await Promise.all([
    loadProjectOSProjection(),
    callApi("GET", "/health"),
  ]);
  const [tools, connections, metrics, plans, logs, chain] = await Promise.all([
    callApi("GET", "/tools"),
    callApi("GET", "/connections"),
    callApi("GET", "/metrics"),
    callApi("GET", "/plans?limit=100"),
    callApi("GET", "/logs?limit=100"),
    callApi("GET", "/logs/verify"),
  ]);
  const verification = chain?.verification || chain;
  const candidate = {
    projectos,
    health,
    tools,
    connections,
    metrics,
    plans,
    logs,
    chain: verification,
    error: state.live.error,
  };
  if (!liveReadiness(candidate)) {
    const readinessError = state.live.error || (verification?.valid !== true
      ? { code: "AUDIT_CHAIN_INVALID", message: "The durable audit chain did not verify" }
      : { code: "CONTROL_PLANE_INCOMPLETE", message: "One or more required production controls are unavailable or invalid" });
    clearLiveReadiness(projectos, readinessError);
    state.mode = "degraded";
    render();
    return;
  }
  state.live = candidate;
  replaceConnectionsFromLive(connections);
  replacePlansFromLive(plans);
  replaceAuditFromLive(logs);
  updateModeFromReadiness();
  render();
}

function navButton(route, label, icon) {
  return `<button class="nav-button" data-route="${route}" aria-current="${state.route === route ? "page" : "false"}"><span class="nav-icon" aria-hidden="true">${icon}</span><span>${label}</span></button>`;
}

function bottomButton(route, label, icon) {
  const active = state.route === route || (route === "more" && ["plans", "connections", "security", "operations", "settings"].includes(state.route));
  return `<button class="bottom-button" data-route="${route}" aria-current="${active ? "page" : "false"}"><span aria-hidden="true">${icon}</span><span>${label}</span></button>`;
}

function shell(content) {
  const [title, subtitle] = ROUTES[state.route] || ROUTES.home;
  return `
    <div class="app-shell">
      <aside class="sidebar" aria-label="Primary navigation">
        <div class="brand">
          <div class="brand-mark"><img src="https://raw.githubusercontent.com/mbanatao/Battle/c3594e4721097714118a3e1a6854e9836410b00a/public/brand/banatao/red-apple-mark-96.png" alt="Banatao Systems Red Apple" /></div>
          <div class="brand-copy"><div class="brand-title">MCPMaster</div><div class="brand-subtitle">BANATAO SYSTEMS</div></div>
        </div>
        <nav class="nav">
          ${navButton("home", "ProjectOS", "⌂")}
          ${navButton("actions", "Manual Actions", "⌘")}
          ${navButton("plans", "Plans", "◇")}
          ${navButton("approvals", "Approvals", "✓")}
          ${navButton("connections", "Connections", "◎")}
          ${navButton("audit", "Audit Trail", "≡")}
          ${navButton("security", "Security", "◆")}
          ${navButton("operations", "Operations", "◫")}
          ${navButton("settings", "Settings", "⚙")}
        </nav>
        <div class="sidebar-footer">
          <div class="environment-card">
            <div class="environment-row"><span>Production</span><span class="status-dot healthy" aria-label="healthy"></span></div>
            <div class="environment-row"><span>main</span><span>canonical</span></div>
            <div class="environment-row"><span>Node</span><span>24 LTS</span></div>
          </div>
        </div>
      </aside>
      <section class="main-shell">
        <header class="topbar">
          <div class="topbar-copy"><div class="eyebrow">MCPMASTER · PROJECTOS</div><h1 class="page-title">${esc(title)}</h1><div class="page-subtitle">${esc(subtitle)}</div></div>
          <div class="topbar-actions">
            <button class="icon-button" data-action="command" aria-label="Open command menu">⌘</button>
            <button class="button ghost desktop-action" data-route="approvals">${PLANS.filter((plan) => plan.status === "pending_approval").length} approvals</button>
            <button class="button primary desktop-action" data-route="builder">Manual override</button>
          </div>
        </header>
        <main id="main-content" class="content" tabindex="-1">
          ${state.mode === "connecting" ? `<div class="demo-banner"><span aria-hidden="true">↻</span><div><strong>Connecting to the production control plane</strong><p>Live actions remain locked until identity, durable plans, distributed rate limiting and the audit chain all respond.</p></div></div>` : ""}
          ${state.live.error ? `<div class="system-banner"><span aria-hidden="true">!</span><div><strong>Control plane unavailable · ${esc(state.live.error.code)}</strong><p>${esc(state.live.error.message)}. This is treated as a degraded security state; live plans and approvals remain unavailable.</p></div></div>` : ""}
          ${content}
        </main>
      </section>
      <nav class="bottom-nav" aria-label="Mobile navigation">
        ${bottomButton("home", "ProjectOS", "⌂")}${bottomButton("actions", "Manual", "⌘")}${bottomButton("approvals", "Approvals", "✓")}${bottomButton("audit", "Activity", "≡")}${bottomButton("more", "More", "•••")}
      </nav>
      ${renderSheet()}
      ${state.toast ? `<div class="toast ${state.toast.kind === "danger" ? "danger" : ""}" role="status"><strong>${esc(state.toast.title)}</strong><p>${esc(state.toast.detail)}</p></div>` : ""}
    </div>`;
}

function renderHome() {
  const projectos = state.live.projectos;
  const phase = projectos?.currentPhase;
  const next = projectos?.nextTask;
  const externalBlockers = (projectos?.blocked || []).filter((task) => task.blockerIds?.length || ["blocked", "partial"].includes(task.status));
  const health = state.live.health || { status: state.mode === "connecting" ? "checking" : "unavailable", protectedRoutesConfigured: false, durableLedgerConfigured: false, distributedRateLimitConfigured: false };
  const pending = PLANS.filter((plan) => plan.status === "pending_approval");
  return `<section class="screen" data-screen="projectos">
    <div class="card pad">
      <div class="control-state"><div><div class="eyebrow">AUTONOMOUS CONTINUATION</div><h2>${next ? `Continuing ${next.repository}` : projectos?.status === "complete" ? "Roadmap complete" : "Waiting on evidence"}</h2><p>ChatGPT is the front door. ProjectOS reads the canonical repository plan, reconciles it against durable evidence, and continues the next dependency-ready item through build, independent review, exact-head CI, repair, and release gates.</p></div><button class="button" data-action="refresh-status">Reconcile</button></div>
      <div class="gate-grid">
        ${gate("Plan evidence", Boolean(projectos && projectos.drift?.length === 0), projectos ? `${projectos.progress.completed}/${projectos.progress.total} verified complete` : "Awaiting projection")}
        ${gate("Current phase", Boolean(phase), phase ? `${phase.id} · ${phase.name}` : "No active phase")}
        ${gate("Next task", Boolean(next), next ? `${next.id} · ${next.status}` : "No eligible task")}
        ${gate("External blockers", externalBlockers.length === 0, externalBlockers.length ? `${externalBlockers.length} evidence-gated` : "None")}
      </div>
    </div>
    <div class="grid metrics">
      ${metric("Roadmap", projectos ? `${projectos.progress.percent}%` : "—", projectos ? `${projectos.progress.completed} of ${projectos.progress.total} tasks complete` : "Awaiting canonical status")}
      ${metric("Phase progress", phase ? `${phase.completedTasks}/${phase.gatingTasks}` : "—", phase?.name || "No active phase")}
      ${metric("Next work item", next?.id || "—", next?.title || "No dependency-ready work")}
      ${metric("Parallel-ready", projectos?.readyParallel?.length ?? "—", "Eligible included-capacity work")}
    </div>
    <div class="grid two">
      <div class="card"><div class="card-header"><div><div class="card-title">Next governed action</div><div class="card-subtitle">Selected from the canonical roadmap</div></div>${next ? badge(next.status.toUpperCase(), "warning") : badge("WAITING", "neutral")}</div><div class="list">${next ? `${detailRow("Task", `${next.id} · ${next.title}`)}${detailRow("Repository", next.repository)}${detailRow("Builder", next.builderAgent || "route at dispatch")}${detailRow("Independent reviewer", next.reviewerAgent || "route at review")}${detailRow("Dependencies", next.missingDependencies.length ? next.missingDependencies.join(", ") : "satisfied")}` : empty("No task selected", "ProjectOS will continue when durable evidence makes a task eligible.")}</div></div>
      <div class="card"><div class="card-header"><div><div class="card-title">Phase sequence</div><div class="card-subtitle">Evidence-backed, dependency ordered</div></div></div><div class="list">${(projectos?.phases || []).map((item) => `<div class="list-row"><span class="status-dot ${item.status === "complete" ? "healthy" : item.status === "active" ? "warning" : ""}"></span><span class="list-main"><span class="list-title">${esc(item.id)} · ${esc(item.name)}</span><span class="list-detail">${item.completedTasks}/${item.gatingTasks} gating tasks</span></span>${badge(item.status.toUpperCase(), item.status === "complete" ? "healthy" : item.status === "active" ? "warning" : "neutral")}</div>`).join("") || empty("Roadmap unavailable", "Reconcile the canonical status projection.")}</div></div>
    </div>
    <div class="card pad">
      <div class="control-state"><div><div class="eyebrow">SECURE EXECUTION SUBSTRATE</div><h2>${health.status === "healthy" ? "Operational" : "Degraded"}</h2><p>The website is the audit, approval, status, and emergency-override surface. Routine roadmap work is initiated from ChatGPT and governed by ProjectOS.</p></div><button class="button ghost" data-route="operations">Inspect</button></div>
      <div class="gate-grid">
        ${gate("Protected routes", health.protectedRoutesConfigured, "Administrator authentication")}
        ${gate("Durable ledger", health.durableLedgerConfigured, "Plans and audit chain")}
        ${gate("Distributed limiter", health.distributedRateLimitConfigured, "Shared Vercel enforcement")}
        ${gate("Break-glass", false, "Disabled by default", true)}
      </div>
    </div>
    <div class="grid two">
      <div class="card"><div class="card-header"><div><div class="card-title">Provider connections</div><div class="card-subtitle">Internal routing and emergency access</div></div><button class="button ghost" data-route="connections">View all</button></div><div class="list">${CONNECTIONS.map(connectionRow).join("")}</div></div>
      <div class="card"><div class="card-header"><div><div class="card-title">Pending approvals</div><div class="card-subtitle">Plans expire after ten minutes</div></div><button class="button ghost" data-route="approvals">Review</button></div><div class="list">${pending.length ? pending.map(planRow).join("") : empty("No approvals waiting", "Write and destructive plans will appear here.")}</div></div>
    </div>
    <div class="card"><div class="card-header"><div><div class="card-title">Recent activity</div><div class="card-subtitle">Human-readable execution events</div></div><button class="button ghost" data-route="audit">Open audit trail</button></div><div class="timeline">${AUDIT.slice(0, 4).map(auditRow).join("")}</div></div>
  </section>`;
}

function gate(label, active, detail, inverted = false) {
  const healthy = inverted ? !active : active;
  return `<div class="gate"><div><span class="status-dot ${healthy ? "healthy" : "warning"}"></span> <strong>${esc(label)}</strong></div><span>${esc(detail)}</span><span class="badge ${healthy ? "healthy" : "warning"}">${healthy ? (inverted ? "OFF" : "ACTIVE") : (inverted ? "ACTIVE" : "UNAVAILABLE")}</span></div>`;
}

function metric(label, value, detail) {
  return `<div class="card pad metric"><div class="metric-label">${esc(label)}</div><div class="metric-value">${esc(value)}</div><div class="metric-detail">${esc(detail)}</div></div>`;
}

function connectionRow(connection) {
  return `<button class="list-row row-button" data-action="connection" data-key="${esc(connectionKey(connection))}"><span class="status-dot ${connection.healthy ? "healthy" : "warning"}"></span><span class="list-main"><span class="list-title">${esc(connection.label)}</span><span class="list-detail">${connection.scopes.length} scopes · ${allConnectionTargets(connection).length} allowlisted targets · mutations ${connection.mutations ? "enabled" : "disabled"}</span></span><span class="list-meta">${esc(connection.lastSuccess)}</span></button>`;
}

function planRow(plan) {
  const reconciliation = plan.terminalOutcome?.terminalClassification === "reconciliation_required";
  return `<button class="list-row row-button" data-action="plan" data-id="${plan.id}">${badge(RISK[plan.risk].label, plan.risk)}${reconciliation ? badge("RECONCILIATION REQUIRED", "danger") : ""}<span class="list-main"><span class="list-title">${esc(TOOLS.find((tool) => tool.name === plan.tool)?.label || plan.tool)}</span><span class="list-detail">${esc(plan.target)}</span></span><span class="list-meta">${esc(expiry(plan))}<br>${esc(short(plan.id))}</span></button>`;
}

function auditRow(event) {
  const kind = event.status === "failed" || event.status === "denied" ? "danger" : event.risk === "write" ? "warning" : "";
  return `<button class="timeline-row row-button" data-action="audit-event" data-seq="${event.seq}"><span class="timeline-dot ${kind}"></span><span class="list-main"><span class="list-title">${esc(event.event.replaceAll("_", " "))}</span><span class="list-detail">${esc(event.detail)}</span><span class="action-name">${esc(event.tool)} · sequence ${event.seq}</span></span><span class="list-meta">${timeAgo(event.at)}</span></button>`;
}

function empty(title, detail) {
  return `<div class="empty"><div><h3>${esc(title)}</h3><p>${esc(detail)}</p></div></div>`;
}

function filteredTools() {
  const query = state.query.trim().toLowerCase();
  return TOOLS.filter((tool) => {
    const availability = toolAvailability(tool);
    return (!query || `${tool.name} ${tool.label} ${tool.description} ${tool.scopes.join(" ")}`.toLowerCase().includes(query))
      && (!state.filters.provider || tool.provider === state.filters.provider)
      && (!state.filters.risk || tool.risk === state.filters.risk)
      && (!state.filters.availability || String(availability.available) === state.filters.availability);
  });
}

function renderActions() {
  const tools = filteredTools();
  return `<section class="screen" data-screen="actions">
    <div class="toolbar">
      <input class="search" type="search" aria-label="Search registered actions" placeholder="Search action, scope or provider" value="${esc(state.query)}" data-input="query" />
      <select class="select" aria-label="Provider filter" data-filter="provider"><option value="">All providers</option><option value="github" ${state.filters.provider === "github" ? "selected" : ""}>GitHub</option><option value="supabase" ${state.filters.provider === "supabase" ? "selected" : ""}>Supabase</option></select>
      <select class="select" aria-label="Risk filter" data-filter="risk"><option value="">All risk levels</option><option value="read" ${state.filters.risk === "read" ? "selected" : ""}>Read</option><option value="write" ${state.filters.risk === "write" ? "selected" : ""}>Write</option><option value="destructive" ${state.filters.risk === "destructive" ? "selected" : ""}>Destructive</option></select>
      <select class="select" aria-label="Availability filter" data-filter="availability"><option value="">Any availability</option><option value="true" ${state.filters.availability === "true" ? "selected" : ""}>Available</option><option value="false" ${state.filters.availability === "false" ? "selected" : ""}>Blocked</option></select>
      <button class="button primary" data-route="builder">Build action</button>
    </div>
    <div class="card pad"><div class="control-state"><div><div class="eyebrow">MANIFEST INVENTORY</div><h2>${tools.length} of ${TOOLS.length} actions</h2><p>Risk, required scopes, mutation policy, confirmation and break-glass classification come from explicit manifests—not naming heuristics.</p></div></div></div>
    <div class="grid three">${tools.length ? tools.map(actionCard).join("") : `<div class="card" style="grid-column:1/-1">${empty("No actions match", "Clear a filter or use a broader search.")}</div>`}</div>
  </section>`;
}

function actionCard(tool) {
  const availability = toolAvailability(tool);
  return `<article class="card action-card" data-risk="${tool.risk}"><div class="action-top">${badge(RISK[tool.risk].label, tool.risk)}${badge(tool.provider.toUpperCase(), "neutral")}${tool.highImpact ? badge("BREAK-GLASS", "hot") : ""}</div><div><div class="list-title">${esc(tool.label)}</div><div class="action-name">${esc(tool.name)}</div></div><p class="action-description">${esc(tool.description)}</p><div class="scope-list">${tool.scopes.map((scope) => badge(scope, "neutral")).join("") || badge("account metadata", "neutral")}</div><div class="alert ${availability.available ? "healthy" : "warning"}"><strong>${availability.available ? "Available" : "Blocked"}</strong><p>${esc(availability.reason)}</p></div><div class="action-footer"><span class="list-detail">Target: ${esc(tool.scope)} · approval ${tool.risk === "read" ? "not required" : "required"}</span><button class="button ${tool.risk === "destructive" ? "danger" : ""}" data-action="choose-tool" data-tool="${esc(tool.name)}">Configure</button></div></article>`;
}

function renderBuilder() {
  const b = state.builder;
  const labels = ["Action", "Target", "Parameters", "Review", "Result"];
  return `<section class="screen" data-screen="builder">
    <ol class="steps">${labels.map((label, index) => `<li class="step ${index < b.step ? "done" : index === b.step ? "active" : ""}"><span class="step-bar"></span><span class="step-label">${index + 1}. ${label}</span></li>`).join("")}</ol>
    ${builderStage()}
    <div class="sticky-actions"><button class="button ghost" data-action="builder-back">${b.step === 0 ? "Cancel" : "Back"}</button><button class="button ${b.step === 3 && b.tool?.risk === "destructive" ? "danger" : "primary"}" data-action="builder-next" ${builderCanContinue() ? "" : "disabled"}>${["Choose action", "Continue", "Review impact", "Create plan", "Open approvals"][b.step]}</button></div>
  </section>`;
}

function builderCanContinue() {
  const b = state.builder;
  if (state.mode !== "live") return false;
  if (b.step === 0) return Boolean(b.tool);
  if (b.step === 1) return Boolean(b.connectionKey && b.target);
  if (b.step === 2) {
    if (b.tool?.name === "github.create-issue") return Boolean(b.title);
    if (b.tool?.name === "github.merge-pull-request") return Boolean(b.pullNumber);
    if (b.tool?.confirmationKind) return Boolean(b.pathSegments || b.tool.risk === "destructive");
    return true;
  }
  if (b.step === 3) return !highImpactReason(b.tool, builderArgs());
  return true;
}

function builderStage() {
  const b = state.builder;
  if (b.step === 0) {
    return `<div class="card pad"><div class="card-title">SELECT AN ACTION</div><div class="card-subtitle">Choose from the explicit tool manifest inventory.</div><div class="toolbar" style="margin-top:12px"><input class="search" type="search" placeholder="Filter actions" value="${esc(state.query)}" data-input="query" /></div><div class="list" style="margin-top:10px">${filteredTools().slice(0, 14).map((tool) => `<button class="list-row row-button" data-action="choose-tool" data-tool="${esc(tool.name)}">${badge(RISK[tool.risk].label, tool.risk)}<span class="list-main"><span class="list-title">${esc(tool.label)}</span><span class="list-detail">${esc(tool.description)}</span></span><span class="list-meta">${esc(tool.provider)}</span></button>`).join("")}</div></div>`;
  }
  if (b.step === 1) {
    const connections = executableConnections(b.tool);
    const selected = connectionByKey(b.connectionKey);
    const targets = connectionTargets(selected, b.tool);
    return `<div class="grid two"><div class="card"><div class="card-header"><div><div class="card-title">CONNECTION</div><div class="card-subtitle">Only live connections granting every required scope and at least one allowlisted target appear.</div></div></div><div class="list">${connections.length ? connections.map((connection) => `<button class="list-row row-button" data-action="builder-connection" data-key="${esc(connectionKey(connection))}"><span class="status-dot healthy"></span><span class="list-main"><span class="list-title">${esc(connection.label)}</span><span class="list-detail">${connection.scopes.length} granted scopes · mutations ${connection.mutations ? "enabled" : "disabled"}</span></span>${b.connectionKey === connectionKey(connection) ? badge("SELECTED", "healthy") : ""}</button>`).join("") : empty("No eligible connection", "The live catalog does not grant every scope and an allowlisted target required by this action.")}</div></div><div class="card"><div class="card-header"><div><div class="card-title">ALLOWLISTED TARGET</div><div class="card-subtitle">A provider action cannot escape this live allowlist.</div></div></div><div class="list">${selected ? (targets.length ? targets.map((target) => `<button class="list-row row-button" data-action="builder-target" data-target="${esc(target)}"><span class="list-main"><span class="list-title">${esc(target)}</span><span class="list-detail">${esc(b.tool.scope)} target</span></span>${b.target === target ? badge("SELECTED", "healthy") : ""}</button>`).join("") : empty("No allowlisted target", "This connection has no target for the selected action.")) : empty("Choose a connection first", "The target allowlist is resolved from the live provider catalog.")}</div></div></div>`;
  }
  if (b.step === 2) return renderBuilderFields();
  if (b.step === 3) return renderBuilderPreview();
  return `<div class="card pad"><div class="alert healthy"><strong>${esc(b.result?.title || "Plan created")}</strong><p>${esc(b.result?.detail || "The plan is bound to the exact payload digest.")}</p></div><div class="list" style="margin-top:12px">${detailRow("Plan ID", b.result?.planId || "—")}${detailRow("Payload SHA-256", b.hash || "—")}${detailRow("Status", b.tool?.risk === "read" ? "completed" : "pending_approval")}${detailRow("Next step", b.tool?.risk === "read" ? "Inspect the audit event" : "Approve before the ten-minute expiry")}</div></div>`;
}

function renderBuilderFields() {
  const b = state.builder;
  const fields = [];
  if (b.tool.confirmationKind) {
    if (b.tool.risk !== "destructive") fields.push(field("method", "HTTP method", "POST, PUT or PATCH", b.method, "select", ["POST", "PUT", "PATCH"]));
    fields.push(field("pathSegments", "Path below target", "Slash-separated path segments. Traversal is rejected.", b.pathSegments, "text", null, "issues/17"));
  }
  if (b.tool.name === "github.create-issue") {
    fields.push(field("title", "Issue title", "Required", b.title, "text", null, "Production follow-up"));
    fields.push(field("body", "Issue body", "Optional and sanitized before audit storage", b.body, "textarea"));
  }
  if (b.tool.name === "github.merge-pull-request") {
    fields.push(field("pullNumber", "Pull request number", "Required", b.pullNumber, "number", null, "31"));
    fields.push(field("mergeMethod", "Merge method", "squash, merge or rebase", b.mergeMethod, "select", ["squash", "merge", "rebase"]));
  }
  if (b.tool.scope === "branch") fields.push(field("branchIdOrRef", "Branch ID or ref", "Must belong to the selected allowlisted project", b.branchIdOrRef, "text", null, "preview-branch"));
  if (!fields.length) fields.push(`<div class="alert healthy full"><strong>No additional parameters required</strong><p>The selected action uses only the allowlisted target and connection.</p></div>`);
  return `<div class="card pad"><div class="card-title">VALIDATED PARAMETERS</div><div class="card-subtitle">The runtime validates every value before planning and provider traffic.</div><div class="form-grid" style="margin-top:14px">${fields.join("")}</div></div>`;
}

function field(name, label, help, value, type = "text", options, placeholder = "") {
  if (type === "textarea") return `<div class="field full"><label for="builder-${name}">${esc(label)}</label><small>${esc(help)}</small><textarea id="builder-${name}" class="textarea" data-builder-field="${name}" placeholder="${esc(placeholder)}">${esc(value)}</textarea></div>`;
  if (type === "select") return `<div class="field"><label for="builder-${name}">${esc(label)}</label><small>${esc(help)}</small><select id="builder-${name}" class="input" data-builder-field="${name}">${options.map((option) => `<option value="${esc(option)}" ${value === option ? "selected" : ""}>${esc(option)}</option>`).join("")}</select></div>`;
  return `<div class="field"><label for="builder-${name}">${esc(label)}</label><small>${esc(help)}</small><input id="builder-${name}" class="input" type="${type}" data-builder-field="${name}" value="${esc(value)}" placeholder="${esc(placeholder)}" /></div>`;
}

function renderBuilderPreview() {
  const b = state.builder;
  const args = builderArgs();
  const confirmation = expectedConfirmation(b.tool, args);
  const highImpact = highImpactReason(b.tool, args);
  const availability = toolAvailability(b.tool);
  const blocked = highImpact || !availability.available;
  return `<div class="grid two"><div class="card pad"><div class="action-top">${badge(RISK[b.tool.risk].label, b.tool.risk)}${badge(b.tool.provider.toUpperCase(), "neutral")}${highImpact ? badge("BREAK-GLASS BLOCK", "hot") : ""}</div><h2>${esc(b.tool.label)}</h2><p class="action-description">${esc(b.tool.description)}</p><div class="list" style="margin-top:12px">${detailRow("Connection", connectionByKey(b.connectionKey)?.label || "—")}${detailRow("Target", b.target)}${detailRow("Required scopes", b.tool.scopes.join(", ") || "account metadata")}${detailRow("Mutation switch", b.tool.mutation ? "required and enabled" : "not required")}${detailRow("Approval", b.tool.risk === "read" ? "not required" : "separate approval required")}${detailRow("Confirmation", confirmation || "manifest declares none")}${detailRow("Payload hash", b.hash || "calculating…")}</div>${blocked ? `<div class="alert danger" style="margin-top:12px"><strong>Operation blocked</strong><p>${esc(highImpact ? `${highImpact} requires supervised break-glass, which is disabled.` : availability.reason)}</p></div>` : `<div class="alert healthy" style="margin-top:12px"><strong>Ready to plan</strong><p>No provider request is sent until the durable plan is created and, where required, approved.</p></div>`}</div><div class="preview ${b.tool.risk === "destructive" ? "danger" : ""} ${highImpact ? "hot" : ""}"><div class="card-header"><div><div class="card-title">EXACT OPERATION</div><div class="card-subtitle">Canonical payload used for the SHA-256 digest</div></div></div><pre>${esc(JSON.stringify({ tool: b.tool.name, args: stable(args) }, null, 2))}</pre></div></div>`;
}

function detailRow(label, value) {
  return `<div class="list-row"><span class="list-main"><span class="list-detail">${esc(label)}</span></span><span class="list-meta" title="${esc(value)}">${esc(short(value, 36))}</span></div>`;
}

function renderPlans() {
  const visible = PLANS.filter((plan) => state.planFilter === "all" || plan.status === state.planFilter);
  return `<section class="screen"><div class="toolbar"><select class="select" data-plan-filter><option value="all">All plan states</option>${["pending_approval", "approved", "completed", "failed", "expired"].map((status) => `<option value="${status}" ${state.planFilter === status ? "selected" : ""}>${status.replaceAll("_", " ")}</option>`).join("")}</select><button class="button primary" data-route="builder">Create plan</button></div><div class="card"><div class="card-header"><div><div class="card-title">DURABLE PLANS</div><div class="card-subtitle">Every production mutation is bound, expiring and single-use.</div></div></div><div class="list">${visible.length ? visible.map(planRow).join("") : empty("No plans in this state", "Change the filter or create a new operation.")}</div></div></section>`;
}

function renderApprovals() {
  const approvals = PLANS.filter((plan) => plan.status === "pending_approval");
  return `<section class="screen"><div class="alert warning"><strong>Approval is separate from administrator access</strong><p>Review the exact target, payload identity, risk, scopes and expiry before approving. Destructive plans require exact confirmation.</p></div>${approvals.length ? approvals.map(approvalCard).join("") : `<div class="card">${empty("Approval inbox is clear", "New write and destructive plans will appear here.")}</div>`}</section>`;
}

function approvalCard(plan) {
  const tool = TOOLS.find((item) => item.name === plan.tool);
  return `<article class="card action-card" data-risk="${plan.risk}"><div class="action-top">${badge(RISK[plan.risk].label, plan.risk)}${badge(plan.reversible ? "REVERSIBLE" : "NOT REVERSIBLE", plan.reversible ? "neutral" : "danger")}<span class="list-meta" style="margin-left:auto">${esc(expiry(plan))}</span></div><div><div class="list-title">${esc(tool?.label || plan.tool)}</div><div class="action-name">${esc(plan.tool)}</div></div><p class="action-description">${esc(plan.target)}</p><div class="list">${detailRow("Plan ID", plan.id)}${detailRow("Request ID", plan.requestId)}${detailRow("Payload SHA-256", plan.payloadHash)}${detailRow("Required scopes", tool?.scopes.join(", ") || "—")}</div><div class="action-footer"><span class="list-detail">Authenticated owner or admin · exact backend confirmation required</span><button class="button ${plan.risk === "destructive" ? "danger" : "warning"}" data-action="approve-plan" data-id="${plan.id}">Review approval</button></div></article>`;
}

function renderConnections() {
  return `<section class="screen"><div class="grid three">${CONNECTIONS.length ? CONNECTIONS.map((connection) => `<article class="card pad"><div class="action-top"><span class="status-dot ${state.mode === "live" && connection.healthy ? "healthy" : "warning"}"></span>${badge(connection.provider.toUpperCase(), "neutral")}${badge(connection.mutations ? "MUTATIONS ON" : "READ ONLY", connection.mutations ? "warning" : "healthy")}</div><h2>${esc(connection.label)}</h2><p class="action-description">Credential material is Vault-backed and never rendered. This screen exposes only live logical authorization metadata.</p><div class="list" style="margin-top:12px">${detailRow("Account", connection.account)}${detailRow("Installation", connection.installation)}${detailRow("Credential state", connection.lastSuccess)}${detailRow("Allowlisted targets", String(allConnectionTargets(connection).length))}${detailRow("Declared scopes", String(connection.scopes.length))}</div><div class="scope-list" style="margin-top:12px">${connection.scopes.map((scope) => badge(scope, "neutral")).join("")}</div><button class="button" style="margin-top:14px;width:100%" data-action="connection" data-key="${esc(connectionKey(connection))}">Inspect connection</button></article>`).join("") : `<div class="card">${empty("No live connections", "Reconnect production to load the sanitized Vault-backed catalog.")}</div>`}</div></section>`;
}

function renderAudit() {
  const query = state.auditQuery.trim().toLowerCase();
  const rows = AUDIT.filter((event) => !query || `${event.event} ${event.tool} ${event.detail} ${event.seq}`.toLowerCase().includes(query));
  const chain = state.live.chain;
  const valid = chain?.valid === true;
  return `<section class="screen"><div class="alert ${valid ? "healthy" : "danger"}"><strong>${valid ? "Audit chain verified" : "Audit chain unavailable"}</strong><p>${esc(chain ? `${chain.eventCount ?? 0} events · last hash ${chain.lastHash ?? "unknown"}${valid ? " · no gap detected" : " · investigate immediately"}` : "Production verification has not completed.")}</p><div><button class="button" data-action="verify-chain">Verify chain</button></div></div><div class="toolbar"><input class="search" type="search" placeholder="Search event, action, plan or request" value="${esc(state.auditQuery)}" data-input="audit-query" /></div><div class="card"><div class="timeline">${rows.length ? rows.map(auditRow).join("") : empty("No audit events", "The durable audit ledger currently has no matching events.")}</div></div></section>`;
}

function renderSecurity() {
  const groups = [
    ["IDENTITY & ROUTES", [["Protected-route configuration", "CONFIGURED", "Administrator authentication resolves only through the private runtime-security boundary."], ["Production OIDC identity", "ENFORCED", "Exact team, project, environment, owner, subject and audience claims are required."], ["Trusted Vercel identity", "CANONICAL ONLY", "Only the old-domain production project may access Vault-backed controls."]]],
    ["EXECUTION CONTROLS", [["Durable plans", "ACTIVE", "Payload-bound plans expire after ten minutes."], ["One-time claims", "ENFORCED", "Atomic claim prevents replay and optimistic mutation retry."], ["Separate approvals", "ACTIVE", "Write and destructive plans require a distinct approval path."], ["Break-glass mutations", "DISABLED", "High-impact provider operations fail closed."]]],
    ["DATA BOUNDARIES", [["Provider allowlists", "ENFORCED", "Repository, organization, project and verified branch scopes are exact."], ["Response redaction", "ACTIVE", "Known secret fields and credential patterns are removed before return."], ["Distributed rate limiting", "ACTIVE", "Only SHA-256 bucket identifiers are stored."]]],
    ["SUPPLY CHAIN", [["Node.js runtime", "24 LTS", "Engine-strict is enforced across local, CI and all production containers."], ["CodeQL", "REQUIRED", "Security-extended JavaScript and TypeScript analysis gates production changes."], ["Production dependencies", "AUDITED", "High-severity production dependency findings fail validation."]]],
  ];
  return `<section class="screen"><div class="alert healthy"><div class="action-top">${badge("DISABLED", "healthy")}${badge("BREAK-GLASS", "hot")}</div><strong>High-impact provider mutations are denied by default</strong><p>Ordinary approval never bypasses identity, plans, scopes, allowlists, exact confirmation, rate limiting or audit logging.</p></div>${groups.map(([title, rows]) => `<div class="card"><div class="card-header"><div class="card-title">${title}</div></div><div class="list">${rows.map(([label, status, detail]) => `<div class="list-row"><span class="status-dot ${status.includes("NEEDED") || status.includes("TEMPORARY") ? "warning" : "healthy"}"></span><span class="list-main"><span class="list-title">${label}</span><span class="list-detail">${detail}</span></span>${badge(status, status.includes("NEEDED") || status.includes("TEMPORARY") ? "warning" : "healthy")}</div>`).join("")}</div></div>`).join("")}</section>`;
}

function renderOperations() {
  const health = state.live.health;
  const rows = [["Deployment state", state.mode === "live" ? "READY" : state.mode.toUpperCase()], ["Source", "main · canonical domain"], ["Environment", "production"], ["Runtime version", health?.version || "awaiting live response"], ["Operator API", state.apiBase], ["Control-plane health", health?.status || "unavailable"], ["Ledger availability", health?.durableLedgerConfigured ? "available" : "unavailable"], ["Distributed limiter", health?.distributedRateLimitConfigured ? "available" : "unavailable"]];
  return `<section class="screen"><div class="grid two"><div class="card"><div class="card-header"><div><div class="card-title">PRODUCTION DEPLOYMENT</div><div class="card-subtitle">Current source of truth</div></div></div><div class="list">${rows.map(([label, value]) => detailRow(label, value)).join("")}</div></div><div class="card"><div class="card-header"><div><div class="card-title">CONTROL INVARIANTS</div><div class="card-subtitle">Production remains locked to these boundaries</div></div></div><div class="list"><div class="list-row"><span class="status-dot healthy"></span><span class="list-main"><span class="list-title">Canonical project only</span><span class="list-detail">Vault-backed controls reject the retired duplicate Vercel identity.</span></span>${badge("ENFORCED", "healthy")}</div><div class="list-row"><span class="status-dot healthy"></span><span class="list-main"><span class="list-title">Same-origin operator API</span><span class="list-detail">Browser credentials are accepted only by the canonical authenticated bridge.</span></span>${badge("ENFORCED", "healthy")}</div><div class="list-row"><span class="status-dot healthy"></span><span class="list-main"><span class="list-title">Fail-closed execution</span><span class="list-detail">Actions stay locked whenever identity, ledger, limiter, or audit verification is unavailable.</span></span>${badge("ENFORCED", "healthy")}</div></div></div></div><div class="card"><div class="card-header"><div><div class="card-title">RECENT RUNTIME EVENTS</div><div class="card-subtitle">Sanitized operational telemetry</div></div></div><div class="timeline">${AUDIT.length ? AUDIT.slice(0, 3).map(auditRow).join("") : empty("No runtime events", "The durable ledger has no events to display.")}</div></div></section>`;
}

function renderSettings() {
  return `<section class="screen"><div class="card pad"><div class="card-title">CONTROL PLANE</div><div class="list" style="margin-top:12px">${detailRow("Operator API", state.apiBase)}${detailRow("Mode", state.mode)}${detailRow("Authentication", "Supabase owner session · memory only")}</div><div class="toolbar" style="margin-top:12px"><button class="button primary" data-action="live-mode">Reconnect production</button></div></div><div class="card"><div class="card-header"><div class="card-title">APPEARANCE</div></div><div class="list"><div class="list-row"><span class="list-main"><span class="list-title">Theme</span><span class="list-detail">Dark is the default operations theme.</span></span><button class="chip-button" data-action="theme" data-value="dark">Dark</button><button class="chip-button" data-action="theme" data-value="light">Light</button></div><div class="list-row"><span class="list-main"><span class="list-title">Density</span><span class="list-detail">Compact tightens rows for one-hand scanning.</span></span><button class="chip-button" data-action="density" data-value="comfortable">Comfortable</button><button class="chip-button" data-action="density" data-value="compact">Compact</button></div></div></div><div class="card"><div class="card-header"><div class="card-title">SESSION SECURITY</div></div><div class="list"><div class="list-row"><span class="list-main"><span class="list-title">Credential storage</span><span class="list-detail">No provider, administrator, approval, Vault, service-role or OIDC credential is stored in localStorage, query strings, logs or analytics.</span></span>${badge("ENFORCED", "healthy")}</div><div class="list-row"><span class="list-main"><span class="list-title">Mutation retries</span><span class="list-detail">The UI never automatically retries a mutation or an already-claimed plan.</span></span>${badge("OFF", "healthy")}</div></div></div></section>`;
}

function renderMore() {
  const links = [["plans", "Plans", "Durable execution lifecycle"], ["connections", "Connections", "Provider accounts, scopes and allowlists"], ["security", "Security Center", "Identity, controls and boundaries"], ["operations", "Operations", "Deployment, telemetry and runbooks"], ["settings", "Settings", "Appearance and control-plane connection"]];
  return `<section class="screen"><div class="card"><div class="list">${links.map(([route, label, detail]) => `<button class="list-row row-button" data-route="${route}"><span class="list-main"><span class="list-title">${label}</span><span class="list-detail">${detail}</span></span><span class="list-meta">›</span></button>`).join("")}</div></div></section>`;
}

function renderSheet() {
  const sheet = state.sheet;
  if (!sheet) return "";
  if (sheet.kind === "command") {
    const links = Object.entries(ROUTES).filter(([route]) => route !== "builder");
    return `<div class="overlay" data-action="close-sheet"><section class="sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-title" data-sheet><div class="sheet-header"><div><div class="card-title">COMMAND MENU</div><h2 id="sheet-title" style="margin:3px 0 0">Go anywhere</h2></div><button class="icon-button" data-action="close-sheet" aria-label="Close">×</button></div><div class="sheet-body"><div class="list">${links.map(([route, [label, detail]]) => `<button class="list-row row-button" data-route="${route}"><span class="list-main"><span class="list-title">${label}</span><span class="list-detail">${detail}</span></span><span class="list-meta">›</span></button>`).join("")}</div></div></section></div>`;
  }
  if (sheet.kind === "approve") {
    const plan = PLANS.find((item) => item.id === sheet.id);
    if (!plan) return "";
    const tool = TOOLS.find((item) => item.name === plan.tool);
    const expected = plan.confirmation || (plan.risk === "destructive" ? plan.target : "");
    return `<div class="overlay" data-action="close-sheet"><section class="sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-title" data-sheet><div class="sheet-header"><div><div class="card-title">APPROVAL REVIEW</div><h2 id="sheet-title" style="margin:3px 0 0">${esc(tool?.label || plan.tool)}</h2></div><button class="icon-button" data-action="close-sheet" aria-label="Close">×</button></div><div class="sheet-body"><div class="action-top">${badge(RISK[plan.risk].label, plan.risk)}${badge(expiry(plan), "neutral")}</div><div class="alert ${plan.risk === "destructive" ? "danger" : "warning"}"><strong>${plan.risk === "destructive" ? "Destructive operation" : "Provider mutation"}</strong><p>This approval becomes valid only after the backend confirms it. Review the exact target, parameters and payload identity.</p></div><div class="list">${detailRow("Target", plan.target)}${detailRow("Plan ID", plan.id)}${detailRow("Payload SHA-256", plan.payloadHash)}${detailRow("Scopes", tool?.scopes.join(", ") || "—")}</div><div class="preview ${plan.risk === "destructive" ? "danger" : ""}" style="margin-top:12px"><div class="card-title">EXACT OPERATION</div><pre>${esc(JSON.stringify({ tool: plan.tool, args: stable(plan.args || {}) }, null, 2))}</pre></div>${expected ? `<div class="field"><label for="confirmation">Type the exact confirmation</label><small>${esc(expected)}</small><input id="confirmation" class="input" data-input="confirmation" autocomplete="off" value="${esc(sheet.phrase || "")}" /></div>` : ""}</div><div class="sheet-actions"><button class="button ghost" data-action="close-sheet">Cancel</button><button class="button ${plan.risk === "destructive" ? "danger" : "warning"}" data-action="confirm-approval" data-id="${plan.id}" data-expected="${esc(expected)}" ${(expected && sheet.phrase !== expected) ? "disabled" : ""}>Approve plan</button></div></section></div>`;
  }
  if (sheet.kind === "detail") {
    return `<div class="overlay" data-action="close-sheet"><section class="sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-title" data-sheet><div class="sheet-header"><div><div class="card-title">${esc(sheet.eyebrow || "DETAIL")}</div><h2 id="sheet-title" style="margin:3px 0 0">${esc(sheet.title)}</h2></div><button class="icon-button" data-action="close-sheet" aria-label="Close">×</button></div><div class="sheet-body">${sheet.body}</div></section></div>`;
  }
  return "";
}

function render() {
  document.documentElement.dataset.theme = state.theme;
  document.documentElement.dataset.density = state.density;
  const screens = { home: renderHome, actions: renderActions, builder: renderBuilder, plans: renderPlans, approvals: renderApprovals, connections: renderConnections, audit: renderAudit, security: renderSecurity, operations: renderOperations, settings: renderSettings, more: renderMore };
  app.innerHTML = shell((screens[state.route] || renderHome)());
}

async function createPlan() {
  const b = state.builder;
  if (state.mode !== "live") {
    toast("Control plane unavailable", "Live planning is locked until every production control passes.", "danger");
    return;
  }
  const args = builderArgs();
  b.hash = await payloadHash(b.tool.name, args);
  const payload = await callApi("POST", "/tools/plan", { tool: b.tool.name, args });
  if (!payload) return;
  const remote = payload.plan || payload;
  const plan = {
    id: remote.planId || remote.id,
    requestId: remote.requestId || payload.requestId,
    tool: remote.tool || b.tool.name,
    risk: remote.risk || b.tool.risk,
    status: remote.status || (b.tool.risk === "read" ? "approved" : "pending_approval"),
    target: b.target,
    args,
    createdAt: Date.parse(remote.createdAt || "") || Date.now(),
    expiresAt: Date.parse(remote.expiresAt || "") || Date.now() + 10 * 60000,
    payloadHash: remote.payloadHash || b.hash,
    reversible: b.tool.risk !== "destructive",
    confirmation: expectedConfirmation(b.tool, args),
  };
  PLANS.unshift(plan);
  addAudit({ event: "plan_created", status: "planned", tool: plan.tool, risk: plan.risk, detail: `Live plan bound to ${plan.target} and payload ${short(plan.payloadHash)}.`, at: Date.now() });
  if (b.tool.risk === "read") {
    const executed = await callApi("POST", "/tools/execute", { planId: plan.id });
    if (!executed) {
      plan.status = "failed";
      b.result = { title: "Read execution failed", detail: "The plan remains visible in the audit trail.", planId: plan.id };
    } else {
      plan.status = "completed";
      plan.result = executed.result;
      addAudit({ event: "execution_completed", status: "completed", tool: plan.tool, risk: plan.risk, detail: `Read plan ${short(plan.id)} executed once.`, at: Date.now() });
      b.result = { title: "Read completed", detail: "The provider response was returned through the redacting control runtime.", planId: plan.id };
    }
  } else {
    b.result = { title: "Plan awaiting approval", detail: "The durable plan is now in the Approval Center for an owner or admin.", planId: plan.id };
  }
  b.step = 4;
  track("plan_created", { action: b.tool.name, risk: b.tool.risk, mode: state.mode });
  render();
}

async function approvePlan(plan) {
  if (state.mode !== "live") return;
  const payload = await callApi("POST", "/tools/approve", { planId: plan.id });
  if (!payload) return;
  plan.status = "approved";
  state.sheet = null;
  addAudit({ event: "plan_approved", status: "approved", tool: plan.tool, risk: plan.risk, detail: `Owner/admin approval recorded for ${plan.target}.`, at: Date.now() });
  track("plan_approved", { action: plan.tool, risk: plan.risk, mode: state.mode });
  toast("Approval recorded", "The durable backend confirmed this owner/admin approval.");
}

app.addEventListener("click", async (event) => {
  const target = event.target.closest("[data-route],[data-action]");
  if (!target) return;
  if (target.dataset.route) {
    if (target.dataset.route === "builder" && state.mode !== "live") {
      await refreshLive();
      if (state.mode !== "live") {
        toast("Control plane unavailable", "Manual override unlocks only after every production control passes.", "danger");
        return;
      }
    }
    if (
      ["plans", "approvals", "audit", "connections", "security", "operations"].includes(target.dataset.route)
      && state.mode !== "live"
    ) {
      setRoute(target.dataset.route);
      await refreshLive();
      return;
    }
    setRoute(target.dataset.route);
    return;
  }
  const action = target.dataset.action;
  if (action === "command") { state.sheet = { kind: "command" }; render(); }
  if (action === "close-sheet" && !event.target.closest("[data-sheet]") || action === "close-sheet" && target === event.target.closest("[data-action='close-sheet']")) { state.sheet = null; render(); }
  if (action === "refresh") await refreshLive();
  if (action === "refresh-status") await refreshProjectOS();
  if (action === "choose-tool") {
    if (state.mode !== "live") {
      toast("Control plane unavailable", "Action configuration is locked until production is connected.", "danger");
      return;
    }
    const tool = TOOLS.find((item) => item.name === target.dataset.tool);
    state.builder = { ...state.builder, step: 1, tool, connectionKey: "", target: "", hash: "", result: null };
    state.query = "";
    track("action_selected", { action: tool.name, provider: tool.provider, risk: tool.risk });
    setRoute("builder");
  }
  if (action === "builder-connection") { state.builder.connectionKey = target.dataset.key; state.builder.target = ""; render(); }
  if (action === "builder-target") {
    state.builder.target = target.dataset.target;
    if (state.builder.tool.provider === "supabase") state.builder.projectRef = target.dataset.target;
    render();
  }
  if (action === "builder-back") {
    if (state.builder.step === 0) setRoute("actions");
    else { state.builder.step -= 1; render(); }
  }
  if (action === "builder-next") {
    if (state.builder.step === 3) { await createPlan(); return; }
    if (state.builder.step === 4) { setRoute(state.builder.tool.risk === "read" ? "audit" : "approvals"); return; }
    state.builder.step += 1;
    if (state.builder.step === 3 && state.builder.tool) state.builder.hash = await payloadHash(state.builder.tool.name, builderArgs());
    render();
  }
  if (action === "approve-plan") { state.sheet = { kind: "approve", id: target.dataset.id, phrase: "" }; track("approval_opened", { planId: target.dataset.id }); render(); }
  if (action === "confirm-approval") { const plan = PLANS.find((item) => item.id === target.dataset.id); if (plan) await approvePlan(plan); }
  if (action === "execute-plan") {
    const plan = PLANS.find((item) => item.id === target.dataset.id);
    if (state.mode === "live" && plan && plan.status === "approved") {
      plan.status = "executing";
      state.sheet = null;
      render();
      const executed = await callApi("POST", "/tools/execute", { planId: plan.id });
      if (!executed) {
        plan.status = "failed";
        toast("Execution failed", "The failed plan was not retried. Inspect the audit event before taking another action.", "danger");
      } else {
        plan.status = "completed";
        plan.result = executed.result;
        addAudit({ event: "execution_completed", status: "completed", tool: plan.tool, risk: plan.risk, detail: `Approved plan ${short(plan.id)} executed exactly once.`, at: Date.now() });
        track("execution_completed", { action: plan.tool, risk: plan.risk, mode: state.mode });
        toast("Execution completed", "The control runtime completed the durable one-time plan claim.");
      }
      render();
    }
  }
  if (action === "verify-chain") await refreshLive();
  if (action === "connection") {
    const connection = connectionByKey(target.dataset.key);
    if (connection) state.sheet = { kind: "detail", eyebrow: "PROVIDER CONNECTION", title: connection.label, body: `<div class="alert ${state.mode === "live" ? "healthy" : "warning"}"><strong>Connection configured</strong><p>Credential material remains in Vault and is never returned to this interface. Provider execution still fails closed if the credential is unavailable or rejected.</p></div><div class="list">${detailRow("Provider", connection.provider)}${detailRow("Account", connection.account)}${detailRow("Mutation switch", connection.mutations ? "enabled" : "disabled")}${detailRow("Credential state", connection.lastSuccess)}</div><div class="scope-list">${connection.scopes.map((scope) => badge(scope, "neutral")).join("")}</div><div class="card-title">ALLOWLISTED TARGETS</div><div class="list">${allConnectionTargets(connection).map((item) => detailRow("Target", item)).join("")}</div>` };
    render();
  }
  if (action === "plan") { const plan = PLANS.find((item) => item.id === target.dataset.id); if (plan) { const terminal = plan.terminalOutcome; const reconciliation = terminal?.terminalClassification === "reconciliation_required"; state.sheet = { kind: "detail", eyebrow: "EXECUTION PLAN", title: TOOLS.find((item) => item.name === plan.tool)?.label || plan.tool, body: `<div class="action-top">${badge(RISK[plan.risk].label, plan.risk)}${badge(plan.status.toUpperCase().replaceAll("_", " "), "neutral")}${reconciliation ? badge("RECONCILIATION REQUIRED", "danger") : ""}</div>${reconciliation ? `<div class="alert danger" style="margin-top:12px"><strong>Provider outcome is not safe to repeat</strong><p>This plan is terminal and was not completed successfully. Reconcile the exact provider outcome before creating any new plan. Automatic retry is disabled.</p></div>` : ""}<div class="list">${detailRow("Target", plan.target)}${detailRow("Plan ID", plan.id)}${detailRow("Request ID", plan.requestId)}${detailRow("Payload hash", plan.payloadHash)}${detailRow("Expiry", expiry(plan))}${terminal ? detailRow("Terminal classification", terminal.terminalClassification) : ""}${terminal ? detailRow("Retry contract", terminal.retryContract) : ""}</div>${plan.status === "approved" ? `<div class="alert warning" style="margin-top:12px"><strong>Approved and ready</strong><p>Execution performs one atomic claim. It is never automatically retried.</p></div><button class="button ${plan.risk === "destructive" ? "danger" : "warning"}" style="width:100%;margin-top:12px" data-action="execute-plan" data-id="${plan.id}">Execute once</button>` : ""}` }; render(); } }
  if (action === "audit-event") { const item = AUDIT.find((entry) => String(entry.seq) === target.dataset.seq); if (item) { state.sheet = { kind: "detail", eyebrow: `AUDIT SEQUENCE ${item.seq}`, title: item.event.replaceAll("_", " "), body: `<div class="action-top">${badge(RISK[item.risk]?.label || "RUNTIME", RISK[item.risk]?.className || "neutral")}${badge(item.status.toUpperCase(), item.status === "failed" || item.status === "denied" ? "danger" : "healthy")}</div><p class="action-description">${esc(item.detail)}</p><div class="list">${detailRow("Tool", item.tool)}${detailRow("Occurred", new Date(item.at).toISOString())}${detailRow("Sequence", String(item.seq))}</div>` }; render(); } }
  if (action === "live-mode") await refreshLive();
  if (action === "theme") { state.theme = target.dataset.value; localStorage.setItem("mcpmaster-theme", state.theme); render(); }
  if (action === "density") { state.density = target.dataset.value; localStorage.setItem("mcpmaster-density", state.density); render(); }
});

app.addEventListener("input", (event) => {
  const target = event.target;
  if (target.dataset.input === "query") { state.query = target.value; render(); }
  if (target.dataset.input === "audit-query") { state.auditQuery = target.value; render(); }
  if (target.dataset.input === "confirmation" && state.sheet?.kind === "approve") { state.sheet.phrase = target.value; render(); requestAnimationFrame(() => document.querySelector("#confirmation")?.focus()); }
  if (target.dataset.builderField) { state.builder[target.dataset.builderField] = target.value; }
});

app.addEventListener("change", (event) => {
  const target = event.target;
  if (target.dataset.filter) { state.filters[target.dataset.filter] = target.value; render(); }
  if (target.dataset.planFilter !== undefined) { state.planFilter = target.value; render(); }
  if (target.dataset.builderField) { state.builder[target.dataset.builderField] = target.value; }
});

window.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); state.sheet = { kind: "command" }; render(); }
  if (event.key === "Escape" && state.sheet) { state.sheet = null; render(); }
});

setInterval(() => {
  if (["home", "plans", "approvals"].includes(state.route)) render();
}, 1000);

track("command_center_viewed", { route: "home" });
render();
refreshProjectOS();
