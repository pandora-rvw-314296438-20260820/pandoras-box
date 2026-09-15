type Json = Record<string, unknown>;
type AdminClient = any;

type EvidenceRef = {
  type: string;
  relation: string;
  ref: string;
};

type ActivityBlocker = {
  reasonCode: string;
  reason: string;
  requiredAction: string;
  approvalRequired: boolean;
  policyRef?: string | null;
};

type EmitActivityInput = {
  state: string;
  message: string;
  sourceType?: string;
  sourceId?: string;
  sourceEventId: string;
  evidence?: EvidenceRef[];
  blocker?: ActivityBlocker | null;\n  control?: { type: 'pause' | 'resume' | 'cancel' | 'redirect' | 'constraint'; requestId: string; acceptedAt: string } | null;\n  controlId?: string | null;
  transition?: {
    priorAttemptId: string;
    priorAuthorityScopeRef: string;
    authorityScopeRef: string;
    consequential: boolean;
    priorIdempotencyKey?: string | null;
    idempotencyKey?: string | null;
    effectAmbiguous?: boolean;
  } | null;
  outcome?: { summary: string; physicalDevice: boolean } | null;
};

export type ActivityControlType = 'cancel' | 'redirect' | 'constraint';
export type ActivityControl = {
  controlId: string;
  requestId: string;
  controlSequence: number;
  controlType: ActivityControlType;
  instruction: string | null;
  requestedAt: string;
  acceptedAt: string;
};

const idPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;

export async function requireActivityJob(admin: AdminClient, jobId: string | null, organizationId: string, userId: string) {
  if (!jobId) return null;
  const result = await admin.from('pandora_activity_jobs').select('id,organization_id,requested_by,thread_id,last_sequence,writer_epoch,writer_id,terminal_state').eq('id', jobId).eq('organization_id', organizationId).eq('requested_by', userId).maybeSingle();
  if (result.error || !result.data) throw Error('ACTIVITY_JOB_NOT_AVAILABLE');
  return result.data as Json;
}

export async function bindActivityThread(admin: AdminClient, jobId: string | null, organizationId: string, userId: string, threadId: string) {
  if (!jobId) return;
  const update = await admin.from('pandora_activity_jobs').update({ thread_id: threadId, updated_at: new Date().toISOString() }).eq('id', jobId).eq('organization_id', organizationId).eq('requested_by', userId).is('terminal_state', null).select('id').maybeSingle();
  if (update.error || !update.data) throw Error('ACTIVITY_JOB_BIND_FAILED');
}

export async function claimActivityControls(admin: AdminClient, jobId: string | null, limit = 8): Promise<ActivityControl[]> {
  if (!jobId) return [];
  const controls: ActivityControl[] = [];
  for (let index = 0; index < limit; index += 1) {
    const claimed = await admin.rpc('pandora_activity_control_claim_v1', { p_job_id: jobId });
    if (claimed.error) throw Error('ACTIVITY_CONTROL_CLAIM_FAILED');
    const value = claimed.data as Json | null;
    if (!value) break;
    const controlType = String(value.controlType ?? '') as ActivityControlType;
    if (!['cancel', 'redirect', 'constraint'].includes(controlType)) throw Error('ACTIVITY_CONTROL_TYPE_INVALID');
    const controlId = String(value.controlId ?? '').trim();
    const requestId = String(value.requestId ?? '').trim();
    const controlSequence = Number(value.controlSequence ?? 0);
    const instructionRaw = value.instruction;
    const instruction = typeof instructionRaw === 'string' && instructionRaw.trim() ? instructionRaw.trim() : null;
    if (!controlId || !requestId || !Number.isInteger(controlSequence) || controlSequence < 1 || ((controlType === 'redirect' || controlType === 'constraint') && !instruction) || (controlType === 'cancel' && instruction != null)) throw Error('ACTIVITY_CONTROL_INVALID');
    controls.push({ controlId, requestId, controlSequence, controlType, instruction, requestedAt: String(value.requestedAt ?? ''), acceptedAt: String(value.acceptedAt ?? '') });
  }
  return controls;
}

