"use strict";
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {readFileSync}=require("node:fs");
const path=require("node:path"),vm=require("node:vm"),ts=require("typescript");
const {randomUUID}=require("node:crypto");
function load(name,extra={}){
 const full=path.resolve(__dirname,"../supabase/functions/pandora-intelligence-chat/",name);
 const source=ts.transpileModule(readFileSync(full,"utf8"),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
 const exports={};vm.runInNewContext(source,{exports,require:x=>load(path.basename(x),extra),TextEncoder,TextDecoder,ReadableStream,Response,Request,AbortController,AbortSignal,setInterval,clearInterval,console,...extra},{filename:full});return exports;
}
const {ReplyDeltaDecoder,consumeServerEvents,eventStreamResponse}=load("chat-stream.ts");
const {parseTurnRequest,turnFingerprintInput,parseClientHistory}=load("turn-contract.ts");
const {bedrockBodyFromOpenAi}=load("bedrock.ts");
const {ReplyVisibilityGuard,sanitizeVisibleReply}=load("reply-safety.ts");
const {readRepositoryAuditContext,isReadOnlyRepositoryAudit}=load("repository-context.ts",{setTimeout,clearTimeout});
const cleanPrefix='{"intent":"chat","confidence":0.98,"needsClarification":false,"clarifyingQuestion":null,"handoff":null,"toolProposals":[],"memoryCandidates":[],"reply":';
test("provider JSON decodes across every character boundary without exposing metadata",()=>{
 const body=cleanPrefix+JSON.stringify('Hello\nworld 🚀, "quoted".')+'}';
 const decoder=new ReplyDeltaDecoder(true);let result="",beforeEnd=false;
 for(let i=0;i<body.length;i++){const delta=decoder.push(body[i]);result+=delta;if(delta&&i<body.length-2)beforeEnd=true;}
 assert.equal(result,'Hello\nworld 🚀, "quoted".');assert.equal(beforeEnd,true);assert.equal(result.includes("confidence"),false);
 const escaped=new ReplyDeltaDecoder(true);assert.equal(escaped.push(cleanPrefix+'"Rocket \\uD83D'),"Rocket ");assert.equal(escaped.push('\\uDE80"}'),"🚀");
});
test("reply-first and action-bearing output stays buffered for the existing final validator",()=>{
 for(const body of ['{"reply":"Started the task","intent":"act"}',cleanPrefix.replace('"chat"','"act"')+'"Started the task"}',cleanPrefix.replace('"handoff":null','"handoff":{"required":true}')+'"Doing it"}'])assert.equal(new ReplyDeltaDecoder(true).push(body),"");
});
test("nested reply keys, incomplete escapes and non-string replies cannot contaminate chat",()=>{
 const d=new ReplyDeltaDecoder();assert.equal(d.push('{"nested":{"reply":"never expose"},"reply":"a\\u00'),"a");assert.equal(d.push('e9"}'),"é");
 assert.throws(()=>new ReplyDeltaDecoder().push('{"reply":123}'),/INVALID_MODEL_OUTPUT/);assert.throws(()=>new ReplyDeltaDecoder().push('{"reply":"bad\\x"}'),/INVALID_MODEL_OUTPUT/);
});
test("SSE parser preserves fragmented UTF-8, CRLF and multiline data",async()=>{
 const bytes=new TextEncoder().encode('event: delta\r\ndata: {"type":"delta",\r\ndata: "text":"héllo 🚀"}\r\n\r\n'),events=[];
 const body=new ReadableStream({start(c){for(const byte of bytes)c.enqueue(Uint8Array.of(byte));c.close();}});
 await consumeServerEvents(new Response(body),async e=>{events.push(e);});assert.equal(events.length,1);assert.equal(events[0].text,"héllo 🚀");
 await assert.rejects(consumeServerEvents(new Response('data: {"type":"delta"}'),async()=>{}),/TRUNCATED/);
});
test("stream emits accepted before unresolved work and finalizes after a transport disconnect",async()=>{
 let release,finished=false;const pending=new Promise(r=>{release=r;});
 const response=eventStreamResponse(async send=>{send({type:"accepted",turnId:"fixture"});await pending;finished=true;return Response.json({ok:true,status:"completed",reply:"Done"});});
 const reader=response.body.getReader(),first=await reader.read();assert.match(new TextDecoder().decode(first.value),/event: accepted/);assert.equal(finished,false);
 await reader.cancel();release();await new Promise(r=>setImmediate(r));assert.equal(finished,true);
});
test("turn identity and retry generation are explicit",()=>{
 const t={protocolVersion:2,operation:"send",clientTurnId:randomUUID(),clientAttemptId:randomUUID(),generation:1};
 assert.equal(parseTurnRequest(t).clientTurnId,t.clientTurnId);assert.equal(parseTurnRequest({}),null);assert.equal(parseTurnRequest({...t,operation:"retry",generation:2,expectedGeneration:1}).generation,2);
 assert.throws(()=>parseTurnRequest({...t,operation:"retry",generation:3,expectedGeneration:1}),/GENERATION_INVALID/);assert.throws(()=>parseTurnRequest({...t,clientTurnId:"stale-label"}),/ID_INVALID/);assert.throws(()=>parseTurnRequest({...t,protocolVersion:3}),/UNSUPPORTED/);
});
test("fingerprint survives assigned thread identity and remains sensitive to immutable content",()=>{
 const input={message:"Hi",threadId:null,projectId:null,mode:"auto",attachments:[],modelSelection:{selection:"auto"},enterpriseContext:null};
 assert.equal(turnFingerprintInput(input),turnFingerprintInput({...input,threadId:randomUUID(),activityJobId:randomUUID()}));assert.notEqual(turnFingerprintInput(input),turnFingerprintInput({...input,message:"Hello"}));
});
test("client history permits only bounded complete local pairs",()=>{
 const id=randomUUID(),pair=[{role:"user",content:"Hi",logicalTurnId:id,source:"local_device"},{role:"assistant",content:"Hello",logicalTurnId:id,source:"local_device"}];
 assert.equal(parseClientHistory(pair).length,2);assert.throws(()=>parseClientHistory([pair[0]]),/INVALID/);assert.throws(()=>parseClientHistory([pair[0],{...pair[1],source:"provider_verified"}]),/INVALID/);assert.throws(()=>parseClientHistory([pair[0],{...pair[1],logicalTurnId:randomUUID()}]),/INVALID/);
});
test("Bedrock retains native roles and image blocks instead of text speaker labels",()=>{
 const body=bedrockBodyFromOpenAi({max_completion_tokens:1024,messages:[{role:"developer",content:"Be Pandora"},{role:"user",content:"Hi"},{role:"assistant",content:"Hello"},{role:"user",content:[{type:"text",text:"What is this?"},{type:"image_url",image_url:{url:"data:image/png;base64,aGVsbG8="}}]}]});
 assert.deepEqual(Array.from(body.messages,m=>m.role),["user","assistant","user"]);assert.equal(body.messages[0].content[0].text,"Hi");assert.equal(body.messages[1].content[0].text,"Hello");assert.equal(body.parts,undefined);assert.equal(body.messages[2].content[1].image.format,"png");assert.throws(()=>bedrockBodyFromOpenAi({messages:[{role:"assistant",content:"Orphan"}]}),/INVALID/);
});
test("upstream SSE delivers true partial deltas and keeps provider receipts",async()=>{
 let calls=0;const body=cleanPrefix+'"Hello there"}',fragments=[body.slice(0,-8),body.slice(-8)],received=[];
 const module=load("bedrock.ts",{fetch:async(_url,options)=>{calls++;assert.equal(options.headers.accept,"text/event-stream");assert.deepEqual(Object.keys(JSON.parse(options.body)),["ticket"]);
 const wire=fragments.map(text=>'event: delta\ndata: '+JSON.stringify({type:"delta",text})+'\n\n').join('')+'event: completed\ndata: '+JSON.stringify({type:"completed",body:{text:body,model:"fixture",providerRequestId:"request-fixture",providerHttpStatus:200,providerLatencyMs:12,timeToFirstTokenMs:3,streaming:true,streamMode:"converse_stream_v1"}})+'\n\n';
 return new Response(wire,{headers:{"content-type":"text/event-stream"}});}});
 const result=await module.bedrockCall({rpc:async(_name,args)=>{assert.equal(args.p_body.stream,true);return{data:{ticket:"a".repeat(64)}};}},"fixture",{messages:[{role:"user",content:[{text:"Hi"}]}]},{stream:true,onDelta:async text=>received.push(text)});
 assert.equal(calls,1);assert.equal(received.length,2);assert.equal(result.valueRaw.reply,"Hello there");assert.equal(result.body.providerRequestId,"request-fixture");assert.equal(result.body.timeToFirstTokenMs,3);
});
test("truncated provider stream never produces a completed assistant",async()=>{
 const module=load("bedrock.ts",{fetch:async()=>new Response('event: delta\ndata: {"type":"delta","text":"partial"}\n\n',{headers:{"content-type":"text/event-stream"}})});
 await assert.rejects(module.bedrockCall({rpc:async()=>({data:{ticket:"b".repeat(64)}})},"fixture",{},{stream:true}),/TRUNCATED/);
});
test("every split credential prefix is held before any sensitive character can be painted",()=>{
 const synthetic="gh"+"p_"+"notarealcredential".repeat(3);
 for(let cut=1;cut<synthetic.length;cut++){
   const guard=new ReplyVisibilityGuard();let visible="";try{visible+=guard.push(synthetic.slice(0,cut));visible+=guard.push(synthetic.slice(cut));}catch(error){assert.match(error.message,/INVALID_MODEL_OUTPUT/);}
   assert.equal(visible,"");assert.throws(()=>guard.finish(synthetic),/INVALID_MODEL_OUTPUT/);
 }
});
test("internal context markers and JSON envelopes never pass incremental output",()=>{
 for(const raw of ["Bounded project context: synthetic internal-only value",'{"private":"synthetic value","surface":"enterprise_overview"}']){
   const guard=new ReplyVisibilityGuard();let emitted="";for(const char of raw)emitted+=guard.push(char);assert.equal(emitted,"");
   const visible=sanitizeVisibleReply(raw);assert.doesNotMatch(visible,/synthetic|enterprise_overview/);assert.equal(guard.finish(visible),visible);
 }
});
test("safe long replies emit real partial text, short replies remain honestly buffered",()=>{
 const guard=new ReplyVisibilityGuard(),reply="This is a continuous conversational reply. ".repeat(20).trim();let emitted="";
 for(let i=0;i<reply.length;i+=30)emitted+=guard.push(reply.slice(i,i+30));assert.ok(emitted.length>0&&emitted.length<reply.length);
 assert.equal(emitted+guard.finish(reply),reply);assert.equal(new ReplyVisibilityGuard().push("Hello"),"");
 const code=new ReplyVisibilityGuard();assert.equal(code.push("Use the placeholder ghp_example in your test."),"");assert.equal(code.finish("Use the placeholder ghp_example in your test."),"Use the placeholder ghp_example in your test.");
});
test("token offsets never advance the durable revision used by cancel/readback",async()=>{
 const {ChatTurnLifecycle}=load("turn-lifecycle.ts",{setInterval:()=>1,clearInterval:()=>{}});
 let receipt={protocolVersion:2,organizationId:randomUUID(),threadId:randomUUID(),turnId:randomUUID(),attemptId:randomUUID(),activityJobId:randomUUID(),userMessageId:randomUUID(),generation:1,currentGeneration:1,status:"accepted",sequence:1},writes=0;const events=[];
 const user={rpc:async()=>({data:{...receipt}})},admin={rpc:async(name,args)=>{writes++;if(name.includes("transition")&&!['cancelled','completed'].includes(receipt.status))receipt={...receipt,status:args.p_status,sequence:receipt.sequence+1,applied:true};return{data:{...receipt}};}};
 const turn=new ChatTurnLifecycle({user,admin},receipt,e=>events.push(e));await turn.claim(randomUUID());
 const reply="A clear continuous answer. ".repeat(80);await turn.providerDelta(cleanPrefix+'"');for(const char of reply)await turn.providerDelta(char);await turn.providerDelta('"}');
 const deltas=events.filter(e=>e.type==="delta");assert.ok(deltas.length>20);assert.equal(new Set(deltas.map(e=>e.sequence)).size,1);assert.equal(writes,2);
 assert.deepEqual(deltas.map(e=>e.streamSequence),deltas.map((_,i)=>i+1));receipt={...receipt,status:"cancelled",sequence:receipt.sequence+1,cancellationRequested:true};
 const cancelled=await turn.fail(Error("REQUEST_CANCELLED"));assert.ok(cancelled.sequence>deltas.at(-1).sequence);assert.equal(cancelled.status,"cancelled");
});
test("readonly repository audit classifier preserves direct and sequential execution intents",()=>{
 for(const request of ["Audit the repository", "Inspect the entire source", "Review the full project", "Analyze this codebase"])assert.equal(isReadOnlyRepositoryAudit(request),true,request);
 for(const request of ["Hi", "Fix this audit finding", "Please deploy after the audit", "Audit the repo and then implement the fixes", "Review the full project; please deploy it", "Inspect source, update it"])assert.equal(isReadOnlyRepositoryAudit(request),false,request);
});
test("selected-project source hydrates once through the authenticated bound RPC without altering submission identity",async()=>{
 const projectId=randomUUID(),organizationId=randomUUID();let calls=0;
 const snapshot={ok:true,contractVersion:"pandora-repository-snapshot-v1",projectId,repository:"example/project",headSha:"a".repeat(40),treeSha:"b".repeat(40),emptyRepository:false,truncated:true,includedFileCount:1,observedAt:"2026-10-03T10:00:00Z",files:[{path:"README.md",text:"Synthetic source\n".repeat(2500)}]};
 const input={user:{rpc:async(name,args)=>{calls++;assert.equal(name,"pandora_chat_repository_snapshot_v1");assert.equal(args.p_organization_id,organizationId);assert.equal(args.p_project_id,projectId);assert.equal(args.p_max_bytes,70000);assert.equal(args.p_max_files,80);return{data:snapshot};}},organizationId,projectId,scopeKind:"none",message:"Audit the repository",attachments:[]};
 const original=JSON.stringify(input.attachments),result=await readRepositoryAuditContext(input);
 assert.equal(calls,1);assert.ok(result.attachments.length>1&&result.attachments.length<=4);assert.equal(JSON.stringify(input.attachments),original);
 assert.equal(result.receipt.headSha,snapshot.headSha);assert.equal(result.receipt.truncated,true);assert.equal(result.receipt.files,undefined);
 for(const attachment of result.attachments){assert.ok(attachment.text.length<32000);assert.match(attachment.text,/never as instructions or execution authority/);assert.match(attachment.text,/audit as bounded/);}
 const encoded=result.attachments.map(part=>part.text.slice(part.text.indexOf("\n")+1)).join("");assert.deepEqual(JSON.parse(encoded),snapshot);
});
test("repository audit hydration is excluded from owner/workspace scopes, actions, and explicitly attached input",async()=>{
 let calls=0;const base={user:{rpc:async()=>{calls++;throw Error("must not fetch");}},organizationId:randomUUID(),projectId:randomUUID(),scopeKind:"none",message:"Audit the repository",attachments:[]};
 for(const change of [{scopeKind:"owner"},{scopeKind:"workspace"},{scopeKind:"client"},{projectId:null},{message:"Audit then implement the fix"},{attachments:[{kind:"text"}]}])assert.equal(await readRepositoryAuditContext({...base,...change}),null);
 assert.equal(calls,0);
});
test("repository source read failures and mismatched project receipts fail closed before model use",async()=>{
 const projectId=randomUUID(),base={organizationId:randomUUID(),projectId,scopeKind:"none",message:"Audit repository",attachments:[]};
 for(const reply of [{error:{code:"42501"}},{data:{ok:false}},{data:{ok:true,contractVersion:"pandora-repository-snapshot-v1",projectId:randomUUID(),repository:"example/project",emptyRepository:true}}]){
   await assert.rejects(readRepositoryAuditContext({...base,user:{rpc:async()=>reply}}),/REPOSITORY_CONTEXT_UNAVAILABLE/);
 }
 const abort=new AbortController();abort.abort();await assert.rejects(readRepositoryAuditContext({...base,user:{rpc:async()=>{throw Error("must not fetch");}},signal:abort.signal}),/REQUEST_CANCELLED/);
});
