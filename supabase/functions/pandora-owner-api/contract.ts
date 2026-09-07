export const DEFAULT_ALLOWED_ORIGINS = [
  "https://mcpmaster.vercel.app",
  "https://pandoras-box-system.vercel.app",
  "https://mcpmaster-hazel.vercel.app",
  "https://mcpmaster-mbanatao-dc676069.vercel.app",
] as const;

export function parseAllowedOrigins(
  configured: string | undefined,
  defaults: readonly string[] = DEFAULT_ALLOWED_ORIGINS,
): Set<string> {
  const candidates = [...defaults, ...(configured || "").split(",")];
  const origins = new Set<string>();
  for (const candidate of candidates) {
    const value = candidate.trim();
    if (!value) continue;
    try {
      const url = new URL(value);
      if (url.protocol === "https:" && url.origin === value) origins.add(value);
    } catch {
      // Invalid configuration is ignored so it can never broaden browser access.
    }
  }
  return origins;
}

export function allowedCorsOrigin(
  requestOrigin: string | null,
  allowedOrigins: ReadonlySet<string>,
): string | null {
  if (!requestOrigin) return null;
  try {
    const url = new URL(requestOrigin);
    return url.origin === requestOrigin && allowedOrigins.has(requestOrigin)
      ? requestOrigin
      : null;
  } catch {
    return null;
  }
}

export function normalizeOwnerRoute(pathname: string): string {
  let route = pathname
    .replace(/^\/functions\/v1\/pandora-owner-api(?=\/|$)/, "")
    .replace(/^\/pandora-owner-api(?=\/|$)/, "")
    .replace(/^\/api\/owner(?=\/|$)/, "")
    .replace(/\/+$/, "");
  if (!route) return "/";
  if (!route.startsWith("/")) route = `/${route}`;
  return route;
}

export type OwnerConnectionAction =
  | "view"
  | "connect"
  | "reconnect"
  | "test"
  | "disconnect";

/**
 * Normalizes only the fields used to fingerprint an owner intake request.
 * The original owner text is still persisted unchanged by ProjectOS.
 */
export function normalizeIntakeFingerprintPart(value: string): string {
  return value.normalize("NFKC").trim().replace(/\s+/g, " ").toLowerCase();
}

/**
 * A short server-side window protects FlutterFlow retries and duplicate taps
 * even before the client can supply a stable Idempotency-Key header.
 */
export function automaticIntakeWindow(
  nowMs: number,
  windowMs = 10 * 60 * 1000,
): number {
  if (!Number.isFinite(nowMs) || !Number.isFinite(windowMs) || windowMs <= 0) {
    throw new RangeError("A finite positive intake window is required.");
  }
  return Math.floor(nowMs / windowMs);
}

export function ownerRiskLabel(riskCode: string): string {
  switch (riskCode.trim().toUpperCase()) {
    case "R0":
    case "READ":
      return "Low";
    case "R1":
      return "Low";
    case "R2":
    case "WRITE":
      return "Medium";
    case "R3":
      return "High";
    case "R4":
    case "CRITICAL":
      return "Critical";
    default:
      return "Not checked yet";
  }
}

export function isReleaseEvidenceType(evidenceType: string): boolean {
  return /(^|[._-])(deploy(?:ment|ed)?|release|preview|production)([._-]|$)/i
    .test(evidenceType.trim());
}

export function connectionActionAllowed(
  action: OwnerConnectionAction,
  state: string,
): boolean {
  const normalizedState = state.trim().toLowerCase();
  if (action === "view" || action === "test") return true;
  if (action === "connect") {
    return normalizedState === "off" || normalizedState === "needs_permission";
  }
  if (action === "reconnect") return normalizedState === "problem";
  return action === "disconnect" && normalizedState === "ready";
}
