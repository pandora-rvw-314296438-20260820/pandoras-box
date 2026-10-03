export type TurnOperation = "send" | "retry" | "readback" | "cancel";
export type TurnRequest = {
  protocolVersion: 2; operation: TurnOperation; clientTurnId: string;
  clientAttemptId: string | null; generation: number; expectedGeneration: number | null;
  acknowledgeUnknown: boolean;
};
type Row = Record<string, unknown>;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function parseTurnRequest(body: Row): TurnRequest | null {
  if (body.protocolVersion === undefined || body.protocolVersion === 1) return null;
  if (body.protocolVersion !== 2) throw Error("CHAT_PROTOCOL_UNSUPPORTED");
  const operation = body.operation ?? "send";
  if (!["send", "retry", "readback", "cancel"].includes(String(operation))) throw Error("CHAT_OPERATION_INVALID");
  if (!uuid.test(String(body.clientTurnId ?? ""))) throw Error("CHAT_TURN_ID_INVALID");
  const attempt = body.clientAttemptId == null ? null : String(body.clientAttemptId);
  if ((["send", "retry"].includes(String(operation)) && !attempt) || (attempt !== null && !uuid.test(attempt))) throw Error("CHAT_ATTEMPT_ID_INVALID");
  if (body.acknowledgeUnknown !== undefined && typeof body.acknowledgeUnknown !== "boolean") throw Error("CHAT_OUTCOME_ACKNOWLEDGEMENT_INVALID");
  const acknowledgeUnknown = body.acknowledgeUnknown === true;
  if (acknowledgeUnknown && (operation !== "cancel" || attempt === null)) throw Error("CHAT_OUTCOME_ACKNOWLEDGEMENT_INVALID");
  const expected = body.expectedGeneration == null ? null : Number(body.expectedGeneration);
  const generation = Number(body.generation ?? (expected == null ? 1 : operation === "retry" ? expected + 1 : expected));
  if (!Number.isSafeInteger(generation) || generation < 1 || generation > 100 ||
      (expected !== null && (!Number.isSafeInteger(expected) || expected < 1 || expected > 100)) ||
      (["retry", "cancel"].includes(String(operation)) && expected === null) ||
      (operation === "send" && generation !== 1) ||
      (operation === "cancel" && generation !== expected) ||
      (operation === "retry" && generation !== expected! + 1)) throw Error("CHAT_GENERATION_INVALID");
  return { protocolVersion: 2, operation: operation as TurnOperation, clientTurnId: String(body.clientTurnId), clientAttemptId: attempt, generation, expectedGeneration: expected, acknowledgeUnknown };
}

export const terminalTurnStates = new Set(["completed", "cancelled", "failed_recoverably", "failed_permanently", "superseded"]);
export function classifyTurnFailure(error: unknown) {
  const e = error as {message?: string; code?: string; retryable?: boolean};
  const code = String(e?.code || e?.message || "CHAT_INTERNAL_FAILURE").replace(/[^A-Za-z0-9_:.-]/g, "_").slice(0,160);
  // Provider adapters use lower-case codes; preserve that bounded audit code
  // while classifying independently of its spelling. An explicit non-retryable
  // adapter result must never become a customer-facing Retry action.
  const classificationCode = code.toUpperCase();
  const message = String(e?.message ?? "").toUpperCase();
  if (["REQUEST_CANCELLED", "CHAT_GENERATION_STALE"].includes(classificationCode) ||
      ["REQUEST_CANCELLED", "CHAT_GENERATION_STALE"].includes(message)) return {status:"cancelled",retryable:false,code};
  if (/RECONCILIATION_REQUIRED|IN_PROGRESS|PREVIOUS_FAILED/.test(classificationCode)) return {status:"outcome_unknown",retryable:false,code};
  const permanent = e?.retryable === false || /SIGN_IN|ACCESS_REQUIRED|ROLE_REQUIRED|SCOPE|INVALID_MESSAGE|CREDENTIAL|LIMIT_REACHED|POLICY_UNAVAILABLE|MANUAL_MODEL_UNAVAILABLE|IDEMPOTENCY_CONFLICT|INVALID_REQUEST|AUTHENTICATION_FAILED|QUOTA_EXHAUSTED|UNSUPPORTED_CAPABILITY/.test(classificationCode);
  return {status:permanent ? "failed_permanently" : "failed_recoverably",retryable:!permanent,code};
}

// Hash the immutable submitted scope, not hydrated runtime snapshots or the
// server-assigned thread. The same first turn must reconcile after a lost ACK.
export function turnFingerprintInput(input: any) {
  return JSON.stringify({message:input.message,projectId:input.projectId ?? null,mode:input.mode,
    modelSelection:input.modelSelection ?? null,attachments:input.attachments,
    enterpriseContext:input.enterpriseContext ?? null,clientHistory:input.clientHistory??[]});
}

export function parseClientHistory(value:unknown) {
  if(value==null)return [];
  if(!Array.isArray(value)||value.length>32||new TextEncoder().encode(JSON.stringify(value)).byteLength>24576||value.length%2!==0)throw Error("CHAT_CLIENT_HISTORY_INVALID");
  const result:Array<{role:string;content:string;logicalTurnId:string;source:string}>=[];
  for(let i=0;i<value.length;i++){
    const row=value[i];
    if(!row||typeof row!=="object"||Array.isArray(row)||!uuid.test(String(row.logicalTurnId??""))||
      row.role!==(i%2===0?"user":"assistant")||typeof row.content!=="string"||!row.content.trim()||row.content.length>8000||
      !["local_device","character","device"].includes(row.source)||
      (i%2===1&&(row.logicalTurnId!==result[i-1].logicalTurnId||row.source!==result[i-1].source)))throw Error("CHAT_CLIENT_HISTORY_INVALID");
    result.push({role:row.role,content:row.content,logicalTurnId:row.logicalTurnId,source:row.source});
  }
  return result;
}
