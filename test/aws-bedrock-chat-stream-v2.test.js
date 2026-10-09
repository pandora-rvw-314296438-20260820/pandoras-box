"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { crc32 } = require("node:zlib");
const crypto = require("node:crypto");
const { Readable } = require("node:stream");
const { EventEmitter } = require("node:events");
const { converseWithBedrockTarget, signBedrockRequest } = require("../src/providers/aws-bedrock-runtime.js");
const { createBedrockChatHandler } = require("../src/providers/aws-bedrock-chat-http.js");

// Fixture credentials never leave these fake transports. The production decoder
// uses a table CRC implementation; fixtures use Node's independent zlib CRC32.
const credentials = { accessKeyId: "FIXTURE", secretAccessKey: "fixture-secret", sessionToken: "fixture-session" };
const nativeHistory = [
  { role: "user", content: [{ text: "Hi" }] },
  { role: "assistant", content: [{ text: "Hello, Mark." }] },
  { role: "user", content: [{ text: "What's up?" }] },
];
const target = { modelId: "vendor.model-v1", invocationTarget: "us.vendor.model-v1", credentials };
const ticket = "a".repeat(64);
const claim = { modelId: target.modelId, invocationTarget: target.invocationTarget, providerName: "Fixture",
  requestBody: { messages: nativeHistory, system: "Answer naturally.", maxTokens: 256, stream: true } };

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function stringHeader(name, value) {
  const nameBytes = Buffer.from(name), valueBytes = Buffer.from(value), lengths = Buffer.alloc(3);
  lengths[0] = 7; lengths.writeUInt16BE(valueBytes.length, 1);
  return Buffer.concat([Buffer.from([nameBytes.length]), nameBytes, lengths, valueBytes]);
}

function frame(type, payload, { messageType = "event", rawPayload, extraHeaders = [] } = {}) {
  const typeHeader = messageType === "exception" ? ":exception-type" : messageType === "error" ? ":error-code" : ":event-type";
  const headers = Buffer.concat([stringHeader(":message-type", messageType), stringHeader(typeHeader, type),
    stringHeader(":content-type", "application/json"), ...extraHeaders]);
  const bytes = rawPayload || Buffer.from(JSON.stringify(payload));
  const prelude = Buffer.alloc(12), total = 16 + headers.length + bytes.length;
  prelude.writeUInt32BE(total, 0); prelude.writeUInt32BE(headers.length, 4);
  prelude.writeUInt32BE(crc32(prelude.subarray(0, 8)), 8);
  const withoutCrc = Buffer.concat([prelude, headers, bytes]), trailer = Buffer.alloc(4);
  trailer.writeUInt32BE(crc32(withoutCrc));
  return Buffer.concat([withoutCrc, trailer]);
}

function events(deltas = ["{\"reply\":\"Hello", " 🌏\"}"]) {
  return [
    frame("messageStart", { role: "assistant" }),
    ...deltas.map((text) => frame("contentBlockDelta", { contentBlockIndex: 0, delta: { text } })),
    frame("contentBlockStop", { contentBlockIndex: 0 }),
    frame("messageStop", { stopReason: "end_turn" }),
    frame("metadata", { usage: { inputTokens: 12, outputTokens: 6, totalTokens: 18 }, metrics: { latencyMs: 37 },
      trace: { hidden: "PRIVATE_DIAGNOSTIC_FIXTURE" } }),
  ];
}

function chunked(bytes, size = bytes.length) {
  let offset = 0;
  return new ReadableStream({
    pull(controller) {
      if (offset >= bytes.length) { controller.close(); return; }
      const next = Math.min(offset + size, bytes.length);
      controller.enqueue(bytes.subarray(offset, next)); offset = next;
    },
  });
}

function providerResponse(body, status = 200) {
  return new Response(body, { status, headers: {
    "content-type": "application/vnd.amazon.eventstream", "x-amzn-requestid": "fixture-request-1",
  } });
}

