type JsonMap = Record<string, unknown>;
type EvidenceRef = { type: string; relation: string; ref: string };

const states = new Set([
  'understanding','planning','acting','checking','needs_you','retrying',
  'fallback','verifying','paused','resuming','result','failed','cancelled',
]);
const sources = new Set(['runtime','device','provider','model','tool']);
const secretPattern = /Authorization\s*:\s*(?:Bearer|Basic)\s+\S+|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|\bsk-[A-Za-z0-9_-]{20,}\b|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i;

function safeText(value: unknown, field: string, max = 1000): string {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${field}_required`);
  const text = value.trim();
  if (text.length > max) throw new Error(`${field}_too_long`);
  if (secretPattern.test(text)) throw new Error(`${field}_credential_like`);
  return text;
}

export type ActivityWriter = {
  readonly jobId: string;
  readonly writerEpoch: number;
  readonly nextSequence: number;
  append(input: ActivityAppendInput): Promise<JsonMap>;
};
export type ActivityAppendInput = {
  state: string;
  message: string;
  sourceType?: string;
  sourceId?: string;
  sourceEventId?: string;
  evidenceRefs?: EvidenceRef[];
  domain?: string | null;
  capability?: string | null;
  executionId?: string | null;
  blocker?: JsonMap | null;
  outcome?: JsonMap | null;
};

export async function admitActivityJob(
  admin: any,
  input: {
    jobId: string;
    organizationId: string;
    threadId: string;
    turnMessageId: string;
    createdBy: string;
    projectId?: string | null;
  },
): Promise<ActivityWriter> {
  const response = await admin.rpc('pandora_activity_admit_job_v1', {
    p_job_id: input.jobId,
    p_organization_id: input.organizationId,
    p_thread_id: input.threadId,
    p_turn_message_id: input.turnMessageId,
    p_created_by: input.createdBy,
    p_project_id: input.projectId ?? null,
  });
  if (response.error) throw new Error('PANDORA_ACTIVITY_ADMISSION_FAILED');
  const admission = response.data && typeof response.data === 'object'
    ? response.data as JsonMap
    : {};
  const writerEpoch = Number(admission.writerEpoch ?? 0);
  let nextSequence = Number(admission.lastSequence ?? 0) + 1;
  if (!Number.isSafeInteger(writerEpoch) || writerEpoch < 1
      || !Number.isSafeInteger(nextSequence) || nextSequence < 1) {
    throw new Error('PANDORA_ACTIVITY_ADMISSION_INVALID');
  }

  const writer: ActivityWriter = {
    jobId: input.jobId,
    writerEpoch,
    get nextSequence() { return nextSequence; },
    async append(value) {
      const state = safeText(value.state, 'activity_state', 40).toLowerCase();
      if (!states.has(state)) throw new Error('PANDORA_ACTIVITY_STATE_INVALID');
      const sourceType = safeText(value.sourceType ?? 'runtime', 'activity_source_type', 40).toLowerCase();
      if (!sources.has(sourceType)) throw new Error('PANDORA_ACTIVITY_SOURCE_INVALID');
      const message = safeText(value.message, 'activity_message');
      const sourceId = safeText(value.sourceId ?? 'pandora-runtime', 'activity_source_id', 200);
      const sequence = nextSequence;
      const now = new Date().toISOString();
      const eventId = `${input.jobId}:activity:${sequence}`;
      const sourceEventId = value.sourceEventId ?? `${input.jobId}:source:${sequence}`;
      const evidenceRefs = Array.isArray(value.evidenceRefs) ? value.evidenceRefs.slice(0, 20) : [];
      for (const evidence of evidenceRefs) {
        safeText(evidence.type, 'activity_evidence_type', 80);
        safeText(evidence.relation, 'activity_evidence_relation', 80);
        safeText(evidence.ref, 'activity_evidence_ref', 500);
      }
      const projection: JsonMap = {
        projectionVersion: 1,
        eventId,
        jobId: input.jobId,
        sequence,
        state,
        message,
        occurredAt: now,
        admittedAt: now,
        domain: value.domain ?? null,
        capability: value.capability ?? null,
        executionId: value.executionId ?? null,
        source: {
          sourceType,
          sourceId,
          sourceEventId: safeText(sourceEventId, 'activity_source_event_id', 200),
          observedAt: now,
        },
        evidenceRefs,
        blocker: value.blocker ?? null,
        outcome: value.outcome ?? null,
      };
      if (secretPattern.test(JSON.stringify(projection))) {
        throw new Error('PANDORA_ACTIVITY_PROJECTION_CREDENTIAL_LIKE');
      }
      const appended = await admin.rpc('pandora_activity_append_event_v1', {
        p_job_id: input.jobId,
        p_expected_sequence: sequence,
        p_event_id: eventId,
        p_writer_epoch: writerEpoch,
        p_projection: projection,
      });
      if (appended.error) throw new Error('PANDORA_ACTIVITY_APPEND_FAILED');
      nextSequence += 1;
      return projection;
    },
  };

  return writer;
}
