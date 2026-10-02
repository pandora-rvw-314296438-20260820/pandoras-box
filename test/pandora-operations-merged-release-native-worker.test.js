'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'api/operations-native-worker.ts'), 'utf8');
const reconciliationSql = fs.readFileSync(path.join(
  root, 'supabase', 'migrations',
  '20260928190000_operations_merged_release_reconciliation_v1.sql',
), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, esModuleInterop: true },
}).outputText;
const head = '3e38b571ae963cc663e622fc1a75d5578b6fb7a2';
const receipt = 'b05c163a-1044-4a24-b4d5-ad1139133188';
const cron = 'fixture-cron-secret-never-used-outside-this-test';
const completion = () => ({
  state: 'complete', taskId: 'FB-025', generation: 5, headSha: head,
  reconciliationReceiptId: receipt, reconciled: true,
  verification: { complete: true },
});
const task = (id = 'FB-025', status = 'verifying') => ({ spec: { id }, status });

async function invoke(options = {}) {
  const calls = [];
  const module = { exports: {} };
  const response = {
    statusCode: 0, body: null, headers: {},
    status(code) { this.statusCode = code; },
    setHeader(key, value) { this.headers[key] = value; },
    end(body) { this.body = JSON.parse(body); },
  };
  const fetch = async (url, input) => {
    const payload = JSON.parse(input.body);
    calls.push({ url: String(url), payload, headers: input.headers });
    if (String(url).includes('/pandora-memory-bridge')) {
      return new Response(JSON.stringify({
        ok: true, projectId: '7c686cbd-d968-49d5-86cc-918f5e777bd2',
        namespace: 'real_life', memoryProjectRef: 'ivmvufhcsezyhczzondn',
        data: { kind: 'task_context', authorizationGranted: false },
      }));
    }
    assert.equal(String(url),
      'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control');
    let operations;
    switch (payload.action) {
      case 'operations_snapshot':
        operations = { controls: { paused: options.paused === true },
          tasks: options.tasks || [task()] };
        break;
      case 'operations_activation_readback':
        operations = { nativeWorkerRpc: true };
        break;
      case 'operations_merged_release_source_step':
        if (options.providerFailure) {
          return new Response(JSON.stringify({ ok: false, error: 'PROVIDER_PROOF_UNAVAILABLE' }),
            { status: 503 });
        }
        operations = Object.hasOwn(options, 'step') ? options.step : completion();
        break;
      case 'operations_native_register':
      case 'operations_heartbeat':
      case 'operations_reasoning_rdp_register':
      case 'operations_reasoning_rdp_heartbeat':
        operations = { ok: true };
        break;
      case 'growth_learning_claim':
      case 'operations_reasoning_rdp_status':
      case 'operations_reasoning_rdp_candidate':
      case 'operations_generic_source_release_step':
      case 'operations_generic_source_candidate':
      case 'operations_preflight_next':
        operations = { state: 'idle' };
        break;
      default:
        throw new Error('Unexpected control action: ' + payload.action);
    }
    return new Response(JSON.stringify({ ok: true, operations }));
  };
  vm.runInNewContext(compiled, {
    module, exports: module.exports, Buffer, URL, Response, AbortSignal, fetch,
    process: { env: { CRON_SECRET: cron } },
    require(id) {
      if (id === 'node:crypto') return require(id);
      if (id === '../src/runtime/vercel-workload-identity.js') {
        return { resolveVercelWorkloadToken: async () =>
          options.missingIdentity ? null : 'fixture-workload-oidc' };
      }
      if (id === '../src/runtime/operations-source-release-policy.cjs') {
        return require(path.join(root, 'src/runtime/operations-source-release-policy.cjs'));
      }
      if (id === '../src/providers/aws-bedrock-runtime.js') {
        return {
          BEDROCK_ROLE_ARN: 'arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2',
          BEDROCK_REGION: 'us-east-1',
          assumeRoleWithVercelOidc: async () => { throw new Error('BEDROCK_SYNC_UNEXPECTED_IN_OPERATIONS_FIXTURE'); },
          converseWithBedrockTarget: async () => { throw new Error('BEDROCK_SYNC_UNEXPECTED_IN_OPERATIONS_FIXTURE'); },
        };
      }
      if (id === '../src/providers/aws-bedrock-catalog-sync.js') {
        return {
          discoverBedrockCatalog: async () => { throw new Error('BEDROCK_SYNC_UNEXPECTED_IN_OPERATIONS_FIXTURE'); },
          applyProbeResult: () => { throw new Error('BEDROCK_SYNC_UNEXPECTED_IN_OPERATIONS_FIXTURE'); },
        };
      }
      throw new Error('Unexpected import: ' + id);
    },
  }, { filename: 'operations-native-worker.js' });
  await module.exports.default({
    method: 'GET', url: '/api/operations-native-worker',
    headers: { authorization: 'Bearer ' + cron, ...(options.headers || {}) },
  }, response);
  return { ...response, calls };
}
const actions = result => result.calls.map(call => call.payload.action).filter(Boolean);
const stepCalls = result => result.calls.filter(call =>
  call.payload.action === 'operations_merged_release_source_step');

