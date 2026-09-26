
import {exact,normalizeContextRequest,requireThat,MemoryIntegrationError,serialized} from './contracts.mjs';
export const OPERATIONS_MEMORY_MAPPING=Object.freeze({
 organizationId:'2270b266-59da-4c39-bfd9-9f8d08352af0',projectId:'ee282126-3f61-4058-8c92-2fedbfcecf1f',
 memoryProjectRef:'ivmvufhcsezyhczzondn',memoryProjectId:'7c686cbd-d968-49d5-86cc-918f5e777bd2',
 memoryUserId:'0a436417-517f-461f-819f-08f66899cdda',namespace:'real_life',principalKey:'pandora-mcpmaster-production',environment:'production',
});
/** Read-only owner entrypoint; it cannot submit, approve or invent an outcome. */
export function createOwnerMemoryRead({authenticator,membershipResolver,memory}) {
 requireThat(typeof authenticator?.authenticate==='function'&&typeof membershipResolver?.resolve==='function'
   &&typeof memory?.getTaskContext==='function'&&typeof memory?.getPerformance==='function','OPS_MEMORY_OWNER_CONFIGURATION_REQUIRED');
 return async (authorization,body)=>{
   exact(body,['operation','request']);serialized(body,8192);requireThat(['context','performance'].includes(body.operation),'OPS_MEMORY_OWNER_OPERATION_DENIED');
   requireThat(typeof authorization==='string'&&!/Bearer\s+pmt_v1_/i.test(authorization),'OPS_MEMORY_OWNER_AUTH_REQUIRED');
   const identity=await authenticator.authenticate(authorization);
   requireThat(identity?.userId&&identity.accessToken&&identity.scopeClaimsPresent!==true,'OPS_MEMORY_OWNER_AUTH_REQUIRED');
   const m=OPERATIONS_MEMORY_MAPPING;
   const membership=await membershipResolver.resolve(m.organizationId,identity.userId,identity.accessToken);
   requireThat(membership?.organizationId===m.organizationId&&membership.userId===identity.userId&&['owner','admin'].includes(membership.role),'OPS_MEMORY_OWNER_SCOPE_DENIED');
   const scope={organizationId:m.organizationId,projectId:m.projectId};
   const value=body.operation==='context'?await memory.getTaskContext(scope,normalizeContextRequest(body.request)):
     await memory.getPerformance(scope,body.request);
   // A role revoked during a potentially slow provider read must not receive that reply.
   const current=await membershipResolver.resolve(m.organizationId,identity.userId,identity.accessToken);
   requireThat(current?.organizationId===m.organizationId&&current.userId===identity.userId&&['owner','admin'].includes(current.role),'OPS_MEMORY_OWNER_SCOPE_DENIED');
   return {ok:true,operation:body.operation,organizationId:m.organizationId,projectId:m.projectId,authorizationGranted:false,data:value};
 };
}
