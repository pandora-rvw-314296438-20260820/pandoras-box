import {generateKeyPairSync,randomUUID,sign} from 'node:crypto';
import {mkdtemp,writeFile,rm,mkdir} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {canonical,sha256,normalizeJob,OPERATIONS} from '../contract.mjs';
import {SignedAresProofs,AresLeaseAuthority} from '../authority.mjs';
import {AresJournal} from '../journal.mjs';
import {AresArtifactVerifier} from '../artifact.mjs';
import {AresHost,normalizeProfile,profileDigest} from '../host.mjs';

export const keys=generateKeyPairSync('ed25519');
export const pkg='com.banataosystems.pandora_mobile';
export const source='a'.repeat(40);
export const signerDigest='b'.repeat(64);
export function signed(payload,type='PANDORA_ARES_GRANT_V1',{privateKey=keys.privateKey,kid='key1'}={}) {
  const h=Buffer.from(canonical({alg:'EdDSA',kid,typ:type})).toString('base64url');
  const p=Buffer.from(canonical(payload)).toString('base64url');
  return h+'.'+p+'.'+sign(null,Buffer.from(h+'.'+p),privateKey).toString('base64url');
}
export function common(nodeId='node-fixture',patch={}) {
  const now=Math.floor(Date.now()/1000);
  return {iss:'operations-m3-fixture',aud:nodeId,iat:now,nbf:now,exp:now+300,jti:randomUUID(),...patch};
}
export function grant(job,patch={}) {
  return {...common(job.nodeId),organizationId:job.organizationId,projectId:job.projectId,taskId:job.taskId,workerId:job.workerId,leaseId:job.leaseId,generation:job.generation,requestId:job.requestId,operation:job.operation,actionHash:sha256(canonical(job)),sourceSha:job.sourceSha,profileSha256:job.profileSha256,serial:job.target.serial,avdName:job.target.avdName,packageName:job.target.packageName,environment:'test',risk:OPERATIONS[job.operation].risk,decision:'ALLOW',policyRef:'fixture:scoped-owner-policy',approvalRef:OPERATIONS[job.operation].risk==='destructive'?'fixture:exact-destructive-approval':null,controlRevision:1,...patch};
}
export class FakeSdk {
  constructor(){
    this.tools=Object.fromEntries(['adb','emulator','aapt','java','apksignerJar'].map(k=>[k,{path:'/synthetic-sdk/'+k,sha256:'d'.repeat(64)}]));
    this.calls=[];this.present=false;this.alive=false;this.ready=true;this.avd='Pandora_Test';this.abis=['x86_64'];this.foreground=pkg;
    this.installed=new Map();this.assets=new Map();this.permissionGranted=false;this.nextPid=100;this.hook=null;
  }
  async verifiedPath(k){return this.tools[k].path;}
  async startManaged(tool,args,{onSpawn}={}) {
    this.calls.push({tool,args,mutating:true});this.present=true;this.alive=true;
    const pid=++this.nextPid;
    onSpawn?.({pid,tool,toolSha256:this.tools[tool].sha256,startedAt:new Date().toISOString()});
    return {pid,isAlive:()=>this.alive};
  }
  async run(tool,args,{onSpawn}={}) {
    this.calls.push({tool,args});const pid=++this.nextPid;
    onSpawn?.({pid,tool,toolSha256:this.tools[tool].sha256,startedAt:new Date().toISOString()});
    const result=(stdout='',code=0)=>({stdout:Buffer.isBuffer(stdout)?stdout:Buffer.from(stdout),code,terminationSignal:null,pid,tool,toolSha256:this.tools[tool].sha256,latencyMs:1,stderrSha256:sha256('')});
    const hook=await this.hook?.(tool,args,result);if(hook!==undefined)return hook;
    if(tool==='emulator' && args[0]==='-list-avds')return result(this.avd+'\n');
    if(tool==='aapt') {
      const hash=path.basename(args.at(-1),'.apk');const m=this.assets.get(hash);
      return result(`package: name='${m.packageName}' versionCode='${m.versionCode}' versionName='fixture'\nnative-code: ${m.abis.map(a=>"'"+a+"'").join(' ')}\n`);
    }
    if(tool==='java')return result('Signer #1 certificate SHA-256 digest: '+signerDigest+'\n');
    if(tool!=='adb')throw Error('unhandled synthetic tool');
    if(args[0]==='devices')return result('List of devices attached\n'+(this.present?'emulator-5554\tdevice product:fixture\n':''));
    const a=args.slice(2),command=a.join(' ');
    if(command==='get-state')return result(this.present?'device':'offline');
    if(command==='shell getprop sys.boot_completed')return result(this.ready?'1':'0');
    if(command==='shell getprop ro.kernel.qemu')return result('1');
    if(command==='shell getprop ro.product.cpu.abilist')return result(this.abis.join(','));
    if(command==='shell pm path android')return result('package:/system/framework/framework-res.apk');
    if(command==='emu avd name')return result(this.avd+'\nOK\n');
    if(command==='emu kill'){this.present=false;this.alive=false;return result('OK: killing emulator');}
    if(a[0]==='install') {
      const hash=path.basename(a.at(-1),'.apk'),m=this.assets.get(hash);this.installed.set(m.packageName,{...m,hash});
      return result('Performing Streamed Install\nSuccess\n');
    }
    if(command.startsWith('shell pm path ')) {
      const name=a[3];return result(this.installed.has(name)?'package:/data/app/'+name+'/base.apk':'');
    }
    if(command.startsWith('shell sha256sum ')) {
      const name=a[2].split('/')[3];return result((this.installed.get(name)?.hash??'missing')+'  '+a[2]);
    }
    if(command.startsWith('shell dumpsys package ')) {
      const name=a[3],m=this.installed.get(name);
      return result(m?`Package [${name}]:\n versionCode=${m.versionCode} minSdk=23\n android.permission.CAMERA: granted=${this.permissionGranted}\n`:'');
    }
    if(a[0]==='uninstall'){this.installed.delete(a[1]);return result('Success');}
    if(command.startsWith('shell pm clear '))return result('Success');
    if(command.startsWith('shell pm grant ')){this.permissionGranted=true;return result();}
    if(command.startsWith('shell pm revoke ')){this.permissionGranted=false;return result();}
    if(command.startsWith('shell am start ')){this.foreground=a.at(-1).split('/')[0];return result('Status: ok');}
    if(command.startsWith('shell am force-stop ')){this.foreground='';return result();}
    if(command.startsWith('shell pidof '))return result(this.foreground===a[2]?'1234':'',this.foreground===a[2]?0:1);
    if(command==='shell dumpsys window windows')return result('  mCurrentFocus=Window{abc u0 '+this.foreground+'/.MainActivity}');
    if(command==='shell wm size')return result('Physical size: 1080x1920');
    if(command.startsWith('shell input '))return result();
    if(command.startsWith('shell am instrument '))return result('Time: 0.1\nOK (2 tests)\nINSTRUMENTATION_CODE: -1\n');
    if(command==='exec-out screencap -p')return result(Buffer.from([137,80,78,71,13,10,26,10,0,0,0,0]));
    if(a[0]==='logcat')return result('FATAL EXCEPTION: main\njava.lang.IllegalStateException: private customer text\nat com.banataosystems.Foo.run(Foo.java:42)\nBearer '+ 's'.repeat(40));
    if(command.startsWith('shell screenrecord '))return result();
    if(command.startsWith('exec-out cat '))return result(Buffer.from([0,0,0,20,102,116,121,112,109,112,52,50]));
    if(command.startsWith('shell rm '))return result();
    if(command==='emu network status')return result('download speed: 0 bits/s\nminimum latency: 0 ms\nOK');
    if(command.startsWith('emu network speed ')||command.startsWith('emu network delay '))return result('OK');
    throw Error('Unhandled synthetic SDK command '+command);
  }
}
export async function fixture({profilePatch={},sdk=new FakeSdk()}={}) {
  const directory=await mkdtemp(path.join(os.tmpdir(),'pandora-ares-test-'));
  const nodeId='node-fixture',organizationId=randomUUID(),projectId=randomUUID();
  const profile=normalizeProfile({organizationId,projectId,serial:'emulator-5554',avdName:'Pandora_Test',packages:[pkg],launchComponents:{[pkg]:pkg+'/.MainActivity'},expectedAbis:['x86_64'],syntheticDataOnly:true,suites:{smoke:{packageName:pkg,testPackage:pkg+'.test',component:pkg+'.test/androidx.test.runner.AndroidJUnitRunner',artifactRef:'artifact:fixture-instrumentation',sourceSha:source}},...profilePatch});
  const proofs=new SignedAresProofs({keys:{key1:keys.publicKey},issuer:'operations-m3-fixture',nodeId});
  const controls={revoked:false,wrongNonce:false,hung:false,checks:0};
  const authority=new AresLeaseAuthority({proofs,readCurrentLease:async request=>{
    controls.checks++;if(controls.hung)return new Promise(()=>{});
    const claims={...common(nodeId,{exp:Math.floor(Date.now()/1000)+20}),nonce:controls.wrongNonce?'wrong':request.nonce,organizationId:request.organizationId,projectId:request.projectId,leaseId:request.leaseId,generation:request.generation,actionHash:request.actionHash,controlRevision:request.controlRevision,state:controls.revoked?'revoked':'running',receiptRef:'fixture:lease-readback'};
    return signed(claims,'PANDORA_ARES_LEASE_V1');
  }});
  const journal=new AresJournal({directory:path.join(directory,'state')});
  const assets=new Map();const artifactRoot=path.join(directory,'artifacts');await mkdir(artifactRoot);
  for(const [ref,packageName] of [['artifact:fixture-candidate',pkg],['artifact:fixture-instrumentation',pkg+'.test']]) {
    const bytes=Buffer.from('SYNTHETIC APK BYTES; SDK MOCKED: '+packageName),hash=sha256(bytes),file=path.join(artifactRoot,hash+'.apk');await writeFile(file,bytes);
    const m={...common(nodeId),organizationId,projectId,artifactRef:ref,sourceSha:source,apkSha256:hash,packageName,versionCode:17,signerSha256:signerDigest,abis:['x86_64'],verificationRef:'fixture:artifact-proof-not-production'};
    assets.set(ref,{path:file,manifestToken:signed(m,'PANDORA_ARES_APK_V1'),manifest:m});sdk.assets.set(hash,m);
  }
  const artifacts=new AresArtifactVerifier({proofs,resolveArtifact:async ref=>{const a=assets.get(ref);return {path:a.path,manifestToken:a.manifestToken};},artifactRoot,cacheRoot:path.join(directory,'cache'),runner:sdk});
  const host=new AresHost({nodeId,profiles:[profile],runner:sdk,authority,journal,artifactVerifier:artifacts,evidenceRoot:path.join(directory,'evidence'),pollMs:5});
  function job(operation='ares.health.read',patch={}) {
    const base={version:1,requestId:randomUUID(),organizationId,projectId,taskId:'ARES-FIXTURE',workerId:'CHATGPT-FIXTURE',nodeId,leaseId:randomUUID(),generation:1,sourceSha:source,profileSha256:profileDigest(nodeId,profile,sdk.tools),operation,target:{serial:profile.serial,avdName:profile.avdName,packageName:OPERATIONS[operation].app?pkg:null},artifactRef:OPERATIONS[operation].artifact?'artifact:fixture-candidate':null,parameters:{},timeoutMs:1000,...patch};
    return normalizeJob(base);
  }
  async function execute(operation,patch={}) {const j=job(operation,patch);return host.execute(j,signed(grant(j)));}
  async function boot(){const result=await execute('ares.emulator.start');if(result.state!=='executed_and_read_back')throw Error(JSON.stringify(result));return result;}
  async function install(){await boot();const result=await execute('ares.apk.install');if(result.state!=='executed_and_read_back')throw Error(JSON.stringify(result));return result;}
  async function close(){journal.close();await rm(directory,{recursive:true,force:true});}
  return {directory,nodeId,organizationId,projectId,profile,proofs,controls,authority,journal,sdk,assets,artifacts,host,job,execute,boot,install,close};
}
