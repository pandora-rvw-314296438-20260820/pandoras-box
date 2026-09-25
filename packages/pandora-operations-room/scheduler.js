"use strict";
const {
	demand,
	integer,
	validateGraph,
	conflicts,
	frozen,
	RISKS,
} = require("./contracts");
// This computes proposals only. The durable store must re-check all constraints when claiming.
function planAssignments(snapshot) {
	const { tasks: records, workers, leases, controls, budget, now } = snapshot;
	demand(Number.isFinite(now), "CLOCK_REQUIRED");
	demand(
		Array.isArray(records) && Array.isArray(workers) && Array.isArray(leases),
		"SNAPSHOT_INVALID",
	);
	integer(controls.maxConcurrency, 1, 256, "CONCURRENCY_INVALID");
	integer(
		controls.revision,
		0,
		Number.MAX_SAFE_INTEGER,
		"CONTROL_REVISION_INVALID",
	);
	integer(budget.availableMicros, 0, Number.MAX_SAFE_INTEGER, "BUDGET_INVALID");
	if (records.length === 0)
		return frozen({
			assignments: [],
			blocked: [],
			controlRevision: controls.revision,
		});
	const g = validateGraph(records.map((r) => r.spec), { maxTasks: records.length });
	const states = new Map(records.map((r) => [r.spec.id, r]));
	demand(
		new Set(workers.map((w) => w.id)).size === workers.length,
		"DUPLICATE_WORKER",
	);
	const blockers = [],
		assignments = [],
		held = [
			...leases.flatMap((l) => l.resources),
			...(snapshot.foreignLeases || []).flatMap((l) => l.resources),
		],
		activeByWorker = new Map();
	for (const l of leases) {
		activeByWorker.set(l.workerId, (activeByWorker.get(l.workerId) || 0) + 1);
	}
	let remaining = budget.availableMicros,
		slots = Math.max(0, controls.maxConcurrency - leases.length);
	const descendants = new Map();
	for (const id of [...g.order].reverse()) {
		const set = new Set();
		for (const child of g.children.get(id)) {
			set.add(child);
			for (const d of descendants.get(child)) set.add(d);
		}
		descendants.set(id, set);
	}
	const availableWorkers = workers.filter(
		(w) =>
			w.engine === "chatgpt" &&
			w.acknowledged === true &&
			w.connected === true &&
			w.health === "ready" &&
			Number.isFinite(w.heartbeatAt) &&
			w.heartbeatAt <= now + 5000 &&
			now - w.heartbeatAt <= 60000 &&
			Number.isSafeInteger(w.capacity) &&
			w.capacity > 0 &&
			Array.isArray(w.lanes) &&
			Array.isArray(w.capabilities),
	);
	const eligible = records.filter((r) => r.status === "queued");
	const effectivePriority = (r) =>
		Math.max(
			0,
			r.spec.priority -
				Math.min(
					2,
					Math.floor(
						Math.max(
							0,
							now - (Number.isFinite(r.queuedAt) ? r.queuedAt : now),
						) / 900000,
					),
				),
		);
	eligible.sort(
		(a, b) =>
			effectivePriority(a) - effectivePriority(b) ||
			descendants.get(b.spec.id).size - descendants.get(a.spec.id).size ||
			(a.queuedAt ?? now) - (b.queuedAt ?? now) ||
			a.spec.id.localeCompare(b.spec.id),
	);
	for (const r of eligible) {
		const t = r.spec;
		let reason = null;
		if (controls.paused === true) reason = "workspace_paused";
		else if ((controls.pausedTasks || []).includes(t.id))
			reason = "task_paused";
		else if (controls.noProduction === true && RISKS.indexOf(t.risk) >= 3)
			reason = "production_paused";
		else if (t.dependsOn.some((id) => states.get(id)?.status !== "complete"))
			reason = "dependency_not_verified";
		else if (
			!Number.isSafeInteger(r.attempt) ||
			r.attempt < 0 ||
			r.attempt >= t.maxAttempts
		)
			reason = "attempt_budget_exhausted";
		else if (t.maxCostMicros > remaining) reason = "cost_budget_exhausted";
		else if (
			t.resources.some((want) => held.some((other) => conflicts(want, other)))
		)
			reason = "resource_conflict";
		else if (slots === 0) reason = "capacity_backpressure";
		let worker;
		if (!reason) {
			worker = availableWorkers
				.filter(
					(w) =>
						w.lanes.includes(t.lane) &&
						t.requiredCapabilities.every((c) => w.capabilities.includes(c)) &&
						(activeByWorker.get(w.id) || 0) < w.capacity,
				)
				.sort(
					(a, b) =>
						(activeByWorker.get(a.id) || 0) - (activeByWorker.get(b.id) || 0) ||
						a.id.localeCompare(b.id),
				)[0];
			if (!worker) reason = "no_acknowledged_compatible_worker";
		}
		if (reason) {
			blockers.push({ taskId: t.id, reason });
			continue;
		}
		assignments.push({
			taskId: t.id,
			workerId: worker.id,
			taskRevision: r.revision,
			controlRevision: controls.revision,
			reservedMicros: t.maxCostMicros,
		});
		held.push(...t.resources);
		activeByWorker.set(worker.id, (activeByWorker.get(worker.id) || 0) + 1);
		remaining -= t.maxCostMicros;
		slots--;
	}
	return frozen({
		assignments,
		blocked: blockers,
		controlRevision: controls.revision,
		remainingMicros: remaining,
	});
}
function adaptiveConcurrency({
	current,
	ceiling,
	sampleSize,
	throughput,
	previousThroughput,
	errorRate,
	verificationBacklog,
}) {
	integer(ceiling, 1, 256, "CONCURRENCY_INVALID");
	integer(current, 1, ceiling, "CONCURRENCY_INVALID");
	integer(sampleSize, 0, 1_000_000, "SAMPLE_INVALID");
	for (const n of [
		throughput,
		previousThroughput,
		errorRate,
		verificationBacklog,
	])
		demand(Number.isFinite(n) && n >= 0, "METRIC_INVALID");
	demand(errorRate <= 1, "METRIC_INVALID");
	if (sampleSize < 5) return current;
	if (
		errorRate > 0.15 ||
		verificationBacklog > current * 2 ||
		throughput < previousThroughput * 0.8
	)
		return Math.max(1, Math.floor(current / 2));
	if (
		throughput > previousThroughput &&
		verificationBacklog <= current &&
		errorRate === 0
	)
		return Math.min(ceiling, current + 1);
	return current;
}
module.exports = { planAssignments, adaptiveConcurrency };
