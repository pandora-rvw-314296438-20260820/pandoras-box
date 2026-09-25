import {
  BRIDGE_RPC, MEMORY_PROJECT_REF, MemoryIntegrationError, UUID, SHA256,
  immutable, isRecord, normalizeMapping, normalizeScope, normalizeContextRequest,
  normalizeOutcome, requireThat, serialized, stableDigest,
} from './contracts.mjs';

/** Server-only native Memory connection. The caller retains Operations Room/M3 authority.
 * A Supabase client is supplied by the trusted credential holder, never by model output.
 * No credentials, raw SQL, canon-promotion action or destination URL are accepted here.
 */
export class NativeOperationsMemoryClient {
  #client; #mapping; #timeoutMs; #clock;
  constructor({ client, mapping, timeoutMs = 15000, clock = Date.now }) {
    requireThat(typeof client?.rpc === 'function', 'OPS_MEMORY_CLIENT_REQUIRED');
    let url;
    try { url = new URL(client.supabaseUrl); } catch { throw new MemoryIntegrationError('OPS_MEMORY_CLIENT_TARGET_INVALID'); }
    requireThat(url.origin === `https://${MEMORY_PROJECT_REF}.supabase.co`
      && url.pathname === '/' && !url.search && !url.hash && !url.username && !url.password,
    'OPS_MEMORY_CLIENT_TARGET_DENIED');
    requireThat(Number.isSafeInteger(timeoutMs) && timeoutMs >= 100 && timeoutMs <= 30000
      && typeof clock === 'function', 'OPS_MEMORY_RUNTIME_OPTIONS_INVALID');
    this.#client = client; this.#mapping = normalizeMapping(mapping);
    this.#timeoutMs = timeoutMs; this.#clock = clock;
  }
  async #invoke(scope, operation, payload, { signal } = {}) {
    normalizeScope(scope, this.#mapping); serialized(payload);
    requireThat(['context','propose_outcome','readback'].includes(operation), 'OPS_MEMORY_OPERATION_DENIED');
    if (signal?.aborted) throw new MemoryIntegrationError('OPS_MEMORY_CANCELLED');
    const mutation = operation === 'propose_outcome', mapping = this.#mapping;
    const args = immutable({p_operation:operation,p_memory_user_id:mapping.memoryUserId,
      p_namespace:mapping.namespace,p_project_id:mapping.memoryProjectId,
      p_principal_key:mapping.principalKey,p_environment:mapping.environment,
      p_payload:structuredClone(payload)});
    const controller = new AbortController();
    let timer, cancel;
    const stop = new Promise((_, reject) => {
      cancel = () => { controller.abort(); reject(new MemoryIntegrationError('OPS_MEMORY_CANCELLED', {outcomeUnknown:mutation})); };
      signal?.addEventListener('abort', cancel, {once:true});
      timer = setTimeout(() => { controller.abort(); reject(new MemoryIntegrationError('OPS_MEMORY_TIMEOUT', {outcomeUnknown:mutation})); }, this.#timeoutMs);
    });
    try {
      let request = this.#client.rpc(BRIDGE_RPC, args);
      if (typeof request?.abortSignal === 'function') request = request.abortSignal(controller.signal);
      const response = await Promise.race([Promise.resolve(request), stop]);
      if (response?.error) {
        const code = response.error.message;
        if (typeof code === 'string' && /^OPS_MEMORY_[A-Z0-9_]{1,100}$/.test(code)) throw new MemoryIntegrationError(code);
        if (response.error.code === '42501') throw new MemoryIntegrationError('OPS_MEMORY_ACCESS_DENIED');
        throw new MemoryIntegrationError('OPS_MEMORY_PROVIDER_ERROR', {outcomeUnknown:mutation});
      }
      requireThat(isRecord(response?.data), 'OPS_MEMORY_RESPONSE_INVALID');
      serialized(response.data, 40000);
      return response.data;
    } catch (error) {
      if (error instanceof MemoryIntegrationError) {
        if (mutation && ['OPS_MEMORY_RESPONSE_INVALID','OPS_MEMORY_CREDENTIAL_REJECTED','OPS_MEMORY_PAYLOAD_LIMIT'].includes(error.code)) {
          throw new MemoryIntegrationError(error.code, {outcomeUnknown:true});
        }
        throw error;
      }
      // Never expose a provider message, stack, URL, token or caller-supplied error string.
      throw new MemoryIntegrationError('OPS_MEMORY_TRANSPORT_UNAVAILABLE', {outcomeUnknown:mutation});
    } finally {
      clearTimeout(timer); signal?.removeEventListener('abort', cancel);
    }
  }
  async getTaskContext(scope, request, options = {}) {
    const sourceScope = normalizeScope(scope, this.#mapping), query = normalizeContextRequest(request);
    const reply = await this.#invoke(sourceScope, 'context', query, options), pack = reply.context;
    requireThat(reply.kind === 'task_context' && reply.projectId === this.#mapping.memoryProjectId
      && reply.namespace === this.#mapping.namespace && reply.authorizationGranted === false,
    'OPS_MEMORY_CONTEXT_SCOPE_MISMATCH');
    requireThat(isRecord(pack) && pack.schemaVersion === 'm5.task-aware-retrieval.v1'
      && pack.status === 'available' && pack.project?.id === this.#mapping.memoryProjectId
      && pack.namespace === this.#mapping.namespace && SHA256.test(pack.contextSha256),
    'OPS_MEMORY_CONTEXT_INVALID');
    requireThat(pack.authorization?.principalKey === this.#mapping.principalKey
      && pack.authorization.environment === this.#mapping.environment
      && pack.authorization.canRead === true
      && pack.authorization.retrievalDoesNotGrantExecutionAuthority === true,
    'OPS_MEMORY_CONTEXT_AUTHORITY_INVALID');
    requireThat(pack.task?.intent === query.intent && pack.task.actionMode === query.actionMode
      && pack.task.consequential === query.consequential, 'OPS_MEMORY_CONTEXT_TASK_MISMATCH');
    requireThat(Array.isArray(pack.policyMemory) && pack.policyMemory.length <= 4
      && Array.isArray(pack.advisoryMemory) && pack.advisoryMemory.length <= 12
      && typeof pack.degradation?.degraded === 'boolean', 'OPS_MEMORY_CONTEXT_SHAPE_INVALID');
    for (const row of [...pack.policyMemory, ...pack.advisoryMemory]) {
      requireThat(isRecord(row) && UUID.test(row.id) && row.canonStatus === 'hard_canon'
        && row.knowledgeSchemaVersion === 'm5.v1', 'OPS_MEMORY_UNAPPROVED_CONTEXT');
    }
    requireThat(pack.policyMemory.every(row => row.recordType === 'policy'
      && row.requiresRuntimeAuthorizationValidation === true
      && row.authorizationEffect === 'requires_exact_runtime_scope_validity_revocation_validation'),
    'OPS_MEMORY_POLICY_AUTHORITY_INVALID');
    requireThat(pack.advisoryMemory.every(row => row.recordType !== 'policy'
      && row.authorizationEffect === 'none'), 'OPS_MEMORY_ADVISORY_AUTHORITY_INVALID');
    serialized(pack, query.maxBytes);
    return immutable({state:pack.degradation.degraded ? 'degraded' : 'available',
      context:structuredClone(pack),receiptRef:`memory-context:${pack.contextSha256}`,
      transportSha256:stableDigest(pack),authorizationGranted:false,
      // Summaries are not numeric routing statistics. Do not invent sample counts from prose.
      performanceStatisticsDerived:false});
  }
  #receipt(raw, outcome) {
    requireThat(raw.kind === 'outcome_receipt' && raw.found === true && raw.readbackVerified === true
      && raw.projectId === this.#mapping.memoryProjectId && raw.namespace === this.#mapping.namespace
      && raw.sourceRunId === outcome.sourceRunId && raw.requiresReview === true
      && raw.canonicalMemoryWritten === false && SHA256.test(raw.payloadSha256)
      && [raw.receiptId,raw.candidateId,raw.reviewItemId].every(id => typeof id === 'string' && UUID.test(id)),
    'OPS_MEMORY_RECEIPT_MISMATCH');
    return immutable({state:'pending_review',deliveryVerified:true,canonicalMemoryWritten:false,
      sourceRunId:raw.sourceRunId,receiptId:raw.receiptId,candidateId:raw.candidateId,
      reviewItemId:raw.reviewItemId,payloadSha256:raw.payloadSha256,
      receiptRef:`memory-delivery:${raw.receiptId}`,currentReviewStatus:raw.currentReviewStatus,
      modelRevisionKnown:raw.modelRevisionKnown === true});
  }
  async reconcileOutcome(scope, raw, options = {}) {
    const sourceScope = normalizeScope(scope, this.#mapping), outcome = normalizeOutcome(raw, this.#clock());
    const reply = await this.#invoke(sourceScope, 'readback', {sourceRunId:outcome.sourceRunId,expectedPayload:outcome}, options);
    if (reply.found === false && reply.requiresReconciliation === true && reply.canonicalMemoryWritten === false) {
      return immutable({state:'reconciliation_required',deliveryVerified:false,sourceRunId:outcome.sourceRunId,
        canonicalMemoryWritten:false,reason:'no_committed_delivery_receipt'});
    }
    return this.#receipt(reply, outcome);
  }
  async proposeOutcome(scope, raw, options = {}) {
    const sourceScope = normalizeScope(scope, this.#mapping), outcome = normalizeOutcome(raw, this.#clock());
    let original, ambiguous = false;
    try { original = this.#receipt(await this.#invoke(sourceScope, 'propose_outcome', outcome, options), outcome); }
    catch (error) {
      if (!(error instanceof MemoryIntegrationError) || error.outcomeUnknown !== true) {
        // A mismatching receipt can follow a committed write; do not label it rolled back.
        if (error?.code !== 'OPS_MEMORY_RECEIPT_MISMATCH') throw error;
      }
      ambiguous = true;
    }
    if (options.signal?.aborted) return immutable({state:'reconciliation_required',deliveryVerified:false,
      sourceRunId:outcome.sourceRunId,canonicalMemoryWritten:false,reason:'cancelled_after_submission'});
    try {
      const readback = await this.reconcileOutcome(sourceScope, outcome, options);
      if (readback.deliveryVerified !== true) return readback;
      requireThat(!original || (original.receiptId === readback.receiptId
        && original.candidateId === readback.candidateId && original.reviewItemId === readback.reviewItemId
        && original.payloadSha256 === readback.payloadSha256), 'OPS_MEMORY_RECEIPT_DRIFT');
      return immutable({...readback,recoveredAfterUnknownResponse:ambiguous});
    } catch (error) {
      return immutable({state:'reconciliation_required',deliveryVerified:false,sourceRunId:outcome.sourceRunId,
        canonicalMemoryWritten:false,reason:error instanceof MemoryIntegrationError ? error.code : 'readback_unavailable'});
    }
  }
}
