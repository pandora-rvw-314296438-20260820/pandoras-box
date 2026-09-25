import { createPublicKey, KeyObject, randomUUID, verify } from 'node:crypto';
import { AresError, OPERATIONS, actionDigest, canonical, demand, exact, identifier, immutable, integer, rejectSecrets } from './contract.mjs';

function publicKey(value) {
  demand(!(typeof value === 'string' && value.includes('PRIVATE KEY')), 'ARES_PRIVATE_KEY_NOT_ACCEPTED');
  const key = value instanceof KeyObject ? value : createPublicKey(value);
  demand(key.type === 'public' && key.asymmetricKeyType === 'ed25519', 'ARES_PUBLIC_KEY_INVALID');
  return key;
}
function decode(part, maxBytes) {
  demand(typeof part === 'string' && /^[A-Za-z0-9_-]+$/.test(part), 'ARES_SIGNATURE_ENCODING');
  const bytes = Buffer.from(part, 'base64url');
  demand(bytes.length <= maxBytes && bytes.toString('base64url') === part, 'ARES_SIGNATURE_ENCODING');
  return bytes;
}
function readJson(part, limit) {
  const bytes = decode(part, limit), raw = bytes.toString('utf8');
  const value = JSON.parse(raw);
  demand(canonical(value) === raw && Buffer.from(raw).equals(bytes), 'ARES_NONCANONICAL_PROOF');
  return value;
}
export class SignedAresProofs {
  constructor({ keys, issuer, nodeId, clock = Date.now }) {
    demand(keys && Object.keys(keys).length > 0 && Object.keys(keys).length <= 16, 'ARES_TRUST_KEYS_REQUIRED');
    this.keys = new Map(Object.entries(keys).map(([id, value]) => [identifier(id), publicKey(value)]));
    this.issuer = identifier(issuer);
    this.nodeId = identifier(nodeId);
    this.clock = clock;
  }
  verifyToken(token, type) {
    demand(typeof token === 'string' && token.length <= 16000, 'ARES_SIGNED_PROOF_REQUIRED');
    const parts = token.split('.');
    demand(parts.length === 3, 'ARES_SIGNED_PROOF_REQUIRED');
    const header = readJson(parts[0], 512), payload = readJson(parts[1], 10000);
    exact(header, ['alg', 'kid', 'typ']);
    demand(header.alg === 'EdDSA' && header.typ === type && this.keys.has(header.kid), 'ARES_UNTRUSTED_SIGNER');
    const signature = decode(parts[2], 64);
    demand(signature.length === 64 && verify(null, Buffer.from(parts[0] + '.' + parts[1]), this.keys.get(header.kid), signature), 'ARES_BAD_SIGNATURE');
    demand(payload.iss === this.issuer && payload.aud === this.nodeId, 'ARES_PROOF_AUDIENCE');
    const now = Math.floor(this.clock() / 1000);
    for (const k of ['iat', 'nbf', 'exp']) integer(payload[k], 0, Number.MAX_SAFE_INTEGER, 'ARES_PROOF_TIME');
    demand(payload.iat <= now + 5 && payload.nbf <= now && payload.exp > now && payload.exp - payload.iat <= 600 && payload.iat <= payload.nbf, 'ARES_EXPIRED_PROOF');
    identifier(payload.jti, 'ARES_PROOF_ID');
    rejectSecrets(payload);
    return immutable(payload);
  }
  grant(token, job) {
    demand(job.nodeId === this.nodeId, 'ARES_NODE_SCOPE');
    const p = this.verifyToken(token, 'PANDORA_ARES_GRANT_V1');
    exact(p, ['iss', 'aud', 'iat', 'nbf', 'exp', 'jti', 'organizationId', 'projectId', 'taskId', 'workerId', 'leaseId', 'generation', 'requestId', 'operation', 'actionHash', 'sourceSha', 'serial', 'avdName', 'packageName', 'environment', 'risk', 'decision', 'policyRef', 'approvalRef', 'controlRevision', 'profileSha256']);
    for (const key of ['organizationId', 'projectId', 'taskId', 'workerId', 'leaseId', 'generation', 'requestId', 'operation', 'sourceSha', 'profileSha256']) demand(p[key] === job[key], 'ARES_GRANT_SCOPE');
    for (const key of ['serial', 'avdName', 'packageName']) demand(p[key] === job.target[key], 'ARES_GRANT_TARGET');
    demand(p.actionHash === actionDigest(job) && p.decision === 'ALLOW' && p.environment === 'test', 'ARES_ACTION_NOT_AUTHORIZED');
    demand(p.risk === OPERATIONS[job.operation].risk && typeof p.policyRef === 'string' && p.policyRef.length > 0 && p.policyRef.length <= 1000, 'ARES_POLICY_BINDING');
    integer(p.controlRevision, 0, Number.MAX_SAFE_INTEGER, 'ARES_CONTROL_REVISION');
    if (p.risk === 'destructive') demand(typeof p.approvalRef === 'string' && p.approvalRef.length > 0 && p.approvalRef.length <= 1000, 'ARES_EXACT_APPROVAL_REQUIRED');
    return p;
  }
  lease(token, job, grant, nonce) {
    const p = this.verifyToken(token, 'PANDORA_ARES_LEASE_V1');
    exact(p, ['iss', 'aud', 'iat', 'nbf', 'exp', 'jti', 'nonce', 'organizationId', 'projectId', 'leaseId', 'generation', 'actionHash', 'controlRevision', 'state', 'receiptRef']);
    demand(p.nonce === nonce && p.organizationId === job.organizationId && p.projectId === job.projectId && p.leaseId === job.leaseId && p.generation === job.generation && p.actionHash === grant.actionHash && p.controlRevision === grant.controlRevision, 'ARES_LEASE_BINDING');
    demand(p.state === 'running' && p.exp - p.iat <= 30 && Math.floor(this.clock()/1000) - p.iat <= 15, 'ARES_LEASE_REVOKED');
    demand(typeof p.receiptRef === 'string' && p.receiptRef.length > 0 && p.receiptRef.length <= 1000, 'ARES_LEASE_RECEIPT_REQUIRED');
    return p;
  }
}

