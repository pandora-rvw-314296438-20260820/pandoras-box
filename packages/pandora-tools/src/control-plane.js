
"use strict";

const { createHash } = require("node:crypto");
const { PandoraToolError } = require("./errors");

function canonicalJson(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") { if (!Number.isFinite(value)) throw new TypeError("non-finite number"); return JSON.stringify(value); }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).filter(key => value[key] !== undefined).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  throw new TypeError(`unsupported canonical JSON type: ${typeof value}`);
}
function sha256(value) { return createHash("sha256").update(Buffer.isBuffer(value) ? value : Buffer.from(String(value), "utf8")).digest("hex"); }
function unwrap(result, code) {
  if (result?.error) throw new PandoraToolError("internal", code, "Durable control-plane operation failed", { provider_code: result.error.code || null });
  return result?.data ?? null;
}
function one(rows) { return Array.isArray(rows) ? rows[0] ?? null : rows ?? null; }

class SupabaseControlPlaneBackend {
  constructor(client) {
    if (!client || typeof client.from !== "function" || typeof client.rpc !== "function") throw new TypeError("Supabase service client is required");
    this.client = client;
    this.durability = "durable";
  }
  async getApproval(id) { return one(unwrap(await this.client.from("approvals").select("*").eq("id", id).limit(1), "CONTROL_PLANE_APPROVAL_READ_FAILED")); }
  async getPolicyAction(approvalId, actionHash) { return one(unwrap(await this.client.from("pandora_policy_actions").select("id,status,executed_at,approval_id,action_hash").eq("approval_id", approvalId).eq("action_hash", actionHash).limit(1), "CONTROL_PLANE_POLICY_READ_FAILED")); }
  async consumePolicyAction(approvalId, actionHash, at) {
    const rows = unwrap(await this.client.from("pandora_policy_actions").update({ status: "executed", executed_at: at.toISOString() }).eq("approval_id", approvalId).eq("action_hash", actionHash).eq("status", "authorized").select("id,status,executed_at"), "CONTROL_PLANE_APPROVAL_CONSUME_FAILED");
    return one(rows);
  }
  async createApproval(row) { return one(unwrap(await this.client.from("approvals").insert(row).select("*"), "CONTROL_PLANE_APPROVAL_CREATE_FAILED")); }
  async getToolCall(scope) {
    const call = one(unwrap(await this.client.from("pandora_tool_calls").select("*").eq("organization_id", scope.organization_id).eq("project_id", scope.project_id).eq("idempotency_key", scope.idempotency_key).limit(1), "CONTROL_PLANE_TOOL_CALL_READ_FAILED"));
    if (!call) return null;
    const result = one(unwrap(await this.client.from("pandora_tool_results").select("*").eq("tool_call_id", call.id).limit(1), "CONTROL_PLANE_TOOL_RESULT_READ_FAILED"));
    return { call, result };
  }
  async claimToolCall(scope, record) {
    const values = { ...record.metadata, idempotency_key: scope.idempotency_key, status: "executing", started_at: record.started_at, error_class: null };
    let rows = unwrap(await this.client.from("pandora_tool_calls").update(values).eq("id", record.metadata.tool_call_id).eq("organization_id", scope.organization_id).eq("project_id", scope.project_id).eq("action_hash", record.action_hash).in("status", ["proposed","authorized","failed"]).select("id"), "CONTROL_PLANE_TOOL_CALL_CLAIM_FAILED");
    if (one(rows)) return true;
    try {
      rows = unwrap(await this.client.from("pandora_tool_calls").insert({ ...values, id: record.metadata.tool_call_id, organization_id: scope.organization_id, project_id: scope.project_id, action_hash: record.action_hash }).select("id"), "CONTROL_PLANE_TOOL_CALL_CLAIM_FAILED");
      return Boolean(one(rows));
    } catch (error) {
      if (error instanceof PandoraToolError && error.details?.provider_code === "23505") return false;
      throw error;
    }
  }
  async updateToolCall(scope, patch) {
    const mapped = { status: patch.status, completed_at: patch.completed_at ?? null, error_class: patch.error_class ?? null };
    const rows = unwrap(await this.client.from("pandora_tool_calls").update(mapped).eq("organization_id", scope.organization_id).eq("project_id", scope.project_id).eq("idempotency_key", scope.idempotency_key).select("id"), "CONTROL_PLANE_TOOL_CALL_UPDATE_FAILED");
    return one(rows);
  }
  async insertToolResult(scope, { status, result, resultSha256, publicSummary = null }) {
    const existing = await this.getToolCall(scope);
    if (!existing?.call) throw new PandoraToolError("internal", "CONTROL_PLANE_TOOL_CALL_MISSING", "Durable tool call is missing");
    if (existing.result) {
      if (existing.result.result_sha256 !== resultSha256) throw new PandoraToolError("conflict", "TOOL_RESULT_ALREADY_FINALIZED", "Tool result was already finalized with different evidence");
      return existing.result;
    }
    try {
      return one(unwrap(await this.client.from("pandora_tool_results").insert({ organization_id: scope.organization_id, project_id: scope.project_id, tool_call_id: existing.call.id, status, result_sha256: resultSha256, public_summary: publicSummary, metadata_redacted: { receipt: result } }).select("*"), "CONTROL_PLANE_TOOL_RESULT_WRITE_FAILED"));
    } catch (error) {
      if (error instanceof PandoraToolError && error.details?.provider_code === "23505") {
        const reread = await this.getToolCall(scope);
        if (reread?.result?.result_sha256 === resultSha256) return reread.result;
      }
      throw error;
    }
  }
  async consumeRateLimit(organizationId, keyHash, maxCalls, windowSeconds) { return unwrap(await this.client.rpc("consume_runtime_rate_limit", { p_organization_id: organizationId, p_key_hash: keyHash, p_limit: maxCalls, p_window_seconds: windowSeconds }), "CONTROL_PLANE_RATE_LIMIT_FAILED"); }
  async recordPolicyAction(event) {
    const row = { organization_id:event.organization_id, project_id:event.project_id, project_spec_id:event.project_spec_id, build_job_id:event.build_job_id??null, tool_call_id:event.tool_call_id, project_version_id:event.project_version_id??null, tool_name:event.tool, tool_version:String(event.tool_version), action_name:event.tool, action_hash:event.action_hash, arguments_sha256:event.arguments_sha256, policy_version:event.policy_version, environment:event.environment, target_resource_ref:event.target_resource??null, risk_level:event.risk, disposition:event.disposition, side_effect:event.side_effect, approval_required:event.approval_required===true, approval_id:event.approval_id??null, status:event.disposition==="ALLOW"?"authorized":event.disposition==="DENY"?"denied":"proposed", expires_at:event.approval_expires_at??null };
    const existing = one(unwrap(await this.client.from("pandora_policy_actions").select("id,status").eq("organization_id", row.organization_id).eq("action_hash", row.action_hash).limit(1), "CONTROL_PLANE_POLICY_READ_FAILED"));
    if (existing) return one(unwrap(await this.client.from("pandora_policy_actions").update(row).eq("id", existing.id).select("*"), "CONTROL_PLANE_POLICY_WRITE_FAILED"));
    return one(unwrap(await this.client.from("pandora_policy_actions").insert(row).select("*"), "CONTROL_PLANE_POLICY_WRITE_FAILED"));
  }
  async appendAudit(event) {
    return unwrap(await this.client.rpc("append_project_audit_event", { target_organization_id:event.organization_id, target_project_id:event.project_id, target_actor_type:"system", target_actor_user_id:null, target_event_type:`pandora_tool.${event.kind}`, target_resource_type:"pandora_tool_call", target_resource_id:event.tool_call_id??null, target_request_id:event.request_id??null, target_idempotency_key:event.idempotency_key??null, target_action_hash:event.action_hash??null, target_provenance:{source:"worker_c",policy_version:event.policy_version??null}, target_payload:{status:event.status??null,decision:event.disposition??null,error_class:event.error_class??null} }), "CONTROL_PLANE_AUDIT_WRITE_FAILED");
  }
}

