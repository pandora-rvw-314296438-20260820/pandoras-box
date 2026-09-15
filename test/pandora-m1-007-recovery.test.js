'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const root = join(__dirname, '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');
const migration = read('supabase','migrations','20260915013000_pandora_activity_recovery_v1.sql');
const activity = read('supabase','functions','pandora-intelligence-chat','activity.ts');
const edge = read('supabase','functions','pandora-intelligence-chat','index.ts');
const mobile = read('apps','pandora-mobile','lib','core','data','pandora_activity_stream_api.dart');

test('M1-007 stores one execution claim, fingerprint, checkpoint and recoverable public result', () => {
  for (const column of ['request_fingerprint','execution_state','execution_claim_id','execution_generation','execution_checkpoint','execution_effect_state','execution_result']) {
    assert.match(migration, new RegExp(`add column if not exists ${column}`));
  }
  assert.match(migration, /request_fingerprint ~ '\^\[0-9a-f\]\{64\}\$'/);
  assert.match(migration, /execution_state in \('ready','running','complete','failed','cancelled'\)/);
  assert.match(migration, /execution_effect_state in \('none','ambiguous','verified'\)/);
});

test('duplicate execution delivery observes or reconciles and never steals an active claim', () => {
  assert.match(migration, /if v_job\.execution_state='running'/);
  assert.match(migration, /if v_job\.execution_claim_id=p_claim_id/);
  assert.match(migration, /'mode','observe'/);
  assert.match(migration, /'mode','reconcile'/);
  assert.match(migration, /pandora_activity_execution_idempotency_conflict/);
  assert.doesNotMatch(migration, /lease_expires|stale_after|claim_timeout|automatic_takeover/i);
});

test('execution mutation RPCs are service-only and stale claims fail closed', () => {
  for (const fn of ['pandora_activity_execution_claim_v1','pandora_activity_execution_checkpoint_v1','pandora_activity_execution_finish_v1','pandora_activity_execution_readback_v1']) {
    assert.match(migration, new RegExp(`revoke all on function public\\.${fn}`));
    assert.match(migration, new RegExp(`grant execute on function public\\.${fn}[\\s\\S]*to service_role`));
  }
  assert.match(migration, /pandora_activity_execution_claim_stale/);
  assert.match(migration, /octet_length\(p_result::text\)>131072/);
});

test('edge runtime claims before routing and fingerprints the full admitted request', () => {
  assert.match(edge, /executionRequestFingerprint/);
  assert.match(edge, /message:i\.message,threadId:i\.threadId,projectId:i\.projectId,mode:i\.mode,attachments:i\.attachments/);
  const claim = edge.indexOf('claimActivityExecution(c.admin');
  const dispatch = edge.indexOf('universalDispatch(c.user');
  const provider = edge.indexOf('providerExact(c.admin');
  assert.ok(claim >= 0 && claim < dispatch && claim < provider);
  assert.match(edge, /if\(executionClaim\.mode!=="execute"\)/);
  assert.match(edge, /reconcileExistingActivityExecution/);
  assert.match(edge, /recovered:true/);
});

test('runtime checkpoints ambiguous capability mutation and model/result persistence separately', () => {
  const ambiguous = edge.indexOf('"capability_dispatching"');
  const dispatch = edge.indexOf('universalDispatch(c.user');
  assert.ok(ambiguous >= 0 && ambiguous < dispatch);
  assert.match(edge, /"request_persisted",`message:\$\{userMessageId\}`,"none"/);
  assert.match(edge, /"provider_running",`attempt:\$\{tid\}:\$\{index\+1\}`,"none"/);
  assert.match(edge, /"result_persisted"/);
  assert.match(edge, /finishActivityExecution\(c\.admin,i\.activityJobId,executionClaim\.claimId,"complete"/);
});

test('duplicate reconnect waits for authoritative readback and can terminalize a persisted result', () => {
  assert.match(activity, /waitForActivityExecutionReadback/);
  assert.match(activity, /pandora_activity_execution_readback_v1/);
  assert.match(edge, /Recovered the persisted verified response after reconnect\./);
  assert.match(edge, /ACTIVITY_EXECUTION_IN_PROGRESS/);
  assert.match(edge, /ACTIVITY_EXECUTION_PREVIOUS_FAILED/);
  assert.match(edge, /That request identity belongs to different input\. Pandora did not execute it twice\./);
});

test('mobile activity stream reconnects from durable sequence replay without fabricating history', () => {
  assert.match(mobile, /afterSequence: cursor/);
  assert.match(mobile, /historyGapDueToRetention/);
  assert.match(mobile, /Activity history is incomplete and requires authoritative recovery/);
  assert.match(mobile, /while \(terminalState == null\)/);
  assert.match(mobile, /reconnectAttempts \+= 1/);
  assert.match(mobile, /reconnectAttempts > 8/);
  assert.match(mobile, /Persisted history remains available/);
  assert.match(mobile, /Duration\(milliseconds: reconnectAttempts \* 250\)/);
  assert.ok((mobile.match(/for \(final event in await catchUp\(\)\)/g) ?? []).length >= 3);
  assert.match(mobile, /sequence != cursor \+ 1/);
  assert.match(mobile, /writer rollback/);
  assert.match(mobile, /two writers in one activity epoch/);
});