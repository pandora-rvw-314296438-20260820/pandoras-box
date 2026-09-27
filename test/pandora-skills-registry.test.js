const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

test('Pandora core skill registry is complete, acyclic, content-addressed, and activation metadata is valid', async () => {
  const rootDir = path.resolve(__dirname, '..');
  const moduleUrl = pathToFileURL(path.join(rootDir, 'scripts/validate-pandora-skills.mjs')).href;
  const { validatePandoraSkills } = await import(moduleUrl);
  const result = validatePandoraSkills({ rootDir });
  assert.deepEqual(result, {
    skills: 51,
    capabilities: 57,
    evals: 16,
    manifestFiles: 79,
  });
});