function bufferedResponse(text = "Hello") {
  return Response.json({ output: { message: { role: "assistant", content: [{ text }] } },
    usage: { inputTokens: 3, outputTokens: 2, totalTokens: 5 }, stopReason: "end_turn" },
  { headers: { "x-amzn-requestid": "fixture-buffered-1" } });
}

function request(body = { ticket }, accept = "text/event-stream") {
  const req = Readable.from([Buffer.from(JSON.stringify(body))]);
  req.method = "POST"; req.headers = { accept }; return req;
}

class Reply extends EventEmitter {
  constructor() { super(); this.headers = {}; this.writes = []; this.writableEnded = false; this.destroyed = false; this.headersSent = false; }
  status(value) { this.statusCode = value; return this; }
  setHeader(name, value) { this.headers[name] = value; }
  flushHeaders() { this.headersSent = true; }
  write(value) { this.headersSent = true; this.writes.push(value); return true; }
  json(value) { this.jsonBody = value; this.end(); return this; }
  end() { this.writableEnded = true; this.emit("close"); }
  events() { return this.writes.join("").split("\n\n").filter(Boolean).map((item) => JSON.parse(item.split("\ndata: ")[1])); }
}

function fakeBridgeFetch({ ticketClaim = claim, runtimeResponse = () => providerResponse(chunked(Buffer.concat(events()))), inspect } = {}) {
  const calls = [];
  const fetchFn = async (url, init) => {
    calls.push({ url, init });
    if (url.endsWith("/functions/v1/mcpmaster-supabase-control")) {
      assert.deepEqual(JSON.parse(init.body), { action: "bedrock_chat_ticket_claim", tokenSha256: crypto.createHash("sha256").update(ticket).digest("hex") });
      assert.equal(init.headers.authorization, "Bearer fixture-oidc");
      assert.equal(init.signal.aborted, false);
      return Response.json({ ok: true, operations: ticketClaim });
    }
    if (url === "https://sts.amazonaws.com/") {
      assert.equal(new URLSearchParams(init.body).get("WebIdentityToken"), "fixture-oidc");
      return new Response("<Credentials><AccessKeyId>FIXTURE</AccessKeyId><SecretAccessKey>fixture-secret</SecretAccessKey>" +
        "<SessionToken>fixture-session</SessionToken><Expiration>2099-01-01T00:00:00Z</Expiration></Credentials>");
    }
    inspect?.(url, init);
    return runtimeResponse(url, init);
  };
  return { calls, fetchFn };
}

test("native history retains real user/assistant roles on buffered Converse", async () => {
  let received;
  const messages = [...nativeHistory.slice(0, -1), { role: "user", content: [{ text: "What's up?" }, { text: "Read this" },
    { image: { format: "png", source: { bytes: "aGVsbG8=" } } }] }];
  const result = await converseWithBedrockTarget({ ...target, messages, system: [{ text: "System context." }],
    fetchFn: async (url, init) => { received = JSON.parse(init.body); assert.match(url, /\/converse$/); return bufferedResponse(); } });
  assert.deepEqual(received.messages, messages);
  assert.deepEqual(received.system, [{ text: "System context." }]);
  assert.equal(result.streaming, false);
  assert.equal(result.timeToFirstTokenMs, null, "buffered completion must not invent TTFT");
});

test("ambiguous history, invalid roles and assistant image input are denied before network work", async () => {
  const invalid = [
    { messages: nativeHistory, parts: [{ type: "text", text: "Flattened" }] },
    { messages: [] },
    { messages: [{ role: "system", content: [{ text: "Escalated context" }] }] },
    { messages: [{ role: "assistant", content: [{ image: { format: "png", source: { bytes: "aA==" } } }] }] },
  ];
  for (const input of invalid) {
    let network = 0;
    await assert.rejects(converseWithBedrockTarget({ ...target, ...input, fetchFn: async () => { network++; } }), /AWS_BEDROCK_INPUT_INVALID/);
    assert.equal(network, 0);
  }
});

