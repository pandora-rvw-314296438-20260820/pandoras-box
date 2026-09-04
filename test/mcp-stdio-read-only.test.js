"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const stdioRuntimePath = require.resolve("../dist/mcp-stdio.js");

function loadFreshStdioRuntime() {
  delete require.cache[stdioRuntimePath];
  return require(stdioRuntimePath);
}

test("stdio remains read-only when the legacy write environment flag is set", async () => {
  const previous = process.env.MCP_ALLOW_WRITES;
  process.env.MCP_ALLOW_WRITES = "true";
  let configurationCalls = 0;
  let executionCalls = 0;

  try {
    const { availableTools, executeStdioTool } = loadFreshStdioRuntime();
    const listed = new Set(availableTools().map((tool) => tool.name));
    assert.ok(listed.has("github.get-repository"));
    assert.equal(listed.has("github.create-issue"), false);

    const response = await executeStdioTool(
      "github.create-issue",
      { owner: "banataosystems", repo: "Pandoras-box", title: "must not run" },
      {
        async buildConfiguration() {
          configurationCalls += 1;
          return {};
        },
        async execute() {
          executionCalls += 1;
          return {};
        },
      },
    );

    assert.equal(response.isError, true);
    assert.match(response.content[0].text, /read-only stdio mode/i);
    assert.match(response.content[0].text, /durable plan/i);
    assert.equal(configurationCalls, 0);
    assert.equal(executionCalls, 0);
  } finally {
    delete require.cache[stdioRuntimePath];
    if (previous === undefined) {
      delete process.env.MCP_ALLOW_WRITES;
    } else {
      process.env.MCP_ALLOW_WRITES = previous;
    }
  }
});

test("stdio continues to execute registered read tools", async () => {
  const { executeStdioTool } = loadFreshStdioRuntime();
  const calls = [];
  const response = await executeStdioTool(
    "github.get-repository",
    { owner: "banataosystems", repo: "Pandoras-box" },
    {
      async buildConfiguration(name) {
        calls.push({ stage: "configuration", name });
        return { fixture: true };
      },
      async execute(name, args, configuration) {
        calls.push({ stage: "execute", name, args, configuration });
        return { full_name: "pandora-rvw-314296438-20260820/pandoras-box" };
      },
    },
  );

  assert.equal(response.isError, undefined);
  assert.deepEqual(calls, [
    { stage: "configuration", name: "github.get-repository" },
    {
      stage: "execute",
      name: "github.get-repository",
      args: { owner: "banataosystems", repo: "Pandoras-box" },
      configuration: { fixture: true },
    },
  ]);
  assert.deepEqual(JSON.parse(response.content[0].text).result, {
    full_name: "pandora-rvw-314296438-20260820/pandoras-box",
  });
});
