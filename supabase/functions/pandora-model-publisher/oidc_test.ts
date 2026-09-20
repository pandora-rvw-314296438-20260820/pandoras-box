import {verifyPublisherJwt} from "./oidc.ts";
const encode=(v:Uint8Array)=>btoa(String.fromCharCode(...v)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const json=(v:unknown)=>encode(new TextEncoder().encode(JSON.stringify(v)));
const repository="pandora-rvw-314296438-20260820/pandoras-box";
const ref="refs/heads/fix/phone-private-model-lifecycle-20260920";
Deno.test("publisher rejects forged, expired, cross-repository and wrong-ref identities",async()=>{
 const pair=await crypto.subtle.generateKey({name:"RSASSA-PKCS1-v1_5",modulusLength:2048,
   publicExponent:new Uint8Array([1,0,1]),hash:"SHA-256"},true,["sign","verify"]) as CryptoKeyPair;
 const key=await crypto.subtle.exportKey("jwk",pair.publicKey);
 const fetcher=(async()=>new Response(JSON.stringify({keys:[{...key,kid:"test"}]}))) as typeof fetch;
 const now=Math.floor(Date.now()/1000);
 const claims={iss:"https://token.actions.githubusercontent.com",aud:"pandora-model-publisher",
   repository,repository_id:"1345495177",ref,workflow_ref:repository+"/.github/workflows/plp-pandora-enterprise-android.yml@"+ref,
   event_name:"workflow_dispatch",iat:now,exp:now+300,sha:"a".repeat(40),run_id:"1234",run_attempt:"1"};
 async function token(change:Record<string,unknown>={}){
   const body=json({alg:"RS256",kid:"test"})+"."+json({...claims,...change});
   return body+"."+encode(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",pair.privateKey,new TextEncoder().encode(body))));
 }
 const accepted=await verifyPublisherJwt(await token(),fetcher);
 if(accepted.run_id!=="1234")throw Error("valid identity rejected");
 for(const delta of [{repository:"other/repo"},{repository_id:"1"},{ref:"refs/heads/main"},
   {exp:now-1},{aud:"wrong"},{event_name:"pull_request"},{workflow_ref:"wrong"}]){
   let denied=false;
   try{await verifyPublisherJwt(await token(delta),fetcher);}catch(_){denied=true;}
   if(!denied)throw Error("untrusted identity accepted");
 }
 const forged=(await token()).split(".");
 forged[1]=json({...claims,repository:"other/repo"});
 let denied=false;
 try{await verifyPublisherJwt(forged.join("."),fetcher);}catch(_){denied=true;}
 if(!denied)throw Error("forged identity accepted");
});
