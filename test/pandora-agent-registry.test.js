"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  PANDORA_AGENTS,
  getPandoraAgent,
  normalizeWorkerId,
  pandoraAgentDisplayName,
} = require("../src/projectos/pandora-agent-registry");

const EXPECTED = Object.freeze({
  worker_a: "Atlas",
  worker_b: "Athena",
  worker_c: "Themis",
  worker_d: "Hephaestus",
  worker_e: "Aletheia",
  worker_f: "Hermes",
  worker_g: "Apollo",
  worker_h: "Plutus",
  worker_i: "Daedalus",
  worker_j: "Argus",
});

test("Greek agent names cover Worker A-J exactly once", () => {
  assert.equal(PANDORA_AGENTS.length, 10);
  assert.deepEqual(
    Object.fromEntries(PANDORA_AGENTS.map(({ workerId, agentName }) => [workerId, agentName])),
    EXPECTED,
  );
  assert.equal(new Set(PANDORA_AGENTS.map(({ agentName }) => agentName)).size, 10);
});

test("machine worker identifiers remain stable compatibility keys", () => {
  for (const workerId of Object.keys(EXPECTED)) {
    assert.equal(normalizeWorkerId(workerId), workerId);
    assert.equal(getPandoraAgent(workerId).workerId, workerId);
  }

  assert.equal(normalizeWorkerId("Worker A"), "worker_a");
  assert.equal(normalizeWorkerId("worker-j"), "worker_j");
  assert.equal(normalizeWorkerId("not-a-worker"), null);
});

test("human-facing labels use Greek agent names and optionally preserve legacy aliases", () => {
  assert.equal(pandoraAgentDisplayName("worker_b"), "Athena Agent");
  assert.equal(
    pandoraAgentDisplayName("Worker G", { includeLegacy: true }),
    "Apollo Agent (Worker G)",
  );
  assert.equal(pandoraAgentDisplayName("external_worker"), "external_worker");
});
