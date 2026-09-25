"use strict";
const {
	demand,
	exactKeys,
	plain,
	frozen,
	digest,
	resourceKey,
	SHA,
	REPOSITORIES,
} = require("./contracts");
const ACTIONS = frozen({
	"github.repository.read": {
		provider: "github",
		risk: "read",
		lane: "backend",
	},
	"github.branch.create": {
		provider: "github",
		risk: "source",
		lane: "backend",
	},
	"github.pull_request.create": {
		provider: "github",
		risk: "source",
		lane: "backend",
	},
	"github.checks.read": { provider: "github", risk: "read", lane: "release" },
	"github.pull_request.merge": {
		provider: "github",
		risk: "production",
		lane: "release",
	},
	"supabase.schema.read": {
		provider: "supabase",
		risk: "read",
		lane: "backend",
	},
	"supabase.rpc.read": { provider: "supabase", risk: "read", lane: "backend" },
	"supabase.migration.prepare": {
		provider: "supabase",
		risk: "source",
		lane: "backend",
	},
	"supabase.migration.apply": {
		provider: "supabase",
		risk: "production",
		lane: "release",
	},
	"supabase.edge.deploy": {
		provider: "supabase",
		risk: "production",
		lane: "release",
	},
	"supabase.logs.read": {
		provider: "supabase",
		risk: "read",
		lane: "reliability",
	},
	"supabase.advisors.read": {
		provider: "supabase",
		risk: "read",
		lane: "reliability",
	},
	"supabase.data.mutate": {
		provider: "supabase",
		risk: "production",
		lane: "backend",
	},
	"vercel.project.read": { provider: "vercel", risk: "read", lane: "web" },
	"vercel.preview.create": { provider: "vercel", risk: "preview", lane: "web" },
	"vercel.logs.read": { provider: "vercel", risk: "read", lane: "reliability" },
	"vercel.production.promote": {
		provider: "vercel",
		risk: "production",
		lane: "release",
	},
	"vercel.domain.reconcile": {
		provider: "vercel",
		risk: "production",
		lane: "release",
	},
	"vercel.rollback": {
		provider: "vercel",
		risk: "production",
		lane: "release",
	},
	"ares.health.read": { provider: "ares", risk: "read", lane: "ares" },
	"ares.test.run": { provider: "ares", risk: "preview", lane: "ares" },
	"ares.emulator.start": { provider: "ares", risk: "preview", lane: "ares" },
	"ares.emulator.stop": { provider: "ares", risk: "preview", lane: "ares" },
	"ares.apk.install": { provider: "ares", risk: "preview", lane: "ares" },
	"ares.app.clear_data": {
		provider: "ares",
		risk: "destructive",
		lane: "ares",
	},
	"ares.ui.test": { provider: "ares", risk: "preview", lane: "ares" },
	"ares.evidence.read": { provider: "ares", risk: "read", lane: "ares" },
});
const secretPattern =
	/(?:github_pat_|gh[pousr]_|sb_secret_|AIza[0-9A-Za-z_-]{20}|-----BEGIN [^-]*PRIVATE KEY|Bearer\s+[A-Za-z0-9._-]{20})/i;