test("ConverseStream signs its own canonical endpoint without altering buffered signatures", () => {
  const input = { region: "us-east-1", modelId: "amazon.nova-lite-v1:0", body: { messages: nativeHistory }, credentials,
    now: new Date("2026-10-03T12:00:00Z") };
  const streamed = signBedrockRequest({ ...input, stream: true }), buffered = signBedrockRequest(input);
  assert.match(streamed.url, /\/amazon\.nova-lite-v1:0\/converse-stream$/);
  assert.notEqual(streamed.headers.authorization, buffered.headers.authorization);
});

test("actual AWS frames survive single-byte and arbitrary fragmentation, including UTF-8", async (t) => {
  const wire = Buffer.concat(events());
  for (const size of [1, 2, 7, 11, 12, 13, 53, wire.length]) {
    await t.test(`chunk size ${size}`, async () => {
      const deltas = [];
      let network = 0;
      const result = await converseWithBedrockTarget({ ...target, messages: nativeHistory, stream: true,
        onDelta: (text) => deltas.push(text),
        fetchFn: async (url, init) => {
          network++; assert.match(url, /\/converse-stream$/);
          assert.equal(init.headers.accept, "application/vnd.amazon.eventstream");
          assert.deepEqual(JSON.parse(init.body).messages, nativeHistory);
          return providerResponse(chunked(wire, size));
        } });
      assert.equal(network, 1);
      assert.deepEqual(deltas, ["{\"reply\":\"Hello", " 🌏\"}"]);
      assert.equal(result.text, deltas.join(""));
      assert.equal(result.streaming, true);
      assert.equal(result.streamMode, "converse_stream_v1");
      assert.equal(result.providerRequestId, "fixture-request-1");
      assert.equal(result.providerHttpStatus, 200);
      assert.equal(result.providerReportedLatencyMs, 37);
      assert.deepEqual(result.usage, { inputTokens: 12, outputTokens: 6, totalTokens: 18 });
      assert.ok(result.timeToFirstTokenMs >= 0 && result.providerLatencyMs >= result.timeToFirstTokenMs);
      assert.equal(JSON.stringify(result).includes("PRIVATE_DIAGNOSTIC_FIXTURE"), false);
    });
  }
});

test("a delta arrives before provider completion and sink backpressure is awaited", { timeout: 2000 }, async () => {
  const first = deferred(), release = deferred(), delivered = [];
  let source, finished = false;
  const wire = events(["first", "second"]);
  const body = new ReadableStream({ start(controller) { source = controller; source.enqueue(Buffer.concat(wire.slice(0, 2))); } });
  const running = converseWithBedrockTarget({ ...target, messages: nativeHistory, stream: true,
    onDelta: async (text) => { delivered.push(text); if (text === "first") { first.resolve(); await release.promise; } },
    fetchFn: async () => providerResponse(body) }).then((value) => { finished = true; return value; });
  await first.promise;
  assert.equal(finished, false);
  source.enqueue(Buffer.concat(wire.slice(2))); source.close();
  await new Promise(setImmediate);
  assert.deepEqual(delivered, ["first"]);
  release.resolve();
  assert.equal((await running).text, "firstsecond");
  assert.deepEqual(delivered, ["first", "second"]);
});

test("reasoning and tool payloads cannot leak into the ordinary text stream", async () => {
  const deltas = [], wire = [
    frame("messageStart", { role: "assistant" }),
    frame("contentBlockDelta", { contentBlockIndex: 0, delta: { reasoningContent: { text: "PRIVATE_REASONING_FIXTURE" } } }),
    frame("contentBlockStop", { contentBlockIndex: 0 }),
    frame("contentBlockDelta", { contentBlockIndex: 1, delta: { text: "Visible answer" } }),
    frame("contentBlockStop", { contentBlockIndex: 1 }),
    ...events().slice(-2),
  ];
  const result = await converseWithBedrockTarget({ ...target, prompt: "Hello", stream: true, onDelta: (text) => deltas.push(text),
    fetchFn: async () => providerResponse(chunked(Buffer.concat(wire))) });
  assert.deepEqual(deltas, ["Visible answer"]);
  assert.equal(result.text, "Visible answer");
  await assert.rejects(converseWithBedrockTarget({ ...target, prompt: "Hello", stream: true,
    fetchFn: async () => providerResponse(chunked(Buffer.concat([wire[0], frame("contentBlockStart", {
      contentBlockIndex: 0, start: { toolUse: { name: "hidden-tool", toolUseId: "fixture" } },
    })]))) }), /AWS_BEDROCK_STREAM_UNSUPPORTED_CONTENT/);
});

