import { getVercelOidcToken } from "@vercel/oidc";

const DEFAULT_GATEWAY_URL =
  "https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-machine-gateway";

export type McpJsonRpcRequest = {
  jsonrpc: "2.0";
  id?: string | number | null;
  method: string;
  params?: unknown;
};

export type McpJsonRpcResponse = {
  jsonrpc?: string;
  id?: string | number | null;
  result?: unknown;
  error?: { code?: number; message?: string; data?: unknown };
};

export async function callPandoraMachineGateway(
  request: McpJsonRpcRequest,
): Promise<McpJsonRpcResponse> {
  const gatewayUrl =
    process.env.PANDORA_MACHINE_GATEWAY_URL?.trim() || DEFAULT_GATEWAY_URL;

  // Vercel mints a short-lived signed workload identity for this exact
  // project/environment. No Vercel protection-bypass secret or Pandora
  // shared password is distributed to Pandora.
  const workloadToken = await getVercelOidcToken();
  if (!workloadToken) {
    throw new Error("pandora_workload_identity_unavailable");
  }

  const response = await fetch(gatewayUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      "mcp-protocol-version": "2025-06-18",
      "x-pandora-workload-oidc": workloadToken,
    },
    body: JSON.stringify(request),
    cache: "no-store",
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const reason =
      payload && typeof payload === "object" && "reason" in payload
        ? String((payload as { reason?: unknown }).reason || "")
        : "";
    throw new Error(
      `pandora_gateway_http_${response.status}${reason ? `:${reason}` : ""}`,
    );
  }

  if (!payload || typeof payload !== "object") {
    throw new Error("pandora_gateway_invalid_response");
  }

  return payload as McpJsonRpcResponse;
}

export async function pandoraMemoryHealth() {
  return callPandoraMachineGateway({
    jsonrpc: "2.0",
    id: crypto.randomUUID(),
    method: "tools/call",
    params: {
      name: "memory_health",
      arguments: {},
    },
  });
}

export async function pandoraMemorySearch(query: string, limit = 10) {
  const normalized = query.trim();
  if (!normalized) throw new Error("pandora_query_required");

  return callPandoraMachineGateway({
    jsonrpc: "2.0",
    id: crypto.randomUUID(),
    method: "tools/call",
    params: {
      name: "memory_search",
      arguments: {
        query: normalized,
        limit: Math.max(1, Math.min(20, Math.trunc(limit))),
      },
    },
  });
}
