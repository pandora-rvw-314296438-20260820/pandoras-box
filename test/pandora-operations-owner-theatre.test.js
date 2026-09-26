
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs/promises');const vm=require('node:vm');
const modules=Promise.all([import('../apps/control-tower/owner-operations-theatre.mjs'),import('../packages/pandora-operations-inference/theatre.mjs')]);
class Element extends EventTarget{
 constructor(tag){super();this.tag=tag;this.children=[];this.style={};this.parent=null;this._connected=false;this._text='';}
 get isConnected(){return this._connected||this.parent?.isConnected||false;}
 set textContent(v){this._text=String(v);this.replaceChildren();}get textContent(){return this._text+this.children.map(c=>c.textContent).join('');}
 setAttribute(k,v){this[k]=v;}append(...children){for(const c of children)this.appendChild(c);}
 appendChild(child){child.parent=this;this.children.push(child);return child;}
 replaceChildren(...children){for(const c of this.children)c.parent=null;this.children=[];this.append(...children);}
 remove(){if(this.parent){this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=null;}}
}
const org='2270b266-59da-4c39-bfd9-9f8d08352af0',project='ee282126-3f61-4058-8c92-2fedbfcecf1f',user='33e5b2de-048b-4814-b601-7d7daac7a649';
const now=Date.parse('2026-09-26T02:30:00Z');
const event=id=>({id:String(id),key:'fixture:'+id,type:'tasks_ingested',taskId:'TASK-'+id,receiptRef:null,occurredAt:new Date(now).toISOString()});
function reply(r,events=[]){return {schemaVersion:'pandora-operations-events-v1',organizationId:r.organizationId,projectId:r.projectId,authority:'immutable_operations_events',syntheticProgress:false,events,hasMore:false,nextCursor:events.at(-1)?.id||r.after,highWatermark:events.at(-1)?.id||r.after,observedAt:new Date(now).toISOString()};}
const flush=()=>new Promise(resolve=>setImmediate(resolve));
async function fixture(reader=async r=>reply(r,[event(1)])){
 const [a,b]=await modules;const main=new Element('main');main._connected=true;const document=new EventTarget();document.visibilityState='visible';document.createElement=tag=>new Element(tag);document.getElementById=id=>id==='main-content'?main:null;
 const window=new EventTarget(),state={route:'activity'},session={authenticated:true,userId:user,organizationId:org,role:'owner'},calls=[],timers=new Map();let timerId=0;
 const mount=a.createOwnerOperationsMount({Theatre:b.OperationsTheatre,renderTheatre:b.renderTheatre,auth:{session:()=>session,readOperationsEvents:(r,o)=>{calls.push({r,o});return reader(r,o);}},getState:()=>state,document,window,clock:()=>now,setTimer:fn=>{const id=++timerId;timers.set(id,fn);return id;},clearTimer:id=>timers.delete(id)});
 return {main,document,window,state,session,calls,timers,mount};
}
test('owner Activity mounts real model and exact scoped event reader',async()=>{const f=await fixture();f.mount.update();await flush();assert.equal(f.calls.length,1);assert.equal(f.calls[0].r.organizationId,org);assert.equal(f.calls[0].r.projectId,project);assert.match(f.main.textContent,/Tasks added/);assert.doesNotMatch(f.main.textContent,/100%|worker finished/i);assert.equal(f.main.children.length,1);f.mount.dispose();});
test('repeat render remounts cached actual events without duplicate read',async()=>{const f=await fixture();f.mount.update();await flush();f.main.replaceChildren();f.mount.update();await flush();assert.equal(f.calls.length,1);assert.equal(f.main.children.length,1);assert.match(f.main.textContent,/Tasks added/);f.mount.dispose();});
test('new unverified event fields cannot inject HTML',async()=>{const f=await fixture(async r=>reply(r,[{...event(1),taskId:'<script>bad</script>'}]));f.mount.update();await flush();assert.match(f.main.textContent,/<script>bad/);assert.equal(f.main.children[0].tag,'section');f.mount.dispose();});
test('signout clears cached events and fences late response',async()=>{let resolve;const f=await fixture(r=>new Promise(done=>{resolve=()=>done(reply(r,[event(1)]));}));f.mount.update();await flush();f.session.authenticated=false;f.window.dispatchEvent(new Event('mcpmaster-auth-changed'));resolve();await flush();assert.equal(f.main.children.length,0);assert.equal(f.timers.size,0);f.mount.dispose();});
test('project change cannot display late data from prior scope',async()=>{const resolves=[];const f=await fixture(r=>new Promise(done=>resolves.push(()=>done(reply(r,[event(resolves.length+1)])))));f.mount.update();await flush();f.state.route='project';f.state.projectWorkspace={runtime:{project:{id:'7c686cbd-d968-49d5-86cc-918f5e777bd2'}}};f.mount.update();await flush();assert.notEqual(f.calls[0].r.projectId,f.calls[1].r.projectId);resolves[1]();await flush();const text=f.main.textContent;resolves[0]();await flush();assert.equal(f.main.textContent,text);f.mount.dispose();});
for(const role of ['viewer','member','operator'])test(`${role} receives no passive execution fetch`,async()=>{const f=await fixture();f.session.role=role;f.mount.update();await flush();assert.equal(f.calls.length,0);assert.equal(f.main.children.length,0);f.mount.dispose();});
test('hidden page stops timers and clears visible scope',async()=>{const f=await fixture();f.mount.update();await flush();f.document.visibilityState='hidden';f.document.dispatchEvent(new Event('visibilitychange'));assert.equal(f.timers.size,0);assert.equal(f.main.children.length,0);f.mount.dispose();});
test('provider access denial clears event data instead of showing stale authorized data',async()=>{const f=await fixture(async()=>{throw Object.assign(new Error('denied'),{accessDenied:true});});f.mount.update();await flush();assert.equal(f.main.children.length,0);f.mount.dispose();});
test('provider failure is shown as unavailable, never as completed work',async()=>{const f=await fixture(async()=>{throw new Error('provider secret');});f.mount.update();await flush();assert.match(f.main.textContent,/could not be refreshed/);assert.doesNotMatch(f.main.textContent,/provider secret|execution complete/i);f.mount.dispose();});
test('dispose removes all lifecycle observers and suppresses future refresh',async()=>{const f=await fixture();f.mount.dispose();f.mount.update();f.window.dispatchEvent(new Event('mcpmaster-auth-changed'));await flush();assert.equal(f.calls.length,0);assert.equal(f.timers.size,0);});
test('project screen requires a current project identity',async()=>{const f=await fixture();f.state.route='project';f.mount.update();await flush();assert.equal(f.calls.length,0);f.mount.dispose();});
test('materializer serves exact canonical event module without committing generated copy',async()=>{const text=await fs.readFile('scripts/materialize-control-tower.mjs','utf8');assert.match(text,/packages\/pandora-operations-inference\/theatre\.mjs/);assert.match(text,/operations-theatre-runtime\.mjs/);assert.match(text,/sourceCount \+ 1/);});
test('actual owner bootstrap and render mount current-event component',async()=>{const [boot,app,auth]=await Promise.all(['owner-first.js','owner-app.js','auth.js'].map(p=>fs.readFile('apps/control-tower/'+p,'utf8')));assert.ok(boot.indexOf('owner-operations-theatre.mjs')<boot.indexOf('owner-app.js'));assert.match(app,/PandoraOperationsTheatreMount\?\.update/);assert.match(auth,/readOperationsEvents,/);assert.match(auth,/userId: authState.user\?\.id/);});
test('actual auth adapter routes only owner event reads and sends current bearer',async()=>{
 const source=await fs.readFile('apps/control-tower/auth.js','utf8'),calls=[];
 const window=new EventTarget();window.location={href:'https://mcpmaster.vercel.app/control-tower/'};window.fetch=async(url,init)=>{calls.push({url,init});if(url==='/api/operator/auth/config')return Response.json({organizationId:org,supabaseUrl:'https://jcyqixttuebxqqfkjonq.supabase.co'});return Response.json({fixture:true});};
 const context=vm.createContext({window,URL,Request,Response,Headers,AbortSignal,TextDecoder,CustomEvent:Event,console});vm.runInContext(source,context);
 vm.runInContext(`acceptAuthenticatedSession({access_token:'fixture-auth-session-for-tests-only',user:{id:'${user}'}});`,context);
 const r=await window.MCPMasterAuth.readOperationsEvents({projectId:project,after:'0',limit:100});assert.equal(r.fixture,true);assert.equal(calls.at(-1).url,'/api/operations-inference?operation=events');assert.equal(calls.at(-1).init.redirect,'error');assert.equal(JSON.parse(calls.at(-1).init.body).organizationId,org);assert.match(calls.at(-1).init.headers.authorization,/^Bearer fixture-/);assert.equal(calls.at(-1).init.headers['x-pandora-vercel-oidc'],undefined);
});