test('authenticated native wake advances FB025 through the action-only server verifier', async () => {
  const result = await invoke();
  assert.equal(result.statusCode, 200);
  assert.equal(result.body.state, 'complete');
  assert.equal(result.body.taskId, 'FB-025');
  assert.equal(result.body.release.reconciliationReceiptId, receipt);
  assert.equal(stepCalls(result).length, 1);
  assert.deepEqual(stepCalls(result)[0].payload, { action: 'operations_merged_release_source_step' });
  assert.equal(stepCalls(result)[0].headers.authorization, 'Bearer fixture-workload-oidc');
  const stepIndex = actions(result).indexOf('operations_merged_release_source_step');
  assert.equal(actions(result)[stepIndex - 1], 'operations_heartbeat');
  assert.equal(actions(result).includes('operations_verification_record'), false);
  assert.equal(actions(result).includes('operations_verification_accept'), false);
  assert.equal(actions(result).includes('operations_generic_source_candidate'), false);
});

test('handed-off FB025 uses the same provider-owned step', async () => {
  const result = await invoke({ tasks: [task('FB-025', 'handed_off')] });
  assert.equal(result.body.state, 'complete');
  assert.equal(stepCalls(result).length, 1);
});

for (const [name, tasks] of [
  ['already complete source task', [task('FB-025', 'complete')]],
  ['production task', [task('FB-012', 'handed_off')]],
  ['queued source task', [task('FB-025', 'queued')]],
  ['missing source task', []],
]) {
  test(name + ' does not trigger reconciliation or starve other source work', async () => {
    const result = await invoke({ tasks });
    assert.equal(result.statusCode, 200);
    assert.equal(stepCalls(result).length, 0);
    assert.equal(actions(result).includes('operations_generic_source_candidate'), true);
  });
}

test('paused workspace prevents merged-source provider work', async () => {
  const result = await invoke({ paused: true });
  assert.equal(result.body.state, 'paused');
  assert.equal(stepCalls(result).length, 0);
});

for (const [name, step] of [
  ['state-held', { state: 'held', taskId: 'FB-025', reason: 'source_state_not_eligible' }],
  ['provider-proof-held', { state: 'held', taskId: 'FB-025', reason: 'provider_proof_unconfirmed' }],
  ['idle', { state: 'idle', taskId: 'FB-025', reason: 'task_missing' }],
]) {
  test(name + ' source does not prevent unrelated work or claim completion', async () => {
    const result = await invoke({ step });
    assert.equal(result.statusCode, 200);
    assert.equal(result.body.state, 'idle');
    assert.equal(result.body.mergedFacebookSource.state, step.state);
    assert.equal(actions(result).includes('operations_generic_source_candidate'), true);
  });
}

for (const [name, step] of [
  ['missing response', null],
  ['unknown state', { state: 'success', taskId: 'FB-025' }],
  ['wrong task', { ...completion(), taskId: 'FB-012' }],
  ['missing acceptance', { ...completion(), verification: { complete: false } }],
  ['wrong head', { ...completion(), headSha: 'a'.repeat(40) }],
  ['invalid generation', { ...completion(), generation: 1 }],
  ['unexpected later generation', { ...completion(), generation: 6 }],
  ['missing receipt', { ...completion(), reconciliationReceiptId: null }],
]) {
  test(name + ' fails closed without falling through to source execution', async () => {
    const result = await invoke({ step });
    assert.equal(result.statusCode, 503);
    assert.equal(result.body.ok, false);
    assert.equal(actions(result).includes('operations_generic_source_candidate'), false);
  });
}

