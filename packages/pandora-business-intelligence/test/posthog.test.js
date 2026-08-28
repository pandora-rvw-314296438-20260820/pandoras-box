'use strict';
const test=require('node:test'); const assert=require('node:assert/strict'); const h=require('../src/analytics/posthog.js');
const scope={organizationId:'o1',projectId:'p1',projectVersionId:'v1',environment:'production'};
const metric={key:'completed_booking',event:'booking_completed',aggregation:'count',freshnessSeconds:3600};
const now=new Date('2026-08-29T00:00:00Z');
function provider(result){return new h.PostHogAnalyticsProvider({now:()=>now,transport:async(req)=>typeof result==='function'?result(req):result});}
test('query windows are bounded',()=>assert.throws(()=>h.boundedWindow({start:'2025-01-01',end:'2026-08-29'}),/exceeds/));
test('metric query normalizes provider response',async()=>{const p=provider({scope,value:12,sampleSize:12,lastObservedAt:'2026-08-28T23:30:00Z',complete:true});const r=await p.queryMetric({scope,metric,window:{start:'2026-08-28',end:'2026-08-29'}});assert.equal(r.value,12);assert.equal(r.stale,false);});
test('cross-project result is rejected',async()=>{const p=provider({scope:{...scope,projectId:'p2'},value:1,sampleSize:1});await assert.rejects(()=>p.queryMetric({scope,metric}),/scope mismatch/);});
test('malformed provider response is rejected',async()=>{const p=provider(null);await assert.rejects(()=>p.queryMetric({scope,metric}),/malformed/);});
test('stale measurements are explicit',async()=>{const p=provider({scope,value:1,sampleSize:1,lastObservedAt:'2026-08-27T00:00:00Z'});const r=await p.queryMetric({scope,metric});assert.equal(r.stale,true);});
test('retention can be not applicable',async()=>{const p=provider({});const r=await p.queryRetention({scope,applicability:false});assert.equal(r.notApplicable,true);});
test('cohorts reject arbitrary dimensions',()=>assert.throws(()=>h.buildQuery('cohort',{scope,dimension:'email'}),/unsupported cohort/));
test('experiment weak state becomes inconclusive',async()=>{const p=provider({scope,state:'magic',sampleSize:2});const r=await p.queryExperiment({scope,experimentId:'e1'});assert.equal(r.state,'inconclusive');});
test('data quality detects duplicates and wrong attribution',()=>{const r=h.inspectDataQuality([{eventId:'1',event:'x',occurredAt:'a',scope},{eventId:'1',event:'x',occurredAt:'a',scope:{...scope,projectId:'p2'}}],{expectedScope:scope});assert.equal(r.valid,false);assert.ok(r.issues.some(x=>x.type==='duplicate_event'));assert.ok(r.issues.some(x=>x.type==='wrong_attribution'));});
test('material change requires sample size',()=>{assert.equal(h.materialChangeSignal({metricKey:'m',current:80,baseline:100,sampleSize:5}).signal,false);assert.equal(h.materialChangeSignal({metricKey:'m',current:70,baseline:100,sampleSize:50}).signal,true);});
test('customer capture cannot forge Pandora internal authority',async()=>{const p=provider({accepted:true,scope});await assert.rejects(()=>p.captureEvent({kind:'customer_app_business_event',event:'build_completed',scope}),/not allowed/);});
test('capture scope is revalidated',async()=>{const p=provider({accepted:true,scope:{...scope,projectId:'p2'}});await assert.rejects(()=>p.captureEvent({kind:'customer_app_business_event',event:'booking_completed',scope}),/scope mismatch/);});
