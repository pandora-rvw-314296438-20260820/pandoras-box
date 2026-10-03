type Row = Record<string, unknown>;

/** Incremental JSON string decoding restricted to the top-level `reply` field.
 * No handoff, tool proposal, chain of thought, or raw partial JSON enters chat.
 * The final object must still pass the existing complete response validator. */
export class ReplyDeltaDecoder {
  private raw = "";
  private delivered = "";
  constructor(private readonly requireSafeMetadata=false) {}
  push(fragment: string): string {
    this.raw += fragment;
    if (this.raw.length > 262144) throw Error("INVALID_MODEL_OUTPUT");
    const text = extractReplyPrefix(this.raw,this.requireSafeMetadata);
    if (text === null) return "";
    if (!text.startsWith(this.delivered)) throw Error("INVALID_MODEL_OUTPUT");
    const next = text.slice(this.delivered.length);
    this.delivered = text;
    return next;
  }
  get visibleText() { return this.delivered; }
}

function readString(raw: string, start: number): {value:string,end:number,complete:boolean} {
  let value="";
  for (let i=start+1;i<raw.length;i++) {
    const char=raw[i];
    if(char==='"')return{value,end:i+1,complete:true};
    if(char==='\\') {
      if(i+1>=raw.length)return{value,end:raw.length,complete:false};
      const escaped=raw[++i];
      const simple:Record<string,string>={'"':'"','\\':'\\','/':'/','b':'\b','f':'\f','n':'\n','r':'\r','t':'\t'};
      if(escaped in simple){value+=simple[escaped];continue;}
      if(escaped!=='u')throw Error("INVALID_MODEL_OUTPUT");
      if(i+4>=raw.length)return{value,end:raw.length,complete:false};
      const digits=raw.slice(i+1,i+5);if(!/^[0-9a-f]{4}$/i.test(digits))throw Error("INVALID_MODEL_OUTPUT");
      const code=parseInt(digits,16);i+=4;
      // Do not emit an unpaired high surrogate between provider chunks.
      if(code>=0xd800&&code<=0xdbff){
        if(i+6>=raw.length)return{value,end:raw.length,complete:false};
        const pair=raw.slice(i+1,i+7);if(!/^\\u[dD][c-fC-F][0-9a-fA-F]{2}$/.test(pair))throw Error("INVALID_MODEL_OUTPUT");
        value+=String.fromCharCode(code,parseInt(pair.slice(2),16));i+=6;
      }else if(code>=0xdc00&&code<=0xdfff)throw Error("INVALID_MODEL_OUTPUT");
      else value+=String.fromCharCode(code);
    }else{
      if(char.charCodeAt(0)<32)throw Error("INVALID_MODEL_OUTPUT");
      const code=char.charCodeAt(0);
      if(code>=0xd800&&code<=0xdbff&&i+1>=raw.length)return{value,end:raw.length,complete:false};
      value+=char;
    }
  }
  return{value,end:raw.length,complete:false};
}
function extractReplyPrefix(raw:string,requireSafeMetadata=false):string|null {
  let depth=0;
  for(let i=0;i<raw.length;i++){
    const c=raw[i];
    if(c==='{'||c==='['){depth++;continue;}
    if(c==='}'||c===']'){depth--;continue;}
    if(c!=='"')continue;
    const s=readString(raw,i);if(!s.complete)return null;
    i=s.end-1;
    if(depth!==1||s.value!=="reply")continue;
    let k=s.end;while(/\s/.test(raw[k]??"")&&k<raw.length)k++;
    if(raw[k]!==':')continue;
    k++;while(/\s/.test(raw[k]??"")&&k<raw.length)k++;
    if(k>=raw.length)return null;
    if(raw[k]!=='"')throw Error("INVALID_MODEL_OUTPUT");
    if(requireSafeMetadata){
      // Require the non-executing classification before exposing partial prose.
      // A provider that sends reply first is safely buffered for full validation.
      let meta;
      try{meta=JSON.parse(raw.slice(0,k)+'""}');}catch{return null;}
      if(!["chat","clarify","other"].includes(meta.intent)||meta.handoff!==null||
        !Array.isArray(meta.toolProposals)||meta.toolProposals.length)return null;
    }
    return readString(raw,k).value;
  }
  return null;
}

export type ChatEventSink = (event: Row) => void;
export function eventStreamResponse(run:(send:ChatEventSink)=>Promise<Response>,headers:Record<string,string>={}) {
  const encoder=new TextEncoder();let closed=false;
  const stream=new ReadableStream<Uint8Array>({
    start(controller){
      const send:ChatEventSink=event=>{if(!closed)controller.enqueue(encoder.encode(`event: ${String(event.type??"message")}\ndata: ${JSON.stringify(event)}\n\n`));};
      // The request continues after a transport disconnect so accepted execution
      // can finalize durably. Explicit cancellation uses the owned turn RPC.
      const work=run(send).then(async response=>{
        const body=await response.json();send({...body,type:body.status==="completed"?"completed":body.ok===false?"failed":"readback"});
      }).catch(()=>send({type:"failed",ok:false,code:"CHAT_TRANSPORT_FAILED",status:"outcome_unknown",retryable:false}))
        .finally(()=>{if(!closed){closed=true;controller.close();}});
      const runtime=(globalThis as any).EdgeRuntime;if(runtime?.waitUntil)runtime.waitUntil(work);
    },
    cancel(){closed=true;},
  });
  return new Response(stream,{headers:{...headers,"content-type":"text/event-stream; charset=utf-8","cache-control":"no-cache, no-transform","x-accel-buffering":"no","x-content-type-options":"nosniff"}});
}

export async function consumeServerEvents(response:Response,onEvent:(event:Row)=>Promise<void>) {
  if(!response.body)throw Error("PROVIDER_STREAM_MISSING");
  const reader=response.body.getReader(),decoder=new TextDecoder();let pending="";
  try{
    while(true){
      const {done,value}=await reader.read();
      pending+=(done?decoder.decode():decoder.decode(value,{stream:true}));
      pending=pending.replace(/\r\n/g,"\n");
      if(pending.length>262144)throw Error("PROVIDER_STREAM_INVALID");
      let delimiter;
      while((delimiter=pending.indexOf("\n\n"))>=0){
        const block=pending.slice(0,delimiter).replace(/\r/g,"");pending=pending.slice(delimiter+2);
        const data=block.split("\n").filter(x=>x.startsWith("data:")).map(x=>x.slice(5).trimStart()).join("\n");
        if(data){const event=JSON.parse(data);if(!event||typeof event!=="object"||Array.isArray(event))throw Error("PROVIDER_STREAM_INVALID");await onEvent(event);}
      }
      if(done){if(pending.trim())throw Error("PROVIDER_STREAM_TRUNCATED");break;}
    }
  }finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
}
