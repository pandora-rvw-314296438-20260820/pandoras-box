
import {exact,normalizeContextRequest,requireThat,MemoryIntegrationError,serialized} from './contracts.mjs';

const CORE_SUPABASE_URL = 'https://jcyqixttuebxqqfkjonq.supabase.co';
const CORE_AUTHORIZATION_URL = `${CORE_SUPABASE_URL}/rest/v1/rpc/pandora_core_authorize_memory_v1`;
const JWT_SHAPE = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const authorizationUnavailable = () => new MemoryIntegrationError('OPS_MEMORY_OWNER_AUTHORIZATION_UNAVAILABLE');

async function readAuthorization(response, signal) {
  const declared = response.headers.get('content-length');
  if ((declared !== null && (!/^[0-9]+$/.test(declared) || Number(declared) > 256)) || !response.body?.getReader) {
    void response.body?.cancel().catch(() => {});
    throw authorizationUnavailable();
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8', {fatal:true});
  let size = 0, text = '';
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', cancel, {once:true});
  try {
    while (true) {
      if (signal.aborted) throw authorizationUnavailable();
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > 256) {
        cancel();
        throw authorizationUnavailable();
      }
      text += decoder.decode(chunk.value, {stream:true});
    }
    text += decoder.decode();
    return JSON.parse(text);
  } finally {
    signal.removeEventListener('abort', cancel);
    try { reader.releaseLock(); } catch {}
  }
}

/** Fixed, caller-JWT authorization. It never receives a service credential or caller-selected scope. */
export class CoreOwnerMemoryAuthorizer {
  #publishableKey; #fetch; #timeoutMs;

  constructor({supabaseUrl, publishableKey, fetchFn = globalThis.fetch, timeoutMs = 6000}) {
    requireThat(supabaseUrl === CORE_SUPABASE_URL
      && typeof publishableKey === 'string' && publishableKey.length <= 512
      && /^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(publishableKey)
      && typeof fetchFn === 'function'
      && Number.isSafeInteger(timeoutMs) && timeoutMs >= 1 && timeoutMs <= 10000,
    'OPS_MEMORY_OWNER_CONFIGURATION_REQUIRED');
    this.#publishableKey = publishableKey;
    this.#fetch = fetchFn;
    this.#timeoutMs = timeoutMs;
  }

  async authorize(accessToken) {
    requireThat(typeof accessToken === 'string' && accessToken.length >= 20 && accessToken.length <= 8192
      && JWT_SHAPE.test(accessToken), 'OPS_MEMORY_OWNER_AUTH_REQUIRED');
    const controller = new AbortController();
    let timer;
    const deadline = new Promise((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(authorizationUnavailable());
      }, this.#timeoutMs);
    });
    try {
      return await Promise.race([(async () => {
        const response = await this.#fetch(CORE_AUTHORIZATION_URL, {
          method:'POST', redirect:'error', signal:controller.signal,
          headers:{apikey:this.#publishableKey, authorization:`Bearer ${accessToken}`,
            'content-type':'application/json', accept:'application/json'},
          body:'{}',
        });
        if (!response.ok) {
          // Do not read or forward provider diagnostics, including authorization errors.
          void response.body?.cancel().catch(() => {});
          if ([401,403].includes(response.status)) throw new MemoryIntegrationError('OPS_MEMORY_OWNER_SCOPE_DENIED');
          throw authorizationUnavailable();
        }
        const allowed = await readAuthorization(response, controller.signal);
        requireThat(allowed === true, 'OPS_MEMORY_OWNER_SCOPE_DENIED');
        return true;
      })(), deadline]);
    } catch (error) {
      if (error instanceof MemoryIntegrationError && error.code === 'OPS_MEMORY_OWNER_SCOPE_DENIED') throw error;
      throw authorizationUnavailable();
    } finally {
      clearTimeout(timer);
    }
  }
}

export const OPERATIONS_MEMORY_MAPPING=Object.freeze({
 organizationId:'2270b266-59da-4c39-bfd9-9f8d08352af0',projectId:'ee282126-3f61-4058-8c92-2fedbfcecf1f',
 memoryProjectRef:'ivmvufhcsezyhczzondn',memoryProjectId:'7c686cbd-d968-49d5-86cc-918f5e777bd2',
 memoryUserId:'0a436417-517f-461f-819f-08f66899cdda',namespace:'real_life',principalKey:'pandora-mcpmaster-production',environment:'production',
});
/** Read-only owner entrypoint; it cannot submit, approve or invent an outcome. */
export function createOwnerMemoryRead({authenticator,coreAuthorizer,memory}) {
 requireThat(typeof authenticator?.authenticate==='function'&&typeof coreAuthorizer?.authorize==='function'
   &&typeof memory?.getTaskContext==='function'&&typeof memory?.getPerformance==='function','OPS_MEMORY_OWNER_CONFIGURATION_REQUIRED');
 return async (authorization,body)=>{
   exact(body,['operation','request']);serialized(body,8192);requireThat(['context','performance'].includes(body.operation),'OPS_MEMORY_OWNER_OPERATION_DENIED');
   const bearer=typeof authorization==='string'?/^Bearer\s+([^\s]+)$/i.exec(authorization.trim()):null;
   // Shape is only an early rejection. Supabase still authenticates the actual user token.
   requireThat(bearer&&bearer[1].length>=20&&bearer[1].length<=8192&&JWT_SHAPE.test(bearer[1]),'OPS_MEMORY_OWNER_AUTH_REQUIRED');
   const identity=await authenticator.authenticate(authorization);
   requireThat(identity?.userId&&identity.accessToken===bearer[1]&&identity.scopeClaimsPresent!==true,'OPS_MEMORY_OWNER_AUTH_REQUIRED');
   const m=OPERATIONS_MEMORY_MAPPING;
   requireThat(await coreAuthorizer.authorize(identity.accessToken)===true,'OPS_MEMORY_OWNER_SCOPE_DENIED');
   const scope={organizationId:m.organizationId,projectId:m.projectId};
   const value=body.operation==='context'?await memory.getTaskContext(scope,normalizeContextRequest(body.request)):
     await memory.getPerformance(scope,body.request);
   // Revalidate explicit Core authority after the provider call; revoked grants never release the reply.
   requireThat(await coreAuthorizer.authorize(identity.accessToken)===true,'OPS_MEMORY_OWNER_SCOPE_DENIED');
   return {ok:true,operation:body.operation,organizationId:m.organizationId,projectId:m.projectId,authorizationGranted:false,data:value};
 };
}
