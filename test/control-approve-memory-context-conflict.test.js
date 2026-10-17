const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const test = require('node:test');
const {
  ExecutionLedgerClient,
  ExecutionLedgerError,
} = require('../src/runtime/execution-ledger-client.js');

test('control edge function maps projectos_memory_context_required_before_approval RPC failure to HTTP 409', async () => {
  const edge = await readFile('supabase/functions/mcpmaster-supabase-control/index.ts', 'utf8');
  assert.match(edge, /class ControlRpcConflict extends Error/);
  assert.match(edge, /projectos_memory_context_required_before_approval/);
  assert.match(edge, /memory_context_required_before_approval/);
  assert.match(edge, /error instanceof ControlRpcConflict[\s\S]*response\(409,\s*\{\s*ok:\s*false,\s*error:\s*error\.errorCode\s*\}\)/);
});

test('ExecutionLedgerClient.approvePlan surfaces 409 memory_context_required_before_approval as ExecutionLedgerError', async () => {
  const client = new ExecutionLedgerClient({
    contextProvider: null,
    contextLedger: null,
    fetchFn: async () => new Response(
      JSON.stringify({
        ok: false,
        error: 'memory_context_required_before_approval',
      }),
      {
        status: 409,
        headers: { 'content-type': 'application/json' },
      },
    ),
  });

  await assert.rejects(
    () => client.approvePlan(
      'vercel-oidc-token-at-least-twenty-chars',
      '11111111-1111-4111-8111-111111111111',
      'operator@example.com',
    ),
    (error) => {
      assert.ok(error instanceof ExecutionLedgerError);
      assert.equal(error.status, 409);
      assert.match(error.message, /memory_context_required_before_approval/);
      return true;
    },
  );
});
