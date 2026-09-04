"use strict";

const assert = require("node:assert/strict");
const { once } = require("node:events");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const express = require("express");
const entrypoint = require("../vercel-entrypoint.js");
const { handleProjectOsMcp } = require("../dist/projectos-mcp-handler.js");

const projectRoot = path.resolve(__dirname, "..");

async function withServer(app, run) {
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    server.close();
    await once(server, "close");
  }
}

async function snapshot(response) {
  return {
    status: response.status,
    authenticate: response.headers.get("www-authenticate"),
    cacheControl: response.headers.get("cache-control"),
    body: await response.json(),
  };
}

function serverlessReferenceApp() {
  const app = express();
  app.all("/api/mcp", handleProjectOsMcp);
  return app;
}

test("Vercel selects the callable source entrypoint and preserves governed web routing", () => {
  const packageJson = JSON.parse(readFileSync(path.join(projectRoot, "package.json"), "utf8"));
  const vercelConfig = JSON.parse(readFileSync(path.join(projectRoot, "vercel.json"), "utf8"));
  const ignored = readFileSync(path.join(projectRoot, ".vercelignore"), "utf8");

  assert.equal(packageJson.main, "vercel-entrypoint.js");
  assert.equal(vercelConfig.buildCommand, "npm run build && bash scripts/build-vercel-pandora-web.sh");
  assert.equal(vercelConfig.framework, "express");
  assert.equal(vercelConfig.env.PANDORA_TRUSTED_EXTERNAL_REVIEW_APP_ID, undefined);
  assert.equal(
    vercelConfig.functions["api/operator.ts"].includeFiles,
    "{supabase/migrations/**,docs/status/**,SOURCE_AUTHORITY_POLICY.json}",
  );

  const rewrites = new Map(vercelConfig.rewrites.map(({ source, destination }) => [source, destination]));
  assert.equal(rewrites.get("/"), "/pandora-web/index.html");
  assert.equal(rewrites.get("/health"), "/api/health");
  assert.equal(rewrites.get("/control-tower"), "/control-tower/index.html");

  assert.equal(typeof entrypoint, "function");
  assert.match(ignored, /^dist\/$/m);
  assert.match(ignored, /^apps\/meta-business-mcp\/dist\/$/m);
  assert.match(ignored, /^packages\/shared-security\/dist\/$/m);
});

test("root entrypoint preserves serverless MCP metadata and challenge responses", async () => {
  await withServer(serverlessReferenceApp(), async (referenceOrigin) => {
    await withServer(entrypoint, async (entrypointOrigin) => {
      for (const request of [
        { publicPath: "/mcp?metadata=mcp", apiPath: "/api/mcp?metadata=mcp" },
        {
          publicPath: "/mcp",
          apiPath: "/api/mcp",
          init: {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              jsonrpc: "2.0",
              id: 1,
              method: "tools/call",
              params: { name: "projectos_list_plans", arguments: {} },
            }),
          },
        },
      ]) {
        const [expected, actual] = await Promise.all([
          fetch(`${referenceOrigin}${request.apiPath}`, request.init).then(snapshot),
          fetch(`${entrypointOrigin}${request.publicPath}`, request.init).then(snapshot),
        ]);
        assert.deepEqual(actual, expected);
      }
    });
  });
});

test("root entrypoint accepts both well-known paths and Vercel's rewritten API path", async () => {
  await withServer(entrypoint, async (origin) => {
    for (const pathName of [
      "/.well-known/oauth-protected-resource",
      "/.well-known/oauth-protected-resource/mcp",
      "/api/mcp?metadata=mcp",
    ]) {
      const response = await fetch(`${origin}${pathName}`);
      assert.equal(response.status, 200, pathName);
      assert.equal((await response.json()).resource, "https://mcpmaster.vercel.app/mcp", pathName);
    }
  });
});
