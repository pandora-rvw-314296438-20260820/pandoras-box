const assert=require('node:assert/strict');
const test=require('node:test');
const { createBusinessTruthExecutor }=require('../dist/operator/business-truth.js');

const ORG='2270b266-59da-4c39-bfd9-9f8d08352af0';
const PROJECT='11111111-1111-4111-8111-111111111111';
const OBJECTIVE='22222222-2222-4222-8222-222222222222';
const TOKEN='human-business-read-token';

function response(data){ return new Response(JSON.stringify(data),{status:200,headers:{'content-type':'application/json'}}); }
function executor(fixtures){
  const seen=[];
  const value=createBusinessTruthExecutor({
    organizationId:ORG,
    supabaseUrl:'https://example.supabase.co',
    publishableKey:['unit','business','key'].join('-'),
    async fetchFn(url,init){
      seen.push({url:String(url),authorization:new Headers(init.headers).get('authorization')});
      const pathname=new URL(url).pathname;
      if(pathname.endsWith('/projectos_projects')) return response(fixtures.projects||[]);
      if(pathname.endsWith('/pandora_project_business_objectives')) return response(fixtures.objectives||[]);
      if(pathname.endsWith('/pandora_budget_limits')) return response(fixtures.budgets||[]);
      if(pathname.endsWith('/pandora_cost_entries')) return response(fixtures.costs||[]);
      return new Response('{}',{status:404});
    },
  });
  return {value,seen};
}

test('Business truth preserves objective readiness and separates internal cost from customer charge',async()=>{
  const {value,seen}=executor({
    projects:[{id:PROJECT,name:'Demo project',repository:'org/demo'}],
    objectives:[{id:OBJECTIVE,project_id:PROJECT,ordinal:1,objective:'Reduce checkout abandonment',desired_outcome:'More completed checkouts',success_metric:'Checkout conversion rate',baseline:'10%',target:'20%',created_at:'2026-09-08T00:00:00Z'}],
    budgets:[{id:'33333333-3333-4333-8333-333333333333',project_id:PROJECT,budget_kind:'project',currency:'USD',warning_limit_micros:8000000,hard_limit_micros:10000000,reserved_micros:1000000,spent_micros:5000000,status:'active'}],
    costs:[
      {id:'44444444-4444-4444-8444-444444444444',project_id:PROJECT,cost_category:'model',estimated_cost_micros:0,billed_cost_micros:2000000,charged_cost_micros:3500000,credit_micros:500000,currency:'USD',occurred_at:'2026-09-08T00:00:00Z'},
      {id:'55555555-5555-4555-8555-555555555555',project_id:PROJECT,cost_category:'verification',estimated_cost_micros:1000000,billed_cost_micros:0,charged_cost_micros:0,credit_micros:0,currency:'USD',occurred_at:'2026-09-08T00:01:00Z'},
    ],
  });
  const result=await value({actor:{identity:{accessToken:TOKEN}}});
  assert.equal(result.kind,'pandora.business-truth.v1');
  assert.equal(result.projects.length,1);
  const project=result.projects[0];
  assert.equal(project.measurementState,'configured_not_measured');
  assert.equal(project.outcomeState,'not_measured');
  assert.equal(project.objectives[0].measurementState,'configured_not_measured');
  assert.equal(project.economics[0].knownInternalCostMicros,3000000);
  assert.equal(project.economics[0].totalInternalCostMicros,3000000);
  assert.equal(project.economics[0].customerChargeMicros,3500000);
  assert.equal(project.economics[0].creditMicros,500000);
  assert.equal(project.economics[0].netCustomerChargeMicros,3000000);
  assert.equal(project.economics[0].confidence,'estimated');
  assert.equal(project.budgets[0].remainingMicros,4000000);
  assert.equal(result.boundaries.revenueState,'not_measured');
  assert.equal(result.boundaries.retentionState,'not_measured');
  assert.equal(result.boundaries.pilotState,'not_measured');
  assert.equal(result.boundaries.roiState,'not_measured');
  assert.ok(seen.every((entry)=>entry.authorization===`Bearer ${TOKEN}`));
});

test('unknown cost entries make total internal cost unknown without erasing known spend',async()=>{
  const {value}=executor({
    projects:[{id:PROJECT,name:'Demo',repository:'org/demo'}],
    costs:[
      {id:'44444444-4444-4444-8444-444444444444',project_id:PROJECT,cost_category:'model',estimated_cost_micros:100,billed_cost_micros:0,charged_cost_micros:0,credit_micros:0,currency:'USD'},
      {id:'55555555-5555-4555-8555-555555555555',project_id:PROJECT,cost_category:'runtime',estimated_cost_micros:0,billed_cost_micros:0,charged_cost_micros:0,credit_micros:0,currency:'USD'},
    ],
  });
  const result=await value({actor:{identity:{accessToken:TOKEN}}});
  const economics=result.projects[0].economics[0];
  assert.equal(economics.knownInternalCostMicros,100);
  assert.equal(economics.totalInternalCostMicros,null);
  assert.equal(economics.unknownCostCount,1);
  assert.equal(economics.confidence,'unknown');
});

test('micros aggregation fails closed instead of rounding beyond safe integer range',async()=>{
  const max=Number.MAX_SAFE_INTEGER;
  const {value}=executor({
    projects:[{id:PROJECT,name:'Demo',repository:'org/demo'}],
    costs:[
      {id:'44444444-4444-4444-8444-444444444444',project_id:PROJECT,cost_category:'model',estimated_cost_micros:0,billed_cost_micros:max,charged_cost_micros:max,credit_micros:0,currency:'USD'},
      {id:'55555555-5555-4555-8555-555555555555',project_id:PROJECT,cost_category:'model',estimated_cost_micros:0,billed_cost_micros:1,charged_cost_micros:1,credit_micros:0,currency:'USD'},
    ],
  });
  const result=await value({actor:{identity:{accessToken:TOKEN}}});
  const economics=result.projects[0].economics[0];
  assert.equal(economics.knownInternalCostMicros,null);
  assert.equal(economics.totalInternalCostMicros,null);
  assert.equal(economics.customerChargeMicros,null);
  assert.equal(economics.netCustomerChargeMicros,null);
});

test('Business response excludes raw provenance, metadata and mutation lineage',async()=>{
  const {value}=executor({
    projects:[{id:PROJECT,name:'Demo',repository:'org/demo'}],
    objectives:[{id:OBJECTIVE,project_id:PROJECT,ordinal:1,objective:'Objective',desired_outcome:'Outcome',success_metric:null,baseline:null,target:null,provenance:{secret:'nope'},created_at:'2026-09-08T00:00:00Z'}],
  });
  const serialized=JSON.stringify(await value({actor:{identity:{accessToken:TOKEN}}}));
  for(const forbidden of ['provenance','metadata_redacted','idempotency_key','build_job_id','tool_call_id','provider_deployment_id']){
    assert.equal(serialized.includes(forbidden),false,forbidden);
  }
});
