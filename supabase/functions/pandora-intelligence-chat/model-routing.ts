import { ModelRouter, normalizeModelSelection, ModelCapabilityRegistry, createModelRequest, createRoutingPolicy } from "./routing-bundle.js";

export type ChatModelSelection = Readonly<{selection:"auto"|"manual";provider:string|null;model:string|null;fallbackMode:"strict"|"allow_fallback"}>;
export type ChatProviderConfig = Readonly<{provider:string;enabled:boolean;routingEligible:boolean;defaultModel:string;models:string[];tasks:string[];preferredTasks:string[];executionBoundary?:"external_provider"|"pandora_trusted_cloud"}>;
const text=(value:unknown)=>typeof value==="string"?value.trim():"";
function modelCostClass(model:string):"low"|"medium"|"high"{if(/flash-lite|haiku|mini|nano|micro|fast/i.test(model))return"low";if(/opus|\bpro\b|astra|deep/i.test(model))return"high";return"medium"}
function modelLatencyClass(model:string):"interactive"|"standard"{return/flash|haiku|mini|nano|micro|fast/i.test(model)?"interactive":"standard"}

export function normalizeChatModelSelection(value:unknown):ChatModelSelection{
  const n=normalizeModelSelection(value);
  return{selection:n.selection==="manual"?"manual":"auto",provider:typeof n.provider==="string"?n.provider:null,model:typeof n.model==="string"?n.model:null,fallbackMode:n.fallbackMode==="strict"?"strict":"allow_fallback"};
}
export function modelSelectionFromRoute(route:Record<string,unknown>|null):ChatModelSelection{
  if(route?.selectionMode==="manual"&&text(route.requestedProvider)&&text(route.requestedModel))return normalizeChatModelSelection({selection:"manual",provider:text(route.requestedProvider),model:text(route.requestedModel),fallbackMode:route.fallbackMode==="allow_fallback"?"allow_fallback":"strict"});
  return normalizeChatModelSelection({selection:"auto"});
}
export function planChatModelCandidates(input:{requestId:string;task:string;hasImage:boolean;modelClass:string;configs:ChatProviderConfig[];route:Record<string,unknown>|null;selection:ChatModelSelection;policyVersion:string;performance:Record<string,unknown>;cohortKey:string}){
  const registry=new ModelCapabilityRegistry(),adapters:Record<string,{execute:()=>Promise<never>}>={},allowedProviders:string[]=[],allowedModels:string[]=[];
  let preferredProvider:string|null=null,preferredModel:string|null=null;
  for(const config of input.configs){
    if(!config.enabled||!config.routingEligible)continue;
    if(config.tasks.length&&!config.tasks.includes(input.task)&&!config.tasks.includes("*"))continue;
    const models=[...new Set(config.models.filter(Boolean))];if(!models.length)continue;
    allowedProviders.push(config.provider);adapters[config.provider]={execute:async()=>{throw new Error("ROUTING_PLAN_ONLY")}};
    if(!preferredProvider&&(config.preferredTasks.includes(input.task)||config.preferredTasks.includes("*"))){preferredProvider=config.provider;preferredModel=config.defaultModel}
    for(const model of models){allowedModels.push(`${config.provider}:${model}`);registry.register({provider:config.provider,modelId:model,capabilities:{reasoning:true,structuredOutput:true,multimodal:true,imageUnderstanding:true,classification:true,summarization:true,copywriting:true},executionBoundary:config.executionBoundary??"external_provider",latencyClass:modelLatencyClass(model),costClass:modelCostClass(model),reliabilityClass:"high",maxContextTokens:128000,outputModes:["structured","json","text"],enabled:true,metadata:{modelVersion:model}})}
  }
  const router=new ModelRouter({registry,adapters});
  const policy=createRoutingPolicy({policyVersion:input.policyVersion,allowedProviders,allowedModels,allowedExecutionBoundaries:["external_provider","pandora_trusted_cloud"],performance:input.performance,taskPreferences:preferredProvider?{[input.task]:{preferredProvider,preferredModel}}:{},adaptive:{enabled:true,minSamples:20,explorationCap:0,explorationEligibleTasks:[],highRiskTasks:["chat"]}});
  const session=input.route?.provider&&input.route?.model?{provider:input.route.provider,model:input.route.model,modelVersion:input.route.modelVersion??null,routingPolicyVersion:input.route.routingPolicyVersion??null,reasoningPolicy:input.route.reasoningPolicy??null,stickinessMode:input.route.stickinessMode??"sticky",recoveryEpoch:Number(input.route.recoveryEpoch??0),lastCompatibleTurnId:input.route.lastCompatibleMessageId??null}:null;
  const maxAttempts=input.selection.selection==="manual"&&input.selection.fallbackMode==="strict"?1:Math.max(1,allowedModels.length);
  const request=createModelRequest({requestId:input.requestId,task:"chat",outputMode:"structured",context:{},requiredCapabilities:input.hasImage?["structuredOutput","multimodal"]:["structuredOutput"],budget:{maxAttempts,remainingAttempts:maxAttempts,maxOutputTokens:4096},metadata:{reasoningClass:input.modelClass}});
  const detailed=router.candidatesDetailed(request,{policy,session,selection:input.selection,allowRecoveryBoundary:true,preferredProvider:input.selection.selection==="manual"?input.selection.provider??undefined:undefined,preferredModel:input.selection.selection==="manual"?input.selection.model??undefined:undefined,cohortKey:input.cohortKey});
  return{selection:input.selection,policyVersion:input.policyVersion,candidates:detailed.candidates.map((item:any)=>{const model=item.model as Record<string,unknown>;return{provider:String(model.provider),model:String(model.modelId),score:Number(item.score??0),scoreComponents:item.scoreComponents??{}}}),excluded:detailed.excluded};
}
