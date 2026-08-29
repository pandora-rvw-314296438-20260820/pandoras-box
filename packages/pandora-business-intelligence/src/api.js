'use strict';
function ownerSafeBusinessSummary(input) {
  return Object.freeze({
    goal: input.objective?.objective ?? null,
    currentResult: input.measurement?.value ?? null,
    metric: input.metric?.key ?? null,
    baseline: input.objective?.baseline?.value ?? null,
    target: input.objective?.target?.value ?? null,
    outcome: input.outcome?.state ?? 'not_measurable',
    health: input.outcome?.health ?? 'not_measured',
    trend: input.trend ?? null,
    lastMeasured: input.measurement?.lastObservedAt ?? null,
    measurementState: input.measurementState ?? 'not_configured',
    topRecommendation: input.recommendation ? {
      recommendationId: input.recommendation.recommendationId,
      observedFact: input.recommendation.observedFact,
      suggestedChange: input.recommendation.suggestedChange,
      expectedImpact: input.recommendation.expectedImpactHypothesis,
      confidence: input.recommendation.confidence,
    } : null,
    creditsUsed: input.creditsUsed ?? null,
    budget: input.budget ?? null,
  });
}
function professionalBusinessSummary(ownerSummary, details = {}) {
  return Object.freeze({ ...ownerSummary, technical:Object.freeze({ eventName:details.eventName ?? null, funnel:details.funnel ?? null, cohort:details.cohort ?? null, versionComparison:details.versionComparison ?? null, experiment:details.experiment ?? null, freshness:details.freshness ?? null }) });
}
module.exports = { ownerSafeBusinessSummary, professionalBusinessSummary };
