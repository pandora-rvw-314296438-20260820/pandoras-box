import {InferenceError,bounded,demand,exact,record,sha256,ID} from './policy.mjs';

const count=value=>Number.isSafeInteger(value)&&value>=0?value:null;

export class BedrockNativeProvider {
  #converse;#catalog;#clock;
  constructor({converse,catalog,clock=Date.now}={}) {
    demand(typeof converse==='function'&&Array.isArray(catalog)&&catalog.length>0,'INFERENCE_PROVIDER_TARGET_DENIED');
    this.#converse=converse;
    this.#catalog=new Map(catalog.map(entry=>[String(entry.modelId),entry]));
    this.#clock=clock;
  }
  preflight(request,model){this.#compile(request,model);return {validated:true,executionStarted:false};}
  #compile(request,model){
    demand(model.provider==='bedrock'&&model.transport==='bedrock_converse'&&model.executionBoundary==='cloud'
      &&request.taskClass!=='local_private','INFERENCE_PROVIDER_SCOPE_DENIED');
    demand(ID.test(model.model)&&Array.isArray(request.parts)&&request.parts.length>=1&&request.parts.length<=16,
      'INFERENCE_PROVIDER_INPUT_INVALID');
    const catalog=this.#catalog.get(model.model);
    demand(catalog&&typeof catalog.invocationTarget==='string','INFERENCE_PROVIDER_MODEL_DENIED');
    const supportsImage=Array.isArray(catalog.inputModalities)&&catalog.inputModalities.includes('IMAGE');
    for(const p of request.parts){
      if(p?.type==='text'){
        exact(p,['type','text']);
        demand(typeof p.text==='string'&&p.text.length>0,'INFERENCE_PROVIDER_INPUT_INVALID');
      }else{
        exact(p,['type','mimeType','data']);
        demand(p.type==='image'&&supportsImage&&['image/png','image/jpeg','image/webp'].includes(p.mimeType)
          &&typeof p.data==='string'&&p.data.length>=4&&p.data.length<=262144,
          'INFERENCE_IMAGE_INVALID');
      }
    }
    bounded({
      model:model.model,
      parts:request.parts.map(p=>p.type==='image'
        ?{type:p.type,mimeType:p.mimeType,dataDigest:sha256(p.data),dataBytes:p.data.length}:p),
      maxOutputTokens:request.maxOutputTokens,
      memoryContext:request.memoryContext||null,
    });
    return {catalog,parts:request.parts,maxTokens:request.maxOutputTokens,system:request.memoryContext||undefined};
  }
  async execute(request,model,{signal}={}){
    const compiled=this.#compile(request,model),started=this.#clock();
    if(signal?.aborted)throw new InferenceError('INFERENCE_CANCELLED');
    try{
      const result=await this.#converse({
        modelId:model.model,
        parts:compiled.parts,
        system:compiled.system,
        maxTokens:compiled.maxTokens,
      });
      if(signal?.aborted)throw new InferenceError('INFERENCE_PROVIDER_OUTCOME_UNKNOWN',{outcomeUnknown:true});
      demand(record(result)&&result.modelId===model.model&&typeof result.text==='string'&&result.text.trim(),
        'INFERENCE_PROVIDER_RESPONSE_INVALID');
      let code=null,output=result.text;
      const stop=String(result.stopReason||'');
      if(['content_filtered','guardrail_intervened'].includes(stop))code='safety_refusal';
      if(['tool_use'].includes(stop))code='invalid_output';
      if(!code&&request.taskClass==='structured_extraction'){
        try{JSON.parse(output);}catch{code='invalid_output';}
      }
      if(!code){try{bounded({output});}catch{code='invalid_output';}}
      if(code)output=null;
      const elapsed=this.#clock()-started;
      const usage=record(result.usage)?result.usage:{};
      const receiptBasis={
        modelId:model.model,
        invocationTarget:String(result.invocationTarget||compiled.catalog.invocationTarget),
        requestId:typeof result.providerRequestId==='string'?result.providerRequestId:null,
        stopReason:stop||null,
        usage,
        outputDigest:output===null?null:sha256(output),
      };
      return {
        output,
        receipt:{
          state:code?'failed':'received',
          outputDigest:output===null?null:sha256(output),
          providerReceipt:`bedrock-sha256:${sha256(receiptBasis)}`,
          billedCostMicros:null,
          usage:{
            inputTokens:count(usage.inputTokens),
            outputTokens:count(usage.outputTokens),
            totalTokens:count(usage.totalTokens),
          },
          code,
          latencyMs:Number.isSafeInteger(elapsed)&&elapsed>=0?elapsed:null,
          modelRevision:null,
        },
      };
    }catch(error){
      if(error instanceof InferenceError)throw error;
      const status=Number(error?.status||0);
      if(Number.isInteger(status)&&status>0){
        const code=status===429?'rate_limit':[401,403].includes(status)?'permission_denied':status>=500?'unavailable':'invalid_output';
        const elapsed=this.#clock()-started;
        return {output:null,receipt:{
          state:'failed',outputDigest:null,
          providerReceipt:`bedrock-http-${status}-sha256:${sha256({model:model.model,status})}`,
          billedCostMicros:null,
          usage:{inputTokens:null,outputTokens:null,totalTokens:null},
          code,
          latencyMs:Number.isSafeInteger(elapsed)&&elapsed>=0?elapsed:null,
          modelRevision:null,
        }};
      }
      throw new InferenceError('INFERENCE_PROVIDER_OUTCOME_UNKNOWN',{outcomeUnknown:true});
    }
  }
}
