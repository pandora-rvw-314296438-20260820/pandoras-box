import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL=Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BASE44_ORIGIN="https://build-with-pandora.base44.app";
const BASE44_APP_ID="6a94ecfadf75736cd4ebf7e1";
const USER_ME=BASE44_ORIGIN+"/api/apps/"+BASE44_APP_ID+"/entities/User/me";
const MAX=65536;

type R=Record<string,unknown>;
const rec=(v:unknown):R=>v&&typeof v==="object"&&!Array.isArray(v)?v as R:{};
const txt=(v:unknown)=>typeof v==="string"?v.trim():"";
const num=(v:unknown)=>{const n=typeof v==="number"?v:Number(v);return Number.isFinite(n)?n:null};

function out(body:unknown,status=200){
  return new Response(status===204?null:JSON.stringify(body),{status,headers:{
    "access-control-allow-origin":BASE44_ORIGIN,
    "access-control-allow-methods":"GET, OPTIONS",
    "access-control-allow-headers":"authorization, content-type",
    "access-control-max-age":"86400","vary":"Origin",
    "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store, max-age=0","x-content-type-options":"nosniff","referrer-policy":"no-referrer"
  }});
}
const fail=(s:number,c:string,m:string)=>out({code:c,plainMessage:m},s);

function bearer(req:Request){
  const h=req.headers.get("authorization")||"";
  if(!h.startsWith("Bearer ")) throw new Error("BASE44_AUTH_REQUIRED");
  if(new TextEncoder().encode(h).byteLength>8192) throw new Error("BASE44_AUTH_INVALID");
  const t=h.slice(7).trim(); if(!t||/\s/.test(t)) throw new Error("BASE44_AUTH_INVALID");
  return "Bearer "+t;
}
async function sha(s:string){const h=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));return Array.from(new Uint8Array(h)).map(v=>v.toString(16).padStart(2,"0")).join("")}

async function base44User(auth:string){
  const ctl=new AbortController(); const timeout=setTimeout(()=>ctl.abort(),8000);
  try{
    const r=await fetch(USER_ME,{headers:{authorization:auth,accept:"application/json"},redirect:"error",signal:ctl.signal});
    const declared=Number(r.headers.get("content-length")||"0"); if(Number.isFinite(declared)&&declared>MAX) throw new Error("BASE44_AUTH_UNAVAILABLE");
    const raw=await r.text(); if(new TextEncoder().encode(raw).byteLength>MAX) throw new Error("BASE44_AUTH_UNAVAILABLE");
    if(r.status===401||r.status===403) throw new Error("BASE44_AUTH_INVALID");
    if(!r.ok||!/application\/json/i.test(r.headers.get("content-type")||"")) throw new Error("BASE44_AUTH_UNAVAILABLE");
    const p=rec(JSON.parse(raw)),u=rec(p.data??p.user??p),id=txt(u.id); if(!id) throw new Error("BASE44_AUTH_INVALID"); return id;
  }catch(e){if(e instanceof Error&&e.name==="AbortError")throw new Error("BASE44_AUTH_UNAVAILABLE");throw e}finally{clearTimeout(timeout)}
}
function theatre(expV:unknown,tV:unknown){
  const e=rec(expV),t=rec(tV),job=txt(t.build_job_id);
  if(!job)return{source:"pandora_project_experience_projection",mode:"idle",buildJobId:null,ownerState:txt(e.experience_state)||"START",ownerStage:null,progressPercent:null,publicMessage:txt(e.public_message)||"What do you want to build?",previewUrl:null,liveUrl:null,needsYou:e.needs_you===true,retryAvailable:e.retry_available===true,updatedAt:txt(e.updated_at)||null};
  return{source:"pandora_build_theatre_projection",mode:"active",buildJobId:job,ownerState:txt(t.owner_state)||null,ownerStage:txt(t.owner_stage)||null,progressPercent:num(t.progress_percent),publicMessage:txt(t.public_message)||txt(e.public_message)||"Pandora is working.",previewUrl:txt(t.preview_url)||null,liveUrl:txt(t.live_url)||null,needsYou:t.needs_you===true,retryAvailable:t.retry_available===true,updatedAt:txt(t.updated_at)||null}
}

