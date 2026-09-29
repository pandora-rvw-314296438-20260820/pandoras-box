"use strict";

const assert = require("node:assert/strict");
const { once } = require("node:events");
const fs = require("node:fs");
const test = require("node:test");
const express = require("express");

const {
  createPandoraMcpHandler,
} = require("../src/pandora-mcp-handler.js");

const consumer = fs.readFileSync("api/gemini-consumer-mcp.ts", "utf8");
const worker = fs.readFileSync("api/gemini-mcp.ts", "utf8");
const vercel = JSON.parse(fs.readFileSync("vercel.json", "utf8"));

async function withServer(handler, run) {
  const app = express();
  app.all("/api/gemini-consumer-mcp", handler);
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

test("consumer Gemini is additive and leaves the existing worker route untouched", () => {
  assert.match(consumer, /createPandoraMcpHandler/);
  assert.match(consumer, /CONSUMER_RESOURCE_PATH = '\/api\/gemini-consumer-mcp'/);
  assert.match(consumer, /role: 'operator'/);
  assert.match(consumer, /allowedRepositories: \[CANONICAL_REPOSITORY\]/);
  assert.match(consumer, /supabase\.list-projects/);
  assert.match(consumer, /supabase\.write-project-api/);
  assert.doesNotMatch(consumer, /supabase\.delete-project-api/);
  assert.doesNotMatch(consumer, /supabase\.delete-organization-api/);
  assert.match(worker, /mcpmaster:development:gemini-worker/);
  assert.equal(
    vercel.functions["api/gemini-consumer-mcp.ts"].includeFiles,
    "{.agents/**/*,config/pandora-capability-fabric-v1.json}",
  );
});

test("consumer Gemini advertises only Supabase-supported standard OAuth scopes", async () => {
  const handler = createPandoraMcpHandler({
    resourceOrigin: "https://mcpmaster.vercel.app",
    resourcePath: "/api/gemini-consumer-mcp",
    resourceName: "Pandora's Box — Consumer Gemini",
    resourceMetadataUrl: "https://mcpmaster.vercel.app/api/gemini-consumer-mcp?metadata=mcp",
    oauthScopes: ["openid", "email", "profile"],
    allowedToolNames: new Set(["github.get-repository"]),
  });
  await withServer(handler, async (origin) => {
    const metadataResponse = await fetch(
      `${origin}/api/gemini-consumer-mcp?metadata=mcp`,
    );
    assert.equal(metadataResponse.status, 200);
    const metadata = await metadataResponse.json();
    assert.equal(
      metadata.resource,
      "https://mcpmaster.vercel.app/api/gemini-consumer-mcp",
    );
    assert.deepEqual(metadata.scopes_supported, ["openid", "email", "profile"]);

    const unauthorized = await fetch(
      `${origin}/api/gemini-consumer-mcp`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "tools/list",
          params: {},
        }),
      },
    );
    assert.equal(unauthorized.status, 401);
    const challenge = unauthorized.headers.get("www-authenticate") || "";
    assert.match(
      challenge,
      /resource_metadata="https:\/\/mcpmaster\.vercel\.app\/api\/gemini-consumer-mcp\?metadata=mcp"/,
    );
    assert.match(challenge, /scope="openid email profile"/);
    assert.doesNotMatch(challenge, /pandora:approve/);
  });
});
