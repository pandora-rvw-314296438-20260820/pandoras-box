"use strict";
const { createHash } = require("node:crypto");
const LANES = Object.freeze([
	"web",
	"backend",
	"mobile",
	"growth",
	"reliability",
	"release",
	"ares",
]);
const RISKS = Object.freeze([
	"read",
	"source",
	"preview",
	"production",
	"destructive",
]);
const REPOSITORIES = Object.freeze([
	"pandora-rvw-314296438-20260820/pandoras-box",
	"pandora-rvw-314296438-20260820/pandoras-box-memory",
]);
const ID = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/;
const SHA = /^[a-f0-9]{40}$/;
function demand(ok, code) {
	if (!ok) {
		const e = new Error(code);
		e.code = code;
		throw e;
	}
}
function plain(x) {
	return (
		x !== null &&
		typeof x === "object" &&
		!Array.isArray(x) &&
		[Object.prototype, null].includes(Object.getPrototypeOf(x))
	);
}
function exactKeys(x, keys, code = "UNKNOWN_FIELD") {
	demand(plain(x), "OBJECT_REQUIRED");
	for (const k of Object.keys(x)) demand(keys.includes(k), code);
}
function integer(x, lo, hi, code) {
	demand(Number.isSafeInteger(x) && x >= lo && x <= hi, code);
	return x;
}
function text(x, max, code) {
	demand(
		typeof x === "string" &&
			x.trim() === x &&
			x.length > 0 &&
			x.length <= max &&
			!/[\u0000-\u001f]/.test(x),
		code,
	);
	return x;
}
function unique(xs, max, validate, code) {
	demand(Array.isArray(xs) && xs.length <= max, code);
	xs.forEach(validate);
	demand(new Set(xs).size === xs.length, code);
	return [...xs];
}
function frozen(x) {
	if (x && typeof x === "object") {
		for (const v of Object.values(x)) frozen(v);
		Object.freeze(x);
	}
	return x;
}
function canonical(x) {
	if (Array.isArray(x)) return "[" + x.map(canonical).join(",") + "]";
	if (plain(x))
		return (
			"{" +
			Object.keys(x)
				.sort()
				.map((k) => JSON.stringify(k) + ":" + canonical(x[k]))
				.join(",") +
			"}"
		);
	demand(
		x === null || ["string", "boolean", "number"].includes(typeof x),
		"NON_JSON_VALUE",
	);
	if (typeof x === "number") demand(Number.isFinite(x), "NON_FINITE_NUMBER");
	return JSON.stringify(x);
}
function digest(x) {
	return createHash("sha256").update(canonical(x)).digest("hex");
}
function resourceKey(k) {
	text(k, 400, "RESOURCE_KEY_INVALID");
	demand(
		/^[A-Za-z0-9][A-Za-z0-9_.:/-]*$/.test(k) &&
			!k.includes("..") &&
			!k.includes("//") &&
			!k.endsWith("/"),
		"RESOURCE_KEY_INVALID",
	);
	return k;
}
function overlap(a, b) {
	return a === b || a.startsWith(b + "/") || b.startsWith(a + "/");
}
function conflicts(a, b) {
	return overlap(a.key, b.key) && (a.mode === "write" || b.mode === "write");
}
function normalizeTask(raw) {
	exactKeys(raw, [
		"id",
		"title",
		"lane",
		"priority",
		"dependsOn",
		"resources",
		"requiredCapabilities",
		"maxCostMicros",
		"maxDurationSeconds",
		"maxAttempts",
		"risk",
		"acceptance",
		"source",
		"verificationProfile",
	]);
	demand(typeof raw.id === "string" && ID.test(raw.id), "TASK_ID_INVALID");
	text(raw.title, 240, "TITLE_INVALID");
	demand(LANES.includes(raw.lane), "LANE_INVALID");
	integer(raw.priority, 0, 3, "PRIORITY_INVALID");
	demand(RISKS.includes(raw.risk), "RISK_INVALID");
	const dependsOn = unique(
		raw.dependsOn ?? [],
		500,
		(x) => demand(typeof x === "string" && ID.test(x), "DEPENDENCY_INVALID"),
		"DEPENDENCIES_INVALID",
	);
	demand(!dependsOn.includes(raw.id), "SELF_DEPENDENCY");
	demand(
		Array.isArray(raw.resources) && raw.resources.length <= 64,
		"RESOURCES_INVALID",
	);
	const resources = raw.resources.map((r) => {
		exactKeys(r, ["key", "mode"]);
		resourceKey(r.key);
		demand(["read", "write"].includes(r.mode), "RESOURCE_MODE_INVALID");
		return { key: r.key, mode: r.mode };
	});
	demand(
		new Set(resources.map((r) => r.key)).size === resources.length,
		"DUPLICATE_RESOURCE",
	);
	if (raw.risk !== "read")
		demand(
			resources.some((r) => r.mode === "write"),
			"WRITE_RESOURCE_REQUIRED",
		);
	const requiredCapabilities = unique(
		raw.requiredCapabilities ?? [],
		64,
		(x) => demand(/^[a-z][a-z0-9._-]{1,100}$/.test(x), "CAPABILITY_INVALID"),
		"CAPABILITIES_INVALID",
	);
	const acceptance = unique(
		raw.acceptance,
		32,
		(x) => text(x, 500, "ACCEPTANCE_INVALID"),
		"ACCEPTANCE_INVALID",
	);
	demand(acceptance.length > 0, "ACCEPTANCE_REQUIRED");
	let source = null;
	if (raw.source != null) {
		exactKeys(raw.source, ["repository", "baseSha"]);
		demand(
			REPOSITORIES.includes(raw.source.repository) &&
				SHA.test(raw.source.baseSha),
			"SOURCE_INVALID",
		);
		source = { ...raw.source };
	}
	if (raw.risk === "source") demand(source !== null, "EXACT_SOURCE_REQUIRED");
	const profiles = require("../pandora-verification/src/registry").PROFILES;
	const verificationProfile =
		raw.verificationProfile ??
		(["production", "destructive"].includes(raw.risk)
			? "production_release"
			: raw.lane === "mobile"
				? "mobile_application"
				: raw.lane === "web"
					? "web_application"
					: "backend_service");
	demand(
		Object.prototype.hasOwnProperty.call(profiles, verificationProfile) &&
			(!["production", "destructive"].includes(raw.risk) ||
				verificationProfile === "production_release"),
		"VERIFICATION_PROFILE_INVALID",
	);
	const out = {
		verificationProfile,
		id: raw.id,
		title: raw.title,
		lane: raw.lane,
		priority: raw.priority,
		dependsOn,
		resources,
		requiredCapabilities,
		maxCostMicros: integer(
			raw.maxCostMicros,
			0,
			1_000_000_000_000,
			"BUDGET_INVALID",
		),
		maxDurationSeconds: integer(
			raw.maxDurationSeconds,
			1,
			3600,
			"DURATION_INVALID",
		),
		maxAttempts: integer(raw.maxAttempts ?? 2, 1, 3, "ATTEMPTS_INVALID"),
		risk: raw.risk,
		acceptance,
		source,
	};
	return frozen(out);
}
function validateGraph(raws) {
	demand(
		Array.isArray(raws) && raws.length > 0 && raws.length <= 5000,
		"TASK_BATCH_INVALID",
	);
	const tasks = raws.map(normalizeTask),
		byId = new Map(tasks.map((t) => [t.id, t]));
	demand(byId.size === tasks.length, "DUPLICATE_TASK");
	const degree = new Map(),
		children = new Map(tasks.map((t) => [t.id, []]));
	for (const t of tasks) {
		degree.set(t.id, t.dependsOn.length);
		for (const dep of t.dependsOn) {
			demand(byId.has(dep), "DEPENDENCY_MISSING");
			children.get(dep).push(t.id);
		}
	}
	const queue = tasks.filter((t) => degree.get(t.id) === 0).map((t) => t.id),
		order = [];
	for (let i = 0; i < queue.length; i++) {
		const id = queue[i];
		order.push(id);
		for (const child of children.get(id)) {
			degree.set(child, degree.get(child) - 1);
			if (degree.get(child) === 0) queue.push(child);
		}
	}
	demand(order.length === tasks.length, "DEPENDENCY_CYCLE");
	return { tasks, byId, children, order };
}
module.exports = {
	LANES,
	RISKS,
	REPOSITORIES,
	ID,
	SHA,
	demand,
	plain,
	exactKeys,
	integer,
	text,
	unique,
	frozen,
	canonical,
	digest,
	resourceKey,
	overlap,
	conflicts,
	normalizeTask,
	validateGraph,
};
