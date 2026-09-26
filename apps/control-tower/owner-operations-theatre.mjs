
const MAIN_PROJECT='ee282126-3f61-4058-8c92-2fedbfcecf1f';
/** Mounts only real event receipts; chat role names and loading indicators are not execution events. */
export function createOwnerOperationsMount({Theatre,renderTheatre,auth,getState,document,window,clock=Date.now,setTimer=setTimeout,clearTimer=clearTimeout}){
 let key='',generation=0,timer=null,root=null,list=null,status=null,lastStarted=-Infinity,stopped=false;
 const model=new Theatre({readEvents:(request,options)=>auth.readOperationsEvents(request,options),clock,maxEvents:500});
 const clear=()=>{generation++;key='';model.reset();if(timer!==null)clearTimer(timer);timer=null;lastStarted=-Infinity;root?.remove();root=list=status=null;};
 const schedule=()=>{if(timer!==null)clearTimer(timer);timer=setTimer(()=>{timer=null;update();},15000);};
 function draw(){if(list)renderTheatre(list,model.snapshot(),{document});}
 function ensureRoot(){
  if(root?.isConnected)return;
  root=document.createElement('section');root.id='owner-operations-live';root.className='owner-section owner-operations-live';root.setAttribute('aria-label','Operations execution');
  const heading=document.createElement('h2');heading.textContent='Operations execution';
  status=document.createElement('p');status.setAttribute('role','status');status.textContent='Reading recorded execution events.';
  const button=document.createElement('button');button.type='button';button.className='owner-btn secondary';button.textContent='Refresh execution events';button.addEventListener('click',()=>{lastStarted=-Infinity;update();});
  list=document.createElement('div');list.style.maxHeight='360px';list.style.overflowY='auto';root.append(heading,status,button,list);
  document.getElementById('main-content')?.appendChild(root);draw();
 }
 function update(){
  if(stopped)return;const state=getState(),session=auth.session();
  const visible=document.visibilityState!=='hidden'&&['activity','run','project'].includes(state.route);
  if(!visible||!session.authenticated||!session.userId||!session.organizationId||!['owner','admin'].includes(session.role)){clear();return;}
  const projectId=state.route==='project'?state.projectWorkspace?.runtime?.project?.id:MAIN_PROJECT;
  if(!/^[a-f0-9-]{36}$/.test(projectId||'')){clear();return;}
  const next=[session.userId,session.organizationId,session.role,projectId].join(':');
  if(next!==key){clear();key=next;model.reset({organizationId:session.organizationId,projectId,sessionKey:session.userId+':'+generation});}
  ensureRoot();draw();schedule();if(clock()-lastStarted<5000)return;
  lastStarted=clock();const current=generation;
  model.refresh().then(()=>{if(stopped||current!==generation)return;ensureRoot();draw();status.textContent='Recorded execution events. Task completion requires a verification receipt.';}).catch(error=>{
   if(stopped||current!==generation)return;if(error?.accessDenied){clear();return;}
   ensureRoot();status.textContent='Execution events could not be refreshed. Earlier verified records remain visible.';
  });
 }
 const changed=()=>{clear();update();};const visibility=()=>update();
 const dispose=()=>{stopped=true;clear();window.removeEventListener('mcpmaster-auth-changed',changed);document.removeEventListener('visibilitychange',visibility);window.removeEventListener('pagehide',dispose);};
 window.addEventListener('mcpmaster-auth-changed',changed);document.addEventListener('visibilitychange',visibility);window.addEventListener('pagehide',dispose);
 return Object.freeze({update,dispose});
}
if(typeof window!=='undefined'&&typeof document!=='undefined'){
 const {OperationsTheatre,renderTheatre}=await import('./operations-theatre-runtime.mjs');
 window.PandoraOperationsTheatreMount=createOwnerOperationsMount({Theatre:OperationsTheatre,renderTheatre,auth:window.MCPMasterAuth,getState:()=>window.PandorasOwnerData.state,document,window});
}