class ControlPlaneApprovalStore {
  constructor(backend) { this.backend=backend; this.durability="durable"; }
  async get(approvalId) {
    const row=await this.backend.getApproval(approvalId); if(!row) return null;
    const binding=row.preview_redacted?.worker_c_binding||{}; const policy=await this.backend.getPolicyAction(row.id,row.action_hash);
    return {...binding,approval_id:row.id,organization_id:row.organization_id,action_hash:row.action_hash,status:row.decision,approved_by:row.decision_by,approved_at:row.decided_at,expires_at:row.expires_at,one_time:binding.one_time!==false,revoked_at:row.decision==="revoked"?row.updated_at:null,consumed_at:policy?.status==="executed"?policy.executed_at:null};
  }
  async request(binding,{run_id,requested_by,assigned_to=null,expires_at,request_reason=null}) {
    if(!run_id||!requested_by||!expires_at) throw new PandoraToolError("invalid_request","APPROVAL_REQUEST_INCOMPLETE","Approval request identity is incomplete");
    return this.backend.createApproval({organization_id:binding.organization_id,run_id,requested_by,assigned_to,action_hash:binding.action_hash,preview_redacted:{worker_c_binding:{...binding,one_time:true}},request_reason,expires_at});
  }
  async consume(approvalId,actionHash,at=new Date()) { const consumed=await this.backend.consumePolicyAction(approvalId,actionHash,at); if(!consumed) throw new PandoraToolError("approval_required","APPROVAL_ALREADY_CONSUMED","One-time approval was already consumed or is no longer authorized"); return consumed; }
}