test("corruption, truncation, duplicate terminals and out-of-order deltas never complete", async (t) => {
  const valid = events(), corruptPrelude = Buffer.from(valid[0]), corruptPayload = Buffer.from(valid[1]);
  corruptPrelude[8] ^= 1; corruptPayload[corruptPayload.length - 5] ^= 1;
  const cases = [
    ["prelude CRC", [corruptPrelude], /CRC_INVALID/],
    ["message CRC", [valid[0], corruptPayload], /CRC_INVALID/],
    ["partial prelude", [valid[0].subarray(0, 5)], /TRUNCATED/],
    ["partial payload", [valid[0], valid[1].subarray(0, -1)], /TRUNCATED/],
    ["missing metadata", valid.slice(0, -1), /TRUNCATED/],
    ["missing message stop", valid.slice(0, -2), /TRUNCATED/],
    ["duplicate metadata", [...valid, valid.at(-1)], /SEQUENCE_INVALID/],
    ["delta after message stop", [...valid, valid[1]], /SEQUENCE_INVALID/],
    ["delta before message start", [valid[1]], /SEQUENCE_INVALID/],
    ["duplicate content block stop", [valid[0], valid[1], valid[3], valid[3]], /SEQUENCE_INVALID/],
    ["invalid JSON with valid CRC", [frame("messageStart", {}, { rawPayload: Buffer.from("{") })], /JSON_INVALID/],
    ["duplicate headers", [frame("messageStart", { role: "assistant" }, { extraHeaders: [stringHeader(":event-type", "messageStart")] })], /HEADERS_INVALID/],
  ];
  for (const [name, frames, expected] of cases) await t.test(name, async () => {
    await assert.rejects(converseWithBedrockTarget({ ...target, prompt: "Hello", stream: true,
      fetchFn: async () => providerResponse(chunked(Buffer.concat(frames), 13)) }), expected);
  });
});

test("frame allocation is bounded only after a valid prelude CRC", async () => {
  const prelude = Buffer.alloc(12);
  prelude.writeUInt32BE(33 * 1024 * 1024, 0); prelude.writeUInt32BE(0, 4); prelude.writeUInt32BE(crc32(prelude.subarray(0, 8)), 8);
  await assert.rejects(converseWithBedrockTarget({ ...target, prompt: "Hello", stream: true,
    fetchFn: async () => providerResponse(chunked(prelude)) }), /STREAM_LIMIT/);
});

test("in-stream provider exceptions retain sanitized receipt evidence without response text", async () => {
  const delivered = [];
  let caught;
  try {
    await converseWithBedrockTarget({ ...target, prompt: "Hello", stream: true, onDelta: (text) => delivered.push(text),
      fetchFn: async () => providerResponse(chunked(Buffer.concat([...events(["partial"]).slice(0, 2),
        frame("modelStreamErrorException", { message: "PRIVATE_PROVIDER_ERROR_FIXTURE" }, { messageType: "exception" })]))) });
  } catch (error) { caught = error; }
  assert.equal(caught?.message, "AWS_BEDROCK_STREAM_FAILED");
  assert.equal(caught.status, 424);
  assert.equal(caught.providerHttpStatus, 200);
  assert.equal(caught.providerRequestId, "fixture-request-1");
  assert.equal(caught.awsCode, "modelStreamErrorException");
  assert.deepEqual(delivered, ["partial"]);
  assert.equal(JSON.stringify(caught).includes("PRIVATE_PROVIDER_ERROR_FIXTURE"), false);
});

