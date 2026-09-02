const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const compiler = fs.readFileSync('supabase/functions/pandora-project-spec-compiler/index.ts', 'utf8');

test('ProjectSpec compiler retries malformed structured output without weakening validation', () => {
  assert.match(compiler, /project-spec-compiler-v5/);
  assert.match(compiler, /for \(let attempt = 1; attempt <= 3; attempt\+\+\)/);
  assert.match(compiler, /candidate = validateCandidate\(parsed\)/);
  assert.match(compiler, /allowedKeys\(product/);
  assert.match(compiler, /allowedKeys\(acceptance/);
  assert.match(compiler, /requiredProposalText\(product\.productPromise/);
  assert.match(compiler, /stringArray\(acceptance\.successCriteria, "acceptance\.successCriteria", true\)/);
  assert.match(compiler, /attempt === 3/);
  assert.match(compiler, /generationConfig\.temperature = 0/);
  assert.match(compiler, /structured_output_attempts: structuredOutputAttempt/);
  assert.match(compiler, /inputTokens \+= attemptInputTokens/);
  assert.match(compiler, /outputTokens \+= attemptOutputTokens/);
  assert.match(compiler, /totalTokens \+= attemptTotalTokens/);
  const validateAt = compiler.indexOf('candidate = validateCandidate(parsed)');
  const commitAt = compiler.indexOf('pandora_commit_compiled_project_spec_memory_v1');
  assert.ok(validateAt > 0 && commitAt > validateAt, 'strict validation must remain before ProjectSpec commit');
});