Deno.serve(async(req)=>{
  const origin=req.headers.get("origin")||"";
  if(origin!==BASE44_ORIGIN)return new Response(JSON.stringify({code:"ORIGIN_NOT_ALLOWED",plainMessage:"That app is not allowed to use this service."}),{status:403,headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store","vary":"Origin"}});
  if(req.method==="OPTIONS")return out(null,204);
  if(req.method!=="GET")return fail(405,"METHOD_NOT_ALLOWED","That action is not available.");
  const path=new URL(req.url).pathname,mark="/pandora-base44-bridge",i=path.indexOf(mark),route=i>=0?(path.slice(i+mark.length)||"/"):path;
  if(route!=="/"&&route!=="/snapshot")return fail(404,"ROUTE_NOT_FOUND","Pandora could not find that item.");
  try{
    const auth=bearer(req),base44UserId=await base44User(auth);
    const admin=createClient(SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:linkData,error:linkError}=await admin.rpc("pandora_base44_resolve_identity_v1",{p_origin:BASE44_ORIGIN,p_app_id:BASE44_APP_ID,p_base44_user_id:base44UserId});
    if(linkError)throw new Error("IDENTITY_LINK_UNAVAILABLE");
    const l=rec(linkData),uid=txt(l.pandoraUserId),org=txt(l.organizationId),projectId=txt(l.projectId);
    if(!uid||!org||!projectId)throw new Error("IDENTITY_NOT_LINKED");
    const {data:rate,error:rateError}=await admin.rpc("consume_runtime_rate_limit",{p_organization_id:org,p_key_hash:await sha(uid+":GET:pandora-base44-bridge"),p_limit:120,p_window_seconds:60});
    if(rateError)throw new Error("RATE_LIMIT_UNAVAILABLE"); if(rec(rate).allowed!==true)throw new Error("RATE_LIMITED");
    const [p,e,t]=await Promise.all([
      admin.from("projectos_projects").select("id,project_key,objective,status,organization_id").eq("id",projectId).eq("organization_id",org).maybeSingle(),
      admin.from("pandora_project_experience_projection").select("experience_state,current_verified,public_message,needs_you,retry_available,can_focus,can_change,can_undo,can_publish,can_rollback,verification_summary,change_summary,safe_failure_code,safe_failure_message,updated_at").eq("project_id",projectId).eq("organization_id",org).maybeSingle(),
      admin.from("pandora_build_theatre_projection").select("build_job_id,owner_state,owner_stage,progress_percent,public_message,preview_url,live_url,needs_you,retry_available,updated_at").eq("project_id",projectId).eq("organization_id",org).maybeSingle()
    ]);
    if(p.error||e.error||t.error)throw new Error("BACKEND_READ_FAILED"); if(!p.data)throw new Error("PROJECT_NOT_FOUND");
    const ex=rec(e.data);
    return out({schemaVersion:"1.0.0",project:{id:txt(p.data.id),projectKey:txt(p.data.project_key),objective:txt(p.data.objective),status:txt(p.data.status)},experience:{state:txt(ex.experience_state)||"START",publicMessage:txt(ex.public_message)||"What do you want to build?",currentVerified:ex.current_verified===true,canFocus:ex.can_focus===true,canChange:ex.can_change===true,canUndo:ex.can_undo===true,canPublish:ex.can_publish===true,canRollback:ex.can_rollback===true,needsYou:ex.needs_you===true,retryAvailable:ex.retry_available===true,verificationSummary:txt(ex.verification_summary)||null,changeSummary:txt(ex.change_summary)||null,safeFailureCode:txt(ex.safe_failure_code)||null,safeFailureMessage:txt(ex.safe_failure_message)||null,updatedAt:txt(ex.updated_at)||null},buildTheatre:theatre(ex,t.data)});
  }catch(e){
    const c=e instanceof Error?e.message:"UNEXPECTED_FAILURE";
    if(c==="BASE44_AUTH_REQUIRED"||c==="BASE44_AUTH_INVALID")return fail(401,c,"Please sign in to Pandora again.");
    if(c==="IDENTITY_NOT_LINKED")return fail(403,c,"This Base44 account is not linked to Pandora.");
    if(c==="RATE_LIMITED")return fail(429,c,"Too many requests. Please try again shortly.");
    if(["BASE44_AUTH_UNAVAILABLE","IDENTITY_LINK_UNAVAILABLE","RATE_LIMIT_UNAVAILABLE","BACKEND_READ_FAILED"].includes(c))return fail(503,c,"Pandora cannot load that information right now.");
    if(c==="PROJECT_NOT_FOUND")return fail(404,c,"Pandora could not find that project.");
    return fail(500,"UNEXPECTED_FAILURE","Pandora could not complete that request.");
  }
});
