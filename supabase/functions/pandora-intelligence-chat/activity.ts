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
  blocker?: ActivityBlocker | null;
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

const idPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;
export async function requireActivityJob(
  admin: AdminClient,
  jobId: string | null,
  organizationId: string,
  userId: string,
) {
  if (!jobId) return null;
  const result = await admin
    .from('pandora_activity_jobs')
    .select(
      'id,organization_id,requested_by,thread_id,last_sequence,writer_epoch,writer_id,terminal_state',
    )
    .eq('id', jobId)
    .eq('organization_id', organizationId)
    .eq('requested_by', userId)
    .maybeSingle();
  if (result.error || !result.data) {
    throw Error('ACTIVITY_JOB_NOT_AVAILABLE');
  }
  return result.data as Json;
}

export async function bindActivityThread(
  admin: AdminClient,
  jobId: string | null,
  organizationId: string,
  userId: string,
  threadId: string,
) {
  if (!jobId) return;
  const update = await admin
    .from('pandora_activity_jobs')
    .update({ thread_id: threadId, updated_at: new Date().toISOString() })
    .eq('id', jobId)
    .eq('organization_id', organizationId)
    .eq('requested_by', userId)
    .is('terminal_state', null)
    .select('id')
    .maybeSingle();
  if (update.error || !update.data) throw Error('ACTIVITY_JOB_BIND_FAILED');
}

export async function emitActivity(
  admin: AdminClient,
  jobId: string | null,
  input: EmitActivityInput,
) {
  if (!jobId) return null;
  const current = await admin
    .from('pandora_activity_jobs')
    .select('last_sequence,writer_epoch,writer_id,terminal_state')
    .eq('id', jobId)
    .single();
  if (current.error || !current.data) throw Error('ACTIVITY_JOB_NOT_AVAILABLE');
  if (current.data.terminal_state != null) return null;

  const sequence = Number(current.data.last_sequence ?? 0) + 1;
  const writerEpoch = Number(current.data.writer_epoch ?? 0);
  const admittedBy = String(current.data.writer_id ?? '').trim();
  const now = new Date().toISOString();
  const sourceType = input.sourceType ?? 'runtime';
  const sourceId = input.sourceId ?? 'pandora-intelligence-chat';
  if (
    writerEpoch < 1 ||
    !idPattern.test(admittedBy) ||
    !idPattern.test(sourceId) ||
    !idPattern.test(input.sourceEventId)
  ) {
    throw Error('ACTIVITY_SOURCE_ID_INVALID');
  }

  const event = {
    schemaVersion: 1,
    eventId: crypto.randomUUID(),
    jobId,
    sequence,
    writerEpoch,
    admittedBy,
    admissionMode: 'online',
    state: input.state,
    message: input.message,
    occurredAt: now,
    admittedAt: now,
    provenance: {
      sourceType,
      sourceId,
      sourceEventId: input.sourceEventId,
      observedAt: now,
    },
    evidence: input.evidence ?? [],
    domain: 'chat',
    capability: 'intelligence.chat',
    executionId: jobId,
    transition: input.transition ?? null,
    blocker: input.blocker ?? null,
    outcome: input.outcome ?? null,
  };

  const admitted = await admin.rpc(
    'pandora_activity_admit_event_v1',
    { p_job_id: jobId, p_event: event },
  );
  if (admitted.error) throw Error('ACTIVITY_ADMISSION_FAILED');
  return event;
}

export async function emitActivityFailure(
  admin: AdminClient,
  jobId: string | null,
  code: string,
) {
  const safeCode = idPattern.test(code) ? code : 'runtime-failure';
  return emitActivity(admin, jobId, {
    state: 'failed',
    message: 'Pandora stopped this turn after a runtime failure.',
    sourceType: 'runtime',
    sourceId: 'pandora-intelligence-chat',
    sourceEventId: `failure:${safeCode}`,
    evidence: [
      { type: 'runtime_event', relation: 'failure', ref: `runtime-failure:${safeCode}` },
    ],
  });
}