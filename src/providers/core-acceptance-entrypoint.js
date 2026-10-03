"use strict";

const { pathToFileURL } = require("node:url");
const { handleBedrockChat } = require("./aws-bedrock-chat-http.js");
const nativeImport = new Function("specifier", "return import(specifier)");

// This entrypoint is the only function in the restricted acceptance artifact.
// No generic operator, Memory, cron or control endpoint is imported or routed.
module.exports = async function coreAcceptanceBridge(req, res) {
  // Vercel's general helpers eagerly read the body. This restricted function
  // disables them and adds response helpers only, leaving admission and the
  // existing 4 KiB ticket-body limit in control of the original request stream.
  if (typeof res.status !== "function") res.status = status => { res.statusCode = status; return res; };
  if (typeof res.json !== "function") res.json = value => {
    res.setHeader("content-type", "application/json; charset=utf-8"); res.end(JSON.stringify(value)); return res;
  };
  res.setHeader("cache-control", "no-store");
  res.setHeader("x-content-type-options", "nosniff");
  try {
    const path = require.resolve("../../supabase/functions/_shared/core-acceptance-profile.mjs");
    const { resolveCoreRuntimeProfile, assertRuntimeRequestBinding } = await nativeImport(pathToFileURL(path).href);
    const profile = await resolveCoreRuntimeProfile(process.env, { role: "bridge" });
    if (!profile.acceptance) throw Object.assign(Error("CORE_RUNTIME_PROFILE_INVALID"), { code: "CORE_RUNTIME_PROFILE_INVALID" });
    assertRuntimeRequestBinding(profile, req.headers);
    const url = new URL(String(req.url || ""), "https://acceptance.invalid");
    if (url.pathname !== "/api/operations-inference" || url.searchParams.get("operation") !== "bedrock-chat" ||
        [...url.searchParams.keys()].some(key => key !== "operation") || url.searchParams.getAll("operation").length !== 1) {
      return res.status(404).json({ ok: false, error: "CORE_RUNTIME_OPERATION_DENIED" });
    }
    return await handleBedrockChat(req, res);
  } catch (error) {
    const code = /^CORE_RUNTIME_(?:PROFILE_INVALID|TARGET_MISMATCH|BINDING_MISMATCH)$/.test(error?.code || "")
      ? error.code : "CORE_RUNTIME_PROFILE_INVALID";
    if (!res.headersSent) return res.status(400).json({ ok: false, error: code, retryable: false });
    res.end();
  }
};
