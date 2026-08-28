"use strict";

const SENSITIVE_KEY = /(^|[_-])(authorization|proxy[_-]?authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|cookie|set[_-]?cookie|private[_-]?key|service[_-]?role|client[_-]?secret|github[_-]?token|vercel[_-]?token|gemini[_-]?api[_-]?key|database[_-]?url)($|[_-])/i;
const VALUE_PATTERNS = [
  /\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi,
  /\bgh[pousr]_[A-Za-z0-9]{20,}\b/g,
  /\bgithub_pat_[A-Za-z0-9_]{20,}\b/g,
  /\bvercel_[A-Za-z0-9_-]{20,}\b/gi,
  /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g,
  /(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?):\/\/[^\s:@/]+:[^\s@/]+@/gi,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/g,
];
const REDACTED = "[REDACTED]";

function redactString(input, canaries = []) {
  let value = String(input);
  for (const canary of canaries) {
    if (typeof canary === "string" && canary.length >= 4) value = value.split(canary).join(REDACTED);
  }
  for (const pattern of VALUE_PATTERNS) value = value.replace(pattern, (match) => match.includes("://") ? match.replace(/:\/\/[^@]+@/, `://${REDACTED}@`) : REDACTED);
  return value;
}

function redactDeep(value, { canaries = [], maxDepth = 12 } = {}, depth = 0, seen = new WeakSet()) {
  if (depth > maxDepth) return "[REDACTED:DEPTH]";
  if (value === null || value === undefined || typeof value === "number" || typeof value === "boolean") return value;
  if (typeof value === "string") return redactString(value, canaries);
  if (typeof value !== "object") return redactString(String(value), canaries);
  if (seen.has(value)) return "[REDACTED:CYCLE]";
  seen.add(value);
  if (Array.isArray(value)) return value.map((item) => redactDeep(item, { canaries, maxDepth }, depth + 1, seen));
  const output = {};
  for (const [key, child] of Object.entries(value)) {
    output[key] = SENSITIVE_KEY.test(key) ? REDACTED : redactDeep(child, { canaries, maxDepth }, depth + 1, seen);
  }
  return output;
}

module.exports = { REDACTED, SENSITIVE_KEY, redactString, redactDeep };
