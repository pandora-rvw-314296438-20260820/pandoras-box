import test from 'node:test';
import assert from 'node:assert/strict';
import { createCustomerOutputChunks } from '../src/logs/log-records.mjs';
import { parseCompileDiagnostics } from '../src/diagnostics/compile-diagnostics.mjs';
import { createRepairController } from '../src/repair/repair-controller.mjs';
import { classifyRepairDisposition, REPAIR_DISPOSITIONS } from '../src/repair/repair-classifier.mjs';
import { executeRepairAttempt } from '../src/repair/repair-runtime.mjs';

const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const eventContext = () => ({ executionId: uuid(1), buildJobId: uuid(2), projectId: uuid(3), organizationId: uuid(4), projectVersionId: uuid(5), attempt: 1 });

test('output is redacted and bounded', () => {
  const secret = 'secret-value-123456';
  const result = createCustomerOutputChunks({ stream: 'stderr', text: `Authorization: Bearer abc.def.ghi\napi_key=${secret}\n${'x'.repeat(5000)}`, secrets: [secret], maxChunkBytes: 512, maxTotalBytes: 1536 });
  const shown = result.chunks.map((chunk) => chunk.text).join('');
  assert.equal(shown.includes(secret), false);
  assert.equal(/Authorization:\s*Bearer/i.test(shown), false);
  assert.equal(result.displayedBytes <= 1536, true);
  assert.equal(result.truncated, true);
});

test('diagnostics are relative and exact duplicates collapse', () => {
  const diagnostics = parseCompileDiagnostics({
    stderr: [
      "/work/project/src/app.ts:4:2 - error TS2304: Cannot find name 'x'",
      "/work/project/src/app.ts:4:2 - error TS2304: Cannot find name 'x'",
      "/work/project/src/app.ts:9:2 - error TS2304: Cannot find name 'x'",
      "/tmp/platform/secret.ts:1:1 - error TS9999: platform detail",
    ].join('\n'),
    tool: 'typescript', workspaceRoot: '/work/project',
  });
  assert.deepEqual(diagnostics.map((item) => [item.filePath, item.line]), [['src/app.ts', 4], ['src/app.ts', 9]]);
  assert.match(diagnostics[0].fingerprint, /^[0-9a-f]{64}$/);
});

test('repair classifier separates source defects from user and infrastructure failures', () => {
  assert.equal(classifyRepairDisposition({ failureClass: 'syntax' }), REPAIR_DISPOSITIONS.AUTO_REPAIRABLE);
  assert.equal(classifyRepairDisposition({ failureClass: 'credential' }), REPAIR_DISPOSITIONS.NEEDS_USER_INPUT);
  assert.equal(classifyRepairDisposition({ failureClass: 'network' }), REPAIR_DISPOSITIONS.RETRY_INFRASTRUCTURE);
  assert.equal(classifyRepairDisposition({ failureClass: 'resource_limit' }), REPAIR_DISPOSITIONS.NON_REPAIRABLE);
});

test('authorized repair streams actual changed source then rebuilds', async () => {
  const controller = createRepairController({ buildJobId: uuid(2), sourceDigest: 'a'.repeat(64), budget: { maxAttempts: 2, maxChangedFiles: 4, maxChangedBytes: 8192, maxCostCents: 20 } });
  const events = []; let rebuilds = 0;
  const result = await executeRepairAttempt({
    controller, failureClass: 'syntax', diagnostics: [{ filePath: 'src/app.js', message: 'Unexpected token' }], failureFingerprint: 'f'.repeat(64), authorizationId: 'repair-auth-1', changedFiles: [{ path: 'src/app.js', operation: 'modify', sizeBytes: 14 }], estimatedCostCents: 3,
    createWorkspace: async () => ({ root: '/candidate/repair-1' }),
    applyChanges: async () => ({ files: [{ path: 'src/app.js', operation: 'modify', content: 'const ok = 1;\n', beforeSha256: 'b'.repeat(64), afterSha256: 'c'.repeat(64) }] }),
    rebuild: async () => { rebuilds += 1; return { status: 'completed', sourceDigest: 'd'.repeat(64) }; },
    eventSink: async (event) => events.push(event), eventContext: eventContext(),
  });
  assert.equal(result.status, 'completed'); assert.equal(rebuilds, 1);
  assert.deepEqual(events.map((event) => event.eventType), ['repair_started','file_started','code_chunk','file_completed','repair_completed']);
  assert.equal(events[0].safePayload.diagnostic_count, 1);
  assert.equal(events[2].contentChunk, 'const ok = 1;\n');
  assert.equal(events.at(-1).safePayload.output_source_digest, 'd'.repeat(64));
});

test('secret-shaped repair source fails before rebuild and repeat fingerprint stops thrash', async () => {
  const controller = createRepairController({ buildJobId: uuid(2), sourceDigest: 'a'.repeat(64) });
  let rebuilds = 0;
  await assert.rejects(() => executeRepairAttempt({ controller, failureClass: 'syntax', diagnostics: [{ filePath: 'src/app.js', message: 'bad' }], authorizationId: 'repair-auth-2', changedFiles: [{ path: 'src/app.js', operation: 'modify', sizeBytes: 40 }], createWorkspace: async () => ({ root: '/candidate/repair-2' }), applyChanges: async () => ({ files: [{ path: 'src/app.js', operation: 'modify', content: 'api_key=secret-value-123456789\n' }] }), rebuild: async () => { rebuilds += 1; return { status: 'completed' }; }, eventSink: async () => {}, eventContext: eventContext() }), /REPAIR_SOURCE_STREAM_SECRET_BLOCKED/);
  assert.equal(rebuilds, 0);

  const loop = createRepairController({ buildJobId: uuid(2), sourceDigest: 'a'.repeat(64) });
  const args = { failureClass: 'syntax', failureFingerprint: 'e'.repeat(64), authorizationId: 'repair-auth-3', changedFiles: [{ path: 'src/app.js', operation: 'modify', sizeBytes: 10 }], estimatedCostCents: 2 };
  loop.authorize(args);
  assert.throws(() => loop.authorize(args), /REPAIR_REPEATED_FAILURE_FINGERPRINT/);
});
