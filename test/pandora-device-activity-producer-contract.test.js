import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const contract = await readFile(
  new URL(
    '../docs/architecture/PANDORA_DEVICE_ACTIVITY_PRODUCER_CONTRACT_V1.md',
    import.meta.url,
  ),
  'utf8',
);

test('device producers reuse frozen canonical Activity Theatre truth', () => {
  assert.match(contract, /does not create a second event schema/);
  assert.match(contract, /provenance\.sourceType = "device"/);
  assert.match(contract, /Use `device_event` evidence only for real Android\/device observations/);
  assert.match(contract, /physical-device `result` requires both overall-job verification evidence and `device_event`/);
});

test('device retries and History remain exactly-once canonical projections', () => {
  assert.match(contract, /reconcile ambiguous outcomes before retry/);
  assert.match(contract, /must not resend an SMS, restart a call/);
  assert.match(contract, /History requires no separate write/);
  assert.match(contract, /same immutable canonical event later/);
});