export async function finishActivityControl(admin: AdminClient, jobId: string | null, controlId: string, applied: boolean, rejectionCode: string | null = null) {
  if (!jobId) return;
  const result = await admin.rpc('pandora_activity_control_finish_v1', { p_job_id: jobId, p_control_id: controlId, p_applied: applied, p_rejection_code: rejectionCode });
  if (result.error) throw Error('ACTIVITY_CONTROL_FINISH_FAILED');
}

export async function emitAcceptedActivityControl(admin: AdminClient, jobId: string | null, control: ActivityControl) {
  const ref = `control:${control.controlId}:${control.controlType}`;
  if (control.controlType === 'cancel') {
    return emitActivity(admin, jobId, { state: 'cancelled', message: "Cancelled the active job at the user's request.", sourceType: 'runtime', sourceId: 'pandora-intelligence-chat', sourceEventId: `control-cancel:${control.controlId}`, evidence: [{ type: 'user_control', relation: 'accepted_control', ref }], control: { type: 'cancel', requestId: control.requestId, acceptedAt: control.acceptedAt }, controlId: control.controlId });
  }
  return emitActivity(admin, jobId, { state: 'planning', message: control.controlType === 'redirect' ? 'Applied a user redirect to the active job.' : 'Applied a user constraint to the active job.', sourceType: 'runtime', sourceId: 'pandora-intelligence-chat', sourceEventId: `control-${control.controlType}:${control.controlId}`, evidence: [{ type: 'user_control', relation: 'accepted_control', ref }], control: { type: control.controlType, requestId: control.requestId, acceptedAt: control.acceptedAt }, controlId: control.controlId });
}

export async function emitActivity(admin: AdminClient, jobId: string | null, input: EmitActivityInput) {
  if (!jobId) return null;
  const current = await admin.from('pandora_activity_jobs').select('last_sequence,writer_epoch,writer_id,terminal_state').eq('id', jobId).single();
  if (current.error || !current.data) throw Error('ACTIVITY_JOB_NOT_AVAILABLE');
  if (current.data.terminal_state != null) return null;
  const sequence = Number(current.data.last_sequence ?? 0) + 1;
  const writerEpoch = Number(current.data.writer_epoch ?? 0);
  const admittedBy = String(current.data.writer_id ?? '').trim();
  const now = new Date().toISOString();
  const sourceType = input.sourceType ?? 'runtime';
  const sourceId = input.sourceId ?? 'pandora-intelligence-chat';
  if (writerEpoch < 1 || !idPattern.test(admittedBy) || !idPattern.test(sourceId) || !idPattern.test(input.sourceEventId)) throw Error('ACTIVITY_SOURCE_ID_INVALID');
  const event = { schemaVersion: 1, eventId: crypto.randomUUID(), jobId, sequence, writerEpoch, admittedBy, admissionMode: 'online', state: input.state, message: input.message, occurredAt: now, admittedAt: now, provenance: { sourceType, sourceId, sourceEventId: input.sourceEventId, observedAt: now }, evidence: input.evidence ?? [], domain: 'chat', capability: 'intelligence.chat', executionId: jobId, transition: input.transition ?? null, blocker: input.blocker ?? null, control: input.control ?? null, outcome: input.outcome ?? null };
  const admitted = input.controlId
    ? await admin.rpc('pandora_activity_control_apply_v1', { p_job_id: jobId, p_control_id: input.controlId, p_event: event })
    : await admin.rpc('pandora_activity_admit_event_v1', { p_job_id: jobId, p_event: event });
  if (admitted.error) throw Error(input.controlId ? 'ACTIVITY_CONTROL_APPLY_FAILED' : 'ACTIVITY_ADMISSION_FAILED');
  return event;
}

export async function emitActivityFailure(admin: AdminClient, jobId: string | null, code: string) {
  const safeCode = idPattern.test(code) ? code : 'runtime-failure';
  return emitActivity(admin, jobId, { state: 'failed', message: 'Pandora stopped this turn after a runtime failure.', sourceType: 'runtime', sourceId: 'pandora-intelligence-chat', sourceEventId: `failure:${safeCode}`, evidence: [{ type: 'runtime_event', relation: 'failure', ref: `runtime-failure:${safeCode}` }] });
}
