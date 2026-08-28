'use strict';
const { AnalyticsProvider, assertProviderScope } = require('./provider.js');
const { validateEventEnvelope } = require('../events.js');

const QUERY_KINDS = Object.freeze(['metric','funnel','retention','cohort','timeseries','experiment']);
const MAX_WINDOW_DAYS = 366;
const COHORT_DIMENSIONS = Object.freeze(['customer_class','device_class','traffic_source','project_version','branch','location','pilot_cohort']);
const EXPERIMENT_STATES = Object.freeze(['winner','loser','no_significant_difference','inconclusive','stopped','guardrail_failed']);

function requireScope(scope){
  if(!scope||typeof scope!=='object') throw new TypeError('scope is required');
  for(const key of ['organizationId','projectId','environment']) if(typeof scope[key]!=='string'||!scope[key]) throw new TypeError(`${key} is required`);
  if(scope.projectVersionId!=null&&(typeof scope.projectVersionId!=='string'||!scope.projectVersionId)) throw new TypeError('projectVersionId is invalid');
  return Object.freeze({...scope});
}
function boundedWindow(window={}){
  const end = new Date(window.end ?? Date.now());
  const start = new Date(window.start ?? end.getTime()-30*86400000);
  if(Number.isNaN(start.getTime())||Number.isNaN(end.getTime())||start>=end) throw new TypeError('invalid analytics window');
  const days=(end-start)/86400000;
  if(days>MAX_WINDOW_DAYS) throw new TypeError(`analytics window exceeds ${MAX_WINDOW_DAYS} days`);
  return Object.freeze({start:start.toISOString(),end:end.toISOString(),days});
}
function scopeFilters(scope){
  const filters={organization_id:scope.organizationId,project_id:scope.projectId,environment:scope.environment};
  if(scope.projectVersionId) filters.project_version_id=scope.projectVersionId;
  return Object.freeze(filters);
}
function buildQuery(kind,input={}){
  if(!QUERY_KINDS.includes(kind)) throw new TypeError('unsupported analytics query kind');
  const scope=requireScope(input.scope); const window=boundedWindow(input.window);
  const q={kind,scope,window,filters:scopeFilters(scope)};
  if(kind==='metric'||kind==='timeseries') { if(!input.metric?.event) throw new TypeError('metric event is required'); q.metric={key:input.metric.key,event:input.metric.event,aggregation:input.metric.aggregation,property:input.metric.property??null,denominatorEvent:input.metric.denominatorEvent??null}; }
  if(kind==='funnel'){ if(!Array.isArray(input.steps)||input.steps.length<2) throw new TypeError('funnel requires at least two steps'); q.steps=[...input.steps]; }
  if(kind==='retention'){ if(input.applicability===false) return Object.freeze({...q,notApplicable:true}); if(!input.returnEvent) throw new TypeError('returnEvent is required'); q.startEvent=input.startEvent??input.returnEvent; q.returnEvent=input.returnEvent; }
  if(kind==='cohort'){ if(!COHORT_DIMENSIONS.includes(input.dimension)) throw new TypeError('unsupported cohort dimension'); q.dimension=input.dimension; q.event=input.event??null; }
  if(kind==='experiment'){ if(!input.experimentId) throw new TypeError('experimentId is required'); q.experimentId=input.experimentId; }
  return Object.freeze(q);
}
function freshness(lastObservedAt,freshnessSeconds=3600,now=new Date()){
  if(!lastObservedAt) return Object.freeze({lastObservedAt:null,stale:false,ageSeconds:null});
  const at=Date.parse(lastObservedAt); if(Number.isNaN(at)) throw new TypeError('invalid lastObservedAt');
  const ageSeconds=Math.max(0,(now.getTime()-at)/1000); return Object.freeze({lastObservedAt:new Date(at).toISOString(),stale:freshnessSeconds>0&&ageSeconds>freshnessSeconds,ageSeconds});
}
function normalizeResult(kind,request,result,options={}){
  if(!result||typeof result!=='object'||Array.isArray(result)) throw new Error('malformed analytics provider response');
  const resultScope=requireScope(result.scope); assertProviderScope(request.scope,resultScope);
  const fresh=freshness(result.lastObservedAt,options.freshnessSeconds??3600,options.now??new Date());
  const base={kind,scope:resultScope,window:request.window,lastObservedAt:fresh.lastObservedAt,stale:fresh.stale,complete:result.complete===true,source:'posthog'};
  if(kind==='metric') return Object.freeze({...base,value:finiteOrNull(result.value),sampleSize:integer(result.sampleSize??0,'sampleSize'),quality:quality(result.quality)});
  if(kind==='funnel') return Object.freeze({...base,steps:normalizeFunnelSteps(result.steps),entryCount:integer(result.entryCount??0,'entryCount'),completionCount:integer(result.completionCount??0,'completionCount'),completionRate:finiteOrNull(result.completionRate)});
  if(kind==='retention') return Object.freeze({...base,notApplicable:result.notApplicable===true,periods:Array.isArray(result.periods)?result.periods.map((p)=>({period:integer(p.period,'period'),rate:finiteOrNull(p.rate),sampleSize:integer(p.sampleSize??0,'sampleSize')})):[]});
  if(kind==='cohort') return Object.freeze({...base,dimension:request.dimension,rows:Array.isArray(result.rows)?result.rows.map((r)=>({key:String(r.key),value:finiteOrNull(r.value),sampleSize:integer(r.sampleSize??0,'sampleSize')})):[]});
  if(kind==='timeseries') return Object.freeze({...base,points:Array.isArray(result.points)?result.points.map((p)=>({at:new Date(p.at).toISOString(),value:finiteOrNull(p.value),sampleSize:integer(p.sampleSize??0,'sampleSize')})):[]});
  if(kind==='experiment'){ const state=EXPERIMENT_STATES.includes(result.state)?result.state:'inconclusive'; return Object.freeze({...base,experimentId:request.experimentId,state,primaryMetric:result.primaryMetric??null,sampleSize:integer(result.sampleSize??0,'sampleSize'),confidence:finiteOrNull(result.confidence),guardrailFailed:state==='guardrail_failed'}); }
  throw new TypeError('unsupported result kind');
}
function finiteOrNull(v){if(v==null)return null;if(typeof v!=='number'||!Number.isFinite(v))throw new TypeError('analytics value must be finite');return v;}
function integer(v,name){if(!Number.isInteger(v)||v<0)throw new TypeError(`${name} must be a non-negative integer`);return v;}
function quality(v='valid'){return ['valid','partial','duplicate_suspected','attribution_missing','schema_mismatch','invalid'].includes(v)?v:'invalid';}
function normalizeFunnelSteps(steps){if(!Array.isArray(steps))throw new Error('malformed funnel response');return steps.map((s)=>Object.freeze({event:String(s.event),count:integer(s.count??0,'count'),stepConversion:finiteOrNull(s.stepConversion),dropOff:integer(s.dropOff??0,'dropOff')}));}

