import { createVisibleExecutionEvent, emitVisibleExecutionEvent } from '../events/visible-execution-events.mjs';
import { redactText, splitUtf8Bounded } from '../logs/log-records.mjs';

async function emitRepairSource({ eventSink, eventContext, plan, applied }) {
  const files = Array.isArray(applied?.files) ? applied.files : [];
  for (const file of files) {
    if (!file || typeof file.path !== 'string') continue;
    const operation = file.operation ?? plan.changedFiles.find((item) => item.path === file.path)?.operation ?? 'modify';
    const content = typeof file.content === 'string' ? file.content : null;
    if (content != null && redactText(content) !== content) {
      throw new Error('REPAIR_SOURCE_STREAM_SECRET_BLOCKED');
    }

    await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
      type: 'file_started',
      request: eventContext,
      stepKey: `repair:${plan.repairAttempt}:${file.path}`,
      payload: {
        activity: 'repair',
        operation,
        repair_attempt: plan.repairAttempt,
      },
      filePath: file.path,
    }));

    if (content != null && operation !== 'delete') {
      for (const chunk of splitUtf8Bounded(content, 4096)) {
        await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
          type: 'code_chunk',
          request: eventContext,
          stepKey: `repair:${plan.repairAttempt}:${file.path}`,
          payload: {
            activity: 'repair',
            operation,
            repair_attempt: plan.repairAttempt,
          },
          filePath: file.path,
          contentChunk: chunk,
        }));
      }
    }

    await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
      type: 'file_completed',
      request: eventContext,
      stepKey: `repair:${plan.repairAttempt}:${file.path}`,
      payload: {
        activity: 'repair',
        operation,
        repair_attempt: plan.repairAttempt,
        bytes: content == null ? Number(file.sizeBytes ?? 0) : Buffer.byteLength(content),
        before_sha256: file.beforeSha256 ?? null,
        after_sha256: file.afterSha256 ?? null,
      },
      filePath: file.path,
    }));
  }
}

async function executeRepairAttempt({
  controller,
  failureClass,
  diagnostics = [],
  failureFingerprint = null,
  repairDisposition = null,
  authorizationId,
  changedFiles,
  estimatedCostCents = 0,
  createWorkspace,
  applyChanges,
  rebuild,
  destroyWorkspace = async () => {},
  signal = null,
  eventSink = null,
  eventContext = null,
}) {
  if (!controller || typeof controller.authorize !== 'function') throw new Error('REPAIR_CONTROLLER_REQUIRED');
  if (typeof createWorkspace !== 'function' || typeof applyChanges !== 'function' || typeof rebuild !== 'function') {
    throw new Error('REPAIR_RUNTIME_DEPENDENCY_REQUIRED');
  }
  if (eventSink && (!eventContext?.buildJobId || !eventContext?.projectId || !eventContext?.organizationId)) {
    throw new Error('REPAIR_EVENT_CONTEXT_REQUIRED');
  }
  if (signal?.aborted) throw signal.reason ?? new Error('REPAIR_CANCELLED');

  const plan = controller.authorize({
    failureClass,
    diagnostics,
    failureFingerprint,
    repairDisposition,
    authorizationId,
    changedFiles,
    estimatedCostCents,
  });
  let workspace = null;
  try {
    if (eventSink) {
      await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
        type: 'repair_started',
        request: eventContext,
        stepKey: `repair:${plan.repairAttempt}`,
        payload: {
          repair_attempt: plan.repairAttempt,
          diagnostic_count: diagnostics.length,
          failure_fingerprint: plan.failureFingerprint,
          input_source_digest: plan.sourceDigest,
          changed_file_count: plan.changedFiles.length,
          estimated_cost_cents: plan.estimatedCostCents,
          cumulative_cost_cents: plan.cumulativeCostCents,
          started_at: new Date().toISOString(),
        },
      }));
    }

    workspace = await createWorkspace({
      workspaceKey: plan.workspaceKey,
      repairAttempt: plan.repairAttempt,
      sourceDigest: plan.sourceDigest,
      signal,
    });
    if (!workspace?.root) throw new Error('REPAIR_WORKSPACE_REQUIRED');

    const applied = await applyChanges({
      workspace,
      changedFiles: plan.changedFiles,
      authorizationId,
      signal,
    });
    if (signal?.aborted) throw signal.reason ?? new Error('REPAIR_CANCELLED');

    if (eventSink) await emitRepairSource({ eventSink, eventContext, plan, applied });

    // Source-changing repair is never considered successful until the governed
    // build/check path executes again against the distinct repair workspace.
    const result = await rebuild({
      workspace,
      repairAttempt: plan.repairAttempt,
      sourceDigest: plan.sourceDigest,
      signal,
    });
    const status = result?.status ?? 'failed';

    if (eventSink) {
      await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
        type: 'repair_completed',
        request: eventContext,
        stepKey: `repair:${plan.repairAttempt}`,
        payload: {
          repair_attempt: plan.repairAttempt,
          status,
          failure_class: result?.failureClass ?? null,
          changed_file_count: plan.changedFiles.length,
          changed_bytes: plan.changedBytes,
          input_source_digest: plan.sourceDigest,
          output_source_digest: result?.manifest?.sourceDigest ?? result?.sourceDigest ?? null,
          completed_at: new Date().toISOString(),
        },
      }));
    }

    return Object.freeze({
      status,
      failureClass: result?.failureClass ?? null,
      repairAttempt: plan.repairAttempt,
      workspaceKey: plan.workspaceKey,
      sourceDigest: plan.sourceDigest,
      changedFiles: plan.changedFiles,
      applied: applied ?? null,
      result,
    });
  } catch (error) {
    if (eventSink) {
      await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
        type: 'repair_completed',
        request: eventContext,
        stepKey: `repair:${plan.repairAttempt}`,
        payload: {
          repair_attempt: plan.repairAttempt,
          status: signal?.aborted ? 'cancelled' : 'failed',
          failure_class: signal?.aborted ? 'cancelled' : 'repair_execution',
          changed_file_count: plan.changedFiles.length,
          changed_bytes: plan.changedBytes,
          input_source_digest: plan.sourceDigest,
          output_source_digest: null,
          completed_at: new Date().toISOString(),
        },
      })).catch(() => {});
    }
    throw error;
  } finally {
    if (workspace) await destroyWorkspace({ workspace, workspaceKey: plan.workspaceKey }).catch(() => {});
  }
}

export { executeRepairAttempt };
