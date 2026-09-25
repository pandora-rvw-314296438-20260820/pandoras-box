import { spawn } from 'node:child_process';
import { createReadStream } from 'node:fs';
import { lstat, realpath, stat } from 'node:fs/promises';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { AresError, SHA256, demand, exact, immutable, integer, rejectSecrets } from './contract.mjs';

const TOOL_KEYS=new Set(['adb','emulator','aapt','java','apksignerJar']);
const ENV_KEYS=new Set(['SystemRoot','WINDIR','TEMP','TMP','ANDROID_USER_HOME','ANDROID_AVD_HOME','ANDROID_SDK_ROOT','JAVA_HOME']);
const samePath=(a,b)=>process.platform==='win32'?a.toLowerCase()===b.toLowerCase():a===b;

export async function hashFile(file,maxBytes=512*1024*1024) {
  const before=await stat(file);
  demand(before.isFile() && before.size>0 && before.size<=maxBytes,'ARES_FILE_SIZE_INVALID');
  const hash=createHash('sha256'); let count=0;
  for await(const chunk of createReadStream(file)) {
    count+=chunk.length; demand(count<=maxBytes,'ARES_FILE_SIZE_INVALID'); hash.update(chunk);
  }
  const after=await stat(file);
  demand(count===before.size && after.size===before.size && after.mtimeMs===before.mtimeMs && after.ino===before.ino,'ARES_FILE_CHANGED');
  return hash.digest('hex');
}
export async function containedFile(root,file,{extension,maxBytes=512*1024*1024}={}) {
  demand(path.isAbsolute(root) && path.isAbsolute(file) && !file.startsWith('\\\\'),'ARES_FILE_PATH_REQUIRED');
  const resolvedRoot=await realpath(root),resolved=await realpath(file),relative=path.relative(resolvedRoot,resolved);
  demand(relative && !relative.startsWith('..'+path.sep) && relative!=='..' && !path.isAbsolute(relative),'ARES_FILE_PATH_ESCAPE');
  const info=await lstat(file);
  demand(info.isFile() && !info.isSymbolicLink() && info.nlink===1 && samePath(path.resolve(file),resolved),'ARES_FILE_LINK_DENIED');
  if(extension)demand(path.extname(file).toLowerCase()===extension,'ARES_FILE_TYPE_DENIED');
  demand(info.size>0 && info.size<=maxBytes,'ARES_FILE_SIZE_INVALID');
  return resolved;
}

