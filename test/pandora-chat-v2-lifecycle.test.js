"use strict";
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {randomUUID}=require("node:crypto");
const {PGlite}=require("@electric-sql/pglite");
const sql=p=>readFileSync(join(__dirname,p),"utf8");
const org=randomUUID(),otherOrg=randomUUID(),owner=randomUUID(),other=randomUUID();
let db;
async function actor(user=owner,role="authenticated"){
 await db.exec("reset role");await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,role})]);
 assert.ok(["authenticated","service_role","anon"].includes(role));await db.exec("set role "+role);
}
async function query(q,a=[]){return(await db.query(q,a)).rows[0]?.r;}
async function admitted(options={}){
 const turn=options.turn??randomUUID(),attempt=options.attempt??randomUUID(),fingerprint=options.fingerprint??"a".repeat(64);
 await actor();
 const r=await query("select public.pandora_chat_turn_admit_v2($1,$2,$3,$4,$5,$6,null,'[]',null,$7) r",[org,turn,attempt,fingerprint,options.message??"Hi",options.thread??null,JSON.stringify(options.history??[])]);
 return{...r,fingerprint};
}
async function claim(t){
 await actor(null,"service_role");const id=randomUUID();
 const r=await query("select public.pandora_activity_execution_claim_v1($1,$2,$3) r",[t.activityJobId,t.fingerprint,id]);
 return{...t,claim:id,claimResult:r};
}
async function transition(t,status="processing",retryable=false){
 await actor(null,"service_role");return query("select public.pandora_chat_turn_transition_v2($1,$2,$3,$4,$5,null,$6,$7,'{}',null) r",
 [t.turnId,t.attemptId,t.generation,t.claim,status,status.startsWith("failed")?"provider_unavailable":null,retryable]);
}
async function finish(t,reply="A continuous conversation"){
 await actor(null,"service_role");return query("select public.pandora_chat_turn_complete_v2($1,$2,$3,$4,$5,'{}',99,'{"+'"providerStartMs":14'+"}') r",
 [t.turnId,t.attemptId,t.generation,t.claim,{reply,routing:{requestedSelection:"auto",executedModel:"fixture"}}]);
}
async function fail(t,{ambiguous=false}={}){
 await actor(null,"service_role");
 if(ambiguous)await query("select public.pandora_activity_execution_checkpoint_v1($1,$2,'capability_dispatching',null,'ambiguous',null) r",[t.activityJobId,t.claim]);
 return transition(t,"failed_recoverably",true);
}
async function retry(t,{id=randomUUID(),expected=t.generation,fingerprint=t.fingerprint}={}){
 await actor();const r=await query("select public.pandora_chat_turn_retry_v2($1,$2,$3,$4,$5,null) r",[org,t.turnId,id,expected,fingerprint]);return{...r,fingerprint};
}
async function counts(){await db.exec("reset role");return(await db.query("select (select count(*) from public.pandora_chat_turns)::int turns,(select count(*) from public.pandora_intelligence_threads)::int threads,(select count(*) from public.pandora_intelligence_messages where author_role='user')::int users,(select count(*) from public.pandora_intelligence_messages where author_role='assistant')::int assistants,(select count(*) from public.pandora_activity_jobs)::int jobs")).rows[0];}
async function rejects(action,pattern=/CHAT_|ACCESS|permission/i){
 await db.exec("savepoint expected_rejection");try{await assert.rejects(action,pattern);}finally{await db.exec("rollback to savepoint expected_rejection;release savepoint expected_rejection");}
}
test.before(async()=>{
 db=new PGlite();await db.exec(sql("fixtures/pandora-chat-v2-schema.sql"));
 await db.exec(sql("../supabase/migrations/20260915013000_pandora_activity_recovery_v1.sql"));
 await db.exec(sql("../supabase/migrations/20261003170000_pandora_chat_turn_lifecycle_v2.sql"));
 await db.query("insert into auth.users values($1),($2)",[owner,other]);await db.query("insert into public.organizations values($1),($2)",[org,otherOrg]);
 await db.query("insert into public.memberships values($1,$3,'owner','active'),($2,$4,'owner','active')",[org,otherOrg,owner,other]);
});
test.after(async()=>{await db?.close();});
test.beforeEach(async()=>{await db.exec("reset role;begin");});
test.afterEach(async()=>{await db.exec("rollback;reset role");});