test("cancel interrupts an outstanding provider read and rejects any terminal completion", { timeout: 2000 }, async () => {
  const controller = new AbortController(), first = deferred(), delivered = [];
  let cancelled = 0, providerSignal;
  const body = new ReadableStream({
    start(source) { source.enqueue(Buffer.concat(events(["first"]).slice(0, 2))); },
    cancel() { cancelled++; },
  });
  const running = converseWithBedrockTarget({ ...target, prompt: "Hello", stream: true, signal: controller.signal,
    onDelta: (text) => { delivered.push(text); first.resolve(); },
    fetchFn: async (_url, init) => { providerSignal = init.signal; return providerResponse(body); } });
  await first.promise;
  controller.abort();
  await assert.rejects(running, (error) => error.message === "AWS_BEDROCK_CANCELLED" && error.status === 499 && error.providerRequestId === "fixture-request-1");
  assert.equal(providerSignal.aborted, true);
  assert.equal(cancelled, 1);
  assert.deepEqual(delivered, ["first"]);
});

test("cancellation while identity resolves prevents STS and inference from starting later", async () => {
  const controller = new AbortController(), identity = deferred();
  let network = 0;
  const running = converseWithBedrockTarget({ modelId: target.modelId, invocationTarget: target.invocationTarget,
    prompt: "Hello", signal: controller.signal, resolveWorkloadToken: () => identity.promise,
    fetchFn: async () => { network++; return bufferedResponse(); } });
  controller.abort();
  await assert.rejects(running, /AWS_BEDROCK_CANCELLED/);
  identity.resolve("late-fixture-oidc");
  await new Promise(setImmediate);
  assert.equal(network, 0);
});

test("stream deadline terminates a provider that never sends the final event", { timeout: 2000 }, async () => {
  const keepAlive = setTimeout(() => {}, 1000);
  let cancelled = false;
  try {
    await assert.rejects(converseWithBedrockTarget({ ...target, prompt: "Hello", stream: true, timeoutMs: 10,
      fetchFn: async () => providerResponse(new ReadableStream({ cancel() { cancelled = true; } })) }),
    (error) => error.message === "AWS_BEDROCK_TIMEOUT" && error.status === 504);
    assert.equal(cancelled, true);
  } finally { clearTimeout(keepAlive); }
});

test("ticket bridge streams native messages with backpressure and one terminal receipt", { timeout: 2000 }, async () => {
  const firstWrite = deferred(), reply = new Reply(), originalWrite = reply.write.bind(reply);
  let blocked = false;
  reply.write = (value) => {
    originalWrite(value);
    if (!blocked) { blocked = true; firstWrite.resolve(); return false; }
    return true;
  };
  const fake = fakeBridgeFetch({ inspect: (url, init) => {
    assert.match(url, /\/converse-stream$/); assert.deepEqual(JSON.parse(init.body).messages, nativeHistory);
  } });
  const handler = createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" });
  const req = request(), running = handler(req, reply);
  await firstWrite.promise;
  await new Promise(setImmediate);
  assert.equal(reply.events().length, 1);
  assert.equal(reply.writableEnded, false);
  reply.emit("drain");
  await running;
  const received = reply.events();
  assert.deepEqual(received.map((event) => event.type), ["delta", "delta", "completed"]);
  assert.equal(received[2].body.text, received.slice(0, 2).map((event) => event.text).join(""));
  assert.equal(received[2].body.streaming, true);
  assert.equal(received[2].body.providerRequestId, "fixture-request-1");
  assert.match(reply.headers["content-type"], /^text\/event-stream/);
  assert.match(reply.headers["cache-control"], /no-transform/);
  assert.equal(fake.calls.length, 3, "one ticket claim, one STS exchange, one provider invocation");
  assert.equal(fake.calls.at(-1).init.signal.aborted, false, "normal request-body close and response end are not cancellation");
  assert.equal(req.listenerCount("aborted"), 0);
  assert.equal(reply.listenerCount("close"), 0);
  assert.equal(JSON.stringify(received).includes("fixture-secret"), false);
  assert.equal(JSON.stringify(received).includes("PRIVATE_DIAGNOSTIC_FIXTURE"), false);
});

