"use strict";
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {readFileSync}=require("node:fs");
const path=require("node:path"),vm=require("node:vm"),ts=require("typescript");
function load(name,extra={}){
 const filename=path.resolve(__dirname,"../supabase/functions/pandora-intelligence-chat",name);
 const source=ts.transpileModule(readFileSync(filename,"utf8"),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
 const exports={};vm.runInNewContext(source,{exports,require:x=>load(path.basename(x),extra),TextEncoder,TextDecoder,ReadableStream,Response,Request,AbortController,AbortSignal,setInterval,clearInterval,...extra},{filename});return exports;
}
const {ReplyDeltaDecoder}=load("chat-stream.ts");
const {ReplyVisibilityGuard,sanitizeVisibleReply}=load("reply-safety.ts");
const cleanPrefix='{"intent":"chat","confidence":0.98,"needsClarification":false,"clarifyingQuestion":null,"handoff":null,"toolProposals":[],"memoryCandidates":[],"reply":';
const client={rpc:async()=>({data:{ticket:"a".repeat(64)}})};
const frame=event=>'data: '+JSON.stringify(event)+'\n\n';
function sse(body){return new Response(body,{headers:{"content-type":"text/event-stream"}});}
function assertTransport(error,kind="provider_unavailable"){
 assert.equal(error.message,"PROVIDER_UNAVAILABLE");assert.equal(error.code,kind);assert.equal(error.retryable,true);assert.equal(error.crossProviderEligible,true);return true;
}
for(const stage of ["before a delta","after a delta"]){
 test(`caller cancellation ${stage} is cancelled rather than a numeric DOMException code`,async()=>{
   const caller=new AbortController();let deltas=0;
   const {bedrockCall}=load("bedrock.ts",{fetch:async(_url,options)=>sse(new ReadableStream({start(c){
     options.signal.addEventListener("abort",()=>c.error(options.signal.reason),{once:true});
     if(stage==="before a delta")caller.abort();else c.enqueue(new TextEncoder().encode(frame({type:"delta",text:"part"})));
   }}))});
   await assert.rejects(bedrockCall(client,"fixture",{},{stream:true,signal:caller.signal,onDelta:async()=>{deltas++;caller.abort();}}),e=>{
     assert.equal(e.message,"REQUEST_CANCELLED");assert.equal(e.code,undefined);assert.equal(e.retryable,undefined);return true;
   });assert.equal(deltas,stage==="before a delta"?0:1);
 });
 test(`deadline ${stage} receives a timeout classification`,async()=>{
   const deadline=new AbortController();let deltas=0;
   const {bedrockCall}=load("bedrock.ts",{AbortSignal:{timeout:()=>deadline.signal,any:signals=>AbortSignal.any(signals)},fetch:async(_url,options)=>sse(new ReadableStream({start(c){
     options.signal.addEventListener("abort",()=>c.error(options.signal.reason),{once:true});
     if(stage==="before a delta")deadline.abort(new DOMException("Synthetic deadline","TimeoutError"));else c.enqueue(new TextEncoder().encode(frame({type:"delta",text:"part"})));
   }}))});
   await assert.rejects(bedrockCall(client,"fixture",{},{stream:true,onDelta:async()=>{deltas++;deadline.abort(new DOMException("Synthetic deadline","TimeoutError"));}}),e=>assertTransport(e,"timeout"));
   assert.equal(deltas,stage==="before a delta"?0:1);
 });
}
test("malformed, invalid and truncated SSE failures are classified and never return raw parser input",async()=>{
 const cases=[
   ['data: {"synthetic-private-parser-input":oops}\n\n',"PROVIDER_STREAM_INVALID"],
   [frame({type:"unknown"}),"PROVIDER_STREAM_INVALID"],
   [frame({type:"delta",text:42}),"PROVIDER_STREAM_INVALID"],
   [frame({type:"delta",text:"part"}),"PROVIDER_STREAM_TRUNCATED"],
   ['data: {"type":"delta"}',"PROVIDER_STREAM_TRUNCATED"],
   ['',"PROVIDER_STREAM_TRUNCATED"],
 ];
 for(const [wire,diagnostic]of cases){
   const {bedrockCall}=load("bedrock.ts",{fetch:async()=>sse(wire)});
   await assert.rejects(bedrockCall(client,"fixture",{},{stream:true}),e=>{
     assertTransport(e);assert.equal(e.transportCode,diagnostic);assert.doesNotMatch(String(e),/synthetic-private-parser-input/);return true;
   });
 }
});
test("mid-stream read failure is normalized and buffered body cancellation shares the cancellation boundary",async()=>{
 const {bedrockCall}=load("bedrock.ts",{fetch:async()=>sse(new ReadableStream({start(c){c.error(new TypeError("Synthetic socket closed"));}}))});
 await assert.rejects(bedrockCall(client,"fixture",{},{stream:true}),assertTransport);
 const caller=new AbortController();const buffered=load("bedrock.ts",{fetch:async(_url,options)=>new Response(new ReadableStream({start(c){
   options.signal.addEventListener("abort",()=>c.error(options.signal.reason),{once:true});caller.abort();
 }}))});
 await assert.rejects(buffered.bedrockCall(client,"fixture",{},{signal:caller.signal}),/REQUEST_CANCELLED/);
});
test("classified provider failure retains retry policy and sanitized receipt",async()=>{
 const receipt={providerRequestId:"synthetic-request",providerHttpStatus:403,providerLatencyMs:17,timeToFirstTokenMs:null};
 const {bedrockCall}=load("bedrock.ts",{fetch:async()=>sse(frame({type:"failed",error:{kind:"authorization",retryable:false},...receipt}))});
 await assert.rejects(bedrockCall(client,"fixture",{},{stream:true}),e=>{
   assert.equal(e.code,"authentication_failed");assert.equal(e.retryable,false);assert.equal(e.crossProviderEligible,true);
   for(const[key,value]of Object.entries(receipt))assert.equal(e[key],value);return true;
 });
});
test("downstream generation, privacy and persistence failures cannot become provider fallback",async()=>{
 for(const code of ["CHAT_GENERATION_STALE","INVALID_MODEL_OUTPUT","BACKEND_WRITE_FAILED","CREDENTIAL_MATERIAL_REJECTED"]){
   const original=Error(code),{bedrockCall}=load("bedrock.ts",{fetch:async()=>sse(frame({type:"delta",text:"part"}))});
   await assert.rejects(bedrockCall(client,"fixture",{},{stream:true,onDelta:async()=>{throw original;}}),e=>{assert.equal(e,original);assert.equal(e.crossProviderEligible,undefined);return true;});
 }
});
test("incremental decoder preserves nested, escaped-key and Unicode boundaries at every split",()=>{
 const reply=' A quoted "value", backslash \\, newline\n and 🚀 with é. ';
 const body='{"nested":{"reply":"hidden"},'+cleanPrefix.slice(1).replace('"reply":','"re\\u0070ly":')+JSON.stringify(reply)+'}';
 for(let split=0;split<=body.length;split++){
   const decoder=new ReplyDeltaDecoder(true);assert.equal(decoder.push(body.slice(0,split))+decoder.push(body.slice(split)),reply);assert.equal(decoder.visibleText,reply);
 }
 for(const raw of ['\\uD83D\\uDE80','🚀']){
   const decoder=new ReplyDeltaDecoder(true);let visible="";
   for(const char of (cleanPrefix+'"'+raw+'"}').split("")){const delta=decoder.push(char);assert.equal(/[\ud800-\udbff]$/.test(delta),false);visible+=delta;}
   assert.equal(visible,"🚀");
 }
 for(const raw of ['\\uD83Dx','\\uDE80','\\q','\ud83dx','\ude80'])assert.throws(()=>new ReplyDeltaDecoder(true).push(cleanPrefix+'"'+raw+'"}'),/INVALID_MODEL_OUTPUT/);
});
test("reply metadata is parsed once even for a 30 KB reply in single-character fragments",()=>{
 let parses=0;const tracked={parse:value=>{parses++;return JSON.parse(value);}};
 const {ReplyDeltaDecoder:Decoder}=load("chat-stream.ts",{JSON:tracked});const decoder=new Decoder(true);
 const reply="Ordinary safe reply. ".repeat(1500),body=cleanPrefix+JSON.stringify(reply)+'}';let output="";
 for(const char of body)output+=decoder.push(char);
 assert.equal(output,reply);assert.equal(parses,1);
});
test("long fragmented stream scans bounded visibility windows and does not rescan prior JSON metadata",()=>{
 let scanned=0,parses=0;
 const measuredJSON={parse:value=>{parses++;return JSON.parse(value);},stringify:value=>{if(typeof value==="string")scanned+=value.length;return JSON.stringify(value);}};
 const {ReplyDeltaDecoder:Decoder}=load("chat-stream.ts",{JSON:measuredJSON});
 const {ReplyVisibilityGuard:Guard}=load("reply-safety.ts",{JSON:measuredJSON});
 const reply="Safe conversational text. ".repeat(1200).trim(),body=cleanPrefix+JSON.stringify(reply)+'}';
 const decoder=new Decoder(true),guard=new Guard();const fragments=[];
 for(const char of body){const text=decoder.push(char);if(text)fragments.push(guard.push(text));}
 const partial=fragments.join("");assert.ok(partial.length>reply.length/2&&partial.length<reply.length);
 assert.equal(partial+guard.finish(reply),reply);assert.equal(parses,1);
 // Instrument the existing full-value credential boundary: at most the new
 // character plus 96 overlap characters, and one final whole-value check.
 assert.ok(scanned<=reply.length*98,`scanned ${scanned} characters for ${reply.length} input characters`);
});
test("visibility is identical to final normalization across whitespace, CRLF and surrogate splits",()=>{
 const raw=' \n First paragraph 🚀. '+"ordinary text ".repeat(30)+'\r\n\r\n\r\n  Second paragraph. '+"more text ".repeat(20)+'  \r\n';
 const expected=sanitizeVisibleReply(raw);
 for(const width of [1,2,7,97,4096]){
   const guard=new ReplyVisibilityGuard();let output="";
   for(let i=0;i<raw.length;i+=width){const delta=guard.push(raw.slice(i,i+width));assert.equal(/[\ud800-\udbff]$/.test(delta),false);output+=delta;}
   assert.equal(output+guard.finish(expected),expected);
 }
});
test("late private JSON keys and split private-context prefixes cannot escape the visibility boundary",()=>{
 const safe="A public paragraph. ".repeat(15).trim(),privateJson='{"detail":"'+"synthetic-private-value ".repeat(20)+'","surface":"enterprise_overview"}',raw=safe+'\n'+privateJson;
 const guard=new ReplyVisibilityGuard();let output="";for(const char of raw)output+=guard.push(char);
 assert.doesNotMatch(output,/synthetic-private-value|enterprise_overview/);assert.equal(output+guard.finish(sanitizeVisibleReply(raw)),safe);
 for(const hidden of ['Bounded enterprise page context: hidden fixture','The authenticated actorrole is authoritative. hidden fixture','Never map roles across identityscope namespaces. hidden fixture']){
   for(let cut=1;cut<hidden.length;cut++){
     const g=new ReplyVisibilityGuard();let visible=g.push(safe+'\n'+hidden.slice(0,cut));visible+=g.push(hidden.slice(cut));
     assert.doesNotMatch(visible,/hidden fixture|Bounded|authenticated actorrole|identityscope/);assert.equal(visible+g.finish(safe),safe);
   }
 }
});
test("credential prefixes after public output remain hidden across every boundary",()=>{
 const prefix="This public explanation is safe. ".repeat(12),synthetic="gh"+"p_"+"synthetic-not-a-real-token".replaceAll("-","").repeat(3);
 for(let cut=1;cut<synthetic.length;cut++){
   const guard=new ReplyVisibilityGuard();let visible=guard.push(prefix);
   try{visible+=guard.push(synthetic.slice(0,cut));visible+=guard.push(synthetic.slice(cut));}catch(e){assert.match(e.message,/INVALID_MODEL_OUTPUT/);}
   assert.ok(prefix.startsWith(visible));assert.doesNotMatch(visible,/ghp_|synthetic/);assert.throws(()=>guard.finish(prefix+synthetic),/INVALID_MODEL_OUTPUT/);
 }
});
test("long whitespace runs normalize once without losing conversational spacing",()=>{
 const raw="First"+" ".repeat(25000)+"second\n\n\nthird",guard=new ReplyVisibilityGuard();let visible="";
 for(let i=0;i<raw.length;i++)visible+=guard.push(raw[i]);
 assert.equal(visible+guard.finish(sanitizeVisibleReply(raw)),sanitizeVisibleReply(raw));
});
test("incremental input limits remain enforced even when output is held or already decoded",()=>{
 const decoder=new ReplyDeltaDecoder(true);decoder.push(cleanPrefix+'"done"}');assert.throws(()=>decoder.push(" ".repeat(262144)),/INVALID_MODEL_OUTPUT/);
 const held=new ReplyDeltaDecoder(true);held.push('{"reply":"buffered"}');assert.throws(()=>held.push(" ".repeat(262144)),/INVALID_MODEL_OUTPUT/);
 const guard=new ReplyVisibilityGuard();guard.push("ghp_placeholder");assert.throws(()=>guard.push(" ".repeat(32000)),/INVALID_MODEL_OUTPUT/);
});
