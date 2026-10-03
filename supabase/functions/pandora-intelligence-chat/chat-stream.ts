type Row = Record<string, unknown>;

/** Decode a JSON string once, including escapes fragmented between chunks. */
class JsonStringCursor {
  private escape=0;private hex="";private high:number|null=null;private rawHigh=false;
  push(char:string):string|null {
    const code=char.charCodeAt(0);
    if(this.rawHigh){
      if(code<0xdc00||code>0xdfff)throw Error("INVALID_MODEL_OUTPUT");
      const value=String.fromCharCode(this.high!,code);this.high=null;this.rawHigh=false;return value;
    }
    if(this.escape===3){if(char!=="\\")throw Error("INVALID_MODEL_OUTPUT");this.escape=4;return "";}
    if(this.escape===4){if(char!=="u")throw Error("INVALID_MODEL_OUTPUT");this.escape=5;return "";}
    if(this.escape===2||this.escape===5){
      if(!/^[0-9a-f]$/i.test(char))throw Error("INVALID_MODEL_OUTPUT");
      this.hex+=char;if(this.hex.length<4)return "";
      const scalar=parseInt(this.hex,16),pair=this.escape===5;this.hex="";this.escape=0;
      if(pair){
        if(scalar<0xdc00||scalar>0xdfff)throw Error("INVALID_MODEL_OUTPUT");
        const value=String.fromCharCode(this.high!,scalar);this.high=null;return value;
      }
      if(scalar>=0xd800&&scalar<=0xdbff){this.high=scalar;this.escape=3;return "";}
      if(scalar>=0xdc00&&scalar<=0xdfff)throw Error("INVALID_MODEL_OUTPUT");
      return String.fromCharCode(scalar);
    }
    if(this.escape===1){
      this.escape=0;
      if(char==="u"){this.escape=2;return "";}
      const simple:Record<string,string>={'"':'"','\\':'\\','/':'/','b':'\b','f':'\f','n':'\n','r':'\r','t':'\t'};
      if(!(char in simple))throw Error("INVALID_MODEL_OUTPUT");return simple[char];
    }
    if(char==='"')return null;
    if(char==="\\"){this.escape=1;return "";}
    if(code<32||code>=0xdc00&&code<=0xdfff)throw Error("INVALID_MODEL_OUTPUT");
    if(code>=0xd800&&code<=0xdbff){this.high=code;this.rawHigh=true;return "";}
    return char;
  }
}

/** Only the top-level reply string is decoded for incremental delivery. The
 * cursor never revisits prior input; metadata is parsed once before delivery.
 * The complete response still goes through the existing final validator. */
export class ReplyDeltaDecoder {
  private size=0;private depth=0;
  private mode:"scan"|"string"|"colon"|"value"|"reply"|"done"|"buffered"="scan";
  private prefix:string[]=[];private token:string[]=[];private text:string[]=[];
  private cursor=new JsonStringCursor();
  constructor(private readonly requireSafeMetadata=false) {}
  push(fragment:string):string {
    this.size+=fragment.length;if(this.size>262144)throw Error("INVALID_MODEL_OUTPUT");
    const delta:string[]=[];
    for(const char of fragment.split("")){
      if(this.mode==="done"||this.mode==="buffered")break;
      if(this.requireSafeMetadata&&this.mode!=="reply")this.prefix.push(char);
      if(this.mode==="reply"||this.mode==="string"){
        const value=this.cursor.push(char);
        if(value===null){
          if(this.mode==="reply")this.mode="done";
          else{this.mode=this.depth===1&&this.token.join("")==="reply"?"colon":"scan";this.token=[];}
        }else if(this.mode==="reply"){if(value)delta.push(value);}
        else if(this.depth===1&&value)this.token.push(value);
        continue;
      }
      if(this.mode==="colon"){
        if(/\s/.test(char))continue;
        if(char===":"){this.mode="value";continue;}
        this.mode="scan";
      }
      if(this.mode==="value"){
        if(/\s/.test(char))continue;
        if(char!=='"')throw Error("INVALID_MODEL_OUTPUT");
        if(this.requireSafeMetadata){
          let meta;
          try{meta=JSON.parse(this.prefix.join("")+'"}');}catch{this.mode="buffered";this.prefix=[];continue;}
          this.prefix=[];
          if(!["chat","clarify","other"].includes(meta.intent)||meta.handoff!==null||
            !Array.isArray(meta.toolProposals)||meta.toolProposals.length){this.mode="buffered";continue;}
        }
        this.cursor=new JsonStringCursor();this.mode="reply";continue;
      }
      if(char==="{"||char==="["){this.depth++;continue;}
      if(char==="}"||char==="]"){this.depth--;continue;}
      if(char==='"'){this.cursor=new JsonStringCursor();this.token=[];this.mode="string";}
    }
    const next=delta.join("");if(next)this.text.push(next);return next;
  }
  get visibleText(){return this.text.join("");}
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
