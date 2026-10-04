// Password userinfo ends before the host, path, query or fragment. Quotes and
// backslashes also bound JSON strings so serialization cannot join unrelated
// lines or fields into a credential. Reuse this boundary in the source redactor.
export const postgresCredentialPrefix=/postgres(?:ql)?:\/\/[^:\s@"\\/?#<>`]*:[^@\s"\\/?#<>`]+@/i;
export function containsCredentialMaterial(value:unknown) {
  const encoded=JSON.stringify(value)??"";
  return /AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i.test(encoded)||postgresCredentialPrefix.test(encoded);
}
export function privateContextLine(line:string) {
  const s=line.trim(),lower=s.toLowerCase();
  return lower.includes("bounded enterprise page context:")||lower.includes("bounded project context:")||
    lower.startsWith("operations room contract:")||lower.startsWith("treat this context as navigation and scope information only.")||
    lower.startsWith("the authenticated actorrole is authoritative.")||lower.startsWith("never map roles across identityscope namespaces.")||
    (s.startsWith("{")&&(/"surface"\s*:/.test(s)||/"identityScope"\s*:/.test(s)||/"enterprise_/.test(s)));
}
export function sanitizeVisibleReply(value:unknown,fallback=true) {
  const input=typeof value==="string"?value:"";
  const result=input.split(/\r?\n/).filter(line=>!privateContextLine(line)).join("\n").replace(/\n{3,}/g,"\n\n").trim();
  return result||(fallback?"I couldn't produce a clean reply for that turn. Please try again.":"");
}

/** Model-generated handoff data can describe requested work, but cannot prove
 * that a worker started it. Verified capability replies use their separate
 * persisted readback path and are not passed through this model-only boundary. */
export function visibleModelReply(value:unknown,handoff:unknown) {
  const proposed=handoff!==null&&typeof handoff==="object"&&(handoff as Record<string,unknown>).required===true;
  return proposed?"I've captured the requested action, but I haven't carried it out yet.":sanitizeVisibleReply(value);
}

/** Provider output is untrusted before completion too. Only a bounded tail is
 * rechecked across chunks. JSON lines stay buffered until their context boundary
 * is known; lexical prefixes stop incremental delivery pending final validation.
 * The final validator remains authoritative and short replies remain buffered. */
export class ReplyVisibilityGuard {
  private size=0;private overlap="";private held=false;
  private linePrefix="";private jsonLine:string[]|null=null;private carriage=false;
  private started=false;private whitespace:string[]=[];private newlines=0;
  private queue:string[]=[];private head=0;private delivered:string[]=[];
  push(delta:string) {
    this.size+=delta.length;if(this.size>32000)throw Error("INVALID_MODEL_OUTPUT");
    const window=this.overlap+delta;this.overlap=window.slice(-96);
    if(containsCredentialMaterial(window))throw Error("INVALID_MODEL_OUTPUT");
    if(/AIza|github_pat_|gh[pousr]_|-----BEGIN|postgres(?:ql)?:\/\//i.test(window)||
      /bounded enterprise page context:|bounded project context:/i.test(window))this.held=true;
    if(this.held)return "";
    for(let i=0;i<delta.length;i++){
      const char=delta[i];
      if(this.carriage){this.carriage=false;if(char!=="\n")this.lineCharacter("\r");}
      if(char==="\r"){this.carriage=true;continue;}
      this.lineCharacter(char);if(this.held)return "";
    }
    let end=Math.max(this.head,this.queue.length-96);
    // A lookahead boundary must not divide a Unicode scalar between events.
    if(end>this.head){const code=this.queue[end-1].charCodeAt(0);if(code>=0xd800&&code<=0xdbff)end--;}
    const next=this.queue.slice(this.head,end).join("");this.head=end;
    if(this.head>=4096){this.queue=this.queue.slice(this.head);this.head=0;}
    if(next)this.delivered.push(next);return next;
  }
  private lineCharacter(char:string) {
    if(char==="\n"){
      if(this.jsonLine!==null){
        const line=this.jsonLine.join("");this.jsonLine=null;
        if(privateContextLine(line)){this.held=true;return;}
        for(let i=0;i<line.length;i++)this.normalizedCharacter(line[i]);
      }
      this.normalizedCharacter("\n");this.linePrefix="";return;
    }
    const first=this.linePrefix.length===0&&!/\s/.test(char);
    if(this.linePrefix.length<96&&(this.linePrefix.length>0||first))this.linePrefix+=char;
    if(privateContextLine(this.linePrefix)){this.held=true;return;}
    if(first&&char==="{")this.jsonLine=[];
    if(this.jsonLine!==null)this.jsonLine.push(char);else this.normalizedCharacter(char);
  }
  private normalizedCharacter(char:string) {
    if(/\s/.test(char)){
      this.newlines=char==="\n"?this.newlines+1:0;
      if(this.newlines>2)return;
      if(this.started)this.whitespace.push(char);
      return;
    }
    this.newlines=0;
    for(const space of this.whitespace)this.queue.push(space);
    this.whitespace=[];this.started=true;this.queue.push(char);
  }
  finish(validatedReply:string) {
    const delivered=this.delivered.join("");
    if(containsCredentialMaterial(validatedReply)||!validatedReply.startsWith(delivered))throw Error("INVALID_MODEL_OUTPUT");
    const tail=validatedReply.slice(delivered.length);this.delivered=[validatedReply];return tail;
  }
}
