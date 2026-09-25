const test=require('node:test');
require('../workers/pandora-ares/test/http-acceptance.mjs');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const {spawn}=require('node:child_process');
const {randomUUID,generateKeyPairSync}=require('node:crypto');
let c,a,j,p,h,apk,f;
test.before(async()=>{
  [c,a,j,p,h,apk,f]=await Promise.all([
    import('../workers/pandora-ares/contract.mjs'),import('../workers/pandora-ares/authority.mjs'),
    import('../workers/pandora-ares/journal.mjs'),import('../workers/pandora-ares/process.mjs'),
    import('../workers/pandora-ares/host.mjs'),import('../workers/pandora-ares/artifact.mjs'),
    import('../workers/pandora-ares/test/fixtures.mjs'),
  ]);
});
async function fixture(t,options){const x=await f.fixture(options);t.after(()=>x.close());return x;}
function modified(job,patch){return {...structuredClone(job),...patch};}

for(const serial of ['phone-12345','192.168.1.2:5555','emulator-5555','emulator-5684','emulator-5554;id']) {
  test('Reject nonexclusive/nonemulator target '+serial,()=>assert.throws(()=>c.portForSerial(serial),/ARES_/));
}
test('Strict job contract permits only bounded registered operations',async t=>{
  const x=await fixture(t),job=x.job();assert.equal(job.operation,'ares.health.read');assert.ok(Object.isFrozen(job.target));
  for(const patch of [{sql:'select 1'},{operation:'shell'},{profileSha256:null},{sourceSha:'main'},{timeoutMs:1},{generation:'1'},{parameters:{command:'whoami'}}])assert.throws(()=>c.normalizeJob(modified(job,patch)),/ARES_/);
});
test('Protected packages and shell-like AVDs are rejected',async t=>{
  const x=await fixture(t),job=x.job('ares.apk.install');
  for(const target of [{...job.target,packageName:'com.globe.gcash.android'},{...job.target,avdName:'../other'},{...job.target,avdName:'foo & calc'}])assert.throws(()=>c.normalizeJob(modified(job,{target})),/ARES_/);
});
for(const text of ['$(id)','a; id','a\nnext','secret|more','$(Get-Content x)','a"b','a&b']) {
  test('ADB typing rejects shell syntax '+JSON.stringify(text),async t=>{const x=await fixture(t);assert.throws(()=>x.job('ares.ui.test',{parameters:{steps:[{kind:'type',text}]}}),/UNSAFE_TEXT/);});
}
test('Permission changes cannot grant SMS/contacts or arbitrary special access',async t=>{
  const x=await fixture(t);for(const permission of ['android.permission.READ_SMS','android.permission.READ_CONTACTS','android.permission.WRITE_SECURE_SETTINGS'])assert.throws(()=>x.job('ares.permission.change',{parameters:{permission,mode:'grant'}}),/PERMISSION_DENIED/);
});
test('Job and profile reject raw credentials',async t=>{
  const x=await fixture(t);assert.throws(()=>x.job('ares.ui.test',{parameters:{steps:[{kind:'type',text:'Bearer '+ 's'.repeat(40)}]}}),/SECRET|UNSAFE/);
  assert.throws(()=>h.normalizeProfile({...x.profile,syntheticDataOnly:false}),/SYNTHETIC/);
});
test('Signed exact grant is accepted and private signing keys are not accepted by host verifier',async t=>{
  const x=await fixture(t),job=x.job();assert.equal(x.proofs.grant(f.signed(f.grant(job)),job).actionHash,c.actionDigest(job));
  assert.throws(()=>new a.SignedAresProofs({keys:{bad:f.keys.privateKey},issuer:'issuer',nodeId:'node'}),/PUBLIC_KEY/);
});
for(const patch of [{aud:'other-node'},{iss:'foreign'},{exp:1},{nbf:9999999999},{environment:'production'},{decision:'DENY'},{actionHash:'f'.repeat(64)},{generation:99},{profileSha256:'e'.repeat(64)},{controlRevision:-1}]) {
  test('Signed grant rejects scope/time/authority drift '+Object.keys(patch)[0],async t=>{
    const x=await fixture(t),job=x.job();assert.throws(()=>x.proofs.grant(f.signed(f.grant(job,patch)),job),/ARES_/);
  });
}
test('Signature from a different key cannot authorize execution',async t=>{
  const x=await fixture(t),job=x.job(),foreign=generateKeyPairSync('ed25519');assert.throws(()=>x.proofs.grant(f.signed(f.grant(job),undefined,{privateKey:foreign.privateKey}),job),/BAD_SIGNATURE/);
});
test('Destructive job requires exact approval binding',async t=>{
  const x=await fixture(t),job=x.job('ares.app.clear_data');assert.throws(()=>x.proofs.grant(f.signed(f.grant(job,{approvalRef:null})),job),/EXACT_APPROVAL/);
});
test('Lease challenge must be fresh and exact before any SDK process starts',async t=>{
  const x=await fixture(t),job=x.job();x.controls.wrongNonce=true;
  await assert.rejects(()=>x.host.execute(job,f.signed(f.grant(job))),/LEASE_BINDING/);assert.equal(x.sdk.calls.length,0);
});
test('Revocation before dispatch prevents all SDK calls',async t=>{
  const x=await fixture(t);x.controls.revoked=true;await assert.rejects(()=>x.execute('ares.health.read'),/LEASE_REVOKED/);assert.equal(x.sdk.calls.length,0);
});
test('Changed trusted profile/tool hashes cannot reuse a signed job',async t=>{
  const x=await fixture(t),job=x.job();x.sdk.tools.adb.sha256='e'.repeat(64);await assert.rejects(()=>x.host.execute(job,f.signed(f.grant(job))),/PROFILE_DRIFT/);assert.equal(x.sdk.calls.length,0);
});
test('Actual healthy observation of an absent guest is not an emulator-ready claim',async t=>{
  const x=await fixture(t),result=await x.execute('ares.health.read');assert.equal(result.state,'executed_and_read_back');assert.equal(result.observation.ready,false);assert.equal(result.observation.present,false);assert.equal(result.physicalDeviceVerified,false);
});
test('Host startup needs ADB, Android boot, package manager, ABI and AVD readbacks',async t=>{
  const x=await fixture(t),result=await x.boot();assert.equal(result.observation.ready,true);assert.equal(result.taskComplete,false);assert.equal(result.releaseVerified,false);
  const launch=x.sdk.calls.find(v=>v.tool==='emulator' && v.args.includes('-avd'));assert.ok(launch.args.includes('-no-snapshot'));assert.ok(launch.args.includes('-read-only'));assert.ok(!launch.args.includes('-wipe-data'));
});
test('Process existence alone cannot pass boot readiness; ambiguous startup keeps resources',async t=>{
  const x=await fixture(t);x.sdk.ready=false;const result=await x.execute('ares.emulator.start',{timeoutMs:100});assert.equal(result.state,'reconciliation_required');assert.equal(x.journal.db.prepare('select count(*) n from resource_holds').get().n,1);
});
test('Host refuses to adopt or kill an emulator not started by this daemon',async t=>{
  const x=await fixture(t);x.sdk.present=true;x.sdk.alive=true;const stop=await x.execute('ares.emulator.stop');assert.equal(stop.state,'failed');assert.equal(stop.code,'ARES_MANAGED_INSTANCE_REQUIRED');assert.ok(!x.sdk.calls.some(v=>v.args.includes('kill')));
});
test('Known managed emulator is stopped and absence is read back before release',async t=>{
  const x=await fixture(t);await x.boot();const result=await x.execute('ares.emulator.stop');assert.equal(result.state,'executed_and_read_back');assert.equal(x.journal.managed('emulator-5554'),null);assert.equal(result.observation.present,false);
});
test('Restart cannot trust a stale PID/managed record as current ownership',async t=>{
  const x=await fixture(t);await x.boot();x.host.bootSession=randomUUID();const result=await x.execute('ares.emulator.stop');assert.equal(result.code,'ARES_MANAGED_INSTANCE_REQUIRED');
});
test('Exact signed APK is hashed, signer-checked, installed, then binary/version read back',async t=>{
  const x=await fixture(t),result=await x.install();const manifest=x.assets.get('artifact:fixture-candidate').manifest;
  assert.equal(result.observation.apkSha256,manifest.apkSha256);assert.equal(result.observation.signerSha256,manifest.signerSha256);assert.equal(result.observation.versionCode,17);
  assert.ok(x.sdk.calls.some(v=>v.tool==='java'&&v.args.includes('--print-certs')));const install=x.sdk.calls.find(v=>v.args[2]==='install');assert.deepEqual(install.args.slice(2,4),['install','-r']);assert.ok(!install.args.includes('-d'));
});
test('APK with altered bytes is denied before adb install',async t=>{
  const x=await fixture(t);await x.boot();await fs.appendFile(x.assets.get('artifact:fixture-candidate').path,'tampered');const result=await x.execute('ares.apk.install');assert.equal(result.code,'ARES_APK_SOURCE_DIGEST_MISMATCH');assert.ok(!x.sdk.calls.some(v=>v.args[2]==='install'));
});
test('Artifact proof from wrong source or project cannot authorize install',async t=>{
  const x=await fixture(t);await x.boot();const asset=x.assets.get('artifact:fixture-candidate');asset.manifestToken=f.signed({...asset.manifest,sourceSha:'c'.repeat(40)},'PANDORA_ARES_APK_V1');const result=await x.execute('ares.apk.install');assert.equal(result.code,'ARES_ARTIFACT_SCOPE_MISMATCH');
});
test('Incompatible guest ABI does not reach install',async t=>{
  const x=await fixture(t,{profilePatch:{expectedAbis:['arm64-v8a']}});x.sdk.abis=['arm64-v8a'];await x.boot();const result=await x.execute('ares.apk.install');assert.equal(result.code,'ARES_APK_ABI_INCOMPATIBLE');
});
test('Installed byte mismatch remains reconciliation-required, not installed success',async t=>{
  const x=await fixture(t);await x.boot();x.sdk.hook=(tool,args,result)=>args.slice(2,4).join(' ')==='shell sha256sum'?result('0'.repeat(64)+' base.apk'):undefined;
  const result=await x.execute('ares.apk.install');assert.equal(result.state,'reconciliation_required');assert.equal(result.code,'ARES_INSTALLED_DIGEST_MISMATCH');
});
test('UI tap/type/swipe only run against target app, exact APK and actual screen bounds',async t=>{
  const x=await fixture(t);await x.install();const result=await x.execute('ares.ui.test',{parameters:{steps:[{kind:'launch'},{kind:'tap',x:10,y:20},{kind:'type',text:'test marker'},{kind:'swipe',x:10,y:20,x2:30,y2:40,durationMs:100},{kind:'back'}]}});
  assert.equal(result.state,'executed_and_read_back');assert.equal(result.observation.completedSteps,5);assert.equal(result.observation.semanticUiAccepted,false);assert.ok(x.sdk.calls.some(v=>v.args.includes('test%smarker')));
});
test('UI input refuses protected/non-target foreground',async t=>{
  const x=await fixture(t);await x.install();x.sdk.foreground='com.globe.gcash.android';const result=await x.execute('ares.ui.test',{parameters:{steps:[{kind:'tap',x:10,y:20}]}});assert.equal(result.code,'ARES_FOREGROUND_NOT_TARGET');assert.ok(!x.sdk.calls.some(v=>v.args.includes('tap')));
});
test('UI coordinates are bounded by observed display rather than global integer limit alone',async t=>{
  const x=await fixture(t);await x.install();const result=await x.execute('ares.ui.test',{parameters:{steps:[{kind:'tap',x:5000,y:10}]}});assert.equal(result.code,'ARES_COORDINATE_OUTSIDE_DISPLAY');
});
test('Clear-data acknowledgement is not fabricated post-reset application verification',async t=>{
  const x=await fixture(t);await x.install();const result=await x.execute('ares.app.clear_data');assert.equal(result.state,'verification_required');assert.equal(result.runtimeReadbackVerified,false);assert.equal(x.journal.db.prepare('select count(*) n from resource_holds').get().n,1);
});
test('Runtime permission grant/revoke require actual package permission readback',async t=>{
  const x=await fixture(t);await x.install();const grant=await x.execute('ares.permission.change',{parameters:{permission:'android.permission.CAMERA',mode:'grant'}});assert.equal(grant.observation.granted,true);const revoke=await x.execute('ares.permission.change',{parameters:{permission:'android.permission.CAMERA',mode:'revoke'}});assert.equal(revoke.observation.granted,false);
});
test('Registered exact-source instrumentation suite executes real argv and requires nonzero passes',async t=>{
  const x=await fixture(t);await x.install();const result=await x.execute('ares.test.run',{parameters:{suiteId:'smoke'}});assert.equal(result.state,'executed_and_read_back');assert.equal(result.observation.testsPassed,2);assert.ok(x.sdk.calls.some(v=>v.args.includes('instrument')));
});
for(const output of ['OK (0 tests)\nINSTRUMENTATION_CODE: -1','OK (2 tests)\nINSTRUMENTATION_CODE: 0','FAILURES!!!\nOK (2 tests)\nINSTRUMENTATION_CODE: -1','INSTRUMENTATION_STATUS_CODE: -2\nOK (2 tests)\nINSTRUMENTATION_CODE: -1']) {
  test('Instrumentation rejects false pass '+output.slice(0,30),()=>assert.throws(()=>h.instrumentationResult(output),/INSTRUMENTATION_FAILED/));
}
test('Screenshot/video artifacts remain private and never imply physical acceptance',async t=>{
  const x=await fixture(t);await x.install();for(const parameters of [{kind:'screenshot'},{kind:'video',seconds:1}]){const result=await x.execute('ares.evidence.read',{parameters});assert.equal(result.state,'executed_and_read_back');assert.equal(result.observation.artifact.private,true);assert.equal(result.physicalDeviceVerified,false);assert.ok(!JSON.stringify(result).includes(x.directory));}
});
test('Crash evidence is scoped to target PID and strips raw messages/credentials',async t=>{
  const x=await fixture(t);await x.install();const result=await x.execute('ares.evidence.read',{parameters:{kind:'crashes'}});assert.equal(result.state,'executed_and_read_back');const file=(await fs.readdir(path.join(x.directory,'evidence'))).find(v=>v.endsWith('.txt'));const content=await fs.readFile(path.join(x.directory,'evidence',file),'utf8');assert.ok(!content.includes('private customer'));assert.ok(!content.includes('Bearer'));assert.ok(content.includes('IllegalStateException'));assert.ok(x.sdk.calls.some(v=>v.args.includes('--pid=1234')));
});
test('Network SDK acknowledgement does not claim verified throughput',async t=>{
  const x=await fixture(t);await x.boot();const result=await x.execute('ares.network.configure',{parameters:{speed:'edge',delay:'edge'}});assert.equal(result.state,'verification_required');assert.equal(result.runtimeReadbackVerified,false);
});
test('Owner revocation after a mutation preserves uncertain state and blocks later commands',async t=>{
  const x=await fixture(t);await x.boot();x.sdk.hook=(tool,args)=>{if(args[2]==='install')x.controls.revoked=true;};const result=await x.execute('ares.apk.install');assert.equal(result.state,'reconciliation_required');assert.equal(result.code,'ARES_LEASE_REVOKED');assert.ok(!x.sdk.calls.some(v=>v.args.includes('sha256sum')));
});
test('Repeated exact request replays stored receipt without repeated SDK execution',async t=>{
  const x=await fixture(t),job=x.job(),token=f.signed(f.grant(job));const first=await x.host.execute(job,token);const count=x.sdk.calls.length;const second=await x.host.execute(job,token);assert.equal(first.state,'executed_and_read_back');assert.equal(second.replayed,true);assert.equal(x.sdk.calls.length,count);
});
test('Same request ID with changed action is rejected rather than replayed',async t=>{
  const x=await fixture(t),job=x.job();await x.host.execute(job,f.signed(f.grant(job)));const changed=x.job('ares.emulator.start',{requestId:job.requestId});await assert.rejects(()=>x.host.execute(changed,f.signed(f.grant(changed))),/REPLAY_CONFLICT/);
});
test('Durable journal retains unknown work across separate connection restart',async t=>{
  const x=await fixture(t),job=x.job();const first=x.journal.begin(job);x.journal.dispatched(first.id,{mutating:true,tool:'adb',toolSha256:'a'.repeat(64)});
  const second=new j.AresJournal({directory:path.join(x.directory,'state')});try{assert.equal(second.begin(job).state,'reconciliation_required');const other=x.job();assert.equal(second.begin(other).state,'resource_busy');}finally{second.close();}
});
test('Journal events and receipts cannot be overwritten',async t=>{
  const x=await fixture(t);await x.execute('ares.health.read');assert.throws(()=>x.journal.db.exec("UPDATE events SET phase='fake'"),/IMMUTABLE_EVENT/);assert.throws(()=>x.journal.db.exec('DELETE FROM receipts'),/IMMUTABLE_RECEIPT/);
});
test('Host deadline bounds a hanging lease transport before SDK launch',async t=>{
  const x=await fixture(t);x.controls.hung=true;const job=x.job('ares.health.read',{timeoutMs:100});await assert.rejects(()=>x.host.execute(job,f.signed(f.grant(job))),/CANCELLED/);assert.equal(x.sdk.calls.length,0);
});
test('Bounded Node runner executes a pinned binary with no inherited environment credential',async t=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'ares-process-'));t.after(()=>fs.rm(directory,{recursive:true,force:true}));const real=await fs.realpath(process.execPath);const hash=await p.hashFile(real,256*1024*1024);
  const env={};if(process.platform==='win32')env.SystemRoot=process.env.SystemRoot;
  const runner=new p.NodeToolRunner({tools:{adb:{path:real,sha256:hash}},workingDirectory:directory,environment:env});
  process.env.ARES_TEST_SECRET='fixture-do-not-inherit';t.after(()=>delete process.env.ARES_TEST_SECRET);
  const result=await runner.run('adb',['-e','process.stdout.write(process.env.ARES_TEST_SECRET ?? "ABSENT")']);assert.equal(result.stdout.toString(),'ABSENT');assert.equal(result.code,0);
  const limited=runner.run('adb',['-e','process.stdout.write("x".repeat(10000))'],{maxBytes:64});await assert.rejects(()=>limited,/OUTPUT_LIMIT/);
  await assert.rejects(()=>runner.run('adb',['-e','setInterval(()=>{},1000)'],{timeoutMs:300}),/PROCESS_TIMEOUT/);
});
test('Runner refuses unknown binaries, changed hashes and command wrappers',async t=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'ares-process-'));t.after(()=>fs.rm(directory,{recursive:true,force:true}));const real=await fs.realpath(process.execPath);
  const runner=new p.NodeToolRunner({tools:{adb:{path:real,sha256:'0'.repeat(64)}},workingDirectory:directory});await assert.rejects(()=>runner.run('adb',['--version']),/DIGEST_MISMATCH/);
  assert.throws(()=>new p.NodeToolRunner({tools:{adb:{path:path.join(directory,'tool.cmd'),sha256:'a'.repeat(64)}},workingDirectory:directory}),/SHELL_WRAPPER/);
  assert.throws(()=>new p.NodeToolRunner({tools:{adb:{path:real,sha256:'a'.repeat(64)}},workingDirectory:directory,environment:{OPENAI_API_KEY:'not-a-real-key'}}),/ENVIRONMENT_DENIED/);
});
test('Artifact path confinement rejects paths outside private root',async t=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'ares-path-'));t.after(()=>fs.rm(directory,{recursive:true,force:true}));await fs.mkdir(path.join(directory,'root'));await fs.writeFile(path.join(directory,'outside.apk'),'fixture');await assert.rejects(()=>p.containedFile(path.join(directory,'root'),path.join(directory,'outside.apk'),{extension:'.apk'}),/PATH_ESCAPE/);
});
test('Separate Node processes compete for one durable serial hold without double admission',async t=>{
  const x=await fixture(t),script=path.join(__dirname,'../workers/pandora-ares/test/race-child.mjs');
  const jobs=Array.from({length:4},()=>x.job());
  const results=await Promise.all(jobs.map(job=>new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[script,path.join(x.directory,'state'),JSON.stringify(job)],{stdio:['ignore','pipe','pipe']});let out='';child.stdout.on('data',b=>out+=b);child.once('error',reject);child.once('close',code=>{if(code!==0)reject(Error('race child failed'));else resolve(JSON.parse(out));});
  })));
  assert.equal(results.filter(v=>v.claimed).length,1);assert.equal(results.filter(v=>v.state==='resource_busy').length,3);
});