const STATES=Object.freeze({STARTED:"started",SUCCEEDED:"succeeded",FAILED_SAFE:"failed_safe",AMBIGUOUS:"ambiguous"});
class ControlPlaneIdempotencyStore {
  constructor(backend){this.backend=backend;this.durability="durable";}
  async get(scope){const found=await this.backend.getToolCall(scope);if(!found)return null;const{call,result}=found;let state=STATES.STARTED;if(call.status==="succeeded"||result?.status==="success")state=STATES.SUCCEEDED;else if(call.error_class==="ambiguous_mutation"||result?.status==="ambiguous")state=STATES.AMBIGUOUS;else if(call.status==="failed")state=STATES.FAILED_SAFE;return{...scope,action_hash:call.action_hash,request_id:call.idempotency_key,state,receipt:result?.metadata_redacted?.receipt??null};}
  async createStarted(scope,record){return this.backend.claimToolCall(scope,record);}
  async update(scope,patch){if(patch.state===STATES.SUCCEEDED){const resultSha256=sha256(canonicalJson(patch.receipt));await this.backend.insertToolResult(scope,{status:"success",result:patch.receipt,resultSha256});await this.backend.updateToolCall(scope,{status:"succeeded",completed_at:patch.finished_at,error_class:null});}else if(patch.state===STATES.AMBIGUOUS){const safe=patch.error?.owner||{error_class:"ambiguous_mutation"};await this.backend.insertToolResult(scope,{status:"ambiguous",result:safe,resultSha256:sha256(canonicalJson(safe))});await this.backend.updateToolCall(scope,{status:"failed",completed_at:patch.finished_at,error_class:"ambiguous_mutation"});}else if(patch.state===STATES.FAILED_SAFE){await this.backend.updateToolCall(scope,{status:"failed",completed_at:patch.finished_at,error_class:patch.error?.error_class||patch.error?.owner?.error_class||"internal"});}else if(patch.state===STATES.STARTED){await this.backend.updateToolCall(scope,{status:"executing",completed_at:null,error_class:null});}return this.get(scope);}
}

class ControlPlaneRateLimitGuard {
  constructor(backend){this.backend=backend;this.store=Object.freeze({durability:"durable"});}
  async consume(scope,{max_calls,window_ms},now=new Date()){if(!Number.isInteger(max_calls)||max_calls<1||!Number.isInteger(window_ms)||window_ms<1000||window_ms>3600000)throw new PandoraToolError("internal","RATE_POLICY_INVALID","Rate-limit policy is invalid");const bucket=[scope.organization_id,scope.project_id,scope.model_run_id||"-",scope.build_job_id||"-",scope.tool,scope.environment].join("|");const result=await this.backend.consumeRateLimit(scope.organization_id,sha256(bucket),max_calls,Math.ceil(window_ms/1000));if(result?.allowed!==true){const reset=result?.resetAt?Math.max(0,new Date(result.resetAt).getTime()-now.getTime()):window_ms;throw new PandoraToolError("rate_limit","TOOL_RATE_LIMIT_EXCEEDED","Tool-call rate limit exceeded",{retry_after_ms:reset});}return{remaining:result.remaining,reset_at:result.resetAt};}
}
class ControlPlaneLineageSink { constructor(backend){this.backend=backend;this.durability="durable";} async record(event){if(event.kind==="tool_proposal")return this.backend.recordToolProposal(event);if(event.kind==="policy_decision")return this.backend.recordPolicyAction(event);if(event.kind==="tool_execution_started"||event.kind==="tool_execution_finished")return this.backend.recordExecutionEvent(event);return null;} }
function durableExecutorConcurrency(mode,owner){if(!["claim","compare_and_set"].includes(mode)||!owner)throw new TypeError("durable executor concurrency contract is invalid");return Object.freeze({durability:"durable",mode,owner});}

module.exports={canonicalJson,sha256,SupabaseControlPlaneBackend,ControlPlaneApprovalStore,ControlPlaneIdempotencyStore,ControlPlaneRateLimitGuard,ControlPlaneLineageSink,durableExecutorConcurrency};
