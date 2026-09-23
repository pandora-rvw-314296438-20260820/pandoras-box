import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const shell = readFileSync(
  'apps/pandora-mobile/lib/app/plp_enterprise_shell.dart',
  'utf8',
);

test('PLP persistent command dock tracks Android keyboard inset', () => {
  assert.match(shell, /MediaQuery\.viewInsetsOf\(context\)\.bottom/);
  assert.match(shell, /plp-command-keyboard-offset/);
  assert.match(shell, /AnimatedPadding\(/);
  assert.match(shell, /padding: EdgeInsets\.only\(bottom: keyboardInset\)/);
});
