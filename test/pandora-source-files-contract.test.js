
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(process.cwd(), 'supabase/functions/pandora-source-files/index.ts'), 'utf8');

test('paid source API is exact-version and capability gated before artifact storage reads', () => {
  assert.match(source, /pandora_get_source_entitlement_v1/);
  assert.match(source, /p_project_id:\s*projectId/);
  assert.match(source, /p_capability:\s*capability/);
  assert.match(source, /SOURCE_ENTITLEMENT_REQUIRED/);
  const gate = source.indexOf('pandora_get_source_entitlement_v1');
  const storage = source.indexOf('.storage.from(');
  assert.ok(gate >= 0 && storage > gate, 'entitlement check must precede durable artifact storage read');
});

test('paid source API audits denied and allowed decisions and exposes bounded operations only', () => {
  assert.match(source, /pandora_record_source_access_audit_service_v1/);
  assert.match(source, /p_allowed:\s*false/);
  assert.match(source, /p_allowed:\s*true/);
  assert.match(source, /new Set\(\["tree", "read", "search", "export"\]\)/);
  assert.match(source, /MAX_SEARCH_MATCHES\s*=\s*50/);
  assert.match(source, /MAX_SOURCE_BYTES\s*=\s*12 \* 1024 \* 1024/);
});

test('paid source API redacts high-risk secrets and emits a real ZIP envelope for export', () => {
  assert.match(source, /REDACTED_PRIVATE_KEY/);
  assert.match(source, /REDACTED_SECRET/);
  assert.match(source, /0x04034b50/);
  assert.match(source, /0x02014b50/);
  assert.match(source, /0x06054b50/);
  assert.match(source, /content-type": "application\/octet-stream"/);
  assert.match(source, /x-pandora-source-version/);
  assert.match(source, /x-pandora-content-type/);
});

test('paid source API never treats membership or preview access as durable source authority', () => {
  assert.doesNotMatch(source, /\.in\("role",\s*\["owner",\s*"admin"\]\)/);
  assert.doesNotMatch(source, /pandora-preview-content/);
  assert.match(source, /SOURCE_ENTITLEMENT_ACTIVE/);
});
