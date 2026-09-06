import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.57.2";

import {
  asRecord,
  type JsonRecord,
  sha256Hex,
  textValue,
} from "./runtime-common.ts";

const BUILD_KINDS = new Set([
  "website",
  "web_app",
  "mobile_app",
  "internal_tool",
  "automation",
  "api_backend",
  "full_system",
  "help_me_decide",
]);

type CreateContext = {
  userId: string;
  organizationId: string;
};

function buildKind(value: unknown) {
  const kind = textValue(value).toLowerCase();
  if (!BUILD_KINDS.has(kind)) throw new Error("INVALID_BUILD_KIND");
  return kind;
}

export async function createCustomerProject(
  client: SupabaseClient,
  context: CreateContext,
  body: JsonRecord,
  idempotencyKey: string,
): Promise<JsonRecord> {
  const name = textValue(body.name);
  const objective = textValue(body.objective);
  const kind = buildKind(body.buildKind);
  if (name.length < 2 || name.length > 100) {
    throw new Error("INVALID_PROJECT_NAME");
  }
  if (objective.length < 10 || objective.length > 50000) {
    throw new Error("INVALID_OBJECTIVE");
  }
  if (idempotencyKey.length < 8 || idempotencyKey.length > 200) {
    throw new Error("IDEMPOTENCY_KEY_REQUIRED");
  }

  const requestSha256 = await sha256Hex(JSON.stringify({
    name,
    objective,
    buildKind: kind,
  }));
  const { data, error } = await client.rpc(
    "pandora_create_customer_project_v1",
    {
      p_organization_id: context.organizationId,
      p_requester_id: context.userId,
      p_idempotency_key: idempotencyKey,
      p_request_sha256: requestSha256,
      p_name: name,
      p_objective: objective,
      p_build_kind: kind,
    },
  );

  if (error) {
    if (error.message?.includes("PROJECT_CREATE_IDEMPOTENCY_COLLISION")) {
      throw new Error("PROJECT_CREATE_IDEMPOTENCY_COLLISION");
    }
    if (error.message?.includes("PROJECT_CREATE_NOT_ALLOWED")) {
      throw new Error("ORGANIZATION_ACCESS_REQUIRED");
    }
    throw new Error("BACKEND_WRITE_FAILED");
  }

  const result = asRecord(data);
  const project = asRecord(result.project);
  if (!textValue(project.id) || !textValue(project.project_key)) {
    throw new Error("BACKEND_WRITE_FAILED");
  }

  return project;
}
