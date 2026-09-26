import {OUTCOME_CONTRACT,normalizeOutcome} from '../pandora-operations-memory/contracts.mjs';
import {demand,record} from './policy.mjs';
/** Only a native independently verified request can produce this metadata-only review candidate. */
export function modelOutcome(native,{now=Date.now(),deploymentRef=null}={}){
 const r=native?.request,a=native?.attempts?.find(x=>x.id===r?.selected_attempt);
 demand(record(r)&&r.state==='verified'&&r.verification_run_id&&record(a)&&a.state==='received'&&a.receipt?.outputDigest,'INFERENCE_VERIFIED_NATIVE_RECEIPT_REQUIRED');
 const occurredAt=r.completed_at;demand(typeof occurredAt==='string'&&Number.isFinite(Date.parse(occurredAt)),'INFERENCE_VERIFIED_TIME_REQUIRED');
 const usage=a.receipt.usage??{};
 return normalizeOutcome({contractVersion:OUTCOME_CONTRACT,sourceRunId:r.id,provider:a.model_snapshot.provider,model:a.model_snapshot.model,
  modelRevision:a.receipt.modelRevision??null,taskClass:r.task_class,routingPolicyVersion:`native-policy:${a.policy_digest}`,
  executionStatus:'succeeded',verificationStatus:'pass',downstreamOutcomeStatus:'unknown',qualitySignal:null,latencyMs:a.receipt.latencyMs??null,
  // A reservation ceiling is not a measured estimate or a bill.
  estimatedCostMicros:null,billedCostMicros:a.billed_micros??null,occurredAt,
  evidenceRefs:[`inference-request:${r.id}`,`inference-attempt:${a.id}`,`verification-run:${r.verification_run_id}`,a.receipt.providerReceipt],
  sourceCommit:r.source_sha,sourceDeploymentRef:deploymentRef,reviewDueAt:new Date(Date.parse(occurredAt)+7*86400000).toISOString(),
  usage:{inputTokens:usage.inputTokens??null,outputTokens:usage.outputTokens??null,totalTokens:usage.totalTokens??null},retryCount:a.ordinal-1,
  configurationDigest:a.model_snapshot.configurationDigest},now);
}
export async function deliverVerifiedOutcome(client,actor,native,options={}){
 if(!client)return{state:'not_configured',deliveryVerified:false,canonicalMemoryWritten:false};
 const outcome=modelOutcome(native,options);
 return client.proposeOutcome({organizationId:actor.organizationId,projectId:actor.projectId},outcome,{signal:options.signal});
}
