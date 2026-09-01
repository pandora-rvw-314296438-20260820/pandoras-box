'use strict';
const { CORPUS_VERSION } = require('./kimi-program.js');

const V = Object.freeze([
  'unit_tests','forbidden_change_scan','typecheck','api_surface_check','contract_tests',
  'citation_reference_check','constraint_coverage_check','hallucinated_path_check','decision_continuity_check',
  'json_parse','json_schema','tool_allowlist','no_invented_fields','visual_fixture_claim_check',
  'security_fixture_check','migration_preflight',
]);

function c(caseId, taskClass, validators, capabilities, options = {}) {
  return Object.freeze({
    caseId, version: CORPUS_VERSION, taskClass,
    input: Object.freeze({ instruction: options.instruction ?? `Synthetic ${taskClass} fixture ${caseId}` }),
    context: Object.freeze({ fixtureRef: `fixtures/${taskClass}/${caseId}`, targetTokens: options.targetTokens ?? null, capabilityGated: options.capabilityGated === true }),
    expectedContract: Object.freeze({ kind: options.kind ?? 'bounded_result', testsMustPass: options.testsMustPass === true }),
    allowedTools: Object.freeze(options.allowedTools ?? []),
    structuredOutputSchema: options.schema ?? null,
    latencyBudgetMs: options.latencyBudgetMs ?? 30000,
    costBudgetUsd: options.costBudgetUsd ?? 0.15,
    riskClass: options.riskClass ?? 'low',
    deterministicValidators: Object.freeze(validators),
    expectedInvariants: Object.freeze(options.invariants ?? ['no production mutation', 'no invented evidence']),
    reviewerRubric: Object.freeze(options.reviewerRubric ?? {}),
    provenance: 'synthetic-sanitized', capabilityRequirements: Object.freeze(capabilities), providerSpecific: false,
  });
}

const CASES = Object.freeze([
  c('coding-function-001','coding',['unit_tests','forbidden_change_scan'],['coding'],{testsMustPass:true}),
  c('coding-repair-002','coding',['unit_tests','typecheck','forbidden_change_scan'],['coding','reasoning'],{testsMustPass:true,riskClass:'medium'}),
  c('coding-refactor-003','coding',['unit_tests','api_surface_check'],['coding'],{testsMustPass:true}),
  c('coding-contract-004','coding',['contract_tests','typecheck'],['coding','structuredOutput'],{riskClass:'medium'}),
  c('long-context-architecture-001','long_context',['citation_reference_check','constraint_coverage_check'],['longContext','reasoning'],{targetTokens:32000,reviewerRubric:{correctness:true,grounding:true}}),
  c('long-context-impact-002','long_context',['constraint_coverage_check','hallucinated_path_check'],['longContext','reasoning'],{targetTokens:48000}),
  c('long-context-continuity-003','long_context',['decision_continuity_check'],['longContext'],{targetTokens:24000}),
  c('structured-json-001','structured_output',['json_parse','json_schema'],['structuredOutput','classification'],{kind:'json_schema',schema:{type:'object',required:['taskClass','confidence'],additionalProperties:false}}),
  c('structured-tool-002','structured_output',['json_parse','json_schema','tool_allowlist'],['structuredOutput','toolCalling'],{kind:'tool_proposal',allowedTools:['repository_read'],schema:{type:'object',required:['tool','arguments'],additionalProperties:false}}),
  c('structured-plan-003','structured_output',['json_parse','json_schema','constraint_coverage_check'],['structuredOutput','reasoning'],{kind:'build_plan',schema:{type:'object',required:['steps']}}),
  c('structured-recovery-004','failure_recovery',['json_parse','json_schema','no_invented_fields'],['structuredOutput','reasoning'],{riskClass:'medium'}),
  c('multimodal-ui-001','multimodal',['visual_fixture_claim_check'],['multimodal','imageUnderstanding'],{capabilityGated:true}),
  c('multimodal-chart-002','multimodal',['json_parse','json_schema','visual_fixture_claim_check'],['multimodal','imageUnderstanding','structuredOutput'],{capabilityGated:true,kind:'structured_visual_result'}),
  c('verification-security-001','verification',['security_fixture_check','constraint_coverage_check'],['reasoning'],{riskClass:'high'}),
  c('verification-migration-002','verification',['migration_preflight','constraint_coverage_check'],['reasoning','longContext'],{riskClass:'high'}),
]);

module.exports = Object.freeze({ CORPUS_VERSION, SANITIZATION: 'synthetic-sanitized-no-production-secrets-or-customer-data', KNOWN_VALIDATORS: V, CASES });
