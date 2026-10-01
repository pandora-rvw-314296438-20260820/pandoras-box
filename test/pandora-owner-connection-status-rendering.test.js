import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(path.join(root, "apps/control-tower/owner-screens-more.js"), "utf8");

test("owner connection badges require authoritative ready plus Connected", () => {
  assert.match(source, /connection\.state === 'ready' && connection\.plainStatus === 'Connected'/);
  assert.match(source, /connection\.plainStatus \|\| 'Needs attention'/);
  assert.match(source, /badge\(status, tone\)/);
  assert.doesNotMatch(source, /badge\('Connected', 'success'\)/);
});

test("owner connection access text uses the authoritative mutation permission", () => {
  assert.match(source, /connection\.canChange === true/);
  assert.match(source, /'Changes require approval' : 'Read only'/);
});
