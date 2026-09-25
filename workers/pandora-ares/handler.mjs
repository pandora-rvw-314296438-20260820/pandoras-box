import {AresHost} from './host.mjs';
import {AresError,demand,exact,integer,publicError} from './contract.mjs';

async function body(request,limit,timeoutMs) {
  const size=request.headers.get('content-length');
  demand(size===null || (/^[0-9]+$/.test(size) && Number(size)<=limit),'ARES_BODY_LIMIT');
  demand(request.body,'ARES_BODY_REQUIRED');
  const reader=request.body.getReader(),chunks=[];let length=0,timer;
  try {
    const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new AresError('ARES_BODY_TIMEOUT')),timeoutMs);});
    while(true) {
      const item=await Promise.race([reader.read(),deadline]);if(item.done)break;
      length+=item.value.byteLength;demand(length<=limit,'ARES_BODY_LIMIT');chunks.push(Buffer.from(item.value));
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch(error) {void reader.cancel().catch(()=>{});throw error;}
  finally {clearTimeout(timer);reader.releaseLock();}
}

/** Mount only in an authorized outbound-relay or protected node service, never a public shell. */
export function createAresHandler({host,maxConcurrent=4,bodyTimeoutMs=5000}) {
  demand(host instanceof AresHost,'ARES_HOST_REQUIRED');
  integer(maxConcurrent,1,16);integer(bodyTimeoutMs,50,10000);let active=0;
  return async request=>{
    const headers={'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'};
    const response=(status,value)=>new Response(JSON.stringify(value),{status,headers});
    if(request.method!=='POST')return response(405,{ok:false,code:'ARES_POST_REQUIRED'});
    if(request.headers.has('origin'))return response(403,{ok:false,code:'ARES_BROWSER_ACCESS_DENIED'});
    if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')return response(415,{ok:false,code:'ARES_JSON_REQUIRED'});
    if(active>=maxConcurrent)return response(429,{ok:false,code:'ARES_HOST_CAPACITY'});
    active++;
    try {
      const input=await body(request,48000,bodyTimeoutMs);exact(input,['job','grantToken']);
      demand(input.job && typeof input.grantToken==='string','ARES_SIGNED_PROOF_REQUIRED');
      // Host independently validates the signed exact action and fresh control-plane lease.
      const result=await host.execute(input.job,input.grantToken,{signal:request.signal});
      return response(result.state==='executed_and_read_back'?200:202,{ok:true,result});
    } catch(error) {
      const code=publicError(error),status=/BODY_LIMIT/.test(code)?413:/PROOF|SIGNATURE|SIGNER|SCOPE|LEASE|AUTHORIZ|APPROVAL|BROWSER/.test(code)?403:400;
      return response(status,{ok:false,code});
    } finally {active--;}
  };
}
