"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createBusinessTruthExecutor = createBusinessTruthExecutor;
const rest_client_1 = require("../supabase/rest-client.js");

const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function text(value,max=1000){ return typeof value==="string" ? value.trim().slice(0,max) : ""; }
function rows(value){ return Array.isArray(value) ? value.filter((x)=>x&&typeof x==="object"&&!Array.isArray(x)) : []; }
function uuid(value){ const v=text(value,64).toLowerCase(); return UUID_RE.test(v)?v:""; }
function micros(value){
  const n=Number(value);
  return Number.isSafeInteger(n)&&n>=0 ? n : null;
}
function currency(value){
  const v=text(value,3).toUpperCase();
  return /^[A-Z]{3}$/.test(v)?v:"USD";
}
function projectBucket(map,projectId,project){
  if(!map.has(projectId)){
    map.set(projectId,{
      projectId,
      projectName:project?.name||"Project",
      repository:project?.repository||"",
      objectives:[],
      economicsByCurrency:new Map(),
      budgetsByCurrency:new Map(),
    });
  }
  return map.get(projectId);
}
function economicsBucket(project,curr){
  if(!project.economicsByCurrency.has(curr)){
    project.economicsByCurrency.set(curr,{
      currency:curr,entryCount:0,knownInternalCostMicros:0,unknownCostCount:0,
      actualCount:0,estimatedCount:0,customerChargeMicros:0,creditMicros:0,
      byCategory:{},
    });
  }
  return project.economicsByCurrency.get(curr);
}
function budgetBucket(project,curr){
  if(!project.budgetsByCurrency.has(curr)){
    project.budgetsByCurrency.set(curr,{
      currency:curr,limitCount:0,hardLimitMicros:0,spentMicros:0,reservedMicros:0,
      exhaustedCount:0,nearLimitCount:0,
    });
  }
  return project.budgetsByCurrency.get(curr);
}

