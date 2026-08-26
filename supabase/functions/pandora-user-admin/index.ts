import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = requiredEnv("SUPABASE_URL");
const SUPABASE_ANON_KEY = requiredEnv("SUPABASE_ANON_KEY");
const SUPABASE_SERVICE_ROLE_KEY = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
const FUNCTION_NAME = "pandora-user-admin";
const ROLES = ["owner", "admin", "operator", "member", "viewer"] as const;
type MemberRole = typeof ROLES[number];
type Json = Record<string, unknown>;
type Client = ReturnType<typeof createClient>;
type Context = {
  userId: string;
  organizationId: string;
  role: "owner" | "admin";
  userClient: Client;
  adminClient: Client;
};

class ApiError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
    this.name = "ApiError";
  }
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function record(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

function uuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function parseOrigins(): Set<string> {
  const configured = Deno.env.get("PANDORA_ALLOWED_ORIGINS") || "";
  const candidates = [
    "https://mcpmaster.vercel.app",
    "https://mcpmaster-hazel.vercel.app",
    "https://mcpmaster-mbanatao-dc676069.vercel.app",
    ...configured.split(","),
  ];
  const result = new Set<string>();
  for (const candidate of candidates) {
    const raw = candidate.trim();
    if (!raw) continue;
    try {
      const parsed = new URL(raw);
      if (parsed.protocol === "https:" && parsed.origin === raw) result.add(raw);
    } catch {
      // Invalid configuration cannot broaden browser access.
    }
  }
  return result;
}

const ALLOWED_ORIGINS = parseOrigins();
const CORS_HEADERS = {
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info, x-organization-id",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-max-age": "86400",
  "vary": "Origin",
};

function corsOrigin(req: Request): string | null {
  const origin = req.headers.get("origin");
  if (!origin) return null;
  try {
    return new URL(origin).origin === origin && ALLOWED_ORIGINS.has(origin)
      ? origin
      : null;
  } catch {
    return null;
  }
}

function response(
  body: unknown,
  status: number,
  requestId: string,
  origin: string | null,
): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      ...(origin ? { "access-control-allow-origin": origin } : {}),
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
      "x-request-id": requestId,
    },
  });
}

function route(pathname: string): string {
  const stripped = pathname
    .replace(new RegExp(`^/functions/v1/${FUNCTION_NAME}(?=/|$)`), "")
    .replace(new RegExp(`^/${FUNCTION_NAME}(?=/|$)`), "")
    .replace(/\/+$/, "");
  return stripped ? (stripped.startsWith("/") ? stripped : `/${stripped}`) : "/";
}

function email(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "INVALID_EMAIL", "A valid email address is required.");
  }
  const normalized = value.trim().toLowerCase();
  if (
    normalized.length < 3 || normalized.length > 320 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)
  ) {
    throw new ApiError(400, "INVALID_EMAIL", "A valid email address is required.");
  }
  return normalized;
}

function optionalText(value: unknown, max: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new ApiError(400, "INVALID_INPUT", "The request contains invalid text.");
  }
  const normalized = value.trim();
  if (!normalized) return null;
  if (normalized.length > max) {
    throw new ApiError(400, "INVALID_INPUT", "The request contains text that is too long.");
  }
  return normalized;
}

function role(value: unknown): MemberRole {
  if (typeof value !== "string" || !ROLES.includes(value as MemberRole)) {
    throw new ApiError(400, "INVALID_ROLE", "A supported organization role is required.");
  }
  return value as MemberRole;
}

async function jsonBody(req: Request): Promise<Json> {
  const declared = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > 8192) {
    throw new ApiError(413, "BODY_TOO_LARGE", "The request body is too large.");
  }
  const raw = await req.text();
  if (new TextEncoder().encode(raw).byteLength > 8192) {
    throw new ApiError(413, "BODY_TOO_LARGE", "The request body is too large.");
  }
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    return parsed as Json;
  } catch {
    throw new ApiError(400, "INVALID_JSON", "A valid JSON object is required.");
  }
}

