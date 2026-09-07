"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ProjectChangeError = void 0;
exports.createProjectChangeExecutor = createProjectChangeExecutor;
exports.focusIntentContext = focusIntentContext;
exports.normalizeFocusToken = normalizeFocusToken;
const rest_client_1 = require("../supabase/rest-client.js");

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;
const FOCUS_TTL_MS = 15 * 60 * 1000;
const MAX_EDGE_RESPONSE_BYTES = 256 * 1024;

class ProjectChangeError extends Error {
    constructor(code, status, message) {
        super(message);
        this.name = "ProjectChangeError";
        this.code = code;
        this.status = status;
    }
}
exports.ProjectChangeError = ProjectChangeError;

function text(value) {
    return typeof value === "string" ? value.trim() : "";
}
function record(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}
function oneRow(value) {
    return Array.isArray(value) && value.length && value[0] && typeof value[0] === "object" ? value[0] : null;
}
function exactKeys(value, allowed) {
    const permitted = new Set(allowed);
    return Object.keys(record(value)).every((key) => permitted.has(key));
}
function requiredUuid(value, code = "INVALID_PROJECT_CHANGE") {
    const normalized = text(value).toLowerCase();
    if (!UUID_RE.test(normalized)) throw new ProjectChangeError(code, 400, "Pandora rejected an invalid project identity.");
    return normalized;
}
function bounded(value, max) {
    return text(value).replace(/[\r\n\0]/g, " ").slice(0, max);
}
function safeSourceFile(value) {
    const normalized = text(value) || "index.html";
    const parts = normalized.split("/");
    if (normalized.length > 512 || normalized.startsWith("/") || normalized.includes("\\")
        || parts.some((part) => !part || part === "." || part === ".." || part.length > 255)) {
        throw new ProjectChangeError("FOCUS_TOKEN_INVALID", 400, "Pandora could not identify that selected object safely.");
    }
    return normalized;
}
function normalizeBounds(value) {
    if (value == null) return null;
    const input = record(value);
    if (!exactKeys(input, ["x", "y", "width", "height"])) throw new ProjectChangeError("FOCUS_TOKEN_INVALID", 400, "Pandora could not identify that selected object safely.");
    const out = {};
    for (const key of ["x", "y", "width", "height"]) {
        const number = Number(input[key]);
        if (!Number.isFinite(number) || number < 0 || number > 100000) throw new ProjectChangeError("FOCUS_TOKEN_INVALID", 400, "Pandora could not identify that selected object safely.");
        out[key] = number;
    }
    return out;
}
function normalizeFocusToken(value, expected, now = Date.now()) {
    const input = record(value);
    if (!exactKeys(input, [
        "schemaVersion","projectId","versionId","artifactDigest","componentId","semanticId",
        "selector","role","accessibleName","route","sourceFile","sourceLine","bounds","issuedAt","expiresAt",
    ]) || Number(input.schemaVersion) !== 2) {
        throw new ProjectChangeError("FOCUS_TOKEN_INVALID", 400, "Pandora could not identify that selected object safely.");
    }
    const projectId = requiredUuid(input.projectId, "FOCUS_TOKEN_INVALID");
    const versionId = requiredUuid(input.versionId, "FOCUS_TOKEN_INVALID");
    const artifactDigest = text(input.artifactDigest).toLowerCase();
    const issuedAt = Date.parse(text(input.issuedAt));
    const expiresAt = Date.parse(text(input.expiresAt));
    const sourceLine = input.sourceLine == null ? null : Number(input.sourceLine);
    const componentId = bounded(input.componentId, 200);
    const semanticId = bounded(input.semanticId, 400);
    if (!SHA256_RE.test(artifactDigest) || !componentId || !semanticId
        || (sourceLine != null && (!Number.isSafeInteger(sourceLine) || sourceLine < 1 || sourceLine > 10000000))
        || !Number.isFinite(issuedAt) || !Number.isFinite(expiresAt)
        || expiresAt <= issuedAt || expiresAt - issuedAt > FOCUS_TTL_MS
        || issuedAt > now + 60000 || expiresAt <= now
        || projectId !== expected.projectId || versionId !== expected.versionId
        || artifactDigest !== expected.artifactDigest.toLowerCase()) {
        throw new ProjectChangeError("FOCUS_TOKEN_STALE", 409, "That selection belongs to an older preview. Select the object again before changing it.");
    }
    return Object.freeze({
        schemaVersion: 2,
        projectId,
        versionId,
        artifactDigest,
        componentId,
        semanticId,
        selector: bounded(input.selector, 1000),
        role: bounded(input.role, 120),
        accessibleName: bounded(input.accessibleName, 300),
        route: bounded(input.route, 500) || "/",
        sourceFile: safeSourceFile(input.sourceFile),
        sourceLine,
        bounds: normalizeBounds(input.bounds),
        issuedAt: new Date(issuedAt).toISOString(),
        expiresAt: new Date(expiresAt).toISOString(),
    });
}
function focusIntentContext(token) {
    const parts = [
        "FocusToken(v2)",
        `project=${token.projectId}`,
        `version=${token.versionId}`,
        `artifact_sha256=${token.artifactDigest}`,
        `component_id=${token.componentId}`,
        `semantic_id=${token.semanticId}`,
        `source=${token.sourceFile}${token.sourceLine == null ? "" : `:${token.sourceLine}`}`,
        `route=${token.route}`,
        `issued_at=${token.issuedAt}`,
        `expires_at=${token.expiresAt}`,
        ...(token.role ? [`role=${token.role}`] : []),
        ...(token.accessibleName ? [`name=${token.accessibleName}`] : []),
        ...(token.selector ? [`selector=${token.selector}`] : []),
        ...(token.bounds ? [`bounds=x=${token.bounds.x.toFixed(1)},y=${token.bounds.y.toFixed(1)},w=${token.bounds.width.toFixed(1)},h=${token.bounds.height.toFixed(1)}`] : []),
    ];
    return `${parts.join(" ")}. Apply the owner change specifically to this exact selected object.`;
}

