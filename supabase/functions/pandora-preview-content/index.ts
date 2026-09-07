
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/;
const MAX_BUNDLE_BYTES = 25 * 1024 * 1024;
const MAX_MOBILE_BYTES = 12 * 1024 * 1024;
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_HOSTED_HTML_BYTES = 2 * 1024 * 1024;
const FOCUS_MODE = "web_focus";

type JsonRecord = Record<string, unknown>;
function asRecord(value: unknown): JsonRecord { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {}; }
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function serviceClient() { if (!SERVICE_ROLE) throw new Error("PREVIEW_CONTENT_NOT_CONFIGURED"); return createClient(SUPABASE_URL,SERVICE_ROLE,{auth:{persistSession:false,autoRefreshToken:false}}); }
async function sha256Hex(bytes: Uint8Array) { const digest=await crypto.subtle.digest("SHA-256",bytes); return [...new Uint8Array(digest)].map((b)=>b.toString(16).padStart(2,"0")).join(""); }
function canonicalBase64(value: unknown) { const source=text(value); if(!source||source.length%4!==0||!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(source)) throw new Error("ARTIFACT_FILE_BASE64_INVALID"); let binary=""; try{binary=atob(source);}catch{throw new Error("ARTIFACT_FILE_BASE64_INVALID");} if(binary.length>MAX_FILE_BYTES) throw new Error("ARTIFACT_FILE_TOO_LARGE"); const bytes=new Uint8Array(binary.length); for(let i=0;i<binary.length;i++) bytes[i]=binary.charCodeAt(i); return bytes; }
function safePath(value: unknown) { const path=text(value); if(!path||path.length>512||path.startsWith("/")||path.endsWith("/")||path.includes("\\")||path.includes("\0")||path.includes("?")||path.includes("#")) throw new Error("ARTIFACT_FILE_PATH_INVALID"); const parts=path.split("/"); if(parts.some((part)=>!part||part==="."||part===".."||part.length>255)) throw new Error("ARTIFACT_FILE_PATH_INVALID"); return path; }
function mimeType(path:string){const ext=path.toLowerCase().split(".").pop()||"";return ({html:"text/html",css:"text/css",js:"text/javascript",mjs:"text/javascript",json:"application/json",txt:"text/plain",xml:"application/xml",svg:"image/svg+xml",png:"image/png",jpg:"image/jpeg",jpeg:"image/jpeg",webp:"image/webp",gif:"image/gif",ico:"image/x-icon",woff:"font/woff",woff2:"font/woff2",ttf:"font/ttf",wasm:"application/wasm",pdf:"application/pdf"} as Record<string,string>)[ext]||"application/octet-stream";}
function json(body:unknown,status=200,requestId?:string){return new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store, max-age=0","x-content-type-options":"nosniff",...(requestId?{"x-request-id":requestId}:{})}});}
function exactHttpsUrl(value: unknown) { const raw=text(value); let parsed:URL; try{parsed=new URL(raw);}catch{throw new Error("HOSTED_PREVIEW_URL_INVALID");} if(parsed.protocol!=="https:"||!parsed.hostname||parsed.username||parsed.password) throw new Error("HOSTED_PREVIEW_URL_INVALID"); return parsed.toString(); }
function exactVercelPreviewUrl(value: unknown) { const url=new URL(exactHttpsUrl(value)); const host=url.hostname.toLowerCase(); if(host!=="vercel.app"&&!host.endsWith(".vercel.app")) throw new Error("HOSTED_PREVIEW_URL_INVALID"); return url.toString(); }
function htmlEscape(value:string){return value.replaceAll("&","&amp;").replaceAll('"',"&quot;").replaceAll("<","&lt;").replaceAll(">","&gt;");}
function base64Bytes(bytes:Uint8Array){let binary="";for(const b of bytes) binary+=String.fromCharCode(b);return btoa(binary);}
function injectHostedBase(html:string,hostedUrl:string){
  const stripped=html.replace(/<base\b[^>]*>/gi,"");
  const base='<base href="'+htmlEscape(hostedUrl)+'">';
  if(/<head\b[^>]*>/i.test(stripped)) return stripped.replace(/<head\b[^>]*>/i,(match)=>match+base);
  if(/<html\b[^>]*>/i.test(stripped)) return stripped.replace(/<html\b[^>]*>/i,(match)=>match+'<head>'+base+'</head>');
  return '<!doctype html><html><head>'+base+'</head><body>'+stripped+'</body></html>';
}
function injectFocusBridge(html:string){
  const bridge=`<style id="pandora-focus-bridge-style">
[data-pandora-focus-hover="true"]{outline:2px solid rgba(220,48,48,.95)!important;outline-offset:2px!important;cursor:crosshair!important}
</style><script id="pandora-focus-bridge-script">
(()=>{let enabled=false;let hover=null;
const clean=(value,max)=>String(value||'').replace(/\\s+/g,' ').trim().slice(0,max);
const label=(el)=>clean(el.getAttribute('aria-label')||el.getAttribute('alt')||el.getAttribute('title')||el.textContent||'',300);
const role=(el)=>el.getAttribute('role')||({A:'link',BUTTON:'button',INPUT:'input',TEXTAREA:'textbox',SELECT:'combobox',IMG:'img',H1:'heading',H2:'heading',H3:'heading',H4:'heading',H5:'heading',H6:'heading'}[el.tagName]||'');
const selector=(el)=>{const parts=[];let node=el;for(let depth=0;node&&node.nodeType===1&&depth<5;depth+=1,node=node.parentElement){let part=node.tagName.toLowerCase();const siblings=node.parentElement?[...node.parentElement.children].filter((item)=>item.tagName===node.tagName):[];if(siblings.length>1)part+=':nth-of-type('+(siblings.indexOf(node)+1)+')';parts.unshift(part);}return parts.join(' > ');};
const clear=()=>{if(hover)hover.removeAttribute('data-pandora-focus-hover');hover=null;};
const choose=(el)=>{const rect=el.getBoundingClientRect();const sel=selector(el);const name=label(el);const r=role(el);const semantic=clean(el.getAttribute('data-pandora-semantic-id')||el.getAttribute('data-pandora-component-id')||el.id||(r&&name?r+':'+name.slice(0,120):sel),400);const component=clean(el.getAttribute('data-pandora-component-id')||el.id||semantic,200);const sourceLine=Number(el.getAttribute('data-pandora-source-line')||0);return{type:'pandora.preview.selection.v2',componentId:component,semanticId:semantic,selector:sel,role:r,accessibleName:name,route:location.pathname+location.hash,sourceFile:clean(el.getAttribute('data-pandora-source-file')||'index.html',512),sourceLine:Number.isSafeInteger(sourceLine)&&sourceLine>0?sourceLine:null,bounds:{x:Math.max(0,rect.x),y:Math.max(0,rect.y),width:Math.max(0,rect.width),height:Math.max(0,rect.height)}};};
addEventListener('message',(event)=>{if(event.source!==parent)return;const data=event.data||{};if(data.type!=='pandora.preview.focus-mode.v1')return;enabled=data.enabled===true;clear();});
addEventListener('pointerover',(event)=>{if(!enabled)return;const el=event.target instanceof Element?event.target:null;if(!el)return;clear();hover=el;hover.setAttribute('data-pandora-focus-hover','true');},true);
addEventListener('pointerout',(event)=>{if(!enabled)return;const next=event.relatedTarget;if(hover&&next instanceof Node&&hover.contains(next))return;clear();},true);
addEventListener('click',(event)=>{if(!enabled)return;const el=event.target instanceof Element?event.target:null;if(!el)return;event.preventDefault();event.stopImmediatePropagation();const payload=choose(el);enabled=false;clear();parent.postMessage(payload,'*');},true);
})();</script>`;
  if(/<\/body\s*>/i.test(html)) return html.replace(/<\/body\s*>/i,`${bridge}</body>`);
  return html+bridge;
}

async function recordAudit(admin:ReturnType<typeof serviceClient>, args:JsonRecord, required:boolean){
  const {error}=await admin.rpc("pandora_record_source_access_audit_service_v1",args);
  if(error&&required) throw new Error("SOURCE_ACCESS_AUDIT_FAILED");
  if(error) console.error(JSON.stringify({code:"SOURCE_ACCESS_AUDIT_FAILED",detail:error.code}));
}

Deno.serve(async(req:Request)=>{
  const requestId=crypto.randomUUID();
  if(req.method==="OPTIONS") return new Response(null,{status:204,headers:{"access-control-allow-origin":"*","access-control-allow-methods":"POST, OPTIONS","access-control-allow-headers":"authorization, apikey, content-type"}});
  if(req.method!=="POST") return json({code:"METHOD_NOT_ALLOWED",plainMessage:"That preview action is not available.",requestId},405,requestId);
  try{
    const authorization=req.headers.get("authorization")||""; if(!/^Bearer\s+\S+$/i.test(authorization)) throw new Error("SIGN_IN_REQUIRED");
    const userClient=createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
    const {data:authData,error:authError}=await userClient.auth.getUser(); if(authError||!authData.user) throw new Error("SIGN_IN_REQUIRED");
    let body:JsonRecord; try{body=asRecord(await req.json());}catch{throw new Error("INVALID_JSON");}
    if(Object.keys(body).some((key)=>!new Set(["projectId","versionId","mode"]).has(key))) throw new Error("INVALID_JSON");
    const projectId=text(body.projectId).toLowerCase(),versionId=text(body.versionId).toLowerCase(),mode=text(body.mode); if(!UUID_RE.test(projectId)||!UUID_RE.test(versionId)||![ "", FOCUS_MODE ].includes(mode)) throw new Error("EXACT_VERSION_REQUIRED");

    const admin=serviceClient();
    const {data:project,error:projectError}=await admin.from("projectos_projects").select("id,organization_id").eq("id",projectId).maybeSingle(); if(projectError||!project) throw new Error("PROJECT_NOT_FOUND");
    const organizationId=text(project.organization_id);
    const {data:membership,error:membershipError}=await admin.from("memberships").select("organization_id,role,status").eq("organization_id",organizationId).eq("user_id",authData.user.id).eq("status","active").in("role",["owner","admin"]).maybeSingle();
    if(membershipError||!membership) throw new Error("ORGANIZATION_ACCESS_REQUIRED");

    const {data:version,error:versionError}=await admin.from("pandora_project_versions").select("id,organization_id,project_id,root_artifact_version_id,artifact_digest_sha256,source_sha256").eq("id",versionId).eq("organization_id",organizationId).eq("project_id",projectId).maybeSingle();
    if(versionError||!version) throw new Error("EXACT_VERSION_REQUIRED");
    const rootArtifactVersionId=text(version.root_artifact_version_id),artifactDigest=text(version.artifact_digest_sha256).toLowerCase(),sourceSha=text(version.source_sha256).toLowerCase();
    if(!UUID_RE.test(rootArtifactVersionId)||!SHA256_RE.test(artifactDigest)||!SHA256_RE.test(sourceSha)) throw new Error("ARTIFACT_LINEAGE_INCOMPLETE");

    if(mode===FOCUS_MODE){
      const {data:deployment,error:deploymentError}=await admin.from("pandora_project_deployments")
        .select("id,provider,url,immutable_url,status,provider_state,verification_state,source_sha256,artifact_digest,created_at")
        .eq("organization_id",organizationId).eq("project_id",projectId).eq("version_id",versionId)
        .eq("environment","preview").eq("provider","vercel")
        .eq("status","ready").eq("provider_state","READY").eq("verification_state","live_verified")
        .order("created_at",{ascending:false}).limit(1).maybeSingle();
      if(deploymentError||!deployment) throw new Error("HOSTED_PREVIEW_NOT_READY");
      if(text(deployment.source_sha256).toLowerCase()!==sourceSha||text(deployment.artifact_digest).toLowerCase()!==artifactDigest) throw new Error("HOSTED_PREVIEW_IDENTITY_MISMATCH");
      const hostedUrl=exactVercelPreviewUrl(text(deployment.immutable_url)||text(deployment.url));
      const hostedResponse=await fetch(hostedUrl,{method:"GET",redirect:"follow",headers:{"accept":"text/html,application/xhtml+xml","cache-control":"no-store","user-agent":"Pandora-Web-Focus/1.0"}});
      if(!hostedResponse.ok) throw new Error("HOSTED_PREVIEW_FETCH_FAILED");
      const hostedContentType=(hostedResponse.headers.get("content-type")||"").toLowerCase();
      if(!hostedContentType.includes("text/html")&&!hostedContentType.includes("application/xhtml+xml")) throw new Error("HOSTED_PREVIEW_CONTENT_TYPE_INVALID");
      const finalHostedUrl=exactVercelPreviewUrl(hostedResponse.url||hostedUrl);
      if(new URL(finalHostedUrl).hostname!==new URL(hostedUrl).hostname) throw new Error("HOSTED_PREVIEW_REDIRECT_INVALID");
      const hostedBytes=new Uint8Array(await hostedResponse.arrayBuffer());
      if(hostedBytes.byteLength<1||hostedBytes.byteLength>MAX_HOSTED_HTML_BYTES) throw new Error("HOSTED_PREVIEW_HTML_SIZE_INVALID");
      let hostedHtml:string;
      try{hostedHtml=new TextDecoder("utf-8",{fatal:true}).decode(hostedBytes);}catch{throw new Error("HOSTED_PREVIEW_HTML_INVALID");}
      const focusHtml=injectFocusBridge(injectHostedBase(hostedHtml,finalHostedUrl));
      const focusBytes=new TextEncoder().encode(focusHtml);
      if(focusBytes.byteLength<1||focusBytes.byteLength>MAX_HOSTED_HTML_BYTES) throw new Error("HOSTED_PREVIEW_HTML_SIZE_INVALID");
      const focusDigest=await sha256Hex(focusBytes);
      await recordAudit(admin,{p_organization_id:organizationId,p_project_id:projectId,p_user_id:authData.user.id,p_entitlement_id:null,p_capability:"read",p_action:"preview.web_focus",p_resource_ref:versionId,p_allowed:true,p_reason:"EXACT_VERIFIED_HOSTED_PREVIEW",p_request_id:requestId,p_metadata:{deploymentId:deployment.id,provider:"vercel",sourceSha256:sourceSha,artifactDigest}},false);
      return json({kind:"pandora.web-focus-preview.v1",projectId,versionId,artifactDigest,deploymentId:deployment.id,provider:"vercel",hostedUrl,byteSize:focusBytes.byteLength,sha256:focusDigest,htmlBase64:base64Bytes(focusBytes)},200,requestId);
    }

    const {data:entitlement,error:entitlementError}=await userClient.rpc("pandora_get_source_entitlement_v1",{p_project_id:projectId,p_capability:"read"});
    if(entitlementError) throw new Error("SOURCE_ENTITLEMENT_CHECK_FAILED");
    const decision=asRecord(entitlement),sourceAllowed=decision.allowed===true,entitlementId=text(decision.entitlementId),decisionReason=text(decision.reason)||"NO_SOURCE_ENTITLEMENT";

    if(!sourceAllowed){
      const {data:deployment,error:deploymentError}=await admin.from("pandora_project_deployments")
        .select("id,url,immutable_url,status,provider_state,verification_state,source_sha256,artifact_digest,created_at")
        .eq("organization_id",organizationId).eq("project_id",projectId).eq("version_id",versionId).eq("environment","preview")
        .eq("status","ready").eq("provider_state","READY").eq("verification_state","live_verified")
        .order("created_at",{ascending:false}).limit(1).maybeSingle();
      if(deploymentError||!deployment) throw new Error("HOSTED_PREVIEW_NOT_READY");
      if(text(deployment.source_sha256).toLowerCase()!==sourceSha||text(deployment.artifact_digest).toLowerCase()!==artifactDigest) throw new Error("HOSTED_PREVIEW_IDENTITY_MISMATCH");
      const hostedUrl=exactHttpsUrl(text(deployment.immutable_url)||text(deployment.url));
      const hostedResponse=await fetch(hostedUrl,{method:"GET",redirect:"follow",headers:{"accept":"text/html,application/xhtml+xml"}});
      if(!hostedResponse.ok) throw new Error("HOSTED_PREVIEW_FETCH_FAILED");
      const hostedContentType=(hostedResponse.headers.get("content-type")||"").toLowerCase();
      if(!hostedContentType.includes("text/html")&&!hostedContentType.includes("application/xhtml+xml")) throw new Error("HOSTED_PREVIEW_CONTENT_TYPE_INVALID");
      const finalHostedUrl=exactHttpsUrl(hostedResponse.url||hostedUrl);
      if(new URL(finalHostedUrl).hostname!==new URL(hostedUrl).hostname) throw new Error("HOSTED_PREVIEW_REDIRECT_INVALID");
      const hostedBytes=new Uint8Array(await hostedResponse.arrayBuffer());
      if(hostedBytes.byteLength<1||hostedBytes.byteLength>MAX_HOSTED_HTML_BYTES) throw new Error("HOSTED_PREVIEW_HTML_SIZE_INVALID");
      let hostedHtml:string;
      try{hostedHtml=new TextDecoder("utf-8",{fatal:true}).decode(hostedBytes);}catch{throw new Error("HOSTED_PREVIEW_HTML_INVALID");}
      const materializedHtml=injectHostedBase(hostedHtml,finalHostedUrl);
      const wrapperBytes=new TextEncoder().encode(materializedHtml);
      if(wrapperBytes.byteLength>MAX_HOSTED_HTML_BYTES) throw new Error("HOSTED_PREVIEW_HTML_SIZE_INVALID");
      const wrapperDigest=await sha256Hex(wrapperBytes);
      await recordAudit(admin,{p_organization_id:organizationId,p_project_id:projectId,p_user_id:authData.user.id,p_entitlement_id:null,p_capability:"read",p_action:"preview.source_withheld",p_resource_ref:versionId,p_allowed:false,p_reason:decisionReason,p_request_id:requestId,p_metadata:{deploymentId:deployment.id,hostedPreview:true,sourceSha256:sourceSha,artifactDigest}},false);
      return json({kind:"pandora.mobile-preview-bundle.v1",projectId,versionId,artifactDigest,totalBytes:wrapperBytes.byteLength,sourceIncluded:false,sourceEntitled:false,hostedPreview:{deploymentId:deployment.id,url:hostedUrl,sourceSha256:sourceSha,artifactDigest},files:[{file:"index.html",mimeType:"text/html",dataBase64:base64Bytes(wrapperBytes),byteSize:wrapperBytes.byteLength,sha256:wrapperDigest}]},200,requestId);
    }

    await recordAudit(admin,{p_organization_id:organizationId,p_project_id:projectId,p_user_id:authData.user.id,p_entitlement_id:UUID_RE.test(entitlementId)?entitlementId:null,p_capability:"read",p_action:"preview.source_bundle",p_resource_ref:versionId,p_allowed:true,p_reason:"SOURCE_ENTITLEMENT_ACTIVE",p_request_id:requestId,p_metadata:{sourceSha256:sourceSha,artifactDigest}},true);

    const {data:artifactVersion,error:avError}=await admin.from("pandora_artifact_versions").select("id,organization_id,project_id,artifact_id,content_sha256,byte_size,storage_provider,storage_bucket,storage_path").eq("id",rootArtifactVersionId).eq("organization_id",organizationId).eq("project_id",projectId).maybeSingle();
    if(avError||!artifactVersion) throw new Error("ARTIFACT_NOT_FOUND");
    if(text(artifactVersion.content_sha256).toLowerCase()!==artifactDigest||text(artifactVersion.storage_provider)!=="supabase_storage") throw new Error("ARTIFACT_DIGEST_MISMATCH");
    const {data:artifact,error:artifactError}=await admin.from("pandora_artifacts").select("id,organization_id,project_id,artifact_kind").eq("id",artifactVersion.artifact_id).eq("organization_id",organizationId).eq("project_id",projectId).maybeSingle();
    if(artifactError||!artifact||!new Set(["build_output","runtime_bundle"]).has(text(artifact.artifact_kind))) throw new Error("ARTIFACT_NOT_FOUND");
    const {data:blob,error:storageError}=await admin.storage.from(text(artifactVersion.storage_bucket)).download(text(artifactVersion.storage_path)); if(storageError||!blob) throw new Error("ARTIFACT_STORAGE_READ_FAILED");
    const bundleBytes=new Uint8Array(await blob.arrayBuffer()),declaredSize=Number(artifactVersion.byte_size); if(!Number.isSafeInteger(declaredSize)||declaredSize<1||declaredSize>MAX_BUNDLE_BYTES||bundleBytes.byteLength!==declaredSize) throw new Error("ARTIFACT_BUNDLE_SIZE_INVALID");
    if(await sha256Hex(bundleBytes)!==artifactDigest) throw new Error("ARTIFACT_BUNDLE_DIGEST_MISMATCH");
    let bundle:JsonRecord; try{bundle=asRecord(JSON.parse(new TextDecoder("utf-8",{fatal:true}).decode(bundleBytes)));}catch{throw new Error("ARTIFACT_BUNDLE_JSON_INVALID");}
    if(bundle.kind!=="pandora.runtime-bundle.v1"||bundle.schemaVersion!==1||text(bundle.projectVersionId)!==versionId||!Array.isArray(bundle.files)) throw new Error("ARTIFACT_BUNDLE_SCHEMA_UNSUPPORTED");
    let totalBytes=0,hasIndex=false;const files:Array<JsonRecord>=[],seen=new Set<string>();let prior="";
    for(const raw of bundle.files){const entry=asRecord(raw),file=safePath(entry.file);if(seen.has(file)||(prior&&prior.localeCompare(file,"en")>=0)) throw new Error("ARTIFACT_FILES_NOT_CANONICAL");seen.add(file);prior=file;if(file==="index.html")hasIndex=true;if(entry.encoding!=="base64")throw new Error("ARTIFACT_FILE_ENCODING_UNSUPPORTED");const fileBytes=canonicalBase64(entry.data);totalBytes+=fileBytes.byteLength;if(totalBytes>MAX_MOBILE_BYTES)throw new Error("PREVIEW_BUNDLE_TOO_LARGE");const fileDigest=text(entry.sha256).toLowerCase();if(!SHA256_RE.test(fileDigest)||await sha256Hex(fileBytes)!==fileDigest||Number(entry.byteSize)!==fileBytes.byteLength)throw new Error("ARTIFACT_FILE_DIGEST_MISMATCH");files.push({file,mimeType:mimeType(file),dataBase64:text(entry.data),byteSize:fileBytes.byteLength,sha256:fileDigest});}
    if(!hasIndex) throw new Error("ARTIFACT_ENTRYPOINT_MISSING");
    return json({kind:"pandora.mobile-preview-bundle.v1",projectId,versionId,artifactDigest,totalBytes,sourceIncluded:true,sourceEntitled:true,entitlementId,files},200,requestId);
  }catch(error){
    const code=error instanceof Error?error.message:"PREVIEW_CONTENT_UNAVAILABLE";
    if(code==="SIGN_IN_REQUIRED")return json({code,plainMessage:"Please sign in again.",requestId},401,requestId);
    if(code==="ORGANIZATION_ACCESS_REQUIRED"||code==="PROJECT_ACCESS_REQUIRED")return json({code,plainMessage:"You do not have permission for this project.",requestId},403,requestId);
    if(new Set(["INVALID_JSON","EXACT_VERSION_REQUIRED"]).has(code))return json({code,plainMessage:"Pandora could not identify that exact preview.",requestId},400,requestId);
    if(code==="PROJECT_NOT_FOUND")return json({code,plainMessage:"Pandora could not find that project.",requestId},404,requestId);
    if(code==="PREVIEW_BUNDLE_TOO_LARGE")return json({code,plainMessage:"This preview is too large for the mobile renderer.",requestId},413,requestId);
    console.error(JSON.stringify({requestId,code}));
    return json({code:"PREVIEW_CONTENT_UNAVAILABLE",plainMessage:"Pandora could not load the exact preview content right now.",requestId},503,requestId);
  }
});
