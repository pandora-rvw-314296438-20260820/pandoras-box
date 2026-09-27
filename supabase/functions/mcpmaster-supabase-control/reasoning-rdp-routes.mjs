const BRIDGE = Object.freeze({
  workerKey: "pandora-reasoning-rdp-bridge-v1",
  principalKey: "vercel:mcpmaster:reasoning-rdp-bridge-v1",
  lanes: ["backend", "reliability", "web", "mobile"],
  capabilities: [
    "inference.route",
    "rdp.execute",
    "rdp.delegate",
    "rdp.toolchain.verify",
    "rdp.github_runner.verify",
    "rdp.android.verify",
    "rdp.flutter.verify",
    "rdp.repo.test",
    "rdp.repo.build",
    "worker.reconcile",
  ],
  capacity: 1,
});
const ARTEMIS_WORKER_KEY = ["pandora", "rdp", "artemis", "01"].join("-");
const ARTEMIS = Object.freeze({
  workerKey: ARTEMIS_WORKER_KEY,
  principalKey: "rdp:EC2AMAZ-SPAE2VG:artemis-verifier-v1",
  receiptRef: "rdp:EC2AMAZ-SPAE2VG:artemis-verifier-v1",
});
const TASK = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const text=(input,key)=>{
  const value=input?.[key];
  return typeof value==="string"&&value.length>0?value:undefined;
};
const integer=(input,key,min=0)=>{
  const value=input?.[key];
  return Number.isInteger(value)&&value>=min?value:undefined;
};

export function routeForReasoningRdpOperations(input,projectId){
  if(!input||typeof input!=="object"||Array.isArray(input))return undefined;

  if(input.action==="operations_rdp_artemis_register"){
    return {action:input.action,rpc:"pandora_ops_register_rdp_artemis_verifier_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_worker_key:ARTEMIS.workerKey,p_principal_key:ARTEMIS.principalKey,
        p_receipt_ref:ARTEMIS.receiptRef}};
  }

  if(input.action==="operations_reasoning_rdp_register"){
    return {action:input.action,rpc:"pandora_ops_register_reasoning_rdp_bridge_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey,
        p_lanes:BRIDGE.lanes,p_capabilities:BRIDGE.capabilities,p_capacity:BRIDGE.capacity,
        p_receipt_ref:"vercel-oidc:mcpmaster:production:pandora-reasoning-rdp-bridge-v1"}};
  }

  if(input.action==="operations_reasoning_rdp_heartbeat"){
    return {action:input.action,rpc:"pandora_ops_heartbeat_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey,
        p_connected:true,p_health:"ready"}};
  }

  if(input.action==="operations_reasoning_rdp_candidate"){
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_candidate_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey}};
  }

  if(input.action==="operations_reasoning_rdp_claim"){
    const taskId=text(input,"taskId"),taskRevision=integer(input,"taskRevision"),controlRevision=integer(input,"controlRevision");
    if(!taskId||!TASK.test(taskId)||taskRevision===undefined||controlRevision===undefined)return undefined;
    return {action:input.action,rpc:"pandora_ops_claim_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_task_key:taskId,p_worker_key:BRIDGE.workerKey,
        p_task_revision:taskRevision,p_control_revision:controlRevision}};
  }

  if(input.action==="operations_reasoning_rdp_dispatch_ack"){
    const leaseId=text(input,"leaseId"),dispatchId=text(input,"dispatchId"),taskId=text(input,"taskId");
    const generation=integer(input,"generation",1),receiptRef=text(input,"receiptRef");
    if(!leaseId||!UUID.test(leaseId)||!dispatchId||!UUID.test(dispatchId)||!taskId||!TASK.test(taskId)
      ||generation===undefined||!receiptRef||receiptRef.length>1000)return undefined;
    return {action:input.action,rpc:"pandora_ops_dispatch_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_lease_id:leaseId,p_generation:generation,
        p_ack:{accepted:true,dispatchId,workerId:BRIDGE.workerKey,taskId,generation,receiptRef}}};
  }

  if(input.action==="operations_reasoning_rdp_begin"){
    const taskId=text(input,"taskId"),leaseId=text(input,"leaseId"),generation=integer(input,"generation",1);
    if(!taskId||!TASK.test(taskId)||!leaseId||!UUID.test(leaseId)||generation===undefined)return undefined;
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_begin_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_task_key:taskId,p_lease_id:leaseId,p_generation:generation,
        p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey}};
  }

  if(input.action==="operations_reasoning_rdp_materialize"){
    const taskId=text(input,"taskId"),generation=integer(input,"generation",1),output=text(input,"output");
    if(!taskId||!TASK.test(taskId)||generation===undefined||!output||output.length>4096)return undefined;
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_materialize_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_task_key:taskId,p_generation:generation,
        p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey,p_output:output}};
  }

  if(input.action==="operations_reasoning_rdp_status"){
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_status_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey}};
  }

  if(input.action==="operations_reasoning_rdp_verify_child"){
    const taskId=text(input,"taskId"),generation=integer(input,"generation",1);
    if(!taskId||!TASK.test(taskId)||generation===undefined)return undefined;
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_verify_child_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_parent_task_key:taskId,p_parent_generation:generation,
        p_verifier_key:ARTEMIS.workerKey,p_verifier_principal:ARTEMIS.principalKey}};
  }

  if(input.action==="operations_reasoning_rdp_parent_handoff"){
    const taskId=text(input,"taskId"),generation=integer(input,"generation",1);
    if(!taskId||!TASK.test(taskId)||generation===undefined)return undefined;
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_parent_handoff_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_parent_task_key:taskId,p_parent_generation:generation,
        p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey}};
  }

  if(input.action==="operations_reasoning_rdp_verify_parent"){
    const taskId=text(input,"taskId"),generation=integer(input,"generation",1);
    if(!taskId||!TASK.test(taskId)||generation===undefined)return undefined;
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_verify_parent_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_parent_task_key:taskId,p_parent_generation:generation,
        p_verifier_key:ARTEMIS.workerKey,p_verifier_principal:ARTEMIS.principalKey}};
  }

  if(input.action==="operations_reasoning_rdp_queue_memory"){
    const taskId=text(input,"taskId"),generation=integer(input,"generation",1);
    if(!taskId||!TASK.test(taskId)||generation===undefined)return undefined;
    return {action:input.action,rpc:"pandora_ops_reasoning_rdp_queue_memory_v1",responseKey:"operations",
      params:{p_project_id:projectId,p_parent_task_key:taskId,p_parent_generation:generation,
        p_worker_key:BRIDGE.workerKey,p_principal_key:BRIDGE.principalKey}};
  }

  return undefined;
}
