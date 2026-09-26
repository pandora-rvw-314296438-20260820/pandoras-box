const ID=/^[a-f0-9-]{36}$/;
const cursor=value=>typeof value==='string'&&/^(0|[1-9][0-9]{0,18})$/.test(value)&&BigInt(value)<=9223372036854775807n;
const requireThat=(ok,code)=>{if(!ok)throw new Error(code);};
const labels=Object.freeze({task_claimed:'Task claimed',dispatch_prepared:'Worker dispatch prepared',worker_started:'Worker execution acknowledged',resource_released:'Task resource settlement recorded',worker_trigger_queued:'Worker trigger queued; acknowledgement pending',inference_preparation_recovered:'Unsent inference preparation fenced and recovered',owner_pause:'Operations paused',owner_resume:'Operations resumed',owner_no_production:'Production execution disabled',owner_cancel_task:'Task cancellation requested',tasks_ingested:'Tasks added',resource_claimed:'Task resources reserved',dispatch_started:'Worker delivery started',worker_acknowledged:'Worker acknowledged',implementation_handed_off:'Implementation handed to verification',verification_accepted:'Task verification accepted',reconciliation_required:'Execution outcome requires reconciliation',inference_admitted:'Inference request admitted',inference_routed:'Approved inference route selected',inference_send_started:'Provider request started',inference_received:'Provider response received; verification pending',inference_failed:'Provider attempt failed',inference_reconciliation_required:'Provider outcome requires reconciliation',inference_verified:'Inference output verified; task acceptance remains separate',inference_cancel_requested:'Inference cancellation requested',inference_not_sent:'Prepared provider request was not sent',inference_billing_reconciled:'Provider billing reconciled'});
export function eventView(event){
 requireThat(event&&cursor(event.id)&&typeof event.type==='string'&&/^[a-z][a-z0-9_]{0,99}$/.test(event.type),'OPS_THEATRE_EVENT_INVALID');
 requireThat(typeof event.key==='string'&&event.key.length<=500&&(event.receiptRef===null||(typeof event.receiptRef==='string'&&event.receiptRef.length<=1000))
  &&typeof event.occurredAt==='string'&&Number.isFinite(Date.parse(event.occurredAt))
  &&(event.taskId===null||(typeof event.taskId==='string'&&event.taskId.length<=180)),'OPS_THEATRE_EVENT_INVALID');
 return Object.freeze({id:event.id,key:event.key,taskId:event.taskId,type:event.type,label:labels[event.type]??'Recorded Operations event',receiptRef:event.receiptRef,
  occurredAt:event.occurredAt,taskComplete:event.type==='verification_accepted',progress:null});
}
/** Read-only current-event model. Reset drops tenant data and fences late responses. */
export class OperationsTheatre{
 #generation=0;#scope=null;#cursor='0';#hasMore=false;#events=new Map();#pending=null;#controller=null;#reader;#clock;#max;
 constructor({readEvents,clock=Date.now,maxEvents=1000}){requireThat(typeof readEvents==='function'&&Number.isInteger(maxEvents)&&maxEvents>=1&&maxEvents<=5000,'OPS_THEATRE_CONFIGURATION_INVALID');this.#reader=readEvents;this.#clock=clock;this.#max=maxEvents;}
 reset(scope=null){this.#generation++;this.#controller?.abort();this.#controller=null;this.#pending=null;this.#scope=null;this.#cursor='0';this.#hasMore=false;this.#events.clear();
  if(scope){requireThat(ID.test(scope.organizationId)&&ID.test(scope.projectId)&&typeof scope.sessionKey==='string'&&scope.sessionKey.length>0&&scope.sessionKey.length<=180,'OPS_THEATRE_SCOPE_INVALID');this.#scope={...scope};}
 }
 snapshot(){return Object.freeze({scope:this.#scope?{organizationId:this.#scope.organizationId,projectId:this.#scope.projectId}:null,cursor:this.#cursor,hasMore:this.#hasMore,
  events:[...this.#events.values()],generatedProgress:false});}
 refresh(){
  if(!this.#scope)return Promise.reject(new Error('OPS_THEATRE_SCOPE_REQUIRED'));
  if(this.#pending)return this.#pending;
  const generation=this.#generation,scope={...this.#scope},after=this.#cursor,controller=new AbortController();this.#controller=controller;
  let timer;const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(new Error('OPS_THEATRE_READ_TIMEOUT'));},12000);});
  const request={organizationId:scope.organizationId,projectId:scope.projectId,after,limit:200};
  const pending=Promise.race([Promise.resolve().then(()=>this.#reader(request,{signal:controller.signal})),timeout]).then(reply=>{
   if(generation!==this.#generation)return this.snapshot();
   requireThat(reply&&reply.schemaVersion==='pandora-operations-events-v1'&&reply.organizationId===scope.organizationId&&reply.projectId===scope.projectId
    &&reply.authority==='immutable_operations_events'&&reply.syntheticProgress===false&&Array.isArray(reply.events)&&reply.events.length<=200
    &&typeof reply.hasMore==='boolean'&&cursor(reply.nextCursor)&&cursor(reply.highWatermark),'OPS_THEATRE_SCOPE_MISMATCH');
   const observed=Date.parse(reply.observedAt),now=this.#clock();requireThat(Number.isFinite(observed)&&observed<=now+30000&&now-observed<=60000,'OPS_THEATRE_STALE');
   let previous=BigInt(after);const next=new Map(this.#events);
   for(const raw of reply.events){const event=eventView(raw),id=BigInt(event.id);requireThat(id>previous&&id<=BigInt(reply.highWatermark),'OPS_THEATRE_CURSOR_INVALID');previous=id;
    requireThat(!next.has(event.id),'OPS_THEATRE_DUPLICATE_EVENT');next.set(event.id,event);}
   requireThat(BigInt(reply.nextCursor)===previous&&previous<=BigInt(reply.highWatermark)
    &&(!reply.hasMore||reply.events.length>0),'OPS_THEATRE_CURSOR_INVALID');
   while(next.size>this.#max)next.delete(next.keys().next().value);
   this.#events=next;this.#cursor=reply.nextCursor;this.#hasMore=reply.hasMore;return this.snapshot();
  }).finally(()=>{clearTimeout(timer);if(generation===this.#generation&&this.#pending===pending){this.#pending=null;this.#controller=null;}});
  this.#pending=pending;return pending;
 }
}
/** Never interpret event strings as HTML or execution instructions. */
export function renderTheatre(container,snapshot,{document=globalThis.document}={}){
 requireThat(container&&typeof container.replaceChildren==='function'&&document&&typeof document.createElement==='function','OPS_THEATRE_DOM_REQUIRED');
 const list=document.createElement('ol');list.setAttribute('aria-label','Operations execution events');list.setAttribute('aria-live','polite');
 if(!snapshot.events.length){const item=document.createElement('li');item.textContent='No recorded execution events.';list.appendChild(item);}
 for(const event of snapshot.events){const item=document.createElement('li'),title=document.createElement('strong'),detail=document.createElement('span');title.textContent=event.label;
  detail.textContent=`${event.taskId??'Workspace'} · ${event.occurredAt} · ${event.receiptRef??'No external receipt recorded'}`;item.appendChild(title);item.appendChild(detail);list.appendChild(item);}
 container.replaceChildren(list);
}
