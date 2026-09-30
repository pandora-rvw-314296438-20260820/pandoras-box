import { validateProviderManifest } from "./index.mjs";

function clone(value){ return structuredClone(value); }
function check(name,pass,detail=""){ return Object.freeze({name,pass:pass===true,detail:String(detail||"")}); }

export async function runProviderConformanceSuite({adapter,baseRequest,probes={}}){
  if(!adapter || typeof adapter.invoke!=="function") throw new TypeError("adapter.invoke required");
  if(!baseRequest || typeof baseRequest!=="object") throw new TypeError("baseRequest required");

  const checks=[];
  try{ validateProviderManifest(adapter.manifest); checks.push(check("manifest",true,"valid")); }
  catch(error){ checks.push(check("manifest",false,error?.message)); }

  try{
    await adapter.invoke({...clone(baseRequest),capabilityVersion:"0.0.0"},{});
    checks.push(check("version",false,"undeclared version executed"));
  }catch(error){
    checks.push(check("version",error?.message==="capability_not_declared",error?.message));
  }

  const declared=adapter.manifest.capabilities.find(
    cap=>cap.capabilityKey===baseRequest.capabilityKey && cap.capabilityVersion===baseRequest.capabilityVersion
  );
  if(declared?.operationMode==="write"){
    const request=clone(baseRequest);
    delete request.idempotencyKey;
    try{ await adapter.invoke(request,{}); checks.push(check("idempotency",false,"missing idempotency executed")); }
    catch(error){ checks.push(check("idempotency",/idempotencyKey/.test(error?.message||""),error?.message)); }
  }else checks.push(check("idempotency",true,"read capability"));

  try{
    await adapter.invoke(clone(baseRequest),{database:{}});
    checks.push(check("database_boundary",false,"direct database access accepted"));
  }catch(error){
    checks.push(check(
      "database_boundary",
      error?.message==="provider_sdk_direct_enterprise_database_access_forbidden",
      error?.message
    ));
  }

  for(const name of ["auth","retry","evidence","error","health"]){
    const probe=probes[name];
    if(typeof probe!=="function"){ checks.push(check(name,false,"required probe missing")); continue; }
    try{
      const value=await probe(adapter,clone(baseRequest));
      if(value && typeof value==="object") checks.push(check(name,value.pass===true,value.detail||""));
      else checks.push(check(name,value===true,value===true?"pass":"probe returned false"));
    }catch(error){
      checks.push(check(name,false,error?.message||"probe threw"));
    }
  }

  return Object.freeze({
    schemaVersion:1,
    providerKey:adapter.manifest.providerKey,
    manifestVersion:adapter.manifest.manifestVersion,
    pass:checks.every(item=>item.pass),
    checks:Object.freeze(checks)
  });
}
