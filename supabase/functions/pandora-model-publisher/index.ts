import { createClient } from "jsr:@supabase/supabase-js@2.57.2";
import { MODEL } from "./model.ts";
import { verifyPublisherJwt } from "./oidc.ts";
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{
  status,headers:{"content-type":"application/json","cache-control":"no-store"},
});
Deno.serve(async req=>{
  if(req.method!=="POST")return reply({code:"METHOD"},405);
  try {
    const bearer=req.headers.get("authorization")??"";
    if(!bearer.startsWith("Bearer "))return reply({code:"AUTH"},401);
    const claims=await verifyPublisherJwt(bearer.slice(7));
    const raw=await req.text();
    if(raw.length>4096)return reply({code:"SIZE"},413);
    const body=JSON.parse(raw||"{}");
    const url=Deno.env.get("SUPABASE_URL")??"";
    const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
    const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
    let {data:bucket}=await admin.storage.getBucket(MODEL.bucket);
    if(!bucket){
      const created=await admin.storage.createBucket(MODEL.bucket,{
        public:false,allowedMimeTypes:["application/octet-stream","application/json"],
      });
      if(created.error)return reply({code:"BUCKET"},503);
      ({data:bucket}=await admin.storage.getBucket(MODEL.bucket));
    }
    if(!bucket||bucket.public)return reply({code:"BUCKET_POLICY"},503);
    if(body.action==="grant"){
      const {data,error}=await admin.storage.from(MODEL.bucket).createSignedUploadUrl(MODEL.object);
      if(error||!data)return reply({code:"UPLOAD_GRANT"},503);
      return reply({bucket:MODEL.bucket,object:MODEL.object,token:data.token,
        endpoint:url.replace(".supabase.co",".storage.supabase.co")+"/storage/v1/upload/resumable",
        sha256:MODEL.sha256,bytes:MODEL.bytes});
    }
    if(body.action==="readback"){
      const {data,error}=await admin.storage.from(MODEL.bucket).createSignedUrl(MODEL.object,3600);
      if(error||!data)return reply({code:"READBACK"},503);
      return reply({downloadUrl:data.signedUrl,bytes:MODEL.bytes,sha256:MODEL.sha256});
    }
    if(body.action==="complete"){
      if(body.sha256!==MODEL.sha256||body.bytes!==MODEL.bytes||body.rangeVerified!==true)
        return reply({code:"PROOF"},400);
      const head=await fetch(url+"/storage/v1/object/authenticated/"+MODEL.bucket+"/"+MODEL.object,{
        method:"HEAD",headers:{authorization:"Bearer "+service,apikey:service},
        signal:AbortSignal.timeout(10000),
      });
      if(!head.ok||Number(head.headers.get("content-length"))!==MODEL.bytes)
        return reply({code:"OBJECT_SIZE"},503);
      const receipt={schema:"pandora.model-distribution-receipt.v1",sha256:MODEL.sha256,bytes:MODEL.bytes,
        distributionVerified:true,rangeVerified:true,sourceSha:claims.sha,workflowRunId:claims.run_id,
        workflowRunAttempt:claims.run_attempt,verifiedAt:new Date().toISOString(),physicalPhoneVerified:false};
      const {error}=await admin.storage.from(MODEL.bucket).upload(MODEL.sha256+"/distribution.json",
        new Blob([JSON.stringify(receipt)],{type:"application/json"}),{upsert:true,contentType:"application/json"});
      if(error)return reply({code:"RECEIPT"},503);
      return reply({recorded:true,physicalPhoneVerified:false});
    }
    return reply({code:"ACTION"},400);
  }catch(_){return reply({code:"AUTH_OR_PROVIDER"},401);}
});
