"use strict";
const { demand, frozen } = require("./contracts");
// Owner projection of durable coordination truth. It cannot manufacture Build Theatre events.
function operationsView(snapshot, { observedAt }) {
	demand(Number.isFinite(observedAt), "OBSERVATION_TIME_REQUIRED");
	const tasks = snapshot.tasks.map((t) => ({
		id: t.spec.id,
		title: t.spec.title,
		lane: t.spec.lane,
		priority: t.spec.priority,
		status: t.status,
		cancelRequested: t.cancelRequested === true,
		dependsOn: [...t.spec.dependsOn],
		headSha: t.headSha ?? null,
	}));
	const workers = snapshot.workers.map((w) => ({
		id: w.id,
		engine: w.engine,
		lanes: [...w.lanes],
		capacity: w.capacity,
		available:
			w.acknowledged === true &&
			w.connected === true &&
			w.health === "ready" &&
			Number.isFinite(w.heartbeatAt) &&
			w.heartbeatAt <= observedAt + 5000 &&
			observedAt - w.heartbeatAt <= 60000,
	}));
	return frozen({
		observedAt,
		controls: { ...snapshot.controls },
		tasks,
		workers,
		activeLeaseCount: snapshot.leases.length,
		completed: tasks.filter((t) => t.status === "complete").length,
		blocked: tasks.filter((t) => t.status === "blocked").length,
		physicalDeviceVerified: false,
		buildTheatreEvents: [],
	});
}
module.exports = { operationsView };
