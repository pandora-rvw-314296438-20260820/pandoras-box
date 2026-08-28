'use strict';
const { objectOrEmpty, optionalFiniteNumber, optionalString, requireEnum, requireString } = require('./contracts.js');
const CONFIDENCE = Object.freeze(['low','medium','high']);
const RISK = Object.freeze(['low','medium','high']);
const STATUS = Object.freeze(['proposed','accepted','rejected','queued','implemented','measuring','validated','dismissed']);

function createRecommendation(input) {
  const value = objectOrEmpty(input,'recommendation');
  if (!Array.isArray(value.evidence) || value.evidence.length === 0) throw new TypeError('recommendation evidence is required');
  return Object.freeze({
    recommendationId: requireString(value.recommendationId,'recommendationId',160),
    organizationId: requireString(value.organizationId,'organizationId',160),
    projectId: requireString(value.projectId,'projectId',160),
    objectiveId: requireString(value.objectiveId,'objectiveId',160),
    observedFact: requireString(value.observedFact,'observedFact',2000),
    evidence: Object.freeze(value.evidence.map((item,i)=>requireString(item,`evidence[${i}]`,2000))),
    affectedMetric: requireString(value.affectedMetric,'affectedMetric',160),
    suggestedChange: requireString(value.suggestedChange,'suggestedChange',2000),
    expectedImpactHypothesis: requireString(value.expectedImpactHypothesis,'expectedImpactHypothesis',2000),
    confidence: requireEnum(value.confidence ?? 'low',CONFIDENCE,'confidence'),
    estimatedCost: optionalFiniteNumber(value.estimatedCost,'estimatedCost'),
    risk: requireEnum(value.risk ?? 'medium',RISK,'risk'),
    customerPriority: optionalFiniteNumber(value.customerPriority,'customerPriority'),
    strategicFit: optionalFiniteNumber(value.strategicFit,'strategicFit'),
    expectedValue: optionalFiniteNumber(value.expectedValue,'expectedValue'),
    status: requireEnum(value.status ?? 'proposed',STATUS,'status'),
    acceptedChangeIntentId: optionalString(value.acceptedChangeIntentId,'acceptedChangeIntentId',160),
  });
}
function prioritizeRecommendation(recommendation) {
  const confidenceWeight = {low:0.35,medium:0.65,high:0.9}[recommendation.confidence];
  const riskPenalty = {low:1,medium:0.75,high:0.4}[recommendation.risk];
  const value = recommendation.expectedValue ?? 1;
  const cost = recommendation.estimatedCost == null ? null : Math.max(recommendation.estimatedCost,0.01);
  const priorityInputs = Object.freeze({value,confidenceWeight,riskPenalty,costKnown:cost!=null,customerPriority:recommendation.customerPriority,strategicFit:recommendation.strategicFit});
  if (cost == null) return { score:null, band:'needs_estimate', inputs:priorityInputs };
  const modifiers = (recommendation.customerPriority ?? 1) * (recommendation.strategicFit ?? 1);
  const score = (value * confidenceWeight * riskPenalty * modifiers) / cost;
  return { score, band:score >= 5 ? 'high' : score >= 1 ? 'medium' : 'low', inputs:priorityInputs };
}
function optimizationChangeIntent(recommendation) {
  if (recommendation.status !== 'accepted') throw new Error('recommendation must be accepted before generating a governed change intent');
  return Object.freeze({ intentKind:'change', source:'pandora', projectId:recommendation.projectId, summary:recommendation.suggestedChange, provenance:{recommendationId:recommendation.recommendationId,objectiveId:recommendation.objectiveId,affectedMetric:recommendation.affectedMetric} });
}
module.exports = { CONFIDENCE, RISK, STATUS, createRecommendation, optimizationChangeIntent, prioritizeRecommendation };
