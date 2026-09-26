import {normalizeRequest,selectCandidates,sha256} from '../policy.mjs';
import {createInferenceHandler} from '../http-handler.mjs';
import {GeminiNativeProvider} from '../gemini-native.mjs';
const check=(condition,message)=>{if(!condition)throw new Error(message);};
Deno.test('runtime uses explicit Node buffer and crypto on Deno without ambient Node globals',()=>{
 const r=normalizeRequest({requestId:'00000000-0000-4000-8000-000000000001',taskId:'TASK',leaseId:'00000000-0000-4000-8000-000000000002',generation:1,sourceSha:'a'.repeat(40),taskClass:'complex_coding',parts:[{type:'text',text:'café'}],maxOutputTokens:128,maxCostMicros:100,deadlineMs:1000});
 check(r.textBytes===5,'UTF-8 byte ceiling');check(r.inputBytes===5,'payload ceiling');check(r.requestDigest.length===64,'request hash');
});
Deno.test('runtime returns denial before untrusted unauthenticated body or store access',async()=>{
 let calls=0;const handler=createInferenceHandler({store:{durability:'durable',authenticate(){calls++;throw new Error('must not run');}},serviceForActor(){throw new Error('must not run');},authenticateOwner(){throw new Error('must not run');},allowedOrigins:['https://owner.example.test']});
 const response=await handler(new Request('https://example.test/functions/v1/pandora-intelligence-router/infer',{method:'POST',headers:{'content-type':'application/json'},body:'{}'}));check(response.status===401,'auth denial');check(calls===0,'no provider access');
});
Deno.test('runtime concrete provider preserves actual response digest and unknown billing',async()=>{
 const provider=new GeminiNativeProvider({supabaseUrl:'https://jcyqixttuebxqqfkjonq.supabase.co',rpc:async()=>({data:{status:200,body:{candidates:[{finishReason:'STOP',content:{parts:[{text:'fixture'}]}}]}},error:null})});
 const r=await provider.execute({taskClass:'complex_coding',parts:[{type:'text',text:'fixture'}],maxOutputTokens:128,deadlineMs:1000,memoryContext:''},{provider:'gemini',transport:'gemini_rpc',executionBoundary:'cloud',model:'fixture-only',modelRevision:null});
 check(r.output==='fixture','actual output');check(r.receipt.outputDigest===sha256('fixture'),'output digest');check(r.receipt.billedCostMicros===null,'unknown cost');
});
