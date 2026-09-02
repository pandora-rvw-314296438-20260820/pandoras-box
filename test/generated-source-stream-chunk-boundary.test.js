
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const MAX_FRAME_BYTES = 256 * 1024;
const encoder = new TextEncoder();

class StreamError extends Error {
  constructor(code) { super(code); this.code = code; }
}

function rec(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function exactKeys(value, expected) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length && actual.every((key, index) => key === wanted[index]);
}

function providerChunkText(envelope) {
  const candidates = Array.isArray(envelope.candidates) ? envelope.candidates : [];
  const content = rec(rec(candidates[0]).content);
  const parts = Array.isArray(content.parts) ? content.parts : [];
  return parts.map((part) => typeof rec(part).text === 'string' ? rec(part).text : '').join('');
}

function assertBounded(value) {
  if (encoder.encode(value).byteLength > MAX_FRAME_BYTES) throw new StreamError('PROVIDER_REJECTED');
}

function parser() {
  const files = new Map();
  let currentPath = null;
  let done = false;

  function accept(rawLine) {
    const line = rawLine.trim();
    if (!line) return;
    let event;
    try { event = rec(JSON.parse(line)); }
    catch { throw new StreamError('INVALID_GENERATED_SOURCE_STREAM'); }
    const kind = typeof event.type === 'string' ? event.type.trim() : '';
    if (kind === 'stream_start') {
      if (!exactKeys(event, ['type','schemaVersion']) || event.schemaVersion !== 1 || files.size || currentPath || done) throw new StreamError('INVALID_GENERATED_SOURCE_STREAM');
      return;
    }
    if (kind === 'file_start') {
      if (!exactKeys(event, ['type','path']) || currentPath || done || typeof event.path !== 'string' || !event.path || files.has(event.path)) throw new StreamError('INVALID_GENERATED_SOURCE_STREAM');
      currentPath = event.path; files.set(currentPath, []); return;
    }
    if (kind === 'file_chunk') {
      if (!exactKeys(event, ['type','path','content']) || done || event.path !== currentPath || typeof event.content !== 'string' || !event.content || !files.has(event.path)) throw new StreamError('INVALID_GENERATED_SOURCE_STREAM');
      files.get(event.path).push(event.content); return;
    }
    if (kind === 'file_end') {
      if (!exactKeys(event, ['type','path']) || done || event.path !== currentPath || !files.has(event.path) || files.get(event.path).length === 0) throw new StreamError('INVALID_GENERATED_SOURCE_STREAM');
      currentPath = null; return;
    }
    if (kind === 'done') {
      if (!exactKeys(event, ['type','schemaVersion']) || event.schemaVersion !== 1 || currentPath || files.size === 0 || done) throw new StreamError('INVALID_GENERATED_SOURCE_STREAM');
      done = true; return;
    }
    throw new StreamError('INVALID_GENERATED_SOURCE_STREAM');
  }

  async function parse(chunks) {
    const decoder = new TextDecoder();
    let sseBuffer = '';
    let modelBuffer = '';

    async function consumeModelText(piece) {
      if (!piece) return;
      modelBuffer += piece;
      for (;;) {
        const newline = modelBuffer.indexOf('\n');
        if (newline < 0) break;
        const line = modelBuffer.slice(0, newline);
        modelBuffer = modelBuffer.slice(newline + 1);
        accept(line);
      }
      assertBounded(modelBuffer);
    }

    async function consumeSseLine(lineValue) {
      const line = lineValue.endsWith('\r') ? lineValue.slice(0, -1) : lineValue;
      if (!line.startsWith('data:')) return;
      const payload = line.slice(5).trim();
      if (!payload || payload === '[DONE]') return;
      let envelope;
      try { envelope = rec(JSON.parse(payload)); }
      catch { throw new StreamError('PROVIDER_REJECTED'); }
      await consumeModelText(providerChunkText(envelope));
    }

    for (const chunk of chunks) {
      sseBuffer += decoder.decode(chunk, { stream: true });
      for (;;) {
        const newline = sseBuffer.indexOf('\n');
        if (newline < 0) break;
        const line = sseBuffer.slice(0, newline);
        sseBuffer = sseBuffer.slice(newline + 1);
        await consumeSseLine(line);
      }
      assertBounded(sseBuffer);
    }
    sseBuffer += decoder.decode();
    assertBounded(sseBuffer);
    if (sseBuffer.trim()) await consumeSseLine(sseBuffer);
    if (modelBuffer.trim()) {
      try { JSON.parse(modelBuffer.trim()); }
      catch { throw new StreamError('PROVIDER_REJECTED'); }
      accept(modelBuffer);
    }
    if (!done) throw new StreamError('INVALID_GENERATED_SOURCE_STREAM');
    return Object.fromEntries([...files].map(([file, pieces]) => [file, pieces.join('')]));
  }
  return { parse };
}

function fixture() {
  const source = 'const greeting = "héllo 世界 😀";\nconsole.log(greeting);\n';
  const lines = [
    JSON.stringify({ type: 'stream_start', schemaVersion: 1 }),
    JSON.stringify({ type: 'file_start', path: 'src/main.js' }),
    JSON.stringify({ type: 'file_chunk', path: 'src/main.js', content: source.slice(0, 21) }),
    JSON.stringify({ type: 'file_chunk', path: 'src/main.js', content: source.slice(21) }),
    JSON.stringify({ type: 'file_end', path: 'src/main.js' }),
    JSON.stringify({ type: 'done', schemaVersion: 1 }),
  ];
  return { source, model: `${lines.join('\n')}\n` };
}

