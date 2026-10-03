export function containsCredentialMaterial(value:unknown) {
  return /AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|postgres(?:ql)?:\/\/[^:\s@]+:[^@\s]+@/i.test(JSON.stringify(value));
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

/** Provider output is untrusted before completion too. Keep enough lexical
 * lookahead that a split credential/context prefix can never already be painted.
 * JSON lines remain buffered until their whole context boundary can be checked.
 * A short response is honestly buffered, not re-emitted as artificial tokens. */
export class ReplyVisibilityGuard {
  private source="";private delivered="";private held=false;
  push(delta:string) {
    this.source+=delta;
    if(this.source.length>32000||containsCredentialMaterial(this.source))throw Error("INVALID_MODEL_OUTPUT");
    // A prefix can be an innocuous code example. Hold it for final validation;
    // never emit it speculatively or disable a legitimate technical response.
    if(/AIza|github_pat_|gh[pousr]_|-----BEGIN|postgres(?:ql)?:\/\//i.test(this.source)||this.source.split(/\r?\n/).some(privateContextLine))this.held=true;
    if(this.held)return "";
    let end=Math.max(0,this.source.length-96);
    const lineStart=this.source.lastIndexOf("\n",end-1)+1;
    if(this.source.slice(lineStart).trimStart().startsWith("{"))end=lineStart;
    const confirmed=sanitizeVisibleReply(this.source.slice(0,end),false);
    if(!confirmed.startsWith(this.delivered))throw Error("INVALID_MODEL_OUTPUT");
    const next=confirmed.slice(this.delivered.length);this.delivered=confirmed;return next;
  }
  finish(validatedReply:string) {
    if(containsCredentialMaterial(validatedReply)||!validatedReply.startsWith(this.delivered))throw Error("INVALID_MODEL_OUTPUT");
    const tail=validatedReply.slice(this.delivered.length);this.delivered=validatedReply;return tail;
  }
}
