const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const root=path.resolve(__dirname,'..');
const read=(...parts)=>fs.readFileSync(path.join(root,...parts),'utf8');

const api=read('apps','meta-business-mcp','src','operator','api.js');
const truth=read('apps','meta-business-mcp','src','operator','business-truth.js');
const app=read('apps','control-tower','owner-app.js');
const professional=read('apps','control-tower','owner-professional.js');

test('Professional Business uses only authenticated operator Business truth',()=>{
  assert.match(api,/router\.get\('\/business-truth'/);
  assert.match(app,/request\('\/business-truth'\)/);
  assert.doesNotMatch(app,/pandora_project_business_objectives|pandora_cost_entries|pandora_budget_limits/);
  assert.match(truth,/identity\?\.accessToken/);
  assert.match(truth,/SupabaseRestClient/);
});

test('Business truth is bounded to safe member-RLS fields',()=>{
  assert.match(truth,/pandora_project_business_objectives\?select=id,project_id,ordinal,objective,desired_outcome,success_metric,baseline,target,created_at/);
  assert.match(truth,/pandora_budget_limits\?select=id,project_id,budget_kind,currency,warning_limit_micros,hard_limit_micros,reserved_micros,spent_micros,status,updated_at/);
  assert.match(truth,/pandora_cost_entries\?select=id,project_id,cost_category,estimated_cost_micros,billed_cost_micros,charged_cost_micros,credit_micros,currency,occurred_at/);
  assert.doesNotMatch(truth,/metadata_redacted|provenance|idempotency_key|source_payload|storage_path|credential/i);
});

test('Business UI refuses to convert missing provider outcomes into commercial claims',()=>{
  assert.ok(professional.includes("metricCard('Revenue', 'Not measured'"));
  assert.ok(professional.includes("metricCard('Retention', 'Not measured'"));
  assert.ok(professional.includes("metricCard('Paid pilots', 'Not measured'"));
  assert.ok(professional.includes("metricCard('ROI', 'Unknown'"));
  assert.ok(professional.includes('Operational economics are not commercial proof'));
  assert.ok(professional.includes('They are not silently relabeled as revenue, margin, ROI, retention, pilot success or customer outcomes.'));
});

test('Business cached records are purged on sign-out',()=>{
  assert.match(app,/state\.businessTruth = \{/);
  assert.match(app,/projects: \[\], boundaries: null, error: null/);
  assert.match(professional,/if \(!session\.authenticated\)/);
  assert.ok(professional.includes('Business control-plane records are protected and are purged from this owner surface after sign-out.'));
});
