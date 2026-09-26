const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const FORBIDDEN =
	/(?:github_pat_|gh[pousr]_[A-Za-z0-9_]{20,}|sb_secret_|AIza[0-9A-Za-z_-]{20,}|-----BEGIN [^-]*PRIVATE KEY|Bearer\s+[A-Za-z0-9._-]{20,})/i;
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
async function boundedJson(request, maxBytes) {
	const advertised = request.headers.get("content-length");
	if (
		advertised &&
		(/^\d+$/.test(advertised) === false || Number(advertised) > maxBytes)
	)
		throw new Error("PAYLOAD_TOO_LARGE");
	const reader = request.body?.getReader();
	if (!reader) throw new Error("BODY_REQUIRED");
	const chunks = [];
	let size = 0;
	try {
		while (true) {
			const { done, value } = await reader.read();
			if (done) break;
			size += value.byteLength;
			if (size > maxBytes) {
				await reader.cancel();
				throw new Error("PAYLOAD_TOO_LARGE");
			}
			chunks.push(value);
		}
	} finally {
		reader.releaseLock();
	}
	const bytes = new Uint8Array(size);
	let at = 0;
	for (const chunk of chunks) {
		bytes.set(chunk, at);
		at += chunk.byteLength;
	}
	const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
	if (FORBIDDEN.test(text)) throw new Error("CREDENTIAL_MATERIAL_REJECTED");
	return JSON.parse(text);
}
/**
 * @param {{
 * authenticate: (request: Request, scope: {organizationId: string, projectId: string}) => Promise<{userId: string, active: boolean, role: string, organizationId: string, projectId: string} | null>,
 * rpc: (name: string, params: Record<string, unknown>) => PromiseLike<{data: unknown, error: {code?: string} | null}>,
 * allowedOrigins?: string[],
 * maxBytes?: number
 * }} options
 */
export function createOperationsHandler({
	authenticate,
	rpc,
	allowedOrigins = [],
	maxBytes = 2 * 1024 * 1024,
}) {
	if (typeof authenticate !== "function" || typeof rpc !== "function")
		throw new Error("TRUSTED_ADAPTERS_REQUIRED");
	const origins = new Set(allowedOrigins);
	if (origins.has("*")) throw new Error("WILDCARD_ORIGIN_DENIED");
	return async function handle(request) {
		const origin = request.headers.get("origin");
		const headers = {
			"content-type": "application/json; charset=utf-8",
			"cache-control": "no-store",
			"x-content-type-options": "nosniff",
			vary: "Origin",
		};
		const response = (status, body) =>
			new Response(JSON.stringify(body), { status, headers });
		if (origin && !origins.has(origin))
			return response(403, { ok: false, code: "ORIGIN_DENIED" });
		if (origin) headers["access-control-allow-origin"] = origin;
		if (request.method === "OPTIONS") {
			headers["access-control-allow-methods"] = "POST, OPTIONS";
			headers["access-control-allow-headers"] =
				"authorization, apikey, content-type";
			return new Response(null, { status: 204, headers });
		}
		if (request.method !== "POST")
			return response(405, { ok: false, code: "POST_REQUIRED" });
		if (
			!request.headers
				.get("content-type")
				?.toLowerCase()
				.startsWith("application/json")
		)
			return response(415, { ok: false, code: "JSON_REQUIRED" });
		try {
			const input = await boundedJson(request, maxBytes);
			if (
				!input ||
				typeof input !== "object" ||
				Array.isArray(input) ||
				!UUID.test(input.organizationId ?? "") ||
				!UUID.test(input.projectId ?? "")
			)
				return response(400, { ok: false, code: "SCOPE_REQUIRED" });
			const keys = [
				"organizationId",
				"projectId",
				"operation",
				"tasks",
				"expectedRevision",
				"taskId",
			];
			if (Object.keys(input).some((k) => !keys.includes(k)))
				return response(400, { ok: false, code: "UNKNOWN_FIELD" });
			const actor = await authenticate(request, {
				organizationId: input.organizationId,
				projectId: input.projectId,
			});
			if (
				!actor?.userId ||
				actor.active !== true ||
				!["owner", "admin"].includes(actor.role) ||
				actor.organizationId !== input.organizationId ||
				actor.projectId !== input.projectId
			)
				return response(403, { ok: false, code: "OWNER_SCOPE_REQUIRED" });
			const params = {
				p_organization_id: actor.organizationId,
				p_project_id: actor.projectId,
			};
			let name;
			if (input.operation === "overview") {
				name = "pandora_ops_snapshot_v1";
				if (
					own(input, "tasks") ||
					own(input, "expectedRevision") ||
					own(input, "taskId")
				)
					return response(400, {
						ok: false,
						code: "UNEXPECTED_OPERATION_FIELD",
					});
			} else if (input.operation === "ingest") {
				if (
					!Array.isArray(input.tasks) ||
					input.tasks.length < 1 ||
					input.tasks.length > 5000
				)
					return response(400, { ok: false, code: "TASK_BATCH_INVALID" });
				if (own(input, "expectedRevision") || own(input, "taskId"))
					return response(400, {
						ok: false,
						code: "UNEXPECTED_OPERATION_FIELD",
					});
				name = "pandora_ops_ingest_v1";
				params.p_tasks = input.tasks;
			} else if (
				["pause", "resume", "no_production", "cancel_task"].includes(
					input.operation,
				)
			) {
				if (
					!Number.isSafeInteger(input.expectedRevision) ||
					input.expectedRevision < 0 ||
					own(input, "tasks")
				)
					return response(400, {
						ok: false,
						code: "CONTROL_REVISION_REQUIRED",
					});
				if (
					input.operation === "cancel_task" &&
					!(
						typeof input.taskId === "string" &&
						/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(input.taskId)
					)
				)
					return response(400, { ok: false, code: "TASK_ID_REQUIRED" });
				name = "pandora_ops_control_v1";
				params.p_expected_revision = input.expectedRevision;
				params.p_action = input.operation;
				params.p_task_key =
					input.operation === "cancel_task" ? input.taskId : null;
			} else return response(400, { ok: false, code: "OPERATION_NOT_EXPOSED" });
			// This endpoint only ingests intent and changes scheduling controls. It cannot register workers,
			// issue claims/approvals, execute provider mutations, or accept verification receipts.
			const result = await rpc("pandora_ops_owner_request_v1", {
				p_organization_id: actor.organizationId,
				p_project_id: actor.projectId,
				p_actor_id: actor.userId,
				p_operation: input.operation,
				p_payload:
					input.operation === "ingest"
						? { tasks: input.tasks }
						: input.operation === "overview"
							? {}
							: {
									expectedRevision: input.expectedRevision,
									...(input.operation === "cancel_task"
										? { taskId: input.taskId }
										: {}),
								},
			});
			if (result.error) {
				if (result.error.code === "42501")
					return response(403, { ok: false, code: "STORE_SCOPE_DENIED" });
				return response(409, {
					ok: false,
					code: "STORE_REJECTED_OR_UNAVAILABLE",
				});
			}
			return response(200, {
				ok: true,
				operation: input.operation,
				result: result.data,
			});
		} catch (error) {
			if (error?.message === "PAYLOAD_TOO_LARGE")
				return response(413, { ok: false, code: "PAYLOAD_TOO_LARGE" });
			if (error?.message === "CREDENTIAL_MATERIAL_REJECTED")
				return response(400, {
					ok: false,
					code: "CREDENTIAL_MATERIAL_REJECTED",
				});
			return response(400, { ok: false, code: "REQUEST_REJECTED" });
		}
	};
}
