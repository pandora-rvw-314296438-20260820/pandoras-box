"use strict";

const express = require("express");
const { createPandoraContainerApp } = require("./src/pandora-container-server.js");
const { handlePandoraMcp } = require("./src/pandora-mcp-handler.js");

function createVercelEntrypoint() {
  const app = express();
  app.disable("x-powered-by");
  app.set("trust proxy", 1);

  // Vercel may apply the public rewrites before invoking a root server. Support
  // both the public and rewritten MCP paths so the existing serverless handler
  // remains the only implementation of the OAuth and JSON-RPC contract.
  app.all(["/mcp", "/api/mcp"], handlePandoraMcp);
  app.all(
    [
      "/.well-known/oauth-protected-resource",
      "/.well-known/oauth-protected-resource/mcp",
    ],
    handlePandoraMcp,
  );

  // Reuse the container app for health, operator, consent, and static routes.
  // It is an Express request listener, so Vercel receives a callable default
  // server export instead of the side-effect-only dist/http-server build.
  app.use(createPandoraContainerApp());
  return app;
}

const app = createVercelEntrypoint();

module.exports = app;
module.exports.createVercelEntrypoint = createVercelEntrypoint;
