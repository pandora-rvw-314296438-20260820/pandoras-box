const VERSION_RE = /^[0-9]+\.[0-9]+\.[0-9]+$/;
const KEY_RE = /^[a-z][a-z0-9_.-]{1,127}$/;
const CAP_RE = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/;

function assertObject(value,label){
  if(!value || Array.isArray(value) || typeof value!=="object") throw new TypeError(label+" must be an object");
}
function assertString(value,label,re){
  if(typeof value!=="string" || !value.length || (re && !re.test(value))) throw new TypeError(label+" is invalid");
}
function clone(value){ return structuredClone(value); }

export function validateProviderManifest(manifest){
  assertObject(manifest,"manifest");
  assertString(manifest.providerKey,"providerKey",KEY_RE);
  assertString(manifest.manifestVersion,"manifestVersion",VERSION_RE);
  assertString(manifest.displayName,"displayName");
  assertString(manifest.authScheme,"authScheme");
  if(!Array.isArray(manifest.regions) || manifest.regions.length===0) throw new TypeError("regions required");
  if(!Array.isArray(manifest.dataResidency) || manifest.dataResidency.length===0) throw new TypeError("dataResidency required");
  assertObject(manifest.dataHandling,"dataHandling");
  assertObject(manifest.deprecationPolicy,"deprecationPolicy");
  assertString(manifest.runbookRef,"runbookRef");
  assertString(manifest.escalationRef,"escalationRef");
  if(!Array.isArray(manifest.capabilities) || manifest.capabilities.length===0) throw new TypeError("capabilities required");

  const seen=new Set();
  for(const cap of manifest.capabilities){
    assertObject(cap,"capability");
    assertString(cap.capabilityKey,"capabilityKey",CAP_RE);
    assertString(cap.capabilityVersion,"capabilityVersion",VERSION_RE);
    if(!["read","write"].includes(cap.operationMode)) throw new TypeError("operationMode invalid");
    assertString(cap.adapterVersion,"adapterVersion",VERSION_RE);
    if(!Array.isArray(cap.evidenceModes)) throw new TypeError("evidenceModes required");
    const id=cap.capabilityKey+"@"+cap.capabilityVersion;
    if(seen.has(id)) throw new TypeError("duplicate capability "+id);
    seen.add(id);
    if(cap.operationMode==="write"){
      assertString(cap.idempotencyStrategy,"idempotencyStrategy");
      if(cap.evidenceModes.length===0) throw new TypeError("write capability requires evidenceModes");
    }
  }
  return Object.freeze(clone(manifest));
}

export function defineProviderAdapter({manifest,handlers}){
  const frozenManifest=validateProviderManifest(manifest);
  assertObject(handlers,"handlers");
  const declared=new Map(frozenManifest.capabilities.map(c=>[c.capabilityKey+"@"+c.capabilityVersion,c]));

  for(const key of Object.keys(handlers)){
    if(!declared.has(key)) throw new TypeError("handler not declared in manifest: "+key);
    if(typeof handlers[key]!=="function") throw new TypeError("handler must be a function: "+key);
  }

  return Object.freeze({
    manifest:frozenManifest,
    async invoke(request,runtime={}){
      assertObject(request,"request");
      assertString(request.requestId,"requestId");
      assertString(request.capabilityKey,"capabilityKey",CAP_RE);
      assertString(request.capabilityVersion,"capabilityVersion",VERSION_RE);
      const id=request.capabilityKey+"@"+request.capabilityVersion;
      const cap=declared.get(id);
      if(!cap) throw new Error("capability_not_declared");
      const handler=handlers[id];
      if(!handler) throw new Error("capability_not_implemented");
      if(cap.operationMode==="write") assertString(request.idempotencyKey,"idempotencyKey");
      if("database" in runtime || "supabase" in runtime || "sql" in runtime){
        throw new Error("provider_sdk_direct_enterprise_database_access_forbidden");
      }
      const safeRuntime=Object.freeze({
        transport:runtime.transport,
        evidence:runtime.evidence,
        clock:runtime.clock || (()=>new Date()),
        signal:runtime.signal
      });
      const result=await handler(Object.freeze(clone(request)),safeRuntime);
      assertObject(result,"adapter result");
      return Object.freeze(clone(result));
    }
  });
}

export function buildProviderReceipt({
  requestId,providerKey,capabilityKey,capabilityVersion,adapterVersion,
  providerOperationId,accepted,evidenceRefs=[],readback=null
}){
  assertString(requestId,"requestId");
  assertString(providerKey,"providerKey",KEY_RE);
  assertString(capabilityKey,"capabilityKey",CAP_RE);
  assertString(capabilityVersion,"capabilityVersion",VERSION_RE);
  assertString(adapterVersion,"adapterVersion",VERSION_RE);
  if(typeof accepted!=="boolean") throw new TypeError("accepted must be boolean");
  if(!Array.isArray(evidenceRefs)) throw new TypeError("evidenceRefs must be an array");
  return Object.freeze({
    schemaVersion:1,
    requestId,providerKey,capabilityKey,capabilityVersion,adapterVersion,
    providerOperationId:providerOperationId ?? null,
    accepted,
    verificationState:readback ? "evidence_available" : "pending_verification",
    evidenceRefs:clone(evidenceRefs),
    readback:readback ? clone(readback) : null
  });
}