function createBusinessTruthExecutor(options){
  const organizationId=uuid(options.organizationId);
  const supabaseUrl=new URL(options.supabaseUrl);
  const publishableKey=text(options.publishableKey,512);
  const fetchFn=options.fetchFn ?? fetch;
  if(!organizationId || (supabaseUrl.protocol!=="https:"&&supabaseUrl.hostname!=="localhost") || !publishableKey){
    throw new Error("Business truth executor is not configured");
  }
  return async function executeBusinessTruth(input){
    const accessToken=text(input?.actor?.identity?.accessToken,8192);
    if(!accessToken) throw Object.assign(new Error("Please sign in again."),{status:401,code:"BUSINESS_SESSION_INVALID"});
    const client=new rest_client_1.SupabaseRestClient({
      supabaseUrl:supabaseUrl.toString(),apiKey:publishableKey,accessToken,fetchFn,
      timeoutMs:10000,maxResponseBytes:2*1024*1024,
    });
    const org=encodeURIComponent(organizationId);
    let projects,objectives,budgets,costs;
    try{
      [projects,objectives,budgets,costs]=await Promise.all([
        client.requestJson(`/rest/v1/projectos_projects?select=id,name,repository&organization_id=eq.${org}&order=updated_at.desc&limit=200`),
        client.requestJson(`/rest/v1/pandora_project_business_objectives?select=id,project_id,ordinal,objective,desired_outcome,success_metric,baseline,target,created_at&organization_id=eq.${org}&order=created_at.desc&limit=300`),
        client.requestJson(`/rest/v1/pandora_budget_limits?select=id,project_id,budget_kind,currency,warning_limit_micros,hard_limit_micros,reserved_micros,spent_micros,status,updated_at&organization_id=eq.${org}&order=updated_at.desc&limit=300`),
        client.requestJson(`/rest/v1/pandora_cost_entries?select=id,project_id,cost_category,estimated_cost_micros,billed_cost_micros,charged_cost_micros,credit_micros,currency,occurred_at&organization_id=eq.${org}&order=occurred_at.desc&limit=500`),
      ]);
    }catch{
      throw Object.assign(new Error("Pandora could not load bounded Business truth."),{status:503,code:"BUSINESS_UNAVAILABLE"});
    }

    const projectMap=new Map(rows(projects).map((p)=>[uuid(p.id),{name:text(p.name,200)||"Project",repository:text(p.repository,300)}]));
    const resultMap=new Map();

    for(const row of rows(objectives)){
      const pid=uuid(row.project_id); if(!pid) continue;
      const project=projectBucket(resultMap,pid,projectMap.get(pid));
      const objective=text(row.objective,1000); if(!objective) continue;
      const successMetric=text(row.success_metric,300);
      project.objectives.push({
        id:uuid(row.id),ordinal:Number.isInteger(Number(row.ordinal))?Number(row.ordinal):null,
        objective,desiredOutcome:text(row.desired_outcome,1000)||null,
        successMetric:successMetric||null,baseline:text(row.baseline,300)||null,target:text(row.target,300)||null,
        measurementState:successMetric?"configured_not_measured":"not_configured",
        createdAt:text(row.created_at,64)||null,
      });
    }

    for(const row of rows(costs)){
      const pid=uuid(row.project_id); if(!pid) continue;
      const project=projectBucket(resultMap,pid,projectMap.get(pid));
      const curr=currency(row.currency); const bucket=economicsBucket(project,curr);
      const estimated=micros(row.estimated_cost_micros), billed=micros(row.billed_cost_micros);
      const charged=micros(row.charged_cost_micros), credits=micros(row.credit_micros);
      const internal=billed!=null&&billed>0?billed:estimated!=null&&estimated>0?estimated:null;
      const confidence=billed!=null&&billed>0?"actual":estimated!=null&&estimated>0?"estimated":"unknown";
      bucket.entryCount+=1;
      if(internal==null) bucket.unknownCostCount+=1; else bucket.knownInternalCostMicros+=internal;
      if(confidence==="actual") bucket.actualCount+=1;
      if(confidence==="estimated") bucket.estimatedCount+=1;
      bucket.customerChargeMicros+=charged??0; bucket.creditMicros+=credits??0;
      const category=text(row.cost_category,80)||"other";
      const existing=bucket.byCategory[category]||{entryCount:0,knownInternalCostMicros:0,unknownCostCount:0};
      existing.entryCount+=1;
      if(internal==null) existing.unknownCostCount+=1; else existing.knownInternalCostMicros+=internal;
      bucket.byCategory[category]=existing;
    }

    for(const row of rows(budgets)){
      const pid=uuid(row.project_id); if(!pid) continue;
      const project=projectBucket(resultMap,pid,projectMap.get(pid));
      const curr=currency(row.currency); const bucket=budgetBucket(project,curr);
      const hard=micros(row.hard_limit_micros),warning=micros(row.warning_limit_micros);
      const spent=micros(row.spent_micros),reserved=micros(row.reserved_micros);
      if(hard==null||spent==null||reserved==null) continue;
      const committed=spent+reserved;
      bucket.limitCount+=1; bucket.hardLimitMicros+=hard; bucket.spentMicros+=spent; bucket.reservedMicros+=reserved;
      if(text(row.status,40)==="exhausted"||committed>=hard) bucket.exhaustedCount+=1;
      if(warning!=null&&warning>0&&committed>=warning) bucket.nearLimitCount+=1;
    }

    const safeProjects=[...resultMap.values()].map((project)=>({
      projectId:project.projectId,projectName:project.projectName,repository:project.repository,
      objectives:project.objectives.slice(0,20),
      measurementState:project.objectives.some((o)=>o.successMetric)?"configured_not_measured":"not_configured",
      outcomeState:"not_measured",
      economics:[...project.economicsByCurrency.values()].map((e)=>({
        ...e,
        totalInternalCostMicros:e.unknownCostCount===0?e.knownInternalCostMicros:null,
        netCustomerChargeMicros:Math.max(0,e.customerChargeMicros-e.creditMicros),
        confidence:e.unknownCostCount>0?"unknown":e.estimatedCount>0?"estimated":e.actualCount>0?"actual":"unknown",
      })),
      budgets:[...project.budgetsByCurrency.values()].map((b)=>({
        ...b,remainingMicros:Math.max(0,b.hardLimitMicros-b.spentMicros-b.reservedMicros),
      })),
    })).sort((a,b)=>a.projectName.localeCompare(b.projectName)).slice(0,100);

    return {
      ok:true,kind:"pandora.business-truth.v1",generatedAt:new Date().toISOString(),
      projects:safeProjects,
      boundaries:{
        providerMeasurementConnected:false,
        revenueMeasured:false,
        retentionMeasured:false,
        pilotMeasured:false,
        roiMeasured:false,
      },
    };
  };
}
