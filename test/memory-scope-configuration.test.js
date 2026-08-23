"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { buildToolConfiguration } = require("../src/runtime/service-config.js");
const { toolRegistry, executeTool } = require("../src/runtime/tool-catalog.js");
const {
  EVIDENCE_CANDIDATE_SUBMIT_SCOPE,
} = require("../src/tools/memory-evidence-intake.js");

const OIDC_TOKEN = "v".repeat(80);
const ENV_KEYS = [
  "PANDORA_MEMORY_GRANTED_SCOPES",
  "PANDORA_MEMORY_ALLOW_MUTATIONS",
  "PANDORA_MEMORY_ALLOWED_NAMESPACES",
  "PANDORA_MEMORY_BASE_URL",
];

async function withMemoryEnvironment(scopes, action) {
  const previous = new Map(ENV_KEYS.map((key) => [key, process.env[key]]));
  process.env.PANDORA_MEMORY_GRANTED_SCOPES = scopes.join(",");
  process.env.PANDORA_MEMORY_ALLOW_MUTATIONS = "true";
  process.env.PANDORA_MEMORY_ALLOWED_NAMESPACES = "real_life";
  delete process.env.PANDORA_MEMORY_BASE_URL;

  try {
    return await action();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test("Memory manifest scopes are grantable through the production configuration path", async () => {
  const memoryEntries = Object.entries(toolRegistry)
    .filter(([, definition]) => definition.handler === "memory");
  const requiredScopes = [...new Set(memoryEntries.flatMap(([, definition]) =>
    definition.manifest.requiredProviderScopes))].sort();

  assert.ok(requiredScopes.includes(EVIDENCE_CANDIDATE_SUBMIT_SCOPE));

  await withMemoryEnvironment(requiredScopes, async () => {
    for (const [name, definition] of memoryEntries) {
      const configuration = await buildToolConfiguration(name, {
        vercelOidcToken: OIDC_TOKEN,
      });
      for (const scope of definition.manifest.requiredProviderScopes) {
        assert.ok(
          configuration.memory.grantedScopes.includes(scope),
          `${name} requires an ungrantable Memory scope: ${scope}`,
        );
      }
    }

    const candidateConfiguration = await buildToolConfiguration(
      "memory.submitEvidenceCandidate",
      { vercelOidcToken: OIDC_TOKEN },
    );
    assert.ok(candidateConfiguration.memory.grantedScopes.includes(
      EVIDENCE_CANDIDATE_SUBMIT_SCOPE,
    ));
  });

  await withMemoryEnvironment(["memory:read", "memory:write"], async () => {
    const configuration = await buildToolConfiguration(
      "memory.submitEvidenceCandidate",
      { vercelOidcToken: OIDC_TOKEN },
    );

    await assert.rejects(
      () => executeTool(
        "memory.submitEvidenceCandidate",
        { namespace: "real_life" },
        configuration,
      ),
      /missing required scope.*memory:evidence-candidate:submit/,
    );
  });
});
