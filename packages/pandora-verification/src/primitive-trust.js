'use strict';
const crypto = require('node:crypto');
const AUTHORITATIVE_ISSUER = 'pandora-verification-engine';
const FINDING_SEVERITIES = Object.freeze(['LOW','MEDIUM','HIGH','CRITICAL']);

function buildPrimitiveVerificationDecision({ definition, run, evidenceId = null } = {}) {
  assertDefinition(definition);
  if (!run || typeof run !== 'object') throw new TypeError('Worker E verification run is required');
  const status = normalizeOutcome(run.status);
  const exactEvidenceId = evidenceId || run.verification_run_id;
  if (typeof exactEvidenceId !== 'string' || !exactEvidenceId.trim()) throw new TypeError('verification evidenceId is required');
  if (!run.request || run.request.source_digest !== definition.sourceDigest) throw new Error('Worker E verification source digest does not match primitive source digest');
  if (status === 'PASS') assertAuthoritativePass(run);
  return Object.freeze({ authority:'worker-e', evidenceId:exactEvidenceId.trim(), status, sourceDigest:definition.sourceDigest, primitive:definition.name, version:definition.version, verificationIdentityDigest:run.identity_digest||null, recordedAt:run.completed_at||null });
}

function createPrimitiveVerificationAuthority({ readVerificationRun } = {}) {
  if (typeof readVerificationRun !== 'function') throw new TypeError('readVerificationRun is required');
  return Object.freeze({
    verifyDecision({ definition, decision } = {}) {
      try {
        assertDefinition(definition);
        if (!decision || decision.authority !== 'worker-e' || typeof decision.evidenceId !== 'string' || !decision.evidenceId.trim()) return false;
        const run = readVerificationRun(decision.evidenceId.trim());
        if (!run || typeof run !== 'object' || typeof run.then === 'function') return false;
        const expected = buildPrimitiveVerificationDecision({ definition, run, evidenceId: decision.evidenceId.trim() });
        return expected.status === decision.status
          && expected.sourceDigest === decision.sourceDigest
          && expected.primitive === decision.primitive
          && expected.version === decision.version
          && expected.verificationIdentityDigest === (decision.verificationIdentityDigest || null);
      } catch (_) {
        return false;
      }
    },
  });
}

function assertAuthoritativePass(run) {
  if (!Array.isArray(run.required_checks) || run.required_checks.length === 0) throw new Error('primitive PASS requires Worker E required checks');
  if (!Array.isArray(run.results)) throw new Error('primitive PASS requires Worker E check results');
  for (const checkId of run.required_checks) {
    const matching = run.results.filter((result) => result && result.check_id === checkId);
    if (!matching.length) throw new Error(`primitive PASS missing required Worker E check ${checkId}`);
    for (const result of matching) {
      if (result.status !== 'PASS') throw new Error(`primitive PASS contains non-PASS required check ${checkId}`);
      if (result.authoritative_issuer !== AUTHORITATIVE_ISSUER) throw new Error(`primitive PASS check ${checkId} is not authoritative Worker E evidence`);
      if (!Array.isArray(result.evidence_refs) || !result.evidence_refs.length) throw new Error(`primitive PASS check ${checkId} requires evidence references`);
    }
  }
  return true;
}