async function edgeJson({ fetchFn, supabaseUrl, publishableKey, accessToken, name, body, timeoutMs }) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const response = await fetchFn(new URL(`/functions/v1/${name}`, supabaseUrl), {
            method: "POST",
            headers: {
                accept: "application/json",
                apikey: publishableKey,
                authorization: `Bearer ${accessToken}`,
                "content-type": "application/json",
            },
            body: JSON.stringify(body),
            redirect: "error",
            signal: controller.signal,
        });
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (bytes.byteLength > MAX_EDGE_RESPONSE_BYTES) throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora returned an oversized change response.");
        let payload = {};
        try { payload = bytes.byteLength ? JSON.parse(Buffer.from(bytes).toString("utf8")) : {}; }
        catch { throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora returned an unreadable change response."); }
        return { status: response.status, payload: record(payload) };
    } catch (error) {
        if (error instanceof ProjectChangeError) throw error;
        throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not reach the governed build service.");
    } finally {
        clearTimeout(timeout);
    }
}

function createProjectChangeExecutor(options) {
    const organizationId = requiredUuid(options.organizationId, "PROJECT_CHANGE_CONFIGURATION_INVALID");
    const supabaseUrl = new URL(options.supabaseUrl);
    const publishableKey = text(options.publishableKey);
    if ((supabaseUrl.protocol !== "https:" && supabaseUrl.hostname !== "localhost") || !publishableKey) throw new Error("Project change executor is not configured");
    const fetchFn = options.fetchFn ?? fetch;
    const q = (value) => encodeURIComponent(String(value));

    return async function executeProjectChange(input) {
        const actor = record(input.actor);
        const identity = record(actor.identity);
        const accessToken = text(identity.accessToken);
        const userId = requiredUuid(identity.userId, "PROJECT_CHANGE_SESSION_INVALID");
        const projectId = requiredUuid(input.projectId);
        const body = record(input.body);
        if (!accessToken || !exactKeys(body, ["change","focusToken","idempotencyKey"])) throw new ProjectChangeError("INVALID_PROJECT_CHANGE", 400, "Pandora rejected unsupported project-change fields.");
        const change = text(body.change);
        const idempotencyKey = text(body.idempotencyKey);
        if (change.length < 4 || change.length > 8000 || idempotencyKey.length < 8 || idempotencyKey.length > 200 || /[\r\n\0]/.test(idempotencyKey)) {
            throw new ProjectChangeError("INVALID_PROJECT_CHANGE", 400, "Pandora rejected an invalid project change.");
        }

        const client = new rest_client_1.SupabaseRestClient({
            supabaseUrl: supabaseUrl.toString(),
            apiKey: publishableKey,
            accessToken,
            fetchFn,
            timeoutMs: 10000,
            maxResponseBytes: 512 * 1024,
        });

        let project;
        let projection;
        try {
            project = oneRow(await client.requestJson(`/rest/v1/projectos_projects?select=id&organization_id=eq.${q(organizationId)}&id=eq.${q(projectId)}&limit=1`));
            projection = oneRow(await client.requestJson(`/rest/v1/pandora_project_experience_projection?select=can_change,current_version_id,candidate_version_id,production_version_id&organization_id=eq.${q(organizationId)}&project_id=eq.${q(projectId)}&limit=1`));
        } catch {
            throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not verify the current project state.");
        }
        if (!project) throw new ProjectChangeError("PROJECT_NOT_FOUND", 404, "Pandora could not find that project.");
        if (!projection || projection.can_change !== true) throw new ProjectChangeError("PROJECT_CHANGE_NOT_AVAILABLE", 409, "Pandora has not marked this project safe for a new change yet.");

        let focusToken = null;
        let intentText = change;
        if (body.focusToken != null) {
            const rawFocus = record(body.focusToken);
            const versionId = requiredUuid(rawFocus.versionId, "FOCUS_TOKEN_INVALID");
            const visible = new Set([projection.current_version_id,projection.candidate_version_id,projection.production_version_id].map((value) => text(value).toLowerCase()).filter(Boolean));
            if (!visible.has(versionId)) throw new ProjectChangeError("FOCUS_TOKEN_STALE", 409, "That selection belongs to an older preview. Select the object again before changing it.");
            let version;
            try {
                version = oneRow(await client.requestJson(`/rest/v1/pandora_project_versions?select=id,artifact_digest_sha256&organization_id=eq.${q(organizationId)}&project_id=eq.${q(projectId)}&id=eq.${q(versionId)}&limit=1`));
            } catch {
                throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not verify the selected preview.");
            }
            const artifactDigest = text(version?.artifact_digest_sha256).toLowerCase();
            if (!version || !SHA256_RE.test(artifactDigest)) throw new ProjectChangeError("FOCUS_TOKEN_STALE", 409, "That selection no longer matches a verified preview.");
            focusToken = normalizeFocusToken(rawFocus, { projectId, versionId, artifactDigest });
            intentText = `${focusIntentContext(focusToken)}\nOwner change: ${change}`;
        }

        let intentId = "";
        const intentPayload = {
            organization_id: organizationId,
            project_id: projectId,
            requester_id: userId,
            intent_kind: "change",
            intent_text: intentText,
            source: "customer",
            idempotency_key: idempotencyKey,
            provenance: {
                surface: "pandora_web_owner_workspace",
                focusTokenSchema: focusToken?.schemaVersion ?? null,
                focusVersionId: focusToken?.versionId ?? null,
            },
        };
        try {
            const inserted = await client.requestJson("/rest/v1/pandora_project_intents?select=id", {
                method: "POST",
                headers: { Prefer: "return=representation" },
                body: JSON.stringify(intentPayload),
            });
            intentId = text(oneRow(inserted)?.id).toLowerCase();
        } catch (error) {
            if (!(error instanceof rest_client_1.SupabaseRestError) || error.code !== "23505") throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not save that change request.");
            try {
                const existing = oneRow(await client.requestJson(`/rest/v1/pandora_project_intents?select=id&organization_id=eq.${q(organizationId)}&project_id=eq.${q(projectId)}&idempotency_key=eq.${q(idempotencyKey)}&limit=1`));
                intentId = text(existing?.id).toLowerCase();
            } catch {
                throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not confirm that change request.");
            }
        }
        if (!UUID_RE.test(intentId)) throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not establish the durable change identity.");

        const compilation = await edgeJson({ fetchFn, supabaseUrl: supabaseUrl.toString(), publishableKey, accessToken, name: "pandora-project-spec-compiler", body: { intentId }, timeoutMs: 22000 });
        if (compilation.status === 422) throw new ProjectChangeError("PROJECT_CHANGE_REJECTED", 422, "Pandora needs a different request before it can make that change.");
        if (compilation.status !== 200) {
            if ([202,409,503].includes(compilation.status)) return { ok: true, httpStatus: 202, state: "working", stage: "understanding", intentId, streamId: null };
            throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not prepare that change right now.");
        }

        let activeSpec;
        try {
            activeSpec = oneRow(await client.requestJson(`/rest/v1/pandora_project_specs?select=id,source_intent_id&organization_id=eq.${q(organizationId)}&project_id=eq.${q(projectId)}&status=eq.active&order=version.desc&limit=1`));
        } catch {
            throw new ProjectChangeError("PROJECT_CHANGE_UNAVAILABLE", 503, "Pandora could not verify the prepared change.");
        }
        if (!activeSpec || text(activeSpec.source_intent_id).toLowerCase() !== intentId) return { ok: true, httpStatus: 202, state: "working", stage: "understanding", intentId, streamId: null };

        const build = await edgeJson({
            fetchFn,
            supabaseUrl: supabaseUrl.toString(),
            publishableKey,
            accessToken,
            name: "pandora-project-source-generator",
            body: { projectId, idempotencyKey: `web-focus-build:${projectId}:${intentId}` },
            timeoutMs: 26000,
        });
        if (![200,202].includes(build.status) || build.payload.ok === false) {
            const providerCode = text(record(build.payload.error).code);
            if (build.status === 409 && providerCode === "PROJECT_SPEC_NOT_READY") return { ok: true, httpStatus: 202, state: "working", stage: "understanding", intentId, streamId: null };
            throw new ProjectChangeError("PROJECT_CHANGE_BUILD_BLOCKED", build.status === 403 ? 403 : 409, "Pandora found something to resolve before this change can build.");
        }
        return {
            ok: true,
            httpStatus: build.status === 200 ? 200 : 202,
            state: text(build.payload.state) || "working",
            stage: text(build.payload.stage) || "building",
            intentId,
            streamId: text(build.payload.streamId) || null,
            buildJobId: text(build.payload.buildJobId) || null,
            projectVersionId: text(build.payload.projectVersionId) || null,
        };
    };
}