function envelope(text) {
  const pivot = Math.max(1, Math.floor(text.length / 2));
  return JSON.stringify({ candidates: [{ content: { parts: [{ text: text.slice(0,pivot) }, { text: text.slice(pivot) }] } }], modelVersion: 'gemini-test' });
}

function transcript({ crlf = false, finalNewline = true } = {}) {
  const model = fixture().model;
  const cuts = [Math.floor(model.length*.19), Math.floor(model.length*.47), Math.floor(model.length*.73)];
  const pieces = []; let start = 0;
  for (const cut of cuts) { pieces.push(model.slice(start, cut)); start = cut; }
  pieces.push(model.slice(start));
  const eol = crlf ? '\r\n' : '\n';
  let value = pieces.map((piece,index) => `data: ${envelope(piece)}${eol}${index % 2 === 0 ? eol : ''}`).join('');
  if (!finalNewline) value = value.replace(/[\r\n]+$/, '');
  return value;
}

function seededChunks(bytes, seed) {
  let state = seed >>> 0 || 1; const chunks = [];
  for (let offset=0; offset<bytes.length;) {
    state ^= state << 13; state ^= state >>> 17; state ^= state << 5;
    const width = 1 + ((state >>> 0) % 23);
    chunks.push(bytes.slice(offset, Math.min(bytes.length, offset + width)));
    offset += width;
  }
  return chunks;
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => error instanceof StreamError && error.code === code);
}

test('seeded arbitrary UTF-8/SSE/NDJSON byte splits reconstruct identical source', async () => {
  const bytes = encoder.encode(transcript({ crlf: true }));
  const expected = fixture().source;
  const oneByte = Array.from(bytes, (_, index) => bytes.slice(index,index+1));
  assert.equal((await parser().parse(oneByte))['src/main.js'], expected);
  for (let seed=1; seed<=160; seed+=1) {
    assert.equal((await parser().parse(seededChunks(bytes, seed)))['src/main.js'], expected, `seed ${seed}`);
  }
  for (let split=1; split<bytes.length; split+=7) {
    assert.equal((await parser().parse([bytes.slice(0,split),bytes.slice(split)]))['src/main.js'], expected, `split ${split}`);
  }
});

test('CRLF, blank SSE lines and final frame without newline remain valid', async () => {
  for (const crlf of [false,true]) {
    const result = await parser().parse(seededChunks(encoder.encode(transcript({ crlf, finalNewline: false })), crlf ? 901 : 902));
    assert.equal(result['src/main.js'], fixture().source);
  }
});

test('incomplete final SSE envelope is provider rejection', async () => {
  const inner = '{"type":"stream_start","schemaVersion":1}\n';
  const bad = `data: ${JSON.stringify({ candidates:[{content:{parts:[{text:inner}]}}] }).slice(0,-1)}`;
  await expectCode(parser().parse([encoder.encode(bad)]), 'PROVIDER_REJECTED');
});

test('incomplete trailing model NDJSON is provider rejection', async () => {
  const inner = [
    JSON.stringify({type:'stream_start',schemaVersion:1}),
    JSON.stringify({type:'file_start',path:'src/main.js'}),
    JSON.stringify({type:'file_chunk',path:'src/main.js',content:'ok'}),
    JSON.stringify({type:'file_end',path:'src/main.js'}),
    '{"type":"done","schemaVersion":1',
  ].join('\n');
  await expectCode(parser().parse([encoder.encode(`data: ${envelope(inner)}`)]), 'PROVIDER_REJECTED');
});

test('oversize SSE/model leftovers fail as provider rejection', async () => {
  await expectCode(parser().parse([encoder.encode(`data: ${'x'.repeat(MAX_FRAME_BYTES+1)}`)]), 'PROVIDER_REJECTED');
  await expectCode(parser().parse([encoder.encode(`data: ${envelope('x'.repeat(MAX_FRAME_BYTES+1))}\n`)]), 'PROVIDER_REJECTED');
});

test('parsed but lifecycle-invalid model event remains generated-source rejection', async () => {
  await expectCode(parser().parse([encoder.encode(`data: ${envelope(JSON.stringify({type:'done',schemaVersion:1}))}`)]), 'INVALID_GENERATED_SOURCE_STREAM');
});

test('canonical source binds framing limits and EOF classification', () => {
  const source = fs.readFileSync(path.join(process.cwd(),'supabase/functions/pandora-project-source-generator/index.ts'),'utf8');
  assert.match(source, /MAX_STREAM_FRAME_BUFFER_BYTES = 256 \* 1024/);
  assert.match(source, /assertProviderFrameBufferBounded\(modelBuffer\)/);
  assert.match(source, /assertProviderFrameBufferBounded\(sseBuffer\)/);
  assert.match(source, /JSON\.parse\(modelBuffer\.trim\(\)\)/);
  assert.match(source, /if \(sseBuffer\.trim\(\)\) await consumeSseLine\(sseBuffer\);/);
  assert.doesNotMatch(source, /consumeSseLine\(sseBuffer\.trim\(\)\)/);
  assert.match(source, /return typeof value === "string" \? value : "";/);
});