test('persisted pagehide clears sensitive view but pageshow restores live updating',async()=>{const f=await fixture();f.mount.update();await flush();const hide=new Event('pagehide');Object.defineProperty(hide,'persisted',{value:true});f.window.dispatchEvent(hide);assert.equal(f.main.children.length,0);assert.equal(f.timers.size,0);const show=new Event('pageshow');Object.defineProperty(show,'persisted',{value:true});f.window.dispatchEvent(show);await flush();assert.equal(f.calls.length,2);assert.match(f.main.textContent,/Tasks added/);f.mount.dispose();});
test('nonpersisted pagehide disposes listeners and prevents later restart',async()=>{const f=await fixture();f.mount.update();await flush();f.window.dispatchEvent(new Event('pagehide'));f.mount.update();const show=new Event('pageshow');Object.defineProperty(show,'persisted',{value:true});f.window.dispatchEvent(show);await flush();assert.equal(f.calls.length,1);assert.equal(f.main.children.length,0);});
test('same user auth refresh retains accepted event rows',async()=>{const f=await fixture();f.mount.update();await flush();const text=f.main.textContent;f.window.dispatchEvent(new Event('mcpmaster-auth-changed'));await flush();assert.equal(f.main.textContent,text);assert.equal(f.calls.length,1);f.mount.dispose();});
for(const mode of ['reject','stall'])test(`optional Theatre import ${mode} cannot block owner app`,async()=>{
 const source=await fs.readFile('apps/control-tower/owner-first.js','utf8'),calls=[],warnings=[];
 vm.runInNewContext(source.replaceAll('import(', '__load('),{window:{},document:{},console:{warn:value=>warnings.push(value)},__load:async value=>{
  calls.push(value);if(value.includes('owner-operations-theatre.mjs')){if(mode==='reject')throw new Error('private module failure');return new Promise(()=>{});}return {};
 }});
 await flush();assert.ok(calls.some(value=>value.includes('owner-app.js')));assert.ok(warnings.every(value=>!value.includes('private module failure')));
});