test("lost acceptance ACK and duplicate delivery retain one thread, user message and Activity job",async()=>{
 const t=await admitted();const again=await admitted({turn:t.turnId,attempt:t.attemptId});
 assert.equal(again.replayed,true);assert.equal(again.threadId,t.threadId);assert.equal(again.userMessageId,t.userMessageId);
 assert.deepEqual(await counts(),{turns:1,threads:1,users:1,assistants:0,jobs:1});
 const first=await claim(t),second=await claim(t);assert.equal(first.claimResult.mode,"execute");assert.equal(second.claimResult.mode,"observe");
});
test("identity collision cannot alter immutable request or create an extra row",async()=>{
 const t=await admitted();await rejects(()=>admitted({turn:t.turnId,attempt:t.attemptId,fingerprint:"b".repeat(64)}),/IDEMPOTENCY_CONFLICT/);
 await rejects(()=>admitted({turn:t.turnId,attempt:randomUUID()}),/IDEMPOTENCY_CONFLICT/);assert.equal((await counts()).users,1);
});
test("generation sequence is monotonic and completion is atomic with the original Activity claim",async()=>{
 const t=await claim(await admitted());let r=await transition(t);assert.equal(r.status,"processing");
 r=await transition(t,"streaming");assert.equal(r.status,"streaming");assert.ok(r.sequence>2);
 const done=await finish(t);assert.equal(done.status,"completed");assert.equal(done.sequence,99);assert.equal(done.timings.providerStartMs,14);
 const again=await finish(t,"Obsolete callback");assert.equal(again.reply,done.reply);assert.equal(again.assistantMessageId,done.assistantMessageId);
 await db.exec("reset role");const job=await query("select execution_result r from public.pandora_activity_jobs where id=$1",[t.activityJobId]);assert.equal(job.reply,done.reply);
 assert.equal((await counts()).assistants,1);
});
test("new turn waits for active execution then uses the same continuous thread",async()=>{
 const a=await claim(await admitted({message:"Hi"}));await transition(a);
 await rejects(()=>admitted({thread:a.threadId,message:"Hello"}),/THREAD_BUSY/);
 await finish(a,"Hi—what are we working on?");const b=await claim(await admitted({thread:a.threadId,message:"Hello"}));await finish(b,"Still here. What would you like to do?");
 assert.equal(b.threadId,a.threadId);assert.equal(b.turnSequence,2);assert.deepEqual(await counts(),{turns:2,threads:1,users:2,assistants:2,jobs:2});
});
test("recoverable retry keeps the original user message and rejects a late old-generation completion",async()=>{
 const a=await claim(await admitted());assert.equal((await fail(a)).status,"failed_recoverably");
 const b=await claim(await retry(a));assert.equal(b.userMessageId,a.userMessageId);assert.equal(b.generation,2);assert.notEqual(b.activityJobId,a.activityJobId);
 await rejects(()=>finish(a),/GENERATION_STALE/);await finish(b);assert.equal((await counts()).users,1);assert.equal((await counts()).assistants,1);
});
test("a lost retry ACK replays the same attempt and never increments generation twice",async()=>{
 const a=await claim(await admitted());await fail(a);const next=randomUUID();const b=await retry(a,{id:next}),again=await retry(a,{id:next});
 assert.equal(again.replayed,true);assert.equal(again.attemptId,b.attemptId);assert.equal(again.generation,2);assert.equal((await counts()).jobs,2);
});
test("ambiguous side effects require reconciliation; retry cannot dispatch another action",async()=>{
 const a=await claim(await admitted());const failed=await fail(a,{ambiguous:true});assert.equal(failed.status,"outcome_unknown");assert.equal(failed.retryable,false);
 await rejects(()=>retry(a),/RECONCILIATION_REQUIRED/);assert.equal((await counts()).jobs,1);
});
test("cancellation fences stale success and permits an immediate following logical turn",async()=>{
 const a=await claim(await admitted());await transition(a);await actor();const r=await query("select public.pandora_chat_turn_cancel_v2($1,$2,1) r",[org,a.turnId]);assert.equal(r.status,"cancelled");
 await rejects(()=>finish(a),/GENERATION_STALE/);const b=await claim(await admitted({thread:a.threadId,message:"Continue"}));await finish(b);assert.equal((await counts()).assistants,1);
 await db.exec("reset role");assert.equal((await db.query("select count(*)::int n from public.pandora_activity_controls where control_type='cancel'")).rows[0].n,1);
});
test("later successful turn resolves obsolete failure presentation while preserving its error audit",async()=>{
 const a=await claim(await admitted());await fail(a);const b=await claim(await admitted({thread:a.threadId,message:"What can you do for me?"}));await finish(b);
 await actor();const old=await query("select public.pandora_chat_turn_read_v2($1,$2) r",[org,a.turnId]);assert.equal(old.status,"superseded");assert.equal(old.supersededBy,b.turnId);assert.equal(old.errorCode,"provider_unavailable");
});
test("legacy deterministic dispatcher binds its assistant and cannot duplicate the accepted user row",async()=>{
 const a=await claim(await admitted({message:"Capability fixture"}));await transition(a);await actor();
 const d=await query("select public.pandora_chat_dispatch_turn_v2($1,$2,$3,1,$4,$5) r",[org,a.turnId,a.attemptId,a.claim,"Capability fixture"]);assert.equal(d.handled,true);
 const done=await finish(a,"Fixture result");assert.ok(done.assistantMessageId);assert.deepEqual(await counts(),{turns:1,threads:1,users:1,assistants:1,jobs:1});
 await db.exec("reset role");assert.equal((await db.query("select count(*)::int n from private.pandora_chat_dispatch_context_v2")).rows[0].n,0);
});
test("unhandled dispatch leaves no messages or private transaction context behind",async()=>{
 const a=await claim(await admitted({message:"unhandled"}));await transition(a);await actor();
 const d=await query("select public.pandora_chat_dispatch_turn_v2($1,$2,$3,1,$4,'unhandled') r",[org,a.turnId,a.attemptId,a.claim]);assert.equal(d.handled,false);assert.equal((await counts()).assistants,0);
});
test("another actor/org cannot read, retry, cancel, dispatch or overwrite a turn",async()=>{
 const a=await claim(await admitted());await actor(other);
 for(const[q,args]of[["select public.pandora_chat_turn_read_v2($1,$2)",[org,a.turnId]],
 ["select public.pandora_chat_turn_cancel_v2($1,$2,1)",[org,a.turnId]],
 ["select public.pandora_chat_turn_retry_v2($1,$2,$3,1,$4)",[org,a.turnId,randomUUID(),a.fingerprint]],
 ["select public.pandora_chat_dispatch_turn_v2($1,$2,$3,1,$4,'fixture')",[org,a.turnId,a.attemptId,a.claim]]])await rejects(()=>db.query(q,args),/NOT_AVAILABLE/);
 const visible=await db.query("select * from public.pandora_chat_turns");assert.equal(visible.rows.length,0);
 await rejects(()=>db.query("update public.pandora_chat_turn_attempts set status='completed' where id=$1",[a.attemptId]),/permission/);
});
test("public callers cannot use internal finalization or forge dispatcher transaction context",async()=>{
 const a=await claim(await admitted());await actor();
 await rejects(()=>db.query("select public.pandora_chat_turn_complete_v2($1,$2,1,$3,'{\"reply\":\"forged\"}')",[a.turnId,a.attemptId,a.claim]),/permission/);
 await rejects(()=>db.query("insert into private.pandora_chat_dispatch_context_v2 values(txid_current(),$1,$2,1,$3)",[a.turnId,a.attemptId,a.claim]),/permission/);
});
test("display history retains owned failures while provider history excludes obsolete failed requests",async()=>{
 const a=await claim(await admitted({message:"Failed request"}));await fail(a);
 const b=await claim(await admitted({thread:a.threadId,message:"Successful request"}));await finish(b,"Successful reply");await actor();
 const view=await query("select public.pandora_chat_thread_view_v2($1) r",[a.threadId]);assert.equal(view.messages.length,3);assert.equal(view.turns.length,2);
 assert.equal(view.messages[0].chat_turn_id,a.turnId);assert.equal(view.messages[0].status,"superseded");assert.equal(view.turns[0].errorCode,"provider_unavailable");
 const provider=await query("select public.pandora_chat_history_v2($1) r",[a.threadId]);assert.deepEqual(provider.map(x=>x.content),["Successful request","Successful reply"]);
 assert.equal(JSON.stringify(view).includes(a.fingerprint),false);assert.equal(JSON.stringify(view).includes(a.claim),false);
});
test("recovered retry occupies its original logical position rather than response-arrival order",async()=>{
 const a=await claim(await admitted({message:"First"}));await fail(a);const b=await claim(await admitted({thread:a.threadId,message:"Second"}));await finish(b,"Second reply");
 const recovered=await claim(await retry(a));await finish(recovered,"First reply, recovered");await actor();
 const history=await query("select public.pandora_chat_history_v2($1) r",[a.threadId]);assert.deepEqual(history.map(x=>x.content),["First","First reply, recovered","Second","Second reply"]);
});
test("local completed pairs import once with declared client provenance and never claim execution proof",async()=>{
 const id=randomUUID(),history=[{logicalTurnId:id,source:"local_device",role:"user",content:"On-device question"},{logicalTurnId:id,source:"local_device",role:"assistant",content:"On-device answer"}];
 const a=await claim(await admitted({history}));await finish(a);const b=await claim(await admitted({thread:a.threadId,message:"Cloud follow-up",history}));await finish(b);
 assert.equal((await counts()).users,3);assert.equal((await counts()).assistants,3);await actor();
 const view=await query("select public.pandora_chat_thread_view_v2($1) r",[a.threadId]);assert.equal(view.messages[0].client_history_turn_id,id);assert.equal(view.messages[0].client_origin,"local_device");
 await db.exec("reset role");const provenance=await query("select structured_response r from public.pandora_intelligence_messages where client_history_turn_id=$1 limit1".replace("limit1","limit 1"),[id]);assert.equal(provenance.executionVerified,false);
 await rejects(()=>admitted({thread:a.threadId,history:[history[0],{...history[1],content:"Forged update"}]}),/HISTORY_CONFLICT/);
});
test("readback distinguishes an absent admission from an accepted/unknown request",async()=>{
 await actor();const r=await query("select public.pandora_chat_turn_read_v2($1,$2) r",[org,randomUUID()]);assert.equal(r.found,false);
 const a=await admitted();await actor();assert.equal((await query("select public.pandora_chat_turn_read_v2($1,$2) r",[org,a.turnId])).found,true);
});
test("expired unclaimed admission is proven unexecuted and safely retryable",async()=>{
 const a=await admitted();await db.exec("reset role");await db.query("update public.pandora_chat_turn_attempts set accepted_at=now()-interval '4 minutes' where id=$1",[a.attemptId]);
 await actor(null,"service_role");const r=await query("select public.pandora_chat_turn_reconcile_v2($1) r",[a.turnId]);assert.equal(r.status,"failed_recoverably");assert.equal(r.errorCode,"CHAT_ADMISSION_INTERRUPTED");assert.equal(r.retryable,true);
 const next=await retry(a);assert.equal(next.generation,2);assert.equal(next.userMessageId,a.userMessageId);
});
test("readback finalizes a verified original capability result without executing or duplicating it",async()=>{
 const a=await claim(await admitted({message:"Capability fixture"}));await transition(a);await actor();
 const result=await query("select public.pandora_chat_dispatch_turn_v2($1,$2,$3,1,$4,'Capability fixture') r",[org,a.turnId,a.attemptId,a.claim]);
 await actor(null,"service_role");await query("select public.pandora_activity_execution_checkpoint_v1($1,$2,'result_persisted',null,'verified',$3) r",[a.activityJobId,a.claim,result]);
 const r=await query("select public.pandora_chat_turn_reconcile_v2($1) r",[a.turnId]);assert.equal(r.status,"completed");assert.equal(r.reply,"Fixture result");assert.equal((await counts()).assistants,1);
});
test("cancellation arriving after verified effects yields to original verified readback",async()=>{
 const a=await claim(await admitted());await transition(a);await actor(null,"service_role");await query("select public.pandora_activity_execution_checkpoint_v1($1,$2,'result_persisted',null,'verified',$3) r",[a.activityJobId,a.claim,{reply:"Already executed",providerReadback:{verified:true}}]);
 await actor();const cancelled=await query("select public.pandora_chat_turn_cancel_v2($1,$2,1) r",[org,a.turnId]);assert.equal(cancelled.status,"outcome_unknown");
 await actor(null,"service_role");const reconciled=await query("select public.pandora_chat_turn_reconcile_v2($1) r",[a.turnId]);assert.equal(reconciled.status,"completed");assert.equal(reconciled.reply,"Already executed");
});
test("server lifecycle refuses a processing regression after visible streaming",async()=>{
 const a=await claim(await admitted());await transition(a);await transition(a,"streaming");await rejects(()=>transition(a,"processing"),/TRANSITION_INVALID/);
});
test("multiple local pairs preserve order under the actual production now() message default",async()=>{
 const ids=[randomUUID(),randomUUID()],history=ids.flatMap((id,i)=>[{logicalTurnId:id,source:"local_device",role:"user",content:`Pair ${i+1} user`},{logicalTurnId:id,source:"local_device",role:"assistant",content:`Pair ${i+1} assistant`}]);
 const a=await claim(await admitted({history}));await finish(a);await actor();const r=await query("select public.pandora_chat_history_v2($1) r",[a.threadId]);
 assert.deepEqual(r.slice(0,4).map(x=>x.content),history.map(x=>x.content));const view=await query("select public.pandora_chat_thread_view_v2($1) r",[a.threadId]);assert.deepEqual(view.messages.slice(0,4).map(x=>x.client_history_order),[1,2,3,4]);
});
test("cancellation wins the atomic effect-start fence before any external mutation is admitted",async()=>{
 const a=await claim(await admitted());await transition(a);await actor();await query("select public.pandora_chat_turn_cancel_v2($1,$2,1) r",[org,a.turnId]);await actor(null,"service_role");
 await rejects(()=>query("select public.pandora_chat_turn_effect_v2($1,$2,1,$3,'begin') r",[a.turnId,a.attemptId,a.claim]),/STALE/);
 const job=await query("select execution_effect_state r from public.pandora_activity_jobs where id=$1",[a.activityJobId]);assert.equal(job,"none");
});
test("effect-start wins first: cancellation reports unknown until the original verified response arrives",async()=>{
 const a=await claim(await admitted());await transition(a);await actor(null,"service_role");await query("select public.pandora_chat_turn_effect_v2($1,$2,1,$3,'begin') r",[a.turnId,a.attemptId,a.claim]);
 await actor();const cancelled=await query("select public.pandora_chat_turn_cancel_v2($1,$2,1) r",[org,a.turnId]);assert.equal(cancelled.status,"outcome_unknown");await rejects(()=>retry(a),/RECONCILIATION_REQUIRED/);
 await actor(null,"service_role");await query("select public.pandora_chat_turn_effect_v2($1,$2,1,$3,'verified',$4) r",[a.turnId,a.attemptId,a.claim,{reply:"The requested change was completed",providerReadback:{verified:true}}]);
 const recovered=await query("select public.pandora_chat_turn_reconcile_v2($1) r",[a.turnId]);assert.equal(recovered.status,"completed");assert.equal((await counts()).assistants,1);
});
test("v2 failure finalizes the original Activity atomically and a late failure cannot reverse completion",async()=>{
 const a=await claim(await admitted());await transition(a);const failed=await transition(a,"failed_recoverably",true);
 assert.equal(failed.status,"failed_recoverably");await actor(null,"service_role");assert.equal(await query("select execution_state r from public.pandora_activity_jobs where id=$1",[a.activityJobId]),"failed");
 const b=await claim(await retry(a));const completed=await finish(b,"Recovered once");const late=await transition(b,"failed_recoverably",true);
 assert.equal(late.status,"completed");assert.equal(late.reply,completed.reply);assert.equal(late.applied,false);await actor(null,"service_role");
 assert.equal(await query("select execution_state r from public.pandora_activity_jobs where id=$1",[b.activityJobId]),"complete");assert.equal((await counts()).assistants,1);
});
test("cancellation before initial admission leaves a durable tombstone and no synthetic conversation or execution",async()=>{
 const turnId=randomUUID(),attemptId=randomUUID();await actor();
 const cancelled=await query("select public.pandora_chat_turn_cancel_v2($1,$2,1,$3) r",[org,turnId,attemptId]);
 assert.equal(cancelled.status,"cancelled");assert.equal(cancelled.admitted,false);assert.equal(cancelled.admissionCancelled,true);assert.equal(cancelled.threadId,null);
 assert.equal(cancelled.activityJobId,null);assert.equal(cancelled.userMessageId,null);assert.equal(cancelled.attemptId,attemptId);assert.equal(cancelled.sequence,1);
 const readback=await query("select public.pandora_chat_turn_read_v2($1,$2) r",[org,turnId]);assert.deepEqual(readback,cancelled);
 const late=await admitted({turn:turnId,attempt:attemptId});assert.equal(late.status,"cancelled");assert.equal(late.admitted,false);
 assert.deepEqual(await counts(),{turns:0,threads:0,users:0,assistants:0,jobs:0});
});
test("admission winning first keeps its true identity and is cancelled without a second execution",async()=>{
 const a=await admitted();await actor();const cancelled=await query("select public.pandora_chat_turn_cancel_v2($1,$2,1,$3) r",[org,a.turnId,a.attemptId]);
 assert.equal(cancelled.status,"cancelled");assert.equal(cancelled.threadId,a.threadId);assert.equal(cancelled.userMessageId,a.userMessageId);assert.equal(cancelled.admissionCancelled,undefined);
 const late=await admitted({turn:a.turnId,attempt:a.attemptId});assert.equal(late.status,"cancelled");await actor(null,"service_role");
 assert.equal(await query("select execution_state r from public.pandora_activity_jobs where id=$1",[a.activityJobId]),"cancelled");assert.equal((await counts()).jobs,1);
});
test("absent-admission cancellation requires the original first attempt and cannot cross actor or organization",async()=>{
 const turnId=randomUUID(),attemptId=randomUUID();await actor();
 await rejects(()=>query("select public.pandora_chat_turn_cancel_v2($1,$2,1) r",[org,turnId]),/ATTEMPT_REQUIRED/);
 await rejects(()=>query("select public.pandora_chat_turn_cancel_v2($1,$2,2,$3) r",[org,turnId,attemptId]),/ATTEMPT_REQUIRED/);
 await query("select public.pandora_chat_turn_cancel_v2($1,$2,1,$3) r",[org,turnId,attemptId]);
 await rejects(()=>query("select public.pandora_chat_turn_cancel_v2($1,$2,1,$3) r",[org,turnId,randomUUID()]),/IDEMPOTENCY_CONFLICT/);
 await rejects(()=>admitted({turn:turnId,attempt:randomUUID()}),/IDEMPOTENCY_CONFLICT/);
 await actor(other);await rejects(()=>query("select public.pandora_chat_turn_read_v2($1,$2) r",[otherOrg,turnId]),/NOT_AVAILABLE/);
 await rejects(()=>query("select public.pandora_chat_turn_cancel_v2($1,$2,1,$3) r",[otherOrg,turnId,attemptId]),/NOT_AVAILABLE/);
 await rejects(()=>db.query("select * from private.pandora_chat_admission_tombstones_v2"),/permission denied/);
});
test("unadmitted retry can be cancelled without original request bytes and late retry cannot create a job",async()=>{
 const a=await claim(await admitted());await fail(a);const pendingAttempt=randomUUID();await actor();
 const cancelled=await query("select public.pandora_chat_turn_cancel_v2($1,$2,2,$3) r",[org,a.turnId,pendingAttempt]);
 assert.equal(cancelled.status,"cancelled");assert.equal(cancelled.admissionCancelled,true);assert.equal(cancelled.admitted,false);
 assert.equal(cancelled.generation,2);assert.equal(cancelled.currentGeneration,2);assert.equal(cancelled.sequence,1);assert.equal(cancelled.attemptId,pendingAttempt);
 assert.equal(cancelled.threadId,a.threadId);assert.equal(cancelled.userMessageId,a.userMessageId);assert.equal(cancelled.activityJobId,null);
 const readback=await query("select public.pandora_chat_turn_read_v2($1,$2) r",[org,a.turnId]);assert.equal(readback.attemptId,pendingAttempt);assert.equal(readback.status,"cancelled");
 const late=await retry(a,{id:pendingAttempt});assert.equal(late.admissionCancelled,true);assert.equal(late.status,"cancelled");
 await rejects(()=>retry(a,{id:randomUUID()}),/RECONCILIATION_REQUIRED/);
 assert.deepEqual(await counts(),{turns:1,threads:1,users:1,assistants:0,jobs:1});await actor();
 const view=await query("select public.pandora_chat_thread_view_v2($1) r",[a.threadId]);assert.equal(view.turns[0].status,"cancelled");assert.equal(view.turns[0].attemptId,pendingAttempt);assert.equal(view.messages[0].status,"cancelled");assert.equal(view.messages[0].retryable,false);
 await db.exec("reset role");const audit=(await db.query("select status,error_code from public.pandora_chat_turn_attempts where id=$1",[a.attemptId])).rows[0];assert.equal(audit.status,"failed_recoverably");assert.equal(audit.error_code,"provider_unavailable");
 const next=await admitted({thread:a.threadId,message:"Continue with a new turn"});assert.equal(next.threadId,a.threadId);assert.equal(next.turnSequence,2);
});
test("retry admission winning first cancels the actual second generation instead of inventing a negative receipt",async()=>{
 const a=await claim(await admitted());await fail(a);const retryTurn=await retry(a);await actor();
 const cancelled=await query("select public.pandora_chat_turn_cancel_v2($1,$2,2,$3) r",[org,a.turnId,retryTurn.attemptId]);
 assert.equal(cancelled.status,"cancelled");assert.equal(cancelled.admissionCancelled,undefined);assert.equal(cancelled.activityJobId,retryTurn.activityJobId);assert.equal(cancelled.generation,2);
 assert.equal((await counts()).jobs,2);assert.equal((await counts()).users,1);
});
test("negative retry cancellation cannot skip generations or obscure ambiguous original effects",async()=>{
 const a=await claim(await admitted());await fail(a,{ambiguous:true});await actor();
 await rejects(()=>query("select public.pandora_chat_turn_cancel_v2($1,$2,2,$3) r",[org,a.turnId,randomUUID()]),/RECONCILIATION_REQUIRED/);
 await rejects(()=>query("select public.pandora_chat_turn_cancel_v2($1,$2,3,$3) r",[org,a.turnId,randomUUID()]),/GENERATION_STALE/);
 await db.exec("reset role");assert.equal(await query("select count(*)::integer r from private.pandora_chat_admission_tombstones_v2"),0);
});
test("UI history restores bounded readonly inspection metadata while excluding mutations and internal payloads",async()=>{
 const a=await claim(await admitted());await finish(a);await db.exec("reset role");
 const handoff={required:true,kind:"core_navigation",source:"core_navigation",action:"inspect",request:"Inspect client records",section:"clients",organizationId:org};
 for(const [content,value] of [["Readonly",handoff],["Mutation",{...handoff,action:"create_client"}],["Wrong kind",{...handoff,kind:"capability_request"}],["Invalid scope",{...handoff,organizationId:"not-a-scope"}]]){
   await db.query("insert into public.pandora_intelligence_messages(thread_id,organization_id,author_role,content,structured_response) values($1,$2,'assistant',$3,$4)",[a.threadId,org,content,{handoff:{...value,internalTrace:"must stay internal"},routing:{privateMetadata:"not projected"},enterpriseContext:{actorRole:"owner"}}]);
 }
 await actor();const view=await query("select public.pandora_chat_thread_view_v2($1) r",[a.threadId]);
 const row=view.messages.find(x=>x.content==="Readonly");assert.deepEqual(row.structured_response,{handoff});
 for(const content of ["Mutation","Wrong kind","Invalid scope"])assert.deepEqual(view.messages.find(x=>x.content===content).structured_response,{});
 assert.equal(JSON.stringify(view.messages).includes("must stay internal"),false);assert.equal(JSON.stringify(view.messages).includes("privateMetadata"),false);
});
