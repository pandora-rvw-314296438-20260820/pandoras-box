import { type TurnRequest, classifyTurnFailure, terminalTurnStates } from "./turn-contract.ts";
import { type ChatEventSink, ReplyDeltaDecoder } from "./chat-stream.ts";
import { ReplyVisibilityGuard, containsCredentialMaterial } from "./reply-safety.ts";
type Row=Record<string,any>;
async function rpc(client:any,name:string,args:Row) {
  const r=await client.rpc(name,args);
  if(r.error){const raw=String(r.error.message??"");const code=raw.match(/(?:CHAT|SERVICE_ROLE)[A-Z0-9_]+/)?.[0]??"BACKEND_WRITE_FAILED";throw Error(code);}
  if(!r.data||typeof r.data!=="object")throw Error("CHAT_RECEIPT_INVALID");return r.data as Row;
}

export class ChatTurnLifecycle {
  receipt:Row;claimId:string|null=null;sequence:number;modelRunId:string|null=null;
  readonly abort=new AbortController();readonly startedAt=Date.now();
  readonly timings:Row={};streamingModels=new Set<string>();private decoder=new ReplyDeltaDecoder(true);private lastRead=0;
  private pollTimer:ReturnType<typeof setInterval>|null=null;private polling=false;
  private streaming=false;private observedDelta=false;private streamSequence=0;
  private visible=new ReplyVisibilityGuard();
  private verifiedEffect=false;
  constructor(readonly clients:any,receipt:Row,readonly sink?:ChatEventSink){this.receipt=receipt;this.sequence=Number(receipt.sequence??1);}
  get turnId(){return this.receipt.turnId;}get attemptId(){return this.receipt.attemptId;}
  get generation(){return Number(this.receipt.generation);}get userMessageId(){return this.receipt.userMessageId;}
  get hasVisibleDelta(){return this.observedDelta;}
  get signal(){return this.abort.signal;}
  get finished(){return terminalTurnStates.has(this.receipt.status);}
  get wantsStream(){return !!this.sink;}
  identity(){return{protocolVersion:2,organizationId:this.receipt.organizationId,threadId:this.receipt.threadId,
    turnId:this.turnId,attemptId:this.attemptId,activityJobId:this.receipt.activityJobId,userMessageId:this.userMessageId,generation:this.generation};}
  emit(type:string,extra:Row={}){this.sink?.({...this.receipt,...this.identity(),...extra,type,sequence:this.sequence});}
  accepted(){this.emit("accepted",{status:this.receipt.status,replayed:this.receipt.replayed===true});}
  async claim(claimId:string){
    this.claimId=claimId;await this.transition("processing");
    this.pollTimer=setInterval(()=>{
      if(this.polling||this.finished)return;
      this.polling=true;
      this.assertActive(true).catch(error=>{if(this.signal.aborted)this.stopPolling();else if(error?.message!=="BACKEND_WRITE_FAILED")this.abort.abort();}).finally(()=>{this.polling=false;});
    },1000);
  }
  private stopPolling(){if(this.pollTimer!==null){clearInterval(this.pollTimer);this.pollTimer=null;}}
  args(){return{p_turn_id:this.turnId,p_attempt_id:this.attemptId,p_generation:this.generation,p_claim_id:this.claimId};}
  async beginEffect(){await rpc(this.clients.admin,"pandora_chat_turn_effect_v2",{...this.args(),p_phase:"begin",p_result:null});}
  async recordEffect(result:Row){
    if(containsCredentialMaterial(result))throw Error("CREDENTIAL_MATERIAL_REJECTED");
    await rpc(this.clients.admin,"pandora_chat_turn_effect_v2",{...this.args(),p_phase:"verified",p_result:result});this.verifiedEffect=true;
  }
  async transition(status:string,extra:Row={}){
    this.receipt=await rpc(this.clients.admin,"pandora_chat_turn_transition_v2",{...this.args(),p_status:status,p_sequence:null,
      p_timings:this.timings,p_model_run_id:this.modelRunId,...extra});
    this.sequence=Math.max(this.sequence,Number(this.receipt.sequence??0));
    if(this.receipt.applied===false&&this.receipt.status!==status){this.abort.abort();throw Error("CHAT_GENERATION_STALE");}
    this.emit(status);
  }
  async assertActive(force=false){
    if(this.abort.signal.aborted)throw Error("REQUEST_CANCELLED");
    if(!force&&Date.now()-this.lastRead<1000)return;
    this.lastRead=Date.now();
    const r=await rpc(this.clients.user,"pandora_chat_turn_read_v2",{p_organization_id:this.receipt.organizationId,p_turn_id:this.turnId,p_generation:this.generation});
    if(Number(r.currentGeneration)!==this.generation||r.cancellationRequested||terminalTurnStates.has(r.status)){
      this.receipt=r;this.abort.abort();throw Error("REQUEST_CANCELLED");
    }
  }
  async providerDelta(raw:string){
    await this.assertActive();
    const decoded=this.decoder.push(raw);if(!decoded)return;
    const delta=this.visible.push(decoded);if(!delta)return;
    if(!this.streaming){this.timings.firstVisibleDeltaMs=Date.now()-this.startedAt;await this.transition("streaming");this.streaming=true;}
    this.observedDelta=true;this.emit("delta",{status:"streaming",textDelta:delta,streamSequence:++this.streamSequence});
  }
  resetProvider(){if(this.observedDelta)throw Error("CHAT_STREAM_RETRY_REQUIRED");this.decoder=new ReplyDeltaDecoder(true);this.visible=new ReplyVisibilityGuard();}
  async complete(result:Row,message:Row={}){
    if(this.finished&&this.receipt.status==="completed"){this.stopPolling();return this.receipt;}
    if(!this.verifiedEffect)await this.assertActive(true);
    if(containsCredentialMaterial(result))throw Error("CREDENTIAL_MATERIAL_REJECTED");
    if(this.observedDelta){const tail=this.visible.finish(String(result.reply??""));if(tail)this.emit("delta",{status:"streaming",textDelta:tail,streamSequence:++this.streamSequence});}
    this.timings.generationTotalMs=Date.now()-this.startedAt;
    this.receipt=await rpc(this.clients.admin,"pandora_chat_turn_complete_v2",{...this.args(),p_result:result,p_message:message,p_sequence:null,p_timings:this.timings});
    this.sequence=Math.max(this.sequence,Number(this.receipt.sequence??0));this.stopPolling();return this.receipt;
  }
  async fail(error:unknown){
    this.stopPolling();if(!this.claimId)return this.receipt;
    const failure=classifyTurnFailure(error);
    this.timings.generationTotalMs=Date.now()-this.startedAt;
    this.receipt=await rpc(this.clients.admin,"pandora_chat_turn_transition_v2",{...this.args(),p_status:failure.status,p_error_code:failure.code,
      p_retryable:failure.retryable,p_sequence:null,p_timings:this.timings,p_model_run_id:this.modelRunId});
    return this.receipt;
  }
}

