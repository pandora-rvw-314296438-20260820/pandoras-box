"use strict";

const PANDORA_AGENTS = Object.freeze([
  Object.freeze({
    workerId: "worker_a",
    legacyName: "Worker A",
    agentName: "Atlas",
    displayName: "Atlas Agent",
    domain: "Control Plane",
    responsibility: "Durable state, ProjectSpec, job engine, and orchestration",
  }),
  Object.freeze({
    workerId: "worker_b",
    legacyName: "Worker B",
    agentName: "Athena",
    displayName: "Athena Agent",
    domain: "Intelligence",
    responsibility: "Intent compilation, model routing, and bounded context",
  }),
  Object.freeze({
    workerId: "worker_c",
    legacyName: "Worker C",
    agentName: "Themis",
    displayName: "Themis Agent",
    domain: "Governance",
    responsibility: "Policy, authorization, approvals, and secrets brokerage",
  }),
  Object.freeze({
    workerId: "worker_d",
    legacyName: "Worker D",
    agentName: "Hephaestus",
    displayName: "Hephaestus Agent",
    domain: "Build Runtime",
    responsibility: "Sandboxed build execution, workspace operations, and repair",
  }),
  Object.freeze({
    workerId: "worker_e",
    legacyName: "Worker E",
    agentName: "Aletheia",
    displayName: "Aletheia Agent",
    domain: "Verification",
    responsibility: "Independent QA, acceptance, and release proof",
  }),
  Object.freeze({
    workerId: "worker_f",
    legacyName: "Worker F",
    agentName: "Hermes",
    displayName: "Hermes Agent",
    domain: "Project Runtime",
    responsibility: "Preview, deployment, domains, and provider runtime",
  }),
  Object.freeze({
    workerId: "worker_g",
    legacyName: "Worker G",
    agentName: "Apollo",
    displayName: "Apollo Agent",
    domain: "Product Experience",
    responsibility: "Flutter, customer journey, preview, and publish experience",
  }),
  Object.freeze({
    workerId: "worker_h",
    legacyName: "Worker H",
    agentName: "Plutus",
    displayName: "Plutus Agent",
    domain: "Business Intelligence",
    responsibility: "Economics, outcomes, analytics, and optimization",
  }),
  Object.freeze({
    workerId: "worker_i",
    legacyName: "Worker I",
    agentName: "Daedalus",
    displayName: "Daedalus Agent",
    domain: "Trusted Primitives",
    responsibility: "Reusable building blocks and composition",
  }),
  Object.freeze({
    workerId: "worker_j",
    legacyName: "Worker J",
    agentName: "Argus",
    displayName: "Argus Agent",
    domain: "Integration & Release",
    responsibility: "Cross-agent convergence, E2E proof, and production readiness",
  }),
]);

const PANDORA_AGENT_BY_WORKER_ID = Object.freeze(
  Object.fromEntries(PANDORA_AGENTS.map((agent) => [agent.workerId, agent])),
);

const PANDORA_AGENT_BY_LEGACY_NAME = Object.freeze(
  Object.fromEntries(PANDORA_AGENTS.map((agent) => [agent.legacyName, agent])),
);

function normalizeWorkerId(value) {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (/^worker_[a-j]$/.test(normalized)) return normalized;

  const legacyMatch = value.trim().match(/^worker\s*([a-j])$/i);
  if (legacyMatch) return `worker_${legacyMatch[1].toLowerCase()}`;

  return null;
}

function getPandoraAgent(value) {
  const workerId = normalizeWorkerId(value);
  return workerId ? PANDORA_AGENT_BY_WORKER_ID[workerId] || null : null;
}

function pandoraAgentDisplayName(value, { includeLegacy = false } = {}) {
  const agent = getPandoraAgent(value);
  if (!agent) return value;
  return includeLegacy
    ? `${agent.displayName} (${agent.legacyName})`
    : agent.displayName;
}

module.exports = {
  PANDORA_AGENTS,
  PANDORA_AGENT_BY_WORKER_ID,
  PANDORA_AGENT_BY_LEGACY_NAME,
  normalizeWorkerId,
  getPandoraAgent,
  pandoraAgentDisplayName,
};
