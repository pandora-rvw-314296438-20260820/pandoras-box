'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const root = join(__dirname, '..');
const ui = readFileSync(join(root, 'apps/pandora-mobile/lib/features/plugins/plugins_screen.dart'), 'utf8');
const native = readFileSync(join(root, 'supabase/migrations/20260925063000_pandora_meta_native_capability_v1.sql'), 'utf8');

function routePattern(provider) {
  const match = native.match(new RegExp(
    "(?:if|elsif) v_norm ~ '([^']+)' then\\s+v_provider := '" + provider + "';"
  ));
  assert.ok(match, provider + ' native classifier is missing');
  return new RegExp(match[1].replace(/\\m|\\M/g, '\\b').replace(/\[\[:space:\]\]/g, '\\s'));
}

test('Meta plugin Connect and Reconnect prepare Facebook authorization when sent', () => {
  assert.match(ui, /_openGovernedPluginAction\(\s*plugin,[\s\S]*?_PluginAction\.connect,/);
  assert.match(ui, /_PluginAction\.connect when plugin\.id == 'meta' =>\s*'Connect Facebook'/);
  assert.match(ui, /_PluginAction\.reconnect when plugin\.id == 'meta' =>\s*'Connect Facebook'/);
  assert.match(ui, /AskPandoraScreen\(initialPrompt: prompt\)/);
  assert.match(ui, /Press Send in Ask Pandora to prepare a secure Facebook authorization link/);

  const prompt = 'Connect Facebook';
  assert.equal(routePattern('connections').test(prompt.toLowerCase()), false);
  assert.equal(routePattern('meta').test(prompt.toLowerCase()), true);
  const meta = native.slice(native.indexOf("elsif v_provider='meta'"));
  assert.match(meta, /elsif v_norm ~ '\\m\(connect\|authorize\|authorization\|sign in\)\\M' then\s+v_meta := public\.pandora_meta_oauth_prepare_v1\(p_organization_id\)/);
  assert.equal(/\b(connect|authorize|authorization|sign in)\b/.test(prompt.toLowerCase()), true);
});
