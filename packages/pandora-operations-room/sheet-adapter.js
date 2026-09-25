"use strict";
const {
	demand,
	normalizeTask,
	validateGraph,
	digest,
	plain,
} = require("./contracts");
const INPUT_COLUMNS = Object.freeze([
	"TASK_ID",
	"TITLE",
	"LANE",
	"PRIORITY",
	"DEPENDS_ON",
	"RESOURCES",
	"CAPABILITIES",
	"MAX_COST_MICROS",
	"MAX_DURATION_SECONDS",
	"MAX_ATTEMPTS",
	"RISK",
	"ACCEPTANCE",
	"REPOSITORY",
	"BASE_SHA",
]);
const OUTPUT_COLUMNS = Object.freeze([
	"STATUS",
	"WORKER",
	"PR",
	"HEAD_SHA",
	"BLOCKER",
	"VERIFICATION",
	"UPDATED_AT",
]);
// Hash only owner inputs. Machine status updates must not invalidate the next sync.
// Header and row order remain part of the fingerprint, preventing stale row addressing.
function inputDigest(headers, rows) {
	demand(
		Array.isArray(headers) &&
			new Set(headers).size === headers.length &&
			INPUT_COLUMNS.every((h) => headers.includes(h)),
		"SHEET_HEADERS_INVALID",
	);
	demand(
		Array.isArray(rows) && rows.length <= 5000 && rows.every(Array.isArray),
		"SHEET_ROWS_INVALID",
	);
	return digest({
		headers,
		rows: rows.map((row) =>
			INPUT_COLUMNS.map((h) => row[headers.indexOf(h)] ?? ""),
		),
	});
}
function list(v) {
	if (v == null || v === "") return [];
	demand(typeof v === "string", "SHEET_LIST_INVALID");
	return v
		.split(";")
		.map((x) => x.trim())
		.filter(Boolean);
}
function natural(v, code) {
	demand(
		(typeof v === "number" && Number.isSafeInteger(v)) ||
			(typeof v === "string" && /^\d+$/.test(v)),
		code,
	);
	return Number(v);
}
// Accept already-decoded cell values only. XLSX/Google I/O never executes macros or formulas here.
function ingestRows(headers, rows) {
	demand(
		Array.isArray(headers) &&
			new Set(headers).size === headers.length &&
			INPUT_COLUMNS.every((h) => headers.includes(h)),
		"SHEET_HEADERS_INVALID",
	);
	demand(Array.isArray(rows) && rows.length <= 5000, "SHEET_LIMIT");
	const sourceDigest = inputDigest(headers, rows);
	const parsed = rows
		.filter((r) => Array.isArray(r) && r.some((v) => v !== "" && v != null))
		.map((row) => {
			demand(row.length <= headers.length, "SHEET_ROW_WIDTH");
			const x = Object.fromEntries(headers.map((h, i) => [h, row[i] ?? ""]));
			for (const h of INPUT_COLUMNS)
				demand(
					!(typeof x[h] === "string" && /^[=+@]/.test(x[h])),
					"FORMULA_INPUT_REJECTED",
				);
			return normalizeTask({
				id: x.TASK_ID,
				title: x.TITLE,
				lane: x.LANE,
				priority: natural(x.PRIORITY, "PRIORITY_INVALID"),
				dependsOn: list(x.DEPENDS_ON),
				resources: list(x.RESOURCES).map((r) => {
					const cut = r.lastIndexOf("|");
					demand(cut > 0, "RESOURCE_CELL_INVALID");
					return { key: r.slice(0, cut), mode: r.slice(cut + 1) };
				}),
				requiredCapabilities: list(x.CAPABILITIES),
				maxCostMicros: natural(x.MAX_COST_MICROS, "BUDGET_INVALID"),
				maxDurationSeconds: natural(x.MAX_DURATION_SECONDS, "DURATION_INVALID"),
				maxAttempts: natural(x.MAX_ATTEMPTS, "ATTEMPTS_INVALID"),
				risk: x.RISK,
				acceptance: list(x.ACCEPTANCE),
				source: x.REPOSITORY
					? { repository: x.REPOSITORY, baseSha: x.BASE_SHA }
					: null,
			});
		});
	validateGraph(parsed);
	return { tasks: parsed, sourceDigest };
}
function planSheetWriteback({
	expectedInputDigest,
	currentHeaders,
	currentRows,
	statuses,
}) {
	demand(
		inputDigest(currentHeaders, currentRows) === expectedInputDigest,
		"SHEET_CHANGED_RECONCILE",
	);
	demand(Array.isArray(statuses), "STATUSES_REQUIRED");
	const nonemptyIds = currentRows
		.map((r) => r[currentHeaders.indexOf("TASK_ID")])
		.filter((id) => id !== "" && id != null);
	demand(new Set(nonemptyIds).size === nonemptyIds.length, "DUPLICATE_TASK");
	const ids = new Map(
		currentRows.map((r, i) => [r[currentHeaders.indexOf("TASK_ID")], i + 2]),
	);
	return statuses.map((s) => {
		demand(plain(s) && ids.has(s.taskId), "SHEET_TASK_MISSING");
		for (const k of Object.keys(s))
			demand(
				k === "taskId" ||
					(OUTPUT_COLUMNS.includes(k) && currentHeaders.includes(k)),
				"OWNER_COLUMN_WRITE_DENIED",
			);
		return {
			row: ids.get(s.taskId),
			valueInputOption: "RAW",
			values: Object.fromEntries(
				OUTPUT_COLUMNS.filter((k) => s[k] !== undefined).map((k) => [
					k,
					String(s[k]),
				]),
			),
		};
	});
}
module.exports = {
	INPUT_COLUMNS,
	OUTPUT_COLUMNS,
	inputDigest,
	ingestRows,
	planSheetWriteback,
};
