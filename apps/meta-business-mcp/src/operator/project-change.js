"use strict";
Object.defineProperty(exports,"__esModule",{value:true});
exports.createProjectChangeHandler=createProjectChangeHandler;
const rest_client_1=require("../supabase/rest-client.js");
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256=/^[0-9a-f]{64}$/;
const MAX_TTL=15*60*1000;
const EXECUTOR_ROLES=new Set(["owner","admin"]);
function text(v){return typeof v==="string"?v.trim():"";}
function rec(v){return v&&typeof v==="object"&&!Array.isArray(v)?v:{};}
function compact(v,max){return text(v).replace(/\s+/g," ").slice(0,max);}
function fail(res,status,code,message){res.status(status).json({ok:false,error:{code,message}});}
function safeFile(v){const s=text(v)||"index.html";return !s.startsWith("/")&&!s.includes("..")&&!s.includes("\\")&&!s.includes("\0")?s:null;}
function component(v){const s=text(v);return s&&s.length<=200&&!/[\r\n\0]/.test(s)?s:null;}
async function edge(options,token,name,body){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000);
  try{
    const response=await (options.projectChangeFetchFn||fetch)(new URL("/functions/v1/"+encodeURIComponent(name),options.supabaseUrl),{
      method:"POST",redirect:"error",signal:controller.signal,
      headers:{apikey:options.supabasePublishableKey,authorization:"Bearer "+token,accept:"application/json","content-type":"application/json"},
      body:JSON.stringify(body)
    });
    const bytes=new Uint8Array(await response.arrayBuffer());
    if(bytes.byteLength>512*1024)throw new Error("EDGE_RESPONSE_TOO_LARGE");
    let payload={};try{payload=bytes.length?JSON.parse(Buffer.from(bytes).toString("utf8")):{}}catch{throw new Error("EDGE_RESPONSE_INVALID")}
    return {status:response.status,payload};
  }finally{clearTimeout(timer)}
}
function focusContext(t){
  const p=["FocusToken(v2)","project="+t.projectId,"version="+t.versionId,"artifact_sha256="+t.artifactDigest,"component_id="+t.componentId,"semantic_id="+t.semanticId,"source="+t.sourceFile+(t.sourceLine?":"+t.sourceLine:""),"route="+t.route,"issued_at="+t.issuedAt,"expires_at="+t.expiresAt];
  if(t.role)p.push("role="+t.role);if(t.accessibleName)p.push("name="+t.accessibleName);if(t.selector)p.push("selector="+t.selector);
  if(t.bounds)p.push("bounds=x="+t.bounds.x.toFixed(1)+",y="+t.bounds.y.toFixed(1)+",w="+t.bounds.width.toFixed(1)+",h="+t.bounds.height.toFixed(1));
  return p.join(" ")+". Apply the owner change specifically to this exact selected object.";
}
async function validateFocus(client,org,projectId,value){
  if(value==null)return null;
  const x=rec(value),keys=Object.keys(x).sort(),allowed=["accessibleName","artifactDigest","bounds","componentId","expiresAt","issuedAt","projectId","role","route","schemaVersion","selector","semanticId","sourceFile","sourceLine","versionId"].sort();
  if(keys.length!==allowed.length||!keys.every((k,i)=>k===allowed[i])||x.schemaVersion!==2)throw Object.assign(new Error("FOCUS_TOKEN_INVALID"),{status:409});
  const t={schemaVersion:2,projectId:text(x.projectId).toLowerCase(),versionId:text(x.versionId).toLowerCase(),artifactDigest:text(x.artifactDigest).toLowerCase(),componentId:component(x.componentId),semanticId:text(x.semanticId),selector:text(x.selector),role:compact(x.role,120),accessibleName:compact(x.accessibleName,300),route:text(x.route)||"/",sourceFile:safeFile(x.sourceFile),sourceLine:Number.isInteger(x.sourceLine)&&x.sourceLine>0?x.sourceLine:null,bounds:null,issuedAt:text(x.issuedAt),expiresAt:text(x.expiresAt)};
  if(t.projectId!==projectId||!UUID.test(t.projectId)||!UUID.test(t.versionId)||!SHA256.test(t.artifactDigest)||!t.componentId||!t.semanticId||!t.sourceFile)throw Object.assign(new Error("FOCUS_TOKEN_INVALID"),{status:409});
  const issued=Date.parse(t.issuedAt),expires=Date.parse(t.expiresAt),now=Date.now();
  if(!Number.isFinite(issued)||!Number.isFinite(expires)||expires<=issued||expires-issued>MAX_TTL||now>=expires||issued>now+30000)throw Object.assign(new Error("FOCUS_TOKEN_STALE"),{status:409});
  const b=rec(x.bounds);if(Object.keys(b).length){const v=["x","y","width","height"].map(k=>Number(b[k]));if(v.some(n=>!Number.isFinite(n)))throw Object.assign(new Error("FOCUS_TOKEN_INVALID"),{status:409});t.bounds={x:v[0],y:v[1],width:v[2],height:v[3]};}
  const versions=await client.requestJson("/rest/v1/pandora_project_versions?select=id,artifact_digest_sha256&organization_id=eq."+encodeURIComponent(org)+"&project_id=eq."+encodeURIComponent(projectId)+"&id=eq."+encodeURIComponent(t.versionId)+"&limit=1");
  if(!Array.isArray(versions)||text(versions[0]?.artifact_digest_sha256).toLowerCase()!==t.artifactDigest)throw Object.assign(new Error("FOCUS_TOKEN_STALE"),{status:409});
  const projections=await client.requestJson("/rest/v1/pandora_project_experience_projection?select=current_version_id,current_verified,candidate_version_id,candidate_verification_state&project_id=eq."+encodeURIComponent(projectId)+"&limit=1");
  const p=Array.isArray(projections)?projections[0]:null;
  const current=p?.current_verified===true&&text(p.current_version_id).toLowerCase()===t.versionId;
  const candidate=text(p?.candidate_verification_state).toLowerCase()==="passed"&&text(p?.candidate_version_id).toLowerCase()===t.versionId;
  if(!current&&!candidate)throw Object.assign(new Error("FOCUS_TOKEN_STALE"),{status:409});
  return t;
}
async function saveIntent(client,org,user,projectId,message,key,focus){
  const body={organization_id:org,project_id:projectId,requester_id:user,intent_kind:"change",intent_text:message,source:"customer",idempotency_key:key,provenance:{surface:"pandora_web_simple_mode",focus_schema_version:focus?.schemaVersion||null,focus_version_id:focus?.versionId||null,focus_artifact_sha256:focus?.artifactDigest||null}};
  try{
    const rows=await client.requestJson("/rest/v1/pandora_project_intents?select=id",{method:"POST",headers:{prefer:"return=representation"},body:JSON.stringify(body)});
    if(Array.isArray(rows)&&UUID.test(text(rows[0]?.id)))return text(rows[0].id);
  }catch(e){if(!(e instanceof rest_client_1.SupabaseRestError)||(e.status!==409&&e.code!=="23505"))throw e;}
  const rows=await client.requestJson("/rest/v1/pandora_project_intents?select=id&organization_id=eq."+encodeURIComponent(org)+"&project_id=eq."+encodeURIComponent(projectId)+"&requester_id=eq."+encodeURIComponent(user)+"&idempotency_key=eq."+encodeURIComponent(key)+"&limit=1");
  if(!Array.isArray(rows)||!UUID.test(text(rows[0]?.id)))throw new Error("CHANGE_INTENT_UNAVAILABLE");
  return text(rows[0].id);
}
async function exactSpec(client,org,projectId,intentId){
  const rows=await client.requestJson("/rest/v1/pandora_project_specs?select=id,status,source_intent_id,version&organization_id=eq."+encodeURIComponent(org)+"&project_id=eq."+encodeURIComponent(projectId)+"&source_intent_id=eq."+encodeURIComponent(intentId)+"&order=version.desc&limit=1");
  return Array.isArray(rows)?rows[0]||null:null;
}
function createProjectChangeHandler(options){
  return async(request,response)=>{
    response.setHeader("Cache-Control","no-store");response.setHeader("X-Content-Type-Options","nosniff");
    const current=response.locals.operatorActor;
    if(!current||!EXECUTOR_ROLES.has(current.membership.role))return fail(response,403,"EXECUTOR_ROLE_REQUIRED","Only an owner or admin may change a project.");
    const projectId=text(request.params.projectId).toLowerCase(),body=rec(request.body),keys=Object.keys(body);
    if(!UUID.test(projectId)||keys.some(k=>!["message","idempotencyKey","focusToken"].includes(k))||!keys.includes("message")||!keys.includes("idempotencyKey"))return fail(response,400,"PROJECT_CHANGE_INVALID","Pandora rejected an invalid project change request.");
    let message=text(body.message),key=text(body.idempotencyKey);
    if(message.length<4||message.length>8000||key.length<8||key.length>200)return fail(response,400,"PROJECT_CHANGE_INVALID","Pandora needs a clear bounded project change request.");
    const client=new rest_client_1.SupabaseRestClient({supabaseUrl:options.supabaseUrl,apiKey:options.supabasePublishableKey,accessToken:current.identity.accessToken,fetchFn:options.projectChangeFetchFn,timeoutMs:12000,maxResponseBytes:1024*1024});
    try{
      const focus=await validateFocus(client,current.membership.organizationId,projectId,body.focusToken);
      if(focus)message=focusContext(focus)+"\nOwner change: "+message;
      const intentId=await saveIntent(client,current.membership.organizationId,current.identity.userId,projectId,message,key,focus);
      const compiled=await edge(options,current.identity.accessToken,"pandora-project-spec-compiler",{intentId});
      const spec=await exactSpec(client,current.membership.organizationId,projectId,intentId);
      if(!spec||spec.status!=="active"){
        if(compiled.status===422||spec?.status==="rejected")return fail(response,422,"PROJECT_CHANGE_REJECTED","Pandora needs a different request before it can make that change.");
        response.status(202).json({ok:true,state:"understanding",intentId});return;
      }
      if(text(spec.source_intent_id)!==intentId)return fail(response,409,"PROJECT_CHANGE_LINEAGE_MISMATCH","Pandora refused a project specification from another request.");
      const built=await edge(options,current.identity.accessToken,"pandora-project-source-generator",{projectId,idempotencyKey:"pandora-web-change-build:"+projectId+":"+intentId});
      if(built.status!==200&&built.status!==202){
        const code=text(rec(built.payload.error).code)||"PROJECT_CHANGE_BUILD_UNAVAILABLE";
        if(built.status===409&&code==="PROJECT_SPEC_NOT_READY"){response.status(202).json({ok:true,state:"understanding",intentId,projectSpecId:spec.id});return;}
        return fail(response,built.status>=400&&built.status<500?built.status:503,code,"Pandora could not admit that exact project change build.");
      }
      const out=rec(built.payload);
      response.status(built.status).json({ok:true,state:text(out.state)||"working",stage:text(out.stage)||"queued",intentId,projectSpecId:spec.id,streamId:text(out.streamId)||null,buildJobId:text(out.buildJobId)||null,projectVersionId:text(out.projectVersionId)||null});
    }catch(e){
      const code=e instanceof Error?e.message:"PROJECT_CHANGE_UNAVAILABLE",status=Number(e?.status)||((code==="FOCUS_TOKEN_STALE"||code==="FOCUS_TOKEN_INVALID")?409:503);
      const msg=code==="FOCUS_TOKEN_STALE"?"That selection belongs to an older preview. Select the object again before changing it.":code==="FOCUS_TOKEN_INVALID"?"Pandora could not bind that object to the exact preview.":"Pandora could not prepare that project change. Your current result is unchanged.";
      fail(response,status,code,msg);
    }
  };
}
