import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const BASE44_APP_ID = "6a94ecfadf75736cd4ebf7e1";
const BASE44_ORIGIN = "https://app--build-with-pandora.base44.app";
const BASE44_USER_ME =
  `https://base44.app/api/apps/${BASE44_APP_ID}/entities/User/me`;

type JsonRecord = Record<string, unknown>;

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function textValue(value: unknown, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function cors(origin: string | null) {
  if (origin !== BASE44_ORIGIN) return {};
  return {
    "access-control-allow-origin": BASE44_ORIGIN,
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-max-age": "600",
    "vary": "Origin",
  };
}

function response(
  body: unknown,
  status: number,
  origin: string | null,
  requestId: string,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
      "x-pandora-request-id": requestId,
      ...cors(origin),
    },
  });
}

function bearerToken(req: Request) {
  const value = req.headers.get("authorization") || "";
  if (!value.startsWith("Bearer ")) return null;
  const token = value.slice(7).trim();
  if (token.length < 20 || token.length > 8192) return null;
  return token;
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function validateBase44User(token: string) {
  let res: Response;
  try {
    res = await fetch(BASE44_USER_ME, {
      method: "GET",
      headers: {
        "authorization": `Bearer ${token}`,
        "accept": "application/json",
        "x-app-id": BASE44_APP_ID,
        "x-origin-url": BASE44_ORIGIN,
      },
      signal: AbortSignal.timeout(5000),
    });
  } catch {
    throw new Error("BASE44_AUTH_UNAVAILABLE");
  }
  if (res.status === 401 || res.status === 403) {
    throw new Error("BASE44_AUTH_INVALID");
  }
  if (!res.ok) throw new Error("BASE44_AUTH_UNAVAILABLE");

  const user = asRecord(await res.json());
  if (
    textValue(user.app_id) !== BASE44_APP_ID ||
    !textValue(user.id) ||
    user.disabled === true ||
    user.is_verified !== true
  ) {
    throw new Error("BASE44_IDENTITY_REJECTED");
  }
  return user;
}

function normalizedTheatre(experienceValue: unknown, theatreValue: unknown) {
  const experience = asRecord(experienceValue);
  const theatre = asRecord(theatreValue);
  const buildJobId = textValue(theatre.build_job_id);
  if (!buildJobId) {
    return {
      source: "pandora_project_experience_projection",
      mode: "idle",
      buildJobId: null,
      ownerState: textValue(experience.experience_state, "START"),
      ownerStage: null,
      progressPercent: null,
      publicMessage: textValue(
        experience.public_message,
        "What do you want to build?",
      ),
      previewUrl: null,
      liveUrl: null,
      needsYou: experience.needs_you === true,
      retryAvailable: experience.retry_available === true,
      lastEventAt: textValue(experience.last_transition_at) || null,
      updatedAt: textValue(experience.updated_at) || null,
    };
  }

  const activeBuildJobId = textValue(experience.active_build_job_id);
  return {
    source: "pandora_build_theatre_projection",
    mode: activeBuildJobId === buildJobId ? "active" : "result",
    buildJobId,
    ownerState: textValue(theatre.owner_state) || null,
    ownerStage: textValue(theatre.owner_stage) || null,
    progressPercent:
      typeof theatre.progress_percent === "number"
        ? theatre.progress_percent
        : null,
    publicMessage: textValue(
      experience.public_message,
      textValue(theatre.public_message, "Pandora is working."),
    ),
    previewUrl: textValue(theatre.preview_url) || null,
    liveUrl: textValue(theatre.live_url) || null,
    needsYou: theatre.needs_you === true,
    retryAvailable: theatre.retry_available === true,
    lastEventAt: textValue(theatre.last_event_at) || null,
    updatedAt: textValue(theatre.updated_at) || null,
  };
}

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID();
  const origin = req.headers.get("origin");

  if (origin !== BASE44_ORIGIN) {
    return response(
      { ok: false, error: "ORIGIN_NOT_ALLOWED" },
      403,
      null,
      requestId,
    );
  }

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "cache-control": "no-store, max-age=0",
        "x-content-type-options": "nosniff",
        "x-pandora-request-id": requestId,
        ...cors(origin),
      },
    });
  }

  if (req.method !== "GET") {
    return response(
      { ok: false, error: "METHOD_NOT_ALLOWED" },
      405,
      origin,
      requestId,
    );
  }

  const token = bearerToken(req);
  if (!token) {
    return response(
      { ok: false, error: "AUTH_REQUIRED" },
      401,
      origin,
      requestId,
    );
  }

  try {
    if (!SUPABASE_URL || !SERVICE_ROLE) throw new Error("SERVICE_UNAVAILABLE");
    const base44User = await validateBase44User(token);
    const base44UserId = textValue(base44User.id);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: link, error: linkError } = await admin
      .from("pandora_base44_identity_links")
      .select("pandora_user_id, organization_id, enabled")
      .eq("base44_app_id", BASE44_APP_ID)
      .eq("base44_user_id", base44UserId)
      .eq("enabled", true)
      .maybeSingle();
    if (linkError) throw new Error("IDENTITY_LINK_UNAVAILABLE");
    if (!link) throw new Error("IDENTITY_NOT_LINKED");

    const userId = String(link.pandora_user_id);
    const organizationId = String(link.organization_id);

    const { data: membership, error: membershipError } = await admin
      .from("memberships")
      .select("role, status")
      .eq("organization_id", organizationId)
      .eq("user_id", userId)
      .eq("status", "active")
      .maybeSingle();
    if (membershipError) throw new Error("MEMBERSHIP_UNAVAILABLE");
    if (!membership) throw new Error("MEMBERSHIP_REQUIRED");

    const key = await sha256Hex(
      `${userId}:GET:pandora-base44-read-bridge`,
    );
    const { data: limit, error: limitError } = await admin.rpc(
      "consume_runtime_rate_limit",
      {
        p_organization_id: organizationId,
        p_key_hash: key,
        p_limit: 120,
        p_window_seconds: 60,
      },
    );
    if (limitError) throw new Error("RATE_LIMIT_UNAVAILABLE");
    if (asRecord(limit).allowed !== true) throw new Error("RATE_LIMITED");

    const projectId = new URL(req.url).searchParams.get("projectId") || "";
    if (!/^[0-9a-f-]{36}$/i.test(projectId)) {
      return response(
        { ok: false, error: "PROJECT_ID_REQUIRED" },
        400,
        origin,
        requestId,
      );
    }

    const [projectResult, experienceResult, theatreResult] = await Promise.all([
      admin
        .from("projectos_projects")
        .select("id, project_key, objective, status, organization_id, updated_at")
        .eq("id", projectId)
        .eq("organization_id", organizationId)
        .maybeSingle(),
      admin
        .from("pandora_project_experience_projection")
        .select(
          "project_id, organization_id, experience_state, public_message, needs_you, retry_available, current_verified, can_change, can_focus, can_undo, can_publish, can_rollback, current_version_id, current_preview_deployment_id, production_version_id, production_deployment_id, verification_summary, active_build_job_id, last_transition_at, updated_at",
        )
        .eq("project_id", projectId)
        .eq("organization_id", organizationId)
        .maybeSingle(),
      admin
        .from("pandora_build_theatre_projection")
        .select(
          "project_id, organization_id, build_job_id, owner_state, owner_stage, progress_percent, public_message, preview_url, live_url, needs_you, retry_available, last_event_at, updated_at",
        )
        .eq("project_id", projectId)
        .eq("organization_id", organizationId)
        .maybeSingle(),
    ]);

    if (projectResult.error) throw new Error("PROJECT_READ_FAILED");
    if (experienceResult.error) throw new Error("EXPERIENCE_READ_FAILED");
    if (theatreResult.error) throw new Error("THEATRE_READ_FAILED");
    if (!projectResult.data) {
      return response(
        { ok: false, error: "PROJECT_NOT_FOUND" },
        404,
        origin,
        requestId,
      );
    }

    const experience = asRecord(experienceResult.data);
    const theatre = normalizedTheatre(
      experienceResult.data,
      theatreResult.data,
    );

    return response(
      {
        ok: true,
        source: "pandora",
        requestId,
        project: {
          id: projectResult.data.id,
          projectKey: projectResult.data.project_key,
          objective: projectResult.data.objective,
          status: projectResult.data.status,
          updatedAt: projectResult.data.updated_at,
        },
        experience: {
          state: textValue(experience.experience_state, "START"),
          publicMessage: textValue(
            experience.public_message,
            "What do you want to build?",
          ),
          needsYou: experience.needs_you === true,
          retryAvailable: experience.retry_available === true,
          currentVerified: experience.current_verified === true,
          canChange: experience.can_change === true,
          canFocus: experience.can_focus === true,
          canUndo: experience.can_undo === true,
          canPublish: experience.can_publish === true,
          canRollback: experience.can_rollback === true,
          currentVersionId: textValue(experience.current_version_id) || null,
          currentPreviewDeploymentId:
            textValue(experience.current_preview_deployment_id) || null,
          productionVersionId:
            textValue(experience.production_version_id) || null,
          productionDeploymentId:
            textValue(experience.production_deployment_id) || null,
          verificationSummary: experience.verification_summary ?? null,
          updatedAt: textValue(experience.updated_at) || null,
        },
        buildTheatre: theatre,
        preview: {
          url: theatre.previewUrl,
          verified: experience.current_verified === true,
          live: Boolean(theatre.liveUrl) &&
            Boolean(textValue(experience.production_deployment_id)),
        },
      },
      200,
      origin,
      requestId,
    );
  } catch (error) {
    const code = error instanceof Error ? error.message : "BRIDGE_FAILED";
    const status =
      code === "BASE44_AUTH_INVALID" || code === "AUTH_REQUIRED"
        ? 401
        : code === "BASE44_IDENTITY_REJECTED" ||
            code === "IDENTITY_NOT_LINKED" ||
            code === "MEMBERSHIP_REQUIRED"
        ? 403
        : code === "RATE_LIMITED"
        ? 429
        : 503;
    return response({ ok: false, error: code }, status, origin, requestId);
  }
});
