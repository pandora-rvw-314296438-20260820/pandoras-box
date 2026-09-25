import { randomUUID } from 'node:crypto';
import { mkdir, writeFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { AresLeaseAuthority } from './authority.mjs';
import { AresJournal } from './journal.mjs';
import { AresArtifactVerifier } from './artifact.mjs';
import { containedFile, hashFile } from './process.mjs';
import { AresError, CONTRACT, PACKAGES, actionDigest, canonical, demand, exact, identifier, immutable, integer, normalizeJob, portForSerial, publicError, rejectSecrets, sha256 } from './contract.mjs';

const COMPONENT=/^[A-Za-z][A-Za-z0-9_.]+\/[A-Za-z.][A-Za-z0-9_.$]+$/;
const DEVICE_APK=/^\/data\/app\/[A-Za-z0-9_~+=/.-]+\/base\.apk$/;
const text=r=>r.stdout.toString('utf8').trim();
const ok=r=>{demand(r.code===0 && r.terminationSignal==null,'ARES_COMMAND_FAILED');return text(r);};
const serialRows=output=>output.split(/\r?\n/).map(s=>s.trim().split(/\s+/)).filter(x=>/^emulator-[0-9]{4}$/.test(x[0]));

export function normalizeProfile(raw) {
  exact(raw,['organizationId','projectId','serial','avdName','packages','launchComponents','expectedAbis','syntheticDataOnly','headless','suites']);
  portForSerial(raw.serial);
  demand(raw.syntheticDataOnly===true,'ARES_SYNTHETIC_TEST_DEVICE_REQUIRED');
  demand(typeof raw.avdName==='string' && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$/.test(raw.avdName) && !raw.avdName.includes('..'),'ARES_AVD_INVALID');
  for(const id of ['organizationId','projectId'])demand(typeof raw[id]==='string' && /^[a-f0-9-]{36}$/.test(raw[id]),'ARES_PROFILE_SCOPE');
  demand(Array.isArray(raw.packages) && raw.packages.length>0 && raw.packages.every(p=>PACKAGES.includes(p)) && new Set(raw.packages).size===raw.packages.length,'ARES_PROFILE_PACKAGE');
  demand(raw.launchComponents && typeof raw.launchComponents==='object','ARES_PROFILE_LAUNCH_REQUIRED');
  for(const [pkg,component] of Object.entries(raw.launchComponents))demand(raw.packages.includes(pkg) && COMPONENT.test(component) && component.startsWith(pkg+'/'),'ARES_PROFILE_COMPONENT');
  demand(Array.isArray(raw.expectedAbis) && raw.expectedAbis.length>0 && raw.expectedAbis.every(a=>['arm64-v8a','armeabi-v7a','x86','x86_64'].includes(a)),'ARES_PROFILE_ABI');
  demand(raw.headless===undefined || typeof raw.headless==='boolean','ARES_PROFILE_HEADLESS');
  const suites=raw.suites??{};
  demand(typeof suites==='object' && !Array.isArray(suites) && Object.keys(suites).length<=20,'ARES_PROFILE_SUITE_LIMIT');
  for(const [key,suite] of Object.entries(suites)) {
    identifier(key);exact(suite,['packageName','testPackage','component','artifactRef','sourceSha']);
    demand(raw.packages.includes(suite.packageName) && suite.testPackage===suite.packageName+'.test' && COMPONENT.test(suite.component) && suite.component.startsWith(suite.testPackage+'/'),'ARES_TEST_COMPONENT_DENIED');
    demand(typeof suite.artifactRef==='string' && /^(?:artifact|github-artifact|sha256):[A-Za-z0-9_./:-]{8,300}$/.test(suite.artifactRef) && /^[a-f0-9]{40}$/.test(suite.sourceSha),'ARES_TEST_ARTIFACT_REQUIRED');
  }
  rejectSecrets(raw);
  return immutable({...structuredClone(raw),headless:raw.headless??true,suites:structuredClone(suites)});
}

export function profileDigest(nodeId,profile,tools) {return sha256(canonical({nodeId,profile,tools}));}
export function instrumentationResult(output) {
  demand(typeof output==='string' && output.length<=1024*1024,'ARES_TEST_OUTPUT_LIMIT');
  const count=/^OK \(([0-9]+) tests?\)\s*$/m.exec(output);
  demand(count && Number(count[1])>0 && /^INSTRUMENTATION_CODE:\s*-1\s*$/m.test(output)
    && !/(?:FAILURES!!!|INSTRUMENTATION_(?:FAILED|ABORTED)|shortMsg=|INSTRUMENTATION_STATUS_CODE:\s*-[1-9])/m.test(output),'ARES_INSTRUMENTATION_FAILED');
  return {testsPassed:Number(count[1]),outputSha256:sha256(output)};
}
export function sanitizedCrashes(output) {
  const lines=output.split(/\r?\n/);const safe=[];
  for(const raw of lines) {
    const line=raw.trim();
    if(/^at [A-Za-z0-9_.$]+\([A-Za-z0-9_.:$ -]{1,120}\)$/.test(line))safe.push(line);
    else if(/^FATAL EXCEPTION: [A-Za-z0-9 _.-]{1,80}$/.test(line))safe.push(line);
    else {
      const kind=/^(?:Caused by: )?([A-Za-z_$][A-Za-z0-9_.$]*(?:Exception|Error))(?::|$)/.exec(line);
      if(kind)safe.push(kind[1]);
    }
  }
  return [...new Set(safe)].slice(0,200).join('\n')+'\n';
}

function within(promise,signal) {
  if(signal.aborted)return Promise.reject(new AresError('ARES_CANCELLED'));
  return new Promise((resolve,reject)=>{
    const aborted=()=>{signal.removeEventListener('abort',aborted);reject(new AresError('ARES_CANCELLED'));};
    signal.addEventListener('abort',aborted,{once:true});
    Promise.resolve(promise).then(x=>{signal.removeEventListener('abort',aborted);resolve(x);},error=>{signal.removeEventListener('abort',aborted);reject(error);});
  });
}

/** The host consumes exact signed M3 grants; it cannot grant tool or release authority. */
export class AresHost {
  constructor({nodeId,profiles,runner,authority,journal,artifactVerifier,evidenceRoot,clock=Date.now,pollMs=500}) {
    identifier(nodeId);
    demand(runner && typeof runner.run==='function' && typeof runner.startManaged==='function' && runner.tools,'ARES_PROCESS_RUNNER_REQUIRED');
    demand(authority instanceof AresLeaseAuthority && journal instanceof AresJournal,'ARES_GOVERNED_HOST_REQUIRED');
    demand(path.isAbsolute(evidenceRoot),'ARES_PRIVATE_EVIDENCE_ROOT_REQUIRED');
    demand(Array.isArray(profiles) && profiles.length>0 && profiles.length<=32,'ARES_PROFILES_REQUIRED');
    const registered=profiles.map(normalizeProfile);
    demand(new Set(registered.map(p=>p.serial)).size===registered.length && new Set(registered.map(p=>p.avdName)).size===registered.length,'ARES_PROFILE_COLLISION');
    this.nodeId=nodeId;this.profiles=new Map(registered.map(p=>[p.serial,p]));
    this.runner=runner;this.authority=authority;this.journal=journal;
    this.artifacts=artifactVerifier;this.evidenceRoot=evidenceRoot;this.clock=clock;
    this.pollMs=integer(pollMs,1,2000);this.bootSession=randomUUID();this.handles=new Map();
  }
  profile(job) {
    demand(job.nodeId===this.nodeId,'ARES_NODE_SCOPE');
    const p=this.profiles.get(job.target.serial);
    demand(p && p.organizationId===job.organizationId && p.projectId===job.projectId && p.avdName===job.target.avdName,'ARES_PROFILE_SCOPE');
    if(job.target.packageName!==null)demand(p.packages.includes(job.target.packageName),'ARES_PROFILE_PACKAGE');
    demand(job.profileSha256===profileDigest(this.nodeId,p,this.runner.tools),'ARES_PROFILE_DRIFT');
    return p;
  }
  async checkpoint(c) {
    demand(!c.signal.aborted && this.clock()<c.deadline,'ARES_CANCELLED');
    c.authority=await within(this.authority.check(c.job,c.grantToken,{signal:c.signal}),c.signal);
    return c.authority;
  }
  async tool(c,tool,args,{mutating=false,timeoutMs=15000,maxBytes=1024*1024}={}) {
    await this.checkpoint(c);
    const remaining=Math.max(1,Math.min(timeoutMs,c.deadline-this.clock()));
    const result=await this.runner.run(tool,args,{timeoutMs:remaining,maxBytes,signal:c.signal,onSpawn:event=>{
      if(mutating)c.mutationPossible=true;
      this.journal.dispatched(c.id,{mutating,tool:event.tool,toolSha256:event.toolSha256});
    }});
    demand(Buffer.isBuffer(result.stdout),'ARES_PROCESS_RESULT_INVALID');
    this.journal.append(c.id,'process_observed',{tool,toolSha256:result.toolSha256,exitCode:result.code,outputSha256:sha256(result.stdout),stderrSha256:result.stderrSha256??null,latencyMs:result.latencyMs??null});
    await this.checkpoint(c);
    return result;
  }
  async adb(c,args,options={}) {return this.tool(c,'adb',['-s',c.job.target.serial,...args],options);}
  owned(c) {
    const owned=this.journal.managed(c.job.target.serial),handle=this.handles.get(c.job.target.serial);
    demand(owned && owned.node_id===this.nodeId && owned.avd_name===c.profile.avdName && owned.boot_session===this.bootSession && handle && handle.pid===owned.process_id && handle.isAlive(),'ARES_MANAGED_INSTANCE_REQUIRED');
  }
  async probe(c) {
    const list=await this.tool(c,'adb',['devices','-l']);ok(list);
    const row=serialRows(text(list)).find(x=>x[0]===c.job.target.serial);
    if(!row)return {present:false,ready:false,adbState:'absent',bootCompleted:false,emulatorVerified:false,abis:[]};
    if(row[1]!=='device')return {present:true,ready:false,adbState:row[1]==='offline'?'offline':'unavailable',bootCompleted:false,emulatorVerified:false,abis:[]};
    const state=ok(await this.adb(c,['get-state']));
    const boot=ok(await this.adb(c,['shell','getprop','sys.boot_completed']));
    const qemu=ok(await this.adb(c,['shell','getprop','ro.kernel.qemu']));
    const abi=ok(await this.adb(c,['shell','getprop','ro.product.cpu.abilist']));
    const abis=abi.split(',').filter(a=>['arm64-v8a','armeabi-v7a','x86','x86_64'].includes(a));
    const shell=ok(await this.adb(c,['shell','pm','path','android']));
    const avd=ok(await this.adb(c,['emu','avd','name'])).split(/\r?\n/)[0];
    demand(qemu==='1' && avd===c.profile.avdName,'ARES_GUEST_IDENTITY_MISMATCH');
    const ready=state==='device' && boot==='1' && shell.startsWith('package:') && c.profile.expectedAbis.some(a=>abis.includes(a));
    return {present:true,ready,adbState:state==='device'?'device':'unavailable',bootCompleted:boot==='1',emulatorVerified:true,abis};
  }
  async requireReady(c) {this.owned(c);const state=await this.probe(c);demand(state.ready,'ARES_EMULATOR_NOT_READY');return state;}
  async poll(c,predicate) {
    while(!c.signal.aborted && this.clock()<c.deadline) {
      if(await predicate())return;
      await within(new Promise(resolve=>setTimeout(resolve,this.pollMs)),c.signal);
    }
    throw new AresError('ARES_READINESS_TIMEOUT',{sideEffectPossible:c.mutationPossible});
  }
  async installed(c,artifact) {
    const name=artifact.packageName;
    const pkg=ok(await this.adb(c,['shell','pm','path',name]));
    const paths=pkg.split(/\r?\n/).filter(Boolean);
    demand(paths.length===1 && paths[0].startsWith('package:'),'ARES_INSTALLED_APK_UNREADABLE');
    const remote=paths[0].slice(8);
    demand(DEVICE_APK.test(remote) && !remote.includes('..'),'ARES_INSTALLED_PATH_DENIED');
    const hash=ok(await this.adb(c,['shell','sha256sum',remote])).split(/\s+/)[0];
    demand(hash===artifact.apkSha256,'ARES_INSTALLED_DIGEST_MISMATCH');
    const details=ok(await this.adb(c,['shell','dumpsys','package',name]));
    const versions=[...details.matchAll(/\bversionCode=([0-9]+)/g)].map(m=>Number(m[1]));
    demand(versions.length>0 && versions.every(v=>v===artifact.versionCode),'ARES_INSTALLED_VERSION_MISMATCH');
    return {packageName:name,versionCode:artifact.versionCode,apkSha256:hash,signerSha256:artifact.signerSha256,sourceSha:artifact.sourceSha};
  }
  async artifact(c,job=c.job) {
    demand(this.artifacts instanceof AresArtifactVerifier,'ARES_ARTIFACT_VERIFIER_REQUIRED');
    return within(this.artifacts.materialize(job,{signal:c.signal,runTool:(tool,args,opts)=>this.tool(c,tool,args,opts)}),c.signal);
  }
  async install(c,artifact) {
    demand(await hashFile(artifact.file)===artifact.apkSha256,'ARES_APK_CHANGED_BEFORE_INSTALL');
    const result=await this.adb(c,['install','-r',artifact.file],{mutating:true,timeoutMs:120000});
    demand(result.code===0 && /(^|\n)Success\s*$/.test(text(result)),'ARES_APK_INSTALL_FAILED');
    return this.installed(c,artifact);
  }
  async foreground(c) {
    const details=ok(await this.adb(c,['shell','dumpsys','window','windows']));
    const focus=details.split(/\r?\n/).find(s=>s.includes('mCurrentFocus='));
    const match=focus && /\bu[0-9]+\s+([A-Za-z0-9_.]+)\/[A-Za-z0-9_.$]+/.exec(focus);
    demand(match && match[1]===c.job.target.packageName,'ARES_FOREGROUND_NOT_TARGET');
  }
  async evidence(c,bytes,extension) {
    demand(Buffer.isBuffer(bytes) && bytes.length>0 && bytes.length<=32*1024*1024,'ARES_EVIDENCE_SIZE');
    await mkdir(this.evidenceRoot,{recursive:true,mode:0o700});
    const real=await realpath(this.evidenceRoot);
    demand((process.platform==='win32'?real.toLowerCase()===path.resolve(this.evidenceRoot).toLowerCase():real===path.resolve(this.evidenceRoot)),'ARES_EVIDENCE_PATH_ESCAPE');
    const hash=sha256(bytes),file=path.join(real,c.id+'-'+hash+extension);
    try {await writeFile(file,bytes,{flag:'wx',mode:0o600});}catch(error){if(error.code!=='EEXIST')throw error;}
    await containedFile(real,file,{extension,maxBytes:32*1024*1024});
    demand(await hashFile(file,32*1024*1024)===hash,'ARES_EVIDENCE_DIGEST_MISMATCH');
    return {ref:'ares-evidence:'+c.id+':'+hash,sha256:hash,bytes:bytes.length,private:true};
  }
  async operate(c) {
    const job=c.job,operation=job.operation;
    if(operation==='ares.health.read')return {observation:await this.probe(c),runtimeReadbackVerified:true};
    if(operation==='ares.emulator.start') {
      const prior=await this.probe(c);
      demand(!prior.present && !this.journal.managed(job.target.serial),'ARES_INSTANCE_ALREADY_EXISTS');
      const available=ok(await this.tool(c,'emulator',['-list-avds'])).split(/\r?\n/);
      demand(available.includes(c.profile.avdName),'ARES_AVD_NOT_AVAILABLE');
      const args=['-avd',c.profile.avdName,'-port',String(portForSerial(job.target.serial)),'-read-only','-no-snapshot','-no-boot-anim','-camera-front','none','-camera-back','none'];
      if(c.profile.headless)args.push('-no-window');
      await this.checkpoint(c);
      const handle=await within(this.runner.startManaged('emulator',args,{signal:c.signal,onSpawn:e=>{c.mutationPossible=true;this.journal.dispatched(c.id,{mutating:true,tool:'emulator',toolSha256:e.toolSha256});}}),c.signal);
      this.handles.set(job.target.serial,handle);this.journal.recordManaged(job,c.id,this.bootSession,handle.pid);
      let observation;
      await this.poll(c,async()=>{demand(handle.isAlive(),'ARES_EMULATOR_EXITED');observation=await this.probe(c);return observation.ready;});
      return {observation,runtimeReadbackVerified:true};
    }
    this.owned(c);
    if(operation==='ares.emulator.stop') {
      await this.requireReady(c);
      ok(await this.adb(c,['emu','kill'],{mutating:true}));
      await this.poll(c,async()=>!serialRows(ok(await this.tool(c,'adb',['devices','-l']))).some(x=>x[0]===job.target.serial));
      this.journal.forgetManaged(job.target.serial,this.bootSession);this.handles.delete(job.target.serial);
      return {observation:{present:false},runtimeReadbackVerified:true};
    }
    const guest=await this.requireReady(c);
    if(operation==='ares.network.configure') {
      const before=ok(await this.adb(c,['emu','network','status']));
      ok(await this.adb(c,['emu','network','speed',job.parameters.speed],{mutating:true}));
      ok(await this.adb(c,['emu','network','delay',job.parameters.delay],{mutating:true}));
      const after=ok(await this.adb(c,['emu','network','status']));
      return {observation:{beforeSha256:sha256(before),afterSha256:sha256(after),requestedSpeed:job.parameters.speed,requestedDelay:job.parameters.delay},runtimeReadbackVerified:false,requiresVerification:'network_parameters_require_semantic_readback'};
    }
    let artifact=null,identity=null;
    if(job.artifactRef) {
      artifact=await this.artifact(c);
      demand(artifact.abis.some(abi=>guest.abis.includes(abi)),'ARES_APK_ABI_INCOMPATIBLE');
      if(operation!=='ares.apk.install')identity=await this.installed(c,artifact);
    }
    if(operation==='ares.apk.install')return {observation:await this.install(c,artifact),runtimeReadbackVerified:true};
    if(operation==='ares.apk.uninstall') {
      demand(/(^|\n)Success\s*$/.test(ok(await this.adb(c,['uninstall',job.target.packageName],{mutating:true}))),'ARES_UNINSTALL_FAILED');
      const read=await this.adb(c,['shell','pm','path',job.target.packageName]);
      demand(read.code===0 && text(read)==='','ARES_UNINSTALL_UNVERIFIED');
      return {observation:{packageName:job.target.packageName,installed:false},runtimeReadbackVerified:true};
    }
    if(operation==='ares.app.clear_data') {
      demand(ok(await this.adb(c,['shell','pm','clear',job.target.packageName],{mutating:true}))==='Success','ARES_CLEAR_DATA_FAILED');
      return {observation:{packageName:job.target.packageName,commandAccepted:true},runtimeReadbackVerified:false,requiresVerification:'app_state_reset_requires_application_assertions'};
    }
    if(operation==='ares.permission.change') {
      ok(await this.adb(c,['shell','pm',job.parameters.mode,job.target.packageName,job.parameters.permission],{mutating:true}));
      const dump=ok(await this.adb(c,['shell','dumpsys','package',job.target.packageName]));
      const permission=job.parameters.permission.replaceAll('.','\\.');
      const match=new RegExp('^\\s*'+permission+': granted=(true|false)\\b','m').exec(dump);
      demand(match && (match[1]==='true')===(job.parameters.mode==='grant'),'ARES_PERMISSION_READBACK_FAILED');
      return {observation:{permission:job.parameters.permission,granted:match[1]==='true'},runtimeReadbackVerified:true};
    }
    if(operation==='ares.ui.test') {
      let completedSteps=0;
      for(const step of job.parameters.steps) {
        if(step.kind==='launch') {
          const component=c.profile.launchComponents[job.target.packageName];demand(component,'ARES_LAUNCH_COMPONENT_REQUIRED');
          const launch=ok(await this.adb(c,['shell','am','start','-W','-n',component],{mutating:true}));
          demand(!/^Error:/m.test(launch),'ARES_LAUNCH_FAILED');await this.foreground(c);
        } else if(step.kind==='force_stop') {
          ok(await this.adb(c,['shell','am','force-stop',job.target.packageName],{mutating:true}));
          const state=await this.adb(c,['shell','pidof',job.target.packageName]);demand(text(state)==='' && [0,1].includes(state.code),'ARES_FORCE_STOP_UNVERIFIED');
        } else {
          await this.foreground(c);
          let args;
          if(step.kind==='back')args=['keyevent','KEYCODE_BACK'];
          if(step.kind==='type')args=['text',step.text.replaceAll(' ','%s')];
          if(step.kind==='tap' || step.kind==='swipe') {
            const size=ok(await this.adb(c,['shell','wm','size']));const matches=[...size.matchAll(/(?:Physical|Override) size: ([0-9]+)x([0-9]+)/g)];
            demand(matches.length>0,'ARES_DISPLAY_SIZE_UNREADABLE');const dimensions=matches.at(-1);
            for(const [x,y] of (step.kind==='tap'?[[step.x,step.y]]:[[step.x,step.y],[step.x2,step.y2]]))demand(x<Number(dimensions[1]) && y<Number(dimensions[2]),'ARES_COORDINATE_OUTSIDE_DISPLAY');
            args=step.kind==='tap'?['tap',String(step.x),String(step.y)]:['swipe',...[step.x,step.y,step.x2,step.y2,step.durationMs].map(String)];
          }
          ok(await this.adb(c,['shell','input',...args],{mutating:true}));
          await this.foreground(c);
        }
        completedSteps++;
      }
      identity=await this.installed(c,artifact);
      return {observation:{...identity,completedSteps,semanticUiAccepted:false},runtimeReadbackVerified:true};
    }
    if(operation==='ares.test.run') {
      const suite=c.profile.suites[job.parameters.suiteId];
      demand(suite && suite.packageName===job.target.packageName && suite.sourceSha===job.sourceSha,'ARES_TEST_SUITE_DENIED');
      const testJob={...job,artifactRef:suite.artifactRef,target:{...job.target,packageName:suite.testPackage}};
      const testApk=await this.artifact(c,testJob);
      demand(testApk.abis.some(a=>guest.abis.includes(a)),'ARES_TEST_ABI_INCOMPATIBLE');
      await this.install(c,testApk);
      const result=await this.adb(c,['shell','am','instrument','-w','-r',suite.component],{mutating:true,timeoutMs:Math.min(job.timeoutMs,180000)});
      const parsed=instrumentationResult(ok(result));
      identity=await this.installed(c,artifact);
      return {observation:{...identity,...parsed,suiteId:job.parameters.suiteId},runtimeReadbackVerified:true};
    }
    if(operation==='ares.evidence.read') {
      const kind=job.parameters.kind;
      if(kind==='package') {
        demand(artifact,'ARES_EXACT_ARTIFACT_REQUIRED');return {observation:await this.installed(c,artifact),runtimeReadbackVerified:true};
      }
      await this.foreground(c);
      if(kind==='screenshot') {
        const result=await this.adb(c,['exec-out','screencap','-p'],{maxBytes:16*1024*1024});ok(result);
        demand(result.stdout.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),'ARES_SCREENSHOT_INVALID');
        await this.foreground(c);
        return {observation:{kind,artifact:await this.evidence(c,result.stdout,'.png')},runtimeReadbackVerified:true};
      }
      if(kind==='crashes') {
        const pid=ok(await this.adb(c,['shell','pidof',job.target.packageName]));demand(/^[0-9]{1,9}$/.test(pid),'ARES_TARGET_PID_REQUIRED');
        const logs=ok(await this.adb(c,['logcat','--pid='+pid,'-b','crash','-d','-t','200','-v','raw']));
        const sanitized=Buffer.from(sanitizedCrashes(logs));
        return {observation:{kind,artifact:await this.evidence(c,sanitized,'.txt'),rawMessagesStored:false},runtimeReadbackVerified:true};
      }
      if(kind==='video') {
        // Capture only an explicitly enrolled synthetic emulator; never a physical or protected app.
        const remote='/sdcard/pandora-ares-'+c.id+'.mp4';
        ok(await this.adb(c,['shell','screenrecord','--time-limit',String(job.parameters.seconds),remote],{mutating:true,timeoutMs:(job.parameters.seconds+5)*1000}));
        await this.foreground(c);
        const video=await this.adb(c,['exec-out','cat',remote],{maxBytes:32*1024*1024});ok(video);
        demand(video.stdout.length>=12 && video.stdout.subarray(4,8).toString('ascii')==='ftyp','ARES_VIDEO_INVALID');
        const artifact=await this.evidence(c,video.stdout,'.mp4');
        ok(await this.adb(c,['shell','rm',remote],{mutating:true}));
        return {observation:{kind,artifact},runtimeReadbackVerified:true};
      }
    }
    throw new AresError('ARES_OPERATION_NOT_IMPLEMENTED');
  }
  async execute(raw,grantToken,{signal}={}) {
    const job=normalizeJob(raw),profile=this.profile(job),hash=actionDigest(job);
    const localAbort=new AbortController();const timer=setTimeout(()=>localAbort.abort(),job.timeoutMs);
    const combined=signal?AbortSignal.any([signal,localAbort.signal]):localAbort.signal;
    const c={job,profile,grantToken,signal:combined,deadline:this.clock()+job.timeoutMs,mutationPossible:false,id:null};
    try {
      await this.checkpoint(c);
      const claim=this.journal.begin(job);
      if(!claim.claimed)return claim.result?{...claim.result,replayed:true}:{state:claim.state,actionHash:hash,releaseVerified:false,physicalDeviceVerified:false};
      c.id=claim.id;
      let result;
      try {
        const outcome=await within(this.operate(c),combined);await this.checkpoint(c);
        const verified=outcome.runtimeReadbackVerified===true;
        result={contract:CONTRACT,requestId:job.requestId,taskId:job.taskId,nodeId:job.nodeId,sourceSha:job.sourceSha,actionHash:hash,generation:job.generation,state:verified?'executed_and_read_back':'verification_required',...outcome,releaseVerified:false,taskComplete:false,physicalDeviceVerified:false,leaseReceiptRef:c.authority.leaseReceiptRef,observedAt:new Date(this.clock()).toISOString()};
        return this.journal.finish(c.id,result,{knownOutcome:verified});
      } catch(error) {
        const possible=c.mutationPossible || error?.sideEffectPossible===true;
        result={contract:CONTRACT,requestId:job.requestId,taskId:job.taskId,nodeId:job.nodeId,sourceSha:job.sourceSha,actionHash:hash,generation:job.generation,state:possible?'reconciliation_required':'failed',code:publicError(error),runtimeReadbackVerified:false,releaseVerified:false,taskComplete:false,physicalDeviceVerified:false,observedAt:new Date(this.clock()).toISOString()};
        return this.journal.finish(c.id,result,{knownOutcome:!possible});
      }
    } finally {clearTimeout(timer);localAbort.abort();}
  }
}