/** Actual bounded child processes. No inherited credentials, shell, or caller-selected executable. */
export class NodeToolRunner {
  constructor({tools,workingDirectory,environment={}}) {
    demand(tools && Object.keys(tools).length>0 && Object.keys(tools).every(k=>TOOL_KEYS.has(k)),'ARES_TOOL_CATALOG_INVALID');
    demand(path.isAbsolute(workingDirectory) && !workingDirectory.startsWith('\\\\'),'ARES_WORKING_DIRECTORY_REQUIRED');
    for(const [key,tool] of Object.entries(tools)) {
      exact(tool,['path','sha256']);
      demand(typeof tool.path==='string' && path.isAbsolute(tool.path) && !tool.path.startsWith('\\\\') && SHA256.test(tool.sha256),'ARES_TOOL_PIN_REQUIRED');
      demand(key==='apksignerJar' ? /\.jar$/i.test(tool.path) : !/\.(?:cmd|bat|ps1|sh|js|mjs)$/i.test(tool.path),'ARES_SHELL_WRAPPER_DENIED');
    }
    demand(Object.keys(environment).every(k=>ENV_KEYS.has(k)),'ARES_AMBIENT_ENVIRONMENT_DENIED');
    for(const value of Object.values(environment))demand(typeof value==='string' && value.length<4096 && !/[\r\n\0]/.test(value),'ARES_ENVIRONMENT_INVALID');
    rejectSecrets(environment);
    this.tools=immutable(structuredClone(tools));
    this.workingDirectory=workingDirectory;
    this.environment=immutable({...environment});
  }
  async verifiedPath(key) {
    const tool=this.tools[key]; demand(tool,'ARES_TOOL_UNAVAILABLE');
    const actual=await realpath(tool.path),info=await lstat(tool.path);
    demand(samePath(path.resolve(tool.path),actual) && info.isFile() && !info.isSymbolicLink(),'ARES_TOOL_LINK_DENIED');
    demand(await hashFile(actual,256*1024*1024)===tool.sha256,'ARES_TOOL_DIGEST_MISMATCH');
    return actual;
  }
  arguments(argv) {
    demand(Array.isArray(argv) && argv.length<=100 && argv.every(x=>typeof x==='string' && x.length<=4096 && !/[\0\r\n]/.test(x)),'ARES_ARGV_INVALID');
    return [...argv];
  }
  async run(key,argv,{timeoutMs=15000,maxBytes=1024*1024,signal,onSpawn}={}) {
    demand(key!=='apksignerJar','ARES_JAR_IS_NOT_EXECUTABLE');
    integer(timeoutMs,1,300000); integer(maxBytes,1,32*1024*1024);
    const args=this.arguments(argv),file=await this.verifiedPath(key);
    if(signal?.aborted)throw new AresError('ARES_CANCELLED');
    return new Promise((resolve,reject)=>{
      const started=performance.now(),startedAt=new Date().toISOString();
      let child,settled=false,spawned=false,size=0,stderrBytes=0;
      const chunks=[],stderrHash=createHash('sha256');
      const cleanup=()=>{clearTimeout(timer);signal?.removeEventListener('abort',abort);};
      const fail=code=>{
        if(settled)return;settled=true;cleanup();
        try {child?.kill('SIGTERM');}catch{}
        child?.stdout?.destroy();child?.stderr?.destroy();child?.unref();
        reject(new AresError(code,{sideEffectPossible:spawned}));
      };
      const abort=()=>fail('ARES_CANCELLED');
      const timer=setTimeout(()=>fail('ARES_PROCESS_TIMEOUT'),timeoutMs);
      signal?.addEventListener('abort',abort,{once:true});
      try {child=spawn(file,args,{cwd:this.workingDirectory,env:this.environment,shell:false,windowsHide:true,stdio:['ignore','pipe','pipe']});}
      catch {fail('ARES_PROCESS_START_FAILED');return;}
      child.once('spawn',()=>{
        spawned=true;
        try {onSpawn?.({pid:child.pid,tool:key,toolSha256:this.tools[key].sha256,startedAt});}
        catch {fail('ARES_JOURNAL_UNAVAILABLE');}
      });
      child.stdout.on('data',chunk=>{if(settled)return;size+=chunk.length;if(size>maxBytes){fail('ARES_PROCESS_OUTPUT_LIMIT');return;}chunks.push(chunk);});
      child.stderr.on('data',chunk=>{if(settled)return;stderrBytes+=chunk.length;if(stderrBytes>65536){fail('ARES_PROCESS_DIAGNOSTIC_LIMIT');return;}stderrHash.update(chunk);});
      child.once('error',()=>fail('ARES_PROCESS_START_FAILED'));
      child.once('close',(code,terminationSignal)=>{
        if(settled)return;settled=true;cleanup();
        resolve({code,terminationSignal,stdout:Buffer.concat(chunks),stderrSha256:stderrHash.digest('hex'),pid:child.pid,startedAt,completedAt:new Date().toISOString(),latencyMs:Math.max(0,Math.round(performance.now()-started)),tool:key,toolSha256:this.tools[key].sha256});
      });
      if(signal?.aborted)abort();
    });
  }
  async startManaged(key,argv,{signal,onSpawn}={}) {
    demand(key==='emulator','ARES_LONG_RUNNING_TOOL_DENIED');
    const file=await this.verifiedPath(key),args=this.arguments(argv);
    if(signal?.aborted)throw new AresError('ARES_CANCELLED');
    return new Promise((resolve,reject)=>{
      let spawned=false,child;
      const observedAt=new Date().toISOString(),instanceId=randomUUID();
      try {child=spawn(file,args,{cwd:this.workingDirectory,env:this.environment,shell:false,windowsHide:true,stdio:['ignore','ignore','ignore']});}
      catch {reject(new AresError('ARES_PROCESS_START_FAILED'));return;}
      child.once('error',()=>{if(!spawned)reject(new AresError('ARES_PROCESS_START_FAILED'));});
      child.once('spawn',()=>{
        spawned=true;
        try {onSpawn?.({pid:child.pid,tool:key,toolSha256:this.tools[key].sha256,startedAt:observedAt});}
        catch {reject(new AresError('ARES_JOURNAL_UNAVAILABLE',{sideEffectPossible:true}));return;}
        resolve(Object.freeze({instanceId,pid:child.pid,startedAt:observedAt,toolSha256:this.tools[key].sha256,isAlive:()=>child.exitCode===null && child.signalCode===null}));
      });
    });
  }
}
