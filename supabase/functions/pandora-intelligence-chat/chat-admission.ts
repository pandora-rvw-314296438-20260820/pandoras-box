/** One durable cloud-chat turn admission; provider retries remain in that turn. */
type Row = Record<string, unknown>;
type Caller = {
  rpc(name: string, parameters: Row): PromiseLike<{ data: unknown; error: unknown }>;
};
const record = (value: unknown): Row => value && typeof value === "object" && !Array.isArray(value) ? value as Row : {};
const uuid = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const digest = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{64}$/.test(value);

const notices = {
  CHAT_REQUEST_LIMIT_REACHED: { status: 429, message: "This client's cloud-chat request limit for the current period has been reached. Ask a Pandora administrator to review the request policy, or wait for the next period." },
  CHAT_REQUEST_POLICY_UNAVAILABLE: { status: 409, message: "This client's request protection needs attention. Review its subscription and request policy before retrying." },
  CHAT_REQUEST_IDEMPOTENCY_REQUIRED: { status: 409, message: "Start this request from the current Pandora composer so its status can be recovered." },
  CHAT_REQUEST_RATE_LIMITED: { status: 429, message: "Too many cloud-chat requests were started recently. Check Activity for existing requests and wait a minute before starting another." },
  CHAT_REQUEST_ALREADY_ADMITTED: { status: 409, message: "This request was already admitted. Open Activity to check its outcome; it has not been sent again." },
  CHAT_REQUEST_ADMISSION_DENIED: { status: 403, message: "This account cannot start cloud chat in the selected workspace. Return to Pandora and reopen the workspace." },
  CHAT_REQUEST_ADMISSION_UNAVAILABLE: { status: 503, message: "Pandora could not verify this request's admission. Check Activity for an existing outcome before starting another request." },
} as const;

export function chatAdmissionNotice(error: unknown): { code: string; status: number; message: string } | null {
  const code = error instanceof Error ? error.message : "";
  return Object.hasOwn(notices, code) ? { code, ...notices[code as keyof typeof notices] } : null;
}

export type ChatAdmissionInput = {
  organizationId: string;
  threadId: string;
  userMessageId: string;
  requestSha: string;
  entryId: string | null;
  activityJobId: string | null;
  activityClaimId: string | null;
  activityRequestFingerprint: string | null;
  metadata: Row;
};

export async function admitChatModelRun(user: Caller, input: ChatAdmissionInput): Promise<{ id: string; fallbackChainId: string }> {
  if (!uuid(input.organizationId) || !uuid(input.threadId) || !uuid(input.userMessageId) || !digest(input.requestSha) ||
      (input.entryId !== null && !uuid(input.entryId)) ||
      (input.activityJobId === null ? input.activityClaimId !== null || input.activityRequestFingerprint !== null :
        !uuid(input.activityJobId) || !uuid(input.activityClaimId) || !digest(input.activityRequestFingerprint))) {
    throw Error("CHAT_REQUEST_ADMISSION_UNAVAILABLE");
  }
  let result;
  try {
    result = await user.rpc("pandora_chat_request_admit_v1", {
      p_organization_id: input.organizationId,
      p_thread_id: input.threadId,
      p_user_message_id: input.userMessageId,
      p_request_sha256: input.requestSha,
      p_entry_id: input.entryId,
      p_metadata: {
        ...input.metadata,
        activity_job_id: input.activityJobId,
        activity_claim_id: input.activityClaimId,
        activity_request_fingerprint: input.activityRequestFingerprint,
      },
    });
  } catch {
    throw Error("CHAT_REQUEST_ADMISSION_UNAVAILABLE");
  }
  if (result.error) {
    throw Error(record(result.error).code === "42501" ? "CHAT_REQUEST_ADMISSION_DENIED" : "CHAT_REQUEST_ADMISSION_UNAVAILABLE");
  }
  const response = record(result.data);
  if (response.admitted === false) {
    const code = response.code;
    throw Error(typeof code === "string" && ["CHAT_REQUEST_LIMIT_REACHED", "CHAT_REQUEST_POLICY_UNAVAILABLE", "CHAT_REQUEST_IDEMPOTENCY_REQUIRED", "CHAT_REQUEST_RATE_LIMITED"].includes(code)
      ? code : "CHAT_REQUEST_ADMISSION_UNAVAILABLE");
  }
  if (response.admitted !== true || typeof response.replay !== "boolean" ||
      response.organization_id !== input.organizationId || response.thread_id !== input.threadId ||
      !uuid(response.id) || !uuid(response.fallback_chain_id)) throw Error("CHAT_REQUEST_ADMISSION_UNAVAILABLE");
  // A repeated receipt grants no right to repeat an uncertain provider call.
  if (response.replay) throw Error("CHAT_REQUEST_ALREADY_ADMITTED");
  return { id: response.id, fallbackChainId: response.fallback_chain_id };
}