function rejectSecrets(x) {
	const s = JSON.stringify(x);
	demand(
		s.length <= 65536 && !secretPattern.test(s),
		"CREDENTIAL_OR_PAYLOAD_REJECTED",
	);
}
function actionEnvelope(raw, scope) {
	exactKeys(raw, [
		"operation",
		"taskId",
		"generation",
		"requestId",
		"target",
		"sourceSha",
		"artifactRef",
		"parameters",
	]);
	const definition = ACTIONS[raw.operation];
	demand(definition, "ACTION_NOT_REGISTERED");
	demand(
		typeof raw.requestId === "string" &&
			/^[a-zA-Z0-9_.:-]{8,160}$/.test(raw.requestId),
		"REQUEST_ID_REQUIRED",
	);
	demand(
		raw.taskId === scope.taskId && raw.generation === scope.generation,
		"ACTION_SCOPE_MISMATCH",
	);
	resourceKey(raw.target);
	demand(scope.targets.includes(raw.target), "TARGET_NOT_AUTHORIZED");
	if (raw.sourceSha != null)
		demand(
			SHA.test(raw.sourceSha) && raw.sourceSha === scope.sourceSha,
			"SOURCE_DRIFT",
		);
	if (definition.risk !== "read")
		demand(
			raw.sourceSha === scope.sourceSha && SHA.test(raw.sourceSha),
			"EXACT_SOURCE_REQUIRED",
		);
	if (
		[
			"supabase.migration.apply",
			"supabase.edge.deploy",
			"supabase.data.mutate",
			"ares.apk.install",
		].includes(raw.operation)
	)
		demand(
			typeof raw.artifactRef === "string" &&
				/^[a-z][a-z0-9+.-]*:[^\s]{1,500}$/.test(raw.artifactRef),
			"ARTIFACT_REQUIRED",
		);
	const parameters = raw.parameters ?? {};
	demand(plain(parameters), "PARAMETERS_INVALID");
	// Never turn a model proposal into a database or host shell.
	for (const k of Object.keys(parameters))
		demand(
			![
				"sql",
				"query",
				"shell",
				"command",
				"script",
				"token",
				"key",
				"authorization",
				"serviceRole",
				"environmentVariables",
			].includes(k),
			"RAW_EXECUTION_DENIED",
		);
	rejectSecrets(raw);
	return frozen({
		operation: raw.operation,
		provider: definition.provider,
		risk: definition.risk,
		taskId: raw.taskId,
		generation: raw.generation,
		requestId: raw.requestId,
		target: raw.target,
		sourceSha: raw.sourceSha ?? null,
		artifactRef: raw.artifactRef ?? null,
		parameters: structuredClone(parameters),
	});
}
class GovernedProviderActions {
	constructor({ executeGoverned, verifyCurrentLease, readback }) {
		demand(
			typeof executeGoverned === "function" &&
				typeof verifyCurrentLease === "function" &&
				typeof readback === "function",
			"GOVERNED_ADAPTERS_REQUIRED",
		);
		this.executeGoverned = executeGoverned;
		this.verifyLease = verifyCurrentLease;
		this.readback = readback;
	}
	async invoke(raw, trustedScope) {
		const scope = frozen(structuredClone(trustedScope));
		const action = actionEnvelope(raw, scope);
		const hash = digest({
			action,
			organizationId: scope.organizationId,
			projectId: scope.projectId,
		});
		demand(await this.verifyLease(scope, action), "LEASE_NOT_CURRENT");
		// The injected M3 adapter must authorize AND execute atomically under its own current policy.
		const result = await this.executeGoverned(action, {
			scope,
			actionHash: hash,
		});
		demand(
			result && typeof result.state === "string",
			"GOVERNED_RESULT_INVALID",
		);
		if (result.state !== "completed")
			return frozen({
				state: result.state,
				actionHash: hash,
				executed: result.executed === true,
			});
		if (!result.receiptRef)
			return frozen({
				state: "reconciliation_required",
				actionHash: hash,
				executed: true,
			});
		const observed = await this.readback(action, result);
		if (
			observed?.verified !== true ||
			observed?.actionHash !== hash ||
			!observed?.receiptRef
		)
			return frozen({
				state: "reconciliation_required",
				actionHash: hash,
				executed: true,
			});
		// Revocation mid-flight does not undo a provider mutation; preserve its outcome without granting a follow-on action.
		const leaseStillCurrent = await this.verifyLease(scope, action);
		rejectSecrets({
			receiptRef: result.receiptRef,
			readbackRef: observed.receiptRef,
		});
		return frozen({
			state: leaseStillCurrent ? "completed" : "reconciliation_required",
			actionHash: hash,
			executed: true,
			receiptRef: result.receiptRef,
			readbackRef: observed.receiptRef,
		});
	}
}
module.exports = {
	ACTIONS,
	actionEnvelope,
	GovernedProviderActions,
	rejectSecrets,
};