test('provider verification failure never becomes completion', async () => {
  const result = await invoke({ providerFailure: true });
  assert.equal(result.statusCode, 503);
  assert.equal(result.body.code, 'PROVIDER_PROOF_UNAVAILABLE');
  assert.equal(actions(result).includes('operations_generic_source_candidate'), false);
});

test('unauthorized wake cannot invoke the source step', async () => {
  const result = await invoke({ headers: { authorization: 'Bearer wrong' } });
  assert.equal(result.statusCode, 401);
  assert.equal(result.calls.length, 0);
});

test('browser-origin wake cannot invoke the source step', async () => {
  const result = await invoke({ headers: { origin: 'https://example.invalid' } });
  assert.equal(result.statusCode, 403);
  assert.equal(result.calls.length, 0);
});

test('missing workload identity cannot invoke provider or source work', async () => {
  const result = await invoke({ missingIdentity: true });
  assert.equal(result.statusCode, 503);
  assert.equal(result.calls.length, 0);
});

test('SQL provider phase is lock-free and apply phase is network-free', () => {
  const collectorStart = reconciliationSql.indexOf(
    'create function private.pandora_ops_collect_merged_release_provider_v1(',
  );
  const reconcileApplyStart = reconciliationSql.indexOf(
    'create function private.pandora_ops_apply_merged_release_reconciliation_v1(',
  );
  const publicReconcileStart = reconciliationSql.indexOf(
    'create function public.pandora_ops_reconcile_merged_release_v1(',
  );
  const verifyApplyStart = reconciliationSql.indexOf(
    'create function private.pandora_ops_apply_merged_release_source_verification_v1(',
  );
  const publicVerifyStart = reconciliationSql.indexOf(
    'create function public.pandora_ops_verify_merged_release_source_v1(',
  );
  const stepStart = reconciliationSql.indexOf(
    'create function public.pandora_ops_merged_release_source_step_v1(',
  );
  const collector = reconciliationSql.slice(collectorStart, reconcileApplyStart);
  const reconcileApply = reconciliationSql.slice(reconcileApplyStart, publicReconcileStart);
  const verifyApply = reconciliationSql.slice(verifyApplyStart, publicVerifyStart);
  const step = reconciliationSql.slice(stepStart);

  assert.ok(collectorStart >= 0 && reconcileApplyStart > collectorStart);
  assert.doesNotMatch(collector, /\bfor\s+(update|share)\b/i);
  assert.doesNotMatch(collector, /pg_(try_)?advisory_/i);
  assert.doesNotMatch(
    collector,
    /private\.pandora_ops_(project_bindings|workspaces|tasks|merged_release_receipts)/,
  );
  assert.match(collector, /private\.pandora_integration_github_api_20260825/g);
  assert.ok(collector.indexOf("'pr:first'") < collector.indexOf("'pr:last'"));
  assert.ok(collector.indexOf("'blob:test'") < collector.indexOf("'pr:last'"));

  assert.doesNotMatch(reconcileApply, /pandora_integration_github_api_20260825/);
  assert.doesNotMatch(verifyApply, /pandora_integration_github_api_20260825/);
  assert.match(reconcileApply, /for update/);
  assert.match(verifyApply, /for update/);
  assert.ok(step.indexOf('pandora_ops_collect_merged_release_provider_v1') <
    step.indexOf('pandora_ops_apply_merged_release_reconciliation_v1'));
  assert.match(step, /'union'/);

  for (const helper of [
    'pandora_ops_collect_merged_release_provider_v1',
    'pandora_ops_apply_merged_release_reconciliation_v1',
    'pandora_ops_apply_merged_release_source_verification_v1',
  ]) {
    assert.match(
      reconciliationSql,
      new RegExp('revoke all on function private\\.' + helper +
        '[\\s\\S]*?from public,anon,authenticated,service_role;'),
    );
  }
});