async function authenticate(req: Request): Promise<Context> {
  const authorization = req.headers.get("authorization") || "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) {
    throw new ApiError(401, "SIGN_IN_REQUIRED", "Sign in is required.");
  }
  const organizationId = req.headers.get("x-organization-id")?.trim() || "";
  if (!uuid(organizationId)) {
    throw new ApiError(400, "ORGANIZATION_REQUIRED", "A valid organization must be selected.");
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const jwt = authorization.replace(/^Bearer\s+/i, "");
  const { data: authData, error: authError } = await userClient.auth.getUser(jwt);
  if (authError || !authData.user || authData.user.is_anonymous === true) {
    throw new ApiError(401, "SIGN_IN_REQUIRED", "A signed-in account is required.");
  }

  const { data: membership, error: membershipError } = await userClient
    .from("memberships")
    .select("role, status")
    .eq("organization_id", organizationId)
    .eq("user_id", authData.user.id)
    .eq("status", "active")
    .maybeSingle();
  const membershipRole = String(membership?.role || "");
  if (membershipError || !["owner", "admin"].includes(membershipRole)) {
    throw new ApiError(
      403,
      "ADMIN_ROLE_REQUIRED",
      "An active owner or administrator role is required.",
    );
  }

  return {
    userId: authData.user.id,
    organizationId,
    role: membershipRole as "owner" | "admin",
    userClient,
    adminClient: createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}

async function rateLimit(context: Context, method: "GET" | "POST"): Promise<void> {
  const keyHash = await sha256(
    `${context.userId}:${context.organizationId}:${method}:${FUNCTION_NAME}`,
  );
  const { data, error } = await context.adminClient.rpc("consume_runtime_rate_limit", {
    p_organization_id: context.organizationId,
    p_key_hash: keyHash,
    p_limit: method === "GET" ? 60 : 10,
    p_window_seconds: 60,
  });
  if (error) {
    throw new ApiError(503, "RATE_LIMIT_UNAVAILABLE", "User administration is temporarily unavailable.");
  }
  if (record(data).allowed !== true) {
    throw new ApiError(429, "RATE_LIMITED", "Too many requests. Try again shortly.");
  }
}

async function findUser(adminClient: Client, targetEmail: string): Promise<Json | null> {
  const perPage = 1000;
  for (let page = 1; page <= 50; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
    if (error) {
      throw new ApiError(503, "USER_DIRECTORY_UNAVAILABLE", "The user directory is temporarily unavailable.");
    }
    const match = (data.users || []).find((user) =>
      typeof user.email === "string" && user.email.toLowerCase() === targetEmail
    );
    if (match) return match as unknown as Json;
    if ((data.users || []).length < perPage) return null;
  }
  throw new ApiError(503, "USER_DIRECTORY_LIMIT_REACHED", "The user directory could not be searched safely.");
}

function inviteRedirect(): string | undefined {
  const raw = Deno.env.get("PANDORA_INVITE_REDIRECT_URL")?.trim();
  if (!raw) return undefined;
  try {
    const parsed = new URL(raw);
    return parsed.protocol === "https:" ? parsed.toString() : undefined;
  } catch {
    return undefined;
  }
}

async function createOrFindUser(
  context: Context,
  targetEmail: string,
  displayName: string | null,
  timezone: string,
  targetRole: MemberRole,
): Promise<{ user: Json; created: boolean; inviteSent: boolean }> {
  const existing = await findUser(context.adminClient, targetEmail);
  if (existing) return { user: existing, created: false, inviteSent: false };

  const options: { data: Json; redirectTo?: string } = {
    data: {
      display_name: displayName,
      timezone,
      invited_organization_id: context.organizationId,
      invited_role: targetRole,
      invited_by: context.userId,
    },
  };
  const redirectTo = inviteRedirect();
  if (redirectTo) options.redirectTo = redirectTo;

  const { data, error } = await context.adminClient.auth.admin
    .inviteUserByEmail(targetEmail, options);
  if (!error && data.user) {
    return { user: data.user as unknown as Json, created: true, inviteSent: true };
  }

  // A concurrent request may have created the same Auth account.
  const raced = await findUser(context.adminClient, targetEmail);
  if (raced) return { user: raced, created: false, inviteSent: false };
  throw new ApiError(502, "INVITE_DELIVERY_FAILED", "Pandora could not create and invite this user.");
}

function membershipError(error: { message?: string } | null): ApiError {
  const message = (error?.message || "").toLowerCase();
  if (
    message.includes("active owner or administrator membership required") ||
    message.includes("authenticated non-anonymous administrator required")
  ) {
    return new ApiError(403, "ADMIN_ROLE_REQUIRED", "An active owner or administrator role is required.");
  }
  if (message.includes("administrators cannot grant owner or admin roles")) {
    return new ApiError(403, "ROLE_GRANT_NOT_ALLOWED", "Only an owner can grant this role.");
  }
  if (message.includes("membership already exists with another role")) {
    return new ApiError(409, "MEMBERSHIP_ALREADY_EXISTS", "This user already belongs to the organization with another role.");
  }
  if (message.includes("cannot change your own membership")) {
    return new ApiError(409, "SELF_MEMBERSHIP_CHANGE_FORBIDDEN", "Use the dedicated ownership workflow to change your own role.");
  }
  return new ApiError(500, "MEMBERSHIP_CREATE_FAILED", "Pandora could not add this user to the organization.");
}

async function invite(req: Request, context: Context, requestId: string, origin: string | null): Promise<Response> {
  await rateLimit(context, "POST");
  const body = await jsonBody(req);
  const targetEmail = email(body.email);
  const displayName = optionalText(body.displayName ?? body.display_name, 120);
  const timezone = optionalText(body.timezone, 64) || "UTC";
  const targetRole = role(body.role);
  if (context.role === "admin" && ["owner", "admin"].includes(targetRole)) {
    throw new ApiError(403, "ROLE_GRANT_NOT_ALLOWED", "Only an owner can grant this role.");
  }

  const authResult = await createOrFindUser(
    context,
    targetEmail,
    displayName,
    timezone,
    targetRole,
  );
  const targetUserId = String(authResult.user.id || "");
  if (!uuid(targetUserId)) {
    throw new ApiError(502, "AUTH_USER_INVALID", "Pandora received an invalid user record from Auth.");
  }

  const { data, error } = await context.adminClient.rpc(
    "pandora_admin_add_organization_member",
    {
      p_actor_user_id: context.userId,
      p_organization_id: context.organizationId,
      p_target_user_id: targetUserId,
      p_role: targetRole,
    },
  );
  if (error) {
    if (authResult.created) {
      const membershipCheck = await context.adminClient
        .from("memberships")
        .select("organization_id")
        .eq("organization_id", context.organizationId)
        .eq("user_id", targetUserId)
        .maybeSingle();
      // Delete only when we positively proved that no membership persisted.
      if (!membershipCheck.error && !membershipCheck.data) {
        await context.adminClient.auth.admin.deleteUser(targetUserId);
      }
    }
    throw membershipError(error);
  }

  const membership = record(data);
  return response(
    {
      user: { id: targetUserId, email: targetEmail, displayName },
      membership,
      inviteSent: authResult.inviteSent,
      existingAccount: !authResult.created,
      requestId,
    },
    membership.created === true || membership.restored === true ? 201 : 200,
    requestId,
    origin,
  );
}

async function members(context: Context, requestId: string, origin: string | null): Promise<Response> {
  await rateLimit(context, "GET");
  const { data: memberships, error } = await context.userClient
    .from("memberships")
    .select("user_id, role, status, invited_by, joined_at, created_at, updated_at")
    .eq("organization_id", context.organizationId)
    .order("created_at", { ascending: true });
  if (error) {
    throw new ApiError(500, "MEMBERSHIP_LIST_FAILED", "Pandora could not load organization users.");
  }

  const wanted = new Set((memberships || []).map((item) => String(item.user_id)));
  const directory = new Map<string, Json>();
  const perPage = 1000;
  for (let page = 1; page <= 50 && directory.size < wanted.size; page += 1) {
    const listed = await context.adminClient.auth.admin.listUsers({ page, perPage });
    if (listed.error) {
      throw new ApiError(503, "USER_DIRECTORY_UNAVAILABLE", "The user directory is temporarily unavailable.");
    }
    for (const user of listed.data.users || []) {
      if (wanted.has(user.id)) directory.set(user.id, user as unknown as Json);
    }
    if ((listed.data.users || []).length < perPage) break;
  }

  const result = (memberships || []).map((membership) => {
    const user = directory.get(String(membership.user_id)) || {};
    const metadata = record(user.user_metadata);
    return {
      id: membership.user_id,
      email: typeof user.email === "string" ? user.email : null,
      displayName: typeof metadata.display_name === "string" ? metadata.display_name : null,
      role: membership.role,
      status: membership.status,
      invitedBy: membership.invited_by,
      joinedAt: membership.joined_at,
      createdAt: membership.created_at,
      updatedAt: membership.updated_at,
    };
  });
  return response(
    { organizationId: context.organizationId, members: result, requestId },
    200,
    requestId,
    origin,
  );
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const suppliedOrigin = req.headers.get("origin");
  const origin = corsOrigin(req);
  if (suppliedOrigin && !origin) {
    return response(
      { code: "ORIGIN_NOT_ALLOWED", plainMessage: "This browser origin is not allowed.", requestId },
      403,
      requestId,
      null,
    );
  }
  if (req.method === "OPTIONS") return response({}, 204, requestId, origin);

  try {
    const context = await authenticate(req);
    const pathname = route(new URL(req.url).pathname);
    if (req.method === "GET" && (pathname === "/" || pathname === "/members")) {
      return await members(context, requestId, origin);
    }
    if (req.method === "POST" && (pathname === "/" || pathname === "/invite")) {
      return await invite(req, context, requestId, origin);
    }
    return response(
      { code: "NOT_FOUND", plainMessage: "This user-administration operation is not available.", requestId },
      404,
      requestId,
      origin,
    );
  } catch (error) {
    const safe = error instanceof ApiError
      ? error
      : new ApiError(500, "INTERNAL_ERROR", "Pandora user administration failed safely.");
    console.error(JSON.stringify({ requestId, code: safe.code, status: safe.status }));
    return response(
      { code: safe.code, plainMessage: safe.message, requestId },
      safe.status,
      requestId,
      origin,
    );
  }
});