function inspectDataQuality(events,{expectedScope=null,expectedSchemaVersion='1.0.0'}={}){
  if(!Array.isArray(events)) throw new TypeError('events must be an array');
  const seen=new Set(); const issues=[];
  for(const e of events){
    if(!e||typeof e!=='object'){issues.push({type:'malformed_event'});continue;}
    const identity=e.eventId??`${e.event}|${e.occurredAt}|${e.distinctId??''}|${e.scope?.projectId??''}`;
    if(seen.has(identity)) issues.push({type:'duplicate_event',eventId:e.eventId??null}); else seen.add(identity);
    if(!e.scope?.organizationId||!e.scope?.projectId||!e.scope?.environment) issues.push({type:'missing_attribution',eventId:e.eventId??null});
    if(expectedScope){try{assertProviderScope(expectedScope,e.scope??{});}catch{issues.push({type:'wrong_attribution',eventId:e.eventId??null});}}
    if(e.schemaVersion&&e.schemaVersion!==expectedSchemaVersion) issues.push({type:'schema_change',eventId:e.eventId??null,observed:e.schemaVersion,expected:expectedSchemaVersion});
    if(e.metricValue!=null&&(!Number.isFinite(e.metricValue)||Math.abs(e.metricValue)>Number.MAX_SAFE_INTEGER)) issues.push({type:'impossible_value',eventId:e.eventId??null});
  }
  return Object.freeze({valid:issues.length===0,issues:Object.freeze(issues),eventCount:events.length,uniqueEventCount:seen.size});
}
function materialChangeSignal({metricKey,current,baseline,threshold=0.2,sampleSize=0,minimumSampleSize=20,direction='both'}){
  if(current==null||baseline==null||sampleSize<minimumSampleSize||baseline===0) return Object.freeze({signal:false,reason:'insufficient_evidence'});
  const relative=(current-baseline)/Math.abs(baseline); const material=Math.abs(relative)>=threshold;
  const allowed=direction==='both'||(direction==='up'&&relative>0)||(direction==='down'&&relative<0);
  return Object.freeze({signal:material&&allowed,metricKey,relativeChange:relative,materialityThreshold:threshold});
}

class PostHogAnalyticsProvider extends AnalyticsProvider{
  constructor({transport,now=()=>new Date()}){super();if(typeof transport!=='function')throw new TypeError('transport function is required');this.transport=transport;this.now=now;}
  async _query(kind,input){const request=buildQuery(kind,input); if(request.notApplicable)return Object.freeze({kind,scope:request.scope,window:request.window,notApplicable:true,complete:true,source:'posthog'}); const raw=await this.transport({operation:'query',query:request}); return normalizeResult(kind,request,raw,{freshnessSeconds:input.metric?.freshnessSeconds??input.freshnessSeconds,now:this.now()});}
  async captureEvent(input,options={}){const event=validateEventEnvelope(input,options); const raw=await this.transport({operation:'capture',event}); if(!raw||raw.accepted!==true)throw new Error('analytics capture rejected'); if(raw.scope){assertProviderScope(event.scope,raw.scope);} return Object.freeze({accepted:true,event:event.event,scope:event.scope,provider:'posthog'});}
  async queryMetric(i){return this._query('metric',i);} async queryFunnel(i){return this._query('funnel',i);} async queryRetention(i){return this._query('retention',i);} async queryCohort(i){return this._query('cohort',i);} async queryTimeseries(i){return this._query('timeseries',i);} async queryExperiment(i){return this._query('experiment',i);}
}
module.exports={COHORT_DIMENSIONS,EXPERIMENT_STATES,MAX_WINDOW_DAYS,PostHogAnalyticsProvider,boundedWindow,buildQuery,freshness,inspectDataQuality,materialChangeSignal,normalizeResult,scopeFilters};
