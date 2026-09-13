"use strict";

const { normalizeActivityEvent } = require("./activity-theatre-event.js");
const { assertNeedsYouBoundary } = require("./needs-you-boundary.js");

const BUILD_THEATRE_WORKFLOWS = Object.freeze(["build", "edit", "publish"]);

const BUILD_THEATRE_PHASES = Object.freeze({
  build: Object.freeze({
    understanding: Object.freeze({ state: "understanding", label: "Understanding" }),
    planning: Object.freeze({ state: "planning", label: "Planning" }),
    building: Object.freeze({ state: "acting", label: "Building" }),
    testing: Object.freeze({ state: "checking", label: "Testing" }),
    preview_ready: Object.freeze({ state: "result", label: "Preview Ready" }),
  }),
  edit: Object.freeze({
    edit_requested: Object.freeze({ state: "planning", label: "Edit Requested" }),
    rebuilding: Object.freeze({ state: "acting", label: "Rebuilding" }),
    verifying: Object.freeze({ state: "verifying", label: "Verifying" }),
    updated_preview: Object.freeze({ state: "result", label: "Updated Preview" }),
  }),
  publish: Object.freeze({
    preparing: Object.freeze({ state: "planning", label: "Preparing" }),
    deploying: Object.freeze({ state: "acting", label: "Deploying" }),
    verifying_live: Object.freeze({ state: "verifying", label: "Verifying Live" }),
    live: Object.freeze({ state: "result", label: "Live" }),
  }),
});

const UNIVERSAL_ONLY_LABELS = Object.freeze({
  needs_you: "Needs You",
  retrying: "Retrying",
  fallback: "Fallback",
  paused: "Paused",
  resuming: "Resuming",
  failed: "Problem",
  cancelled: "Cancelled",
});

const PHASE_REQUIRED_STATES = new Set([
  "understanding",
  "planning",
  "acting",
  "checking",
  "verifying",
  "result",
]);

function normalizeWorkflow(value) {
  if (typeof value !== "string") throw new Error("Build Theatre workflow is required");
  const workflow = value.trim().toLowerCase();
  if (!BUILD_THEATRE_WORKFLOWS.includes(workflow)) throw new Error(`unsupported Build Theatre workflow: ${workflow}`);
  return workflow;
}

function normalizePhase(workflow, value) {
  if (typeof value !== "string" || !value.trim()) throw new Error("Build Theatre phase is required");
  const phase = value.trim().toLowerCase();
  const definition = BUILD_THEATRE_PHASES[workflow][phase];
  if (!definition) throw new Error(`unsupported ${workflow} Build Theatre phase: ${phase}`);
  return Object.freeze({ phase, ...definition });
}

function projectBuildTheatreEvent(input, options = {}) {
  const workflow = normalizeWorkflow(options.workflow);
  const event = input?.state === "needs_you"
    ? assertNeedsYouBoundary(input, { authorityDecision: options.authorityDecision })
    : normalizeActivityEvent(input);

  let phase = null;
  let label = UNIVERSAL_ONLY_LABELS[event.state] ?? null;

  if (PHASE_REQUIRED_STATES.has(event.state)) {
    const definition = normalizePhase(workflow, options.phase);
    if (definition.state !== event.state) {
      throw new Error(`Build Theatre phase ${definition.phase} cannot override canonical state ${event.state}`);
    }
    phase = definition.phase;
    label = definition.label;
  } else if (options.phase != null) {
    throw new Error(`Build Theatre phase is not valid for canonical state ${event.state}`);
  }

  if (!label) throw new Error(`canonical state ${event.state} has no Build Theatre projection`);

  return Object.freeze({
    projection: "build",
    workflow,
    phase,
    label,
    state: event.state,
    message: event.message,
    jobId: event.jobId,
    eventId: event.eventId,
    sequence: event.sequence,
    occurredAt: event.occurredAt,
    admittedAt: event.admittedAt,
  });
}

module.exports = {
  BUILD_THEATRE_PHASES,
  BUILD_THEATRE_WORKFLOWS,
  projectBuildTheatreEvent,
};