test("legacy ticket and explicit JSON negotiation both retain buffered behavior", async (t) => {
  const legacy = { ...claim, requestBody: { parts: [{ type: "text", text: "Legacy input" }], system: "", maxTokens: 16 } };
  const cases = [[legacy, "text/event-stream"], [claim, "application/json"], [claim, "text/event-stream;q=0"]];
  for (const [ticketClaim, accept] of cases) await t.test(accept + (ticketClaim === legacy ? " legacy" : " native"), async () => {
    const fake = fakeBridgeFetch({ ticketClaim, runtimeResponse: () => bufferedResponse(), inspect: (url) => assert.match(url, /\/converse$/) });
    const reply = new Reply();
    await createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request({ ticket }, accept), reply);
    assert.equal(reply.statusCode, 200); assert.equal(reply.jsonBody.ok, true);
    assert.equal(reply.jsonBody.body.streaming, false); assert.equal(reply.jsonBody.body.timeToFirstTokenMs, null);
    assert.equal(reply.writes.length, 0);
  });
});

test("ticket bridge emits one sanitized failed terminal after partial provider output", async () => {
  const fake = fakeBridgeFetch({ runtimeResponse: () => providerResponse(chunked(Buffer.concat([
    ...events(["partial"]).slice(0, 2), frame("modelStreamErrorException", { message: "PRIVATE_FAILURE_FIXTURE" }, { messageType: "exception" }),
  ]))) });
  const reply = new Reply();
  await createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request(), reply);
  const received = reply.events();
  assert.deepEqual(received.map((event) => event.type), ["delta", "failed"]);
  assert.equal(received[1].status, 424); assert.equal(received[1].error.retryable, true);
  assert.equal(received[1].providerRequestId, "fixture-request-1");
  assert.equal(received[1].streaming, true);
  assert.equal(JSON.stringify(received).includes("PRIVATE_FAILURE_FIXTURE"), false);
  assert.equal(fake.calls.length, 3);
});

test("HTTP provider failures preserve v1 envelopes and redact raw AWS error messages", async () => {
  const fake = fakeBridgeFetch({ runtimeResponse: () => Response.json({ message: "PRIVATE_BODY_FIXTURE", __type: "AccessDeniedException" },
    { status: 403, headers: { "x-amzn-requestid": "denied-fixture" } }) });
  const reply = new Reply();
  await createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request({ ticket }, "application/json"), reply);
  assert.equal(reply.statusCode, 200);
  assert.equal(reply.jsonBody.status, 403);
  assert.equal(reply.jsonBody.error.kind, "authorization");
  assert.equal(reply.jsonBody.error.retryable, false);
  assert.equal(reply.jsonBody.providerRequestId, "denied-fixture");
  assert.equal(JSON.stringify(reply.jsonBody).includes("PRIVATE_BODY_FIXTURE"), false);
});

test("unsupported stream responses fail closed instead of fabricating token deltas", async () => {
  const fake = fakeBridgeFetch({ runtimeResponse: () => bufferedResponse("{\"reply\":\"Not streamed\"}") });
  const reply = new Reply();
  await createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request(), reply);
  const received = reply.events();
  assert.deepEqual(received.map((event) => event.type), ["failed"]);
  assert.equal(received[0].status, 502);
  assert.equal(received[0].providerHttpStatus, 200, "receipt distinguishes HTTP success from invalid stream protocol");
  assert.equal(received[0].streaming, false);
  assert.equal(received[0].timeToFirstTokenMs, null);
  assert.equal(fake.calls.length, 3, "unsupported transport never triggers an implicit second invocation");
});