export class AresLeaseAuthority {
  constructor({ proofs, readCurrentLease }) {
    demand(proofs instanceof SignedAresProofs && typeof readCurrentLease === 'function', 'ARES_AUTHORITY_TRANSPORT_REQUIRED');
    this.proofs = proofs;
    this.readCurrentLease = readCurrentLease;
  }
  async check(job, grantToken, { signal } = {}) {
    const grant = this.proofs.grant(grantToken, job), nonce = randomUUID();
    if (signal?.aborted) throw new AresError('ARES_CANCELLED');
    const proof = await this.readCurrentLease(immutable({
      nodeId: job.nodeId, organizationId: job.organizationId, projectId: job.projectId,
      requestId: job.requestId, leaseId: job.leaseId, generation: job.generation,
      actionHash: grant.actionHash, controlRevision: grant.controlRevision, nonce,
    }), { signal });
    if (signal?.aborted) throw new AresError('ARES_CANCELLED');
    const lease = this.proofs.lease(proof, job, grant, nonce);
    return immutable({grantRef: grant.jti, expiresAt: grant.exp*1000, policyRef: grant.policyRef, leaseReceiptRef: lease.receiptRef, controlRevision: grant.controlRevision});
  }
}

function abortable(promise, signal) {
  if(signal.aborted)return Promise.reject(new AresError('ARES_CONTROL_UNAVAILABLE'));
  return new Promise((resolve,reject)=>{
    const abort=()=>{signal.removeEventListener('abort',abort);reject(new AresError('ARES_CONTROL_UNAVAILABLE'));};
    signal.addEventListener('abort',abort,{once:true});
    Promise.resolve(promise).then(value=>{signal.removeEventListener('abort',abort);resolve(value);},error=>{signal.removeEventListener('abort',abort);reject(error);});
  });
}

/** The signer holds only the enrolled node identity, not a provider/master credential. */
export function createHttpsLeaseReader({ endpoint, signNodeRequest, fetchImpl = fetch, timeoutMs = 5000 }) {
  const url = new URL(endpoint);
  demand(url.protocol === 'https:' && /^[a-z]{20}\.supabase\.co$/.test(url.hostname) && url.pathname === '/functions/v1/pandora-ares-control' && !url.port && !url.search && !url.hash && !url.username && !url.password, 'ARES_CONTROL_ENDPOINT_DENIED');
  demand(typeof signNodeRequest === 'function' && typeof fetchImpl === 'function', 'ARES_NODE_IDENTITY_REQUIRED');
  integer(timeoutMs, 100, 10000);
  return async (payload, { signal } = {}) => {
    const timerController=new AbortController();
    const timer=setTimeout(()=>timerController.abort(),timeoutMs);
    const combined = signal ? AbortSignal.any([signal, timerController.signal]) : timerController.signal;
    let response;
    try {
      const signedRequest = await abortable(signNodeRequest(payload),combined);
      demand(typeof signedRequest === 'string' && signedRequest.length <= 16000, 'ARES_NODE_SIGNATURE_REQUIRED');
      response = await abortable(fetchImpl(url.href, {method:'POST', redirect:'error', signal:combined, headers:{'content-type':'application/json'}, body:JSON.stringify({operation:'lease_check', signedRequest})}),combined);
      demand(response.ok && response.body, 'ARES_CONTROL_UNAVAILABLE');
      const reader = response.body.getReader(); let size=0; const chunks=[];
      try {
        while (true) { const item=await abortable(reader.read(),combined); if(item.done)break; size+=item.value.byteLength; if(size>20000){void reader.cancel().catch(()=>{});throw new AresError('ARES_CONTROL_RESPONSE_LIMIT');} chunks.push(Buffer.from(item.value)); }
      } finally { if(combined.aborted)void reader.cancel().catch(()=>{}); reader.releaseLock(); }
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      exact(body, ['ok', 'signedProof']);
      demand(body.ok === true && typeof body.signedProof === 'string', 'ARES_CONTROL_INVALID');
      return body.signedProof;
    } catch(error) {
      if(error instanceof AresError)throw error;
      throw new AresError(signal?.aborted ? 'ARES_CANCELLED' : 'ARES_CONTROL_UNAVAILABLE');
    } finally {clearTimeout(timer);timerController.abort();}
  };
}