function scanPrimitiveAdversarialFixtures(files,{upgrade=null}={}) {
  if(!Array.isArray(files)||!files.length)throw new TypeError('fixture files are required'); const findings=[];
  for(const file of files){if(!file||typeof file.path!=='string'||typeof file.content!=='string')throw new TypeError('fixture file path/content are required');const text=file.content;
    add(text,/DISABLE\s+ROW\s+LEVEL\s+SECURITY/i,findings,file.path,'RLS_DISABLED','CRITICAL','Row-level security is explicitly disabled');
    add(text,/CREATE\s+POLICY[\s\S]{0,400}\b(?:USING|WITH\s+CHECK)\s*\(\s*true\s*\)/i,findings,file.path,'RLS_ALLOW_ALL','CRITICAL','RLS policy allows all rows');
    add(text,/GRANT\s+(?:INSERT|UPDATE|DELETE|ALL)(?:\s*,\s*(?:INSERT|UPDATE|DELETE|ALL))*\s+ON[\s\S]{0,180}\s+TO\s+authenticated/i,findings,file.path,'CLIENT_PRIVILEGED_WRITE','HIGH','Authenticated client receives privileged table writes');
    add(text,/\bservice[_-]?role\b|\bPANDORA_FAKE_SECRET_CANARY\b/i,findings,file.path,'SECRET_BOUNDARY','CRITICAL','Primitive source contains privileged-secret-shaped material');
    add(text,/\b(?:clientSuccess|client_success|markPaidFromClient|paymentSuccessFromClient)\b/i,findings,file.path,'PAYMENT_CLIENT_AUTHORITY','CRITICAL','Client-controlled state can assert payment success');
    add(text,/\b(?:tenant_id|scope_id)\s*=\s*(?:tenant_id|scope_id)\b/i,findings,file.path,'CROSS_TENANT_BYPASS','CRITICAL','Tenant predicate is tautological');
    if(/\bwebhook\b/i.test(text)&&!/\bidempot(?:ent|ency)\b/i.test(text))findings.push(finding(file.path,'WEBHOOK_REPLAY_UNBOUNDED','HIGH','Webhook handling lacks explicit idempotency/replay identity'));
    if(/\b(?:DROP\s+TABLE|TRUNCATE\s+TABLE|ALTER\s+TABLE[\s\S]{0,160}\s+DROP\s+COLUMN)\b/i.test(text)&&!/\b(?:rollback|forwardFix|forward_fix|recovery)\b/i.test(text))findings.push(finding(file.path,'UNSAFE_DESTRUCTIVE_MIGRATION','CRITICAL','Destructive migration has no recovery/forward-fix context'));
  }
  if(upgrade){if(typeof upgrade!=='object')throw new TypeError('upgrade fixture must be an object');if(upgrade.decision==='AUTO'&&(upgrade.irreversible===true||upgrade.targetTrustState==='BLOCKED'||upgrade.majorChange===true))findings.push(finding('upgrade','UNSAFE_AUTO_UPGRADE','CRITICAL','Unsafe upgrade is incorrectly marked AUTO'));if(upgrade.migrationDigest&&!/^sha256:[0-9a-f]{64}$/.test(upgrade.migrationDigest))findings.push(finding('upgrade','MUTABLE_MIGRATION_IDENTITY','HIGH','Upgrade migration is not bound to immutable SHA-256 identity'));}
  return Object.freeze({ok:findings.length===0,findings:Object.freeze(findings.sort((a,b)=>a.code.localeCompare(b.code)||a.path.localeCompare(b.path))),evidenceDigest:digestFindings(findings)});
}

function buildPrimitiveFailureDecision({definition,evidenceId,findings,recordedAt=null}={}){assertDefinition(definition);if(typeof evidenceId!=='string'||!evidenceId.trim())throw new TypeError('evidenceId is required');if(!Array.isArray(findings)||!findings.length)throw new TypeError('at least one independent verification finding is required');return Object.freeze({authority:'worker-e',evidenceId:evidenceId.trim(),status:'FAIL',sourceDigest:definition.sourceDigest,primitive:definition.name,version:definition.version,findingCodes:Object.freeze([...new Set(findings.map((item)=>item.code))].sort()),recordedAt});}
function finding(path,code,severity,summary){if(!FINDING_SEVERITIES.includes(severity))throw new TypeError('invalid finding severity');return Object.freeze({path,code,severity,summary});}
function add(text,pattern,findings,path,code,severity,summary){if(pattern.test(text))findings.push(finding(path,code,severity,summary));}
function digestFindings(findings){const canonical=findings.map(({path,code,severity,summary})=>({path,code,severity,summary})).sort((a,b)=>a.code.localeCompare(b.code)||a.path.localeCompare(b.path));return `sha256:${crypto.createHash('sha256').update(JSON.stringify(canonical)).digest('hex')}`;}
function normalizeOutcome(status){if(status==='PASS')return'PASS';if(status==='BLOCKED')return'BLOCKED';if(['FAIL','INCONCLUSIVE','STALE'].includes(status))return'FAIL';throw new Error(`Worker E verification run is not final: ${status}`);}
function assertDefinition(definition){if(!definition||typeof definition!=='object')throw new TypeError('primitive definition is required');for(const field of ['name','version','sourceDigest'])if(typeof definition[field]!=='string'||!definition[field].trim())throw new TypeError(`primitive ${field} is required`);if(!/^sha256:[0-9a-f]{64}$/.test(definition.sourceDigest))throw new TypeError('primitive sourceDigest must be immutable SHA-256');}
module.exports={AUTHORITATIVE_ISSUER,FINDING_SEVERITIES,assertAuthoritativePass,buildPrimitiveFailureDecision,buildPrimitiveVerificationDecision,createPrimitiveVerificationAuthority,scanPrimitiveAdversarialFixtures};