export async function readChatTurnReceipt(clients:any,turnId:string){
  let receipt=await rpc(clients.user,"pandora_chat_turn_read_v2",{p_organization_id:clients.organizationId,p_turn_id:turnId,p_generation:null});
  if(receipt.found!==false&&!terminalTurnStates.has(receipt.status)){
    receipt=await rpc(clients.admin,"pandora_chat_turn_reconcile_v2",{p_turn_id:turnId});
  }
  return receipt;
}

export async function openChatTurn(clients:any,input:any,fingerprint:string,sink?:ChatEventSink){
  const v:TurnRequest=input.turn,entryId=input.enterpriseContext?.selectedObject?.entryId??null;
  const common={p_organization_id:clients.organizationId,p_turn_id:v.clientTurnId};
  if(v.operation==="readback"||v.operation==="cancel"){
    const readback=v.operation==="readback"?await readChatTurnReceipt(clients,v.clientTurnId):
      await rpc(clients.user,"pandora_chat_turn_cancel_v2",{...common,p_expected_generation:v.expectedGeneration,p_attempt_id:v.clientAttemptId,p_acknowledge_unknown:v.acknowledgeUnknown===true});
    return{readback};
  }
  const args=v.operation==="retry"?{...common,p_attempt_id:v.clientAttemptId,p_expected_generation:v.expectedGeneration,p_request_sha256:fingerprint,p_entry_id:entryId}:
    {...common,p_attempt_id:v.clientAttemptId,p_request_sha256:fingerprint,p_message:input.message,p_thread_id:input.threadId,p_project_id:input.projectId,
      p_attachment_manifest:input.attachments.map((a:any)=>({kind:a.kind,name:a.name,mimeType:a.mimeType})),p_entry_id:entryId,p_client_history:input.clientHistory??[]};
  const receipt=await rpc(clients.user,v.operation==="retry"?"pandora_chat_turn_retry_v2":"pandora_chat_turn_admit_v2",args);
  if(receipt.admissionCancelled===true)return{readback:receipt};
  const lifecycle=new ChatTurnLifecycle(clients,receipt,sink);lifecycle.accepted();
  return{lifecycle};
}
