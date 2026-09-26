import {createHash, randomUUID} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createWorkloadOperationsMemory} from '../packages/pandora-operations-memory/workload-rpc.mjs';
import {OPERATIONS_MEMORY_MAPPING} from '../packages/pandora-operations-memory/owner-read.mjs';
import {OUTCOME_CONTRACT} from '../packages/pandora-operations-memory/contracts.mjs';

const require=createRequire(import.meta.url);
const {getVercelOidcToken}=require('@vercel/oidc');
const proofPath=new URL('../public/operations-memory-canary.json',import.meta.url);

if(process.env.VERCEL_ENV!=='production'){
  console.log('OPERATIONS_MEMORY_CANARY skipped outside production');
  process.exit(0);
}

const sourceCommit=String(process.env.VERCEL_GIT_COMMIT_SHA||'');
if(!/^[0-9a-f]{40}$/.test(sourceCommit)) throw new Error('OPS_MEMORY_CANARY_SOURCE_REQUIRED');

const token=String(await getVercelOidcToken()).trim();
if(!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) throw new Error('OPS_MEMORY_CANARY_IDENTITY_REQUIRED');

const memory=createWorkloadOperationsMemory({
  mapping:OPERATIONS_MEMORY_MAPPING,
  resolveWorkloadToken:async()=>token,
  timeoutMs:20000,
});
const scope={organizationId:OPERATIONS_MEMORY_MAPPING.organizationId,projectId:OPERATIONS_MEMORY_MAPPING.projectId};
const started=Date.now();
const context=await memory.getTaskContext(scope,{
  intent:'coding_building',
  actionMode:'read_only',
  consequential:false,
  terms:['memory','operations','verification'],
  requiredCapabilities:['identity.verify','memory.integrate'],
  maxBytes:12288,
});
const performance=await memory.getPerformance(scope,{taskClass:'independent_verification',maxRecords:4});

const occurredAt=new Date().toISOString();
const reviewDueAt=new Date(Date.now()+7*86400000).toISOString();
const sourceRunId=randomUUID();
const outcome={
  contractVersion:OUTCOME_CONTRACT,
  sourceRunId,
  provider:'vercel',
  model:'pandora-memory-bridge',
  modelRevision:null,
  taskClass:'independent_verification',
  routingPolicyVersion:'operations-memory-build-canary-v1',
  executionStatus:'succeeded',
  verificationStatus:'pass',
  downstreamOutcomeStatus:'accepted',
  qualitySignal:1,
  latencyMs:Date.now()-started,
  estimatedCostMicros:null,
  billedCostMicros:null,
  occurredAt,
  evidenceRefs:[
    'github:commit:'+sourceCommit,
    'vercel:memory-canary:'+sourceRunId,
  ],
  sourceCommit,
  sourceDeploymentRef:process.env.VERCEL_URL?'vercel:'+process.env.VERCEL_URL:null,
  reviewDueAt,
  usage:{inputTokens:null,outputTokens:null,totalTokens:null},
  retryCount:0,
  configurationDigest:null,
};

const delivered=await memory.proposeOutcome(scope,outcome);
if(delivered.state!=='pending_review'||delivered.deliveryVerified!==true||delivered.canonicalMemoryWritten!==false){
  throw new Error('OPS_MEMORY_CANARY_DELIVERY_INVALID');
}
const readback=await memory.reconcileOutcome(scope,outcome);
if(readback.state!=='pending_review'||readback.deliveryVerified!==true||readback.canonicalMemoryWritten!==false
   ||readback.receiptId!==delivered.receiptId||readback.candidateId!==delivered.candidateId
   ||readback.reviewItemId!==delivered.reviewItemId){
  throw new Error('OPS_MEMORY_CANARY_READBACK_INVALID');
}

const proof={
  schemaVersion:'pandora-operations-memory-production-canary-v1',
  sourceCommit,
  observedAt:new Date().toISOString(),
  identity:'vercel-workload-oidc',
  context:{
    state:context.state,
    authorizationGranted:false,
    receiptRef:context.receiptRef,
  },
  performance:{
    state:performance.state,
    recordCount:Array.isArray(performance.records)?performance.records.length:0,
    authorizationGranted:false,
    providerApprovalGranted:false,
    receiptRef:performance.receiptRef,
  },
  outcome:{
    sourceRunId,
    state:readback.state,
    deliveryVerified:readback.deliveryVerified,
    canonicalMemoryWritten:readback.canonicalMemoryWritten,
    currentReviewStatus:readback.currentReviewStatus,
    receiptRef:readback.receiptRef,
    readbackMatchesSubmission:true,
    modelRevisionKnown:readback.modelRevisionKnown,
    usageKnown:false,
    estimatedCostKnown:false,
    billedCostKnown:false,
  },
};
await mkdir(new URL('../public/',import.meta.url),{recursive:true});
await writeFile(proofPath,JSON.stringify(proof,null,2)+'\n',{encoding:'utf8',mode:0o644});
console.log('OPERATIONS_MEMORY_CANARY PASS source='+sourceCommit+' proofSha256='+createHash('sha256').update(JSON.stringify(proof)).digest('hex'));