test("stream failure receipts reject credential-shaped request IDs and do not invent an HTTP response", async () => {
  for (const requestId of ["sk-fixture-not-a-request-id", "github_pat_fixture", "eyJfixtureNotAnAwsRequestId"]) {
    const fake = fakeBridgeFetch({ runtimeResponse: () => Response.json({ message: "PRIVATE_REQUEST_FIXTURE" },
      { status: 503, headers: { "x-amzn-requestid": requestId } }) });
    const reply = new Reply();
    await createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request(), reply);
    const failure = reply.events()[0];
    assert.equal(failure.providerRequestId, null);
    assert.equal(failure.providerHttpStatus, 503);
    assert.equal(JSON.stringify(failure).includes(requestId), false);
    assert.equal(JSON.stringify(failure).includes("PRIVATE_REQUEST_FIXTURE"), false);
  }
  const fake = fakeBridgeFetch({ runtimeResponse: () => { throw Error("PRIVATE_TRANSPORT_ERROR_FIXTURE"); } }), reply = new Reply();
  await createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request(), reply);
  const failure = reply.events()[0];
  assert.equal(failure.providerRequestId, null);
  assert.equal(failure.providerHttpStatus, null);
  assert.equal(failure.timeToFirstTokenMs, null);
  assert.equal(JSON.stringify(failure).includes("PRIVATE_TRANSPORT_ERROR_FIXTURE"), false);
});

test("bridge disconnect aborts provider work and prevents late response writes", { timeout: 2000 }, async () => {
  const first = deferred(), reply = new Reply(), delivered = reply.write.bind(reply);
  let providerCancelled = 0;
  reply.write = (value) => { delivered(value); first.resolve(); return true; };
  const fake = fakeBridgeFetch({ runtimeResponse: () => providerResponse(new ReadableStream({
    start(source) { source.enqueue(Buffer.concat(events(["partial"]).slice(0, 2))); },
    cancel() { providerCancelled++; },
  })) });
  const running = createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request(), reply);
  await first.promise;
  reply.destroyed = true; reply.emit("close");
  await running;
  await new Promise(setImmediate);
  assert.deepEqual(reply.events().map((event) => event.type), ["delta"]);
  assert.equal(providerCancelled, 1);
  assert.equal(fake.calls.at(-1).init.signal.aborted, true);
});

test("bridge deadline fences late identity completion without consuming a ticket", { timeout: 2000 }, async () => {
  const keepAlive = setTimeout(() => {}, 1000), identity = deferred(), fake = fakeBridgeFetch(), reply = new Reply();
  try {
    await createBedrockChatHandler({ timeoutMs: 10, fetchFn: fake.fetchFn, resolveWorkloadToken: () => identity.promise })(request(), reply);
    assert.equal(reply.jsonBody.error.kind, "timeout");
    identity.resolve("fixture-oidc");
    await new Promise(setImmediate);
    assert.equal(fake.calls.length, 0);
  } finally { clearTimeout(keepAlive); }
});

test("public bridge payload cannot smuggle model requests or ambiguous native/legacy history", async () => {
  const fake = fakeBridgeFetch(), reply = new Reply();
  await createBedrockChatHandler({ fetchFn: fake.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request({ ticket, messages: nativeHistory }), reply);
  assert.equal(reply.statusCode, 404); assert.equal(fake.calls.length, 0);
  const ambiguous = fakeBridgeFetch({ ticketClaim: { ...claim, requestBody: { ...claim.requestBody, parts: [{ type: "text", text: "Other input" }] } } });
  const invalidReply = new Reply();
  await createBedrockChatHandler({ fetchFn: ambiguous.fetchFn, resolveWorkloadToken: async () => "fixture-oidc" })(request(), invalidReply);
  assert.equal(invalidReply.statusCode, 400); assert.equal(ambiguous.calls.length, 1);
});
