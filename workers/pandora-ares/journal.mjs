import { DatabaseSync } from 'node:sqlite';
import { lstatSync, mkdirSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { AresError, actionDigest, canonical, demand, integer, rejectSecrets, sha256 } from './contract.mjs';

function localDirectory(directory) {
  demand(typeof directory === 'string' && path.isAbsolute(directory) && !directory.startsWith('\\\\'), 'ARES_LOCAL_STATE_REQUIRED');
  mkdirSync(directory, {recursive:true, mode:0o700});
  const expected=path.resolve(directory), actual=realpathSync(directory);
  const comparable=x=>process.platform==='win32'?x.toLowerCase():x;
  demand(comparable(expected)===comparable(actual) && !lstatSync(directory).isSymbolicLink(), 'ARES_STATE_PATH_ESCAPE');
  return actual;
}

/** Local delivery fencing, not an alternative to the Operations Room's authority. */
export class AresJournal {
  constructor({directory, clock=Date.now}) {
    this.directory=localDirectory(directory);
    this.clock=clock;
    const file=path.join(this.directory,'ares-journal-v1.sqlite');
    try { const stat=lstatSync(file); demand(stat.isFile()&&!stat.isSymbolicLink()&&stat.nlink===1,'ARES_JOURNAL_PATH_INVALID'); }
    catch(error) { if(error.code!=='ENOENT')throw error; }
    this.db=new DatabaseSync(file);
    this.db.exec(`
      PRAGMA foreign_keys=ON;
      PRAGMA busy_timeout=5000;
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS jobs (
        id TEXT PRIMARY KEY, action_hash TEXT NOT NULL, resource_key TEXT NOT NULL,
        request_key TEXT NOT NULL, operation TEXT NOT NULL, task_key TEXT NOT NULL,
        organization_id TEXT NOT NULL, project_id TEXT NOT NULL, node_id TEXT NOT NULL,
        generation INTEGER NOT NULL, state TEXT NOT NULL CHECK(state IN ('admitted','executing','ambiguous','completed','failed')),
        mutation_possible INTEGER NOT NULL DEFAULT 0 CHECK(mutation_possible IN (0,1)),
        receipt_id TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS resource_holds (
        resource_key TEXT PRIMARY KEY, job_id TEXT NOT NULL UNIQUE REFERENCES jobs(id)
      );
      CREATE TABLE IF NOT EXISTS receipts (
        id TEXT PRIMARY KEY, job_id TEXT NOT NULL REFERENCES jobs(id),
        digest TEXT NOT NULL, body TEXT NOT NULL, observed_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS events (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT NOT NULL UNIQUE,
        job_id TEXT NOT NULL REFERENCES jobs(id), phase TEXT NOT NULL, body TEXT NOT NULL, occurred_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS managed_instances (
        serial TEXT PRIMARY KEY, avd_name TEXT NOT NULL, node_id TEXT NOT NULL,
        boot_session TEXT NOT NULL, process_id INTEGER NOT NULL, launch_job_id TEXT NOT NULL REFERENCES jobs(id),
        created_at INTEGER NOT NULL
      );
      CREATE TRIGGER IF NOT EXISTS receipts_no_update BEFORE UPDATE ON receipts BEGIN SELECT RAISE(ABORT,'ARES_IMMUTABLE_RECEIPT'); END;
      CREATE TRIGGER IF NOT EXISTS receipts_no_delete BEFORE DELETE ON receipts BEGIN SELECT RAISE(ABORT,'ARES_IMMUTABLE_RECEIPT'); END;
      CREATE TRIGGER IF NOT EXISTS events_no_update BEFORE UPDATE ON events BEGIN SELECT RAISE(ABORT,'ARES_IMMUTABLE_EVENT'); END;
      CREATE TRIGGER IF NOT EXISTS events_no_delete BEFORE DELETE ON events BEGIN SELECT RAISE(ABORT,'ARES_IMMUTABLE_EVENT'); END;
    `);
  }
  transaction(fn) {
    this.db.exec('BEGIN IMMEDIATE');
    try { const result=fn(); this.db.exec('COMMIT'); return result; }
    catch(error) { this.db.exec('ROLLBACK'); throw error; }
  }
  jobId(job) { return sha256(canonical([job.organizationId,job.projectId,job.nodeId,job.requestId])); }
  begin(job) {
    return this.transaction(()=>{
      const id=this.jobId(job), hash=actionDigest(job), resource=job.nodeId+'/'+job.target.serial;
      const old=this.db.prepare('SELECT * FROM jobs WHERE id=?').get(id);
      if(old) {
        demand(old.action_hash===hash,'ARES_REQUEST_REPLAY_CONFLICT');
        if(old.receipt_id && ['completed','failed'].includes(old.state)) {
          const row=this.db.prepare('SELECT body FROM receipts WHERE id=?').get(old.receipt_id);
          return {claimed:false,replayed:true,result:JSON.parse(row.body),id};
        }
        return {claimed:false,state:'reconciliation_required',id};
      }
      if(this.db.prepare('SELECT 1 FROM resource_holds WHERE resource_key=?').get(resource))return {claimed:false,state:'resource_busy',id};
      const now=this.clock();
      this.db.prepare('INSERT INTO jobs(id,action_hash,resource_key,request_key,operation,task_key,organization_id,project_id,node_id,generation,state,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)')
        .run(id,hash,resource,job.requestId,job.operation,job.taskId,job.organizationId,job.projectId,job.nodeId,job.generation,'admitted',now,now);
      this.db.prepare('INSERT INTO resource_holds(resource_key,job_id) VALUES(?,?)').run(resource,id);
      this.append(id,'admitted',{actionHash:hash,taskId:job.taskId,nodeId:job.nodeId,generation:job.generation});
      return {claimed:true,id,actionHash:hash};
    });
  }
  append(id, phase, body) {
    demand(/^[a-z_]{1,60}$/.test(phase),'ARES_EVENT_PHASE');
    rejectSecrets(body);
    const text=canonical(body);
    demand(Buffer.byteLength(text)<=12000,'ARES_EVENT_LIMIT');
    const eventId=randomUUID(), at=this.clock();
    this.db.prepare('INSERT INTO events(event_id,job_id,phase,body,occurred_at) VALUES(?,?,?,?,?)').run(eventId,id,phase,text,at);
    return {eventId,occurredAt:new Date(at).toISOString()};
  }
  dispatched(id,{mutating,tool,toolSha256}) {
    return this.transaction(()=>{
      const row=this.db.prepare('SELECT state FROM jobs WHERE id=?').get(id);
      demand(row && ['admitted','executing'].includes(row.state),'ARES_DELIVERY_FENCED');
      this.db.prepare('UPDATE jobs SET state=?,mutation_possible=MAX(mutation_possible,?),updated_at=? WHERE id=?')
        .run('executing',mutating?1:0,this.clock(),id);
      return this.append(id,'process_started',{tool,toolSha256,mutating:mutating===true});
    });
  }
  state(id) { return this.db.prepare('SELECT state,mutation_possible,action_hash FROM jobs WHERE id=?').get(id)??null; }
  finish(id, result, {knownOutcome}) {
    return this.transaction(()=>{
      const row=this.db.prepare('SELECT * FROM jobs WHERE id=?').get(id);
      demand(row,'ARES_JOB_MISSING');
      rejectSecrets(result);
      const text=canonical(result), digest=sha256(text);
      demand(Buffer.byteLength(text)<=24000,'ARES_RECEIPT_LIMIT');
      if(['completed','failed'].includes(row.state)) {
        const old=this.db.prepare('SELECT digest,body FROM receipts WHERE id=?').get(row.receipt_id);
        demand(old.digest===digest,'ARES_FINAL_REPLAY_CONFLICT');
        return JSON.parse(old.body);
      }
      const state=knownOutcome?(result.state==='executed_and_read_back'?'completed':'failed'):'ambiguous';
      if(knownOutcome && state==='completed')demand(result.runtimeReadbackVerified===true,'ARES_READBACK_REQUIRED');
      const receiptId=randomUUID();
      this.db.prepare('INSERT INTO receipts VALUES(?,?,?,?,?)').run(receiptId,id,digest,text,this.clock());
      this.db.prepare('UPDATE jobs SET state=?,receipt_id=?,updated_at=? WHERE id=?').run(state,receiptId,this.clock(),id);
      if(knownOutcome)this.db.prepare('DELETE FROM resource_holds WHERE job_id=?').run(id);
      this.append(id,'execution_'+state,{receiptId,receiptSha256:digest,previousReceiptId:row.receipt_id??null,releaseVerified:false,physicalDeviceVerified:false});
      return result;
    });
  }
  managed(serial) { return this.db.prepare('SELECT * FROM managed_instances WHERE serial=?').get(serial)??null; }
  recordManaged(job,id,bootSession,pid) {
    integer(pid,1,0x7fffffff);
    demand(!this.managed(job.target.serial),'ARES_INSTANCE_OWNERSHIP_CONFLICT');
    this.db.prepare('INSERT INTO managed_instances VALUES(?,?,?,?,?,?,?)')
      .run(job.target.serial,job.target.avdName,job.nodeId,bootSession,pid,id,this.clock());
  }
  forgetManaged(serial,bootSession) {
    const result=this.db.prepare('DELETE FROM managed_instances WHERE serial=? AND boot_session=?').run(serial,bootSession);
    demand(result.changes===1,'ARES_INSTANCE_OWNERSHIP_CONFLICT');
  }
  pendingEvents(afterSequence=0,limit=100) {
    integer(afterSequence,0,Number.MAX_SAFE_INTEGER); integer(limit,1,1000);
    return this.db.prepare('SELECT * FROM events WHERE sequence>? ORDER BY sequence LIMIT ?').all(afterSequence,limit)
      .map(x=>({...x,body:JSON.parse(x.body)}));
  }
  close() { this.db.close(); }
}
