import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const read = (name) => readFile(`.github/workflows/${name}`, 'utf8');

const [mobile, engineering, dependency, edge, canonical] = await Promise.all([
  read('pandora-mobile-integration.yml'),
  read('engineering-toolchain.yml'),
  read('dependency-review.yml'),
  read('pandora-edge-source-artifact.yml'),
  read('canonical-release-evidence.yml'),
]);

test('pull-request validation is independent of release artifact capacity', () => {
  assert.match(
    mobile,
    /Upload Web validation candidate\n\s+if: \$\{\{ github\.event_name != 'pull_request' \}\}/,
  );
  assert.match(
    mobile,
    /Upload Android validation candidate\n\s+if: \$\{\{ github\.event_name != 'pull_request' \}\}/,
  );
  assert.match(
    engineering,
    /GITLEAKS_ENABLE_UPLOAD_ARTIFACT: false/,
  );
  assert.match(
    edge,
    /PANDORA_EDGE_PR_SOURCE_RECEIPT[\s\S]*release_authority=false artifact_provider=deferred/,
  );
  assert.match(
    edge,
    /Upload exact Edge sources\n\s+if: \$\{\{ github\.event_name != 'pull_request'/,
  );
});

test('private dependency review remains fail-closed without Advanced Security', () => {
  assert.match(dependency, /github\.event\.repository\.private/);
  assert.match(dependency, /npm run audit:prod/);
  assert.match(dependency, /npm run tooling:audit/);
  assert.match(
    dependency,
    /!github\.event\.repository\.private/,
  );
});

test('release authority still requires the non-PR provider lane', () => {
  assert.match(
    canonical,
    /Upload the source-only binding\n\s+if: \$\{\{ !github\.event\.repository\.private \}\}/,
  );
  assert.match(canonical, /Record private source-only binding/);
  assert.match(canonical, /Release authority: `false`/);
  assert.match(mobile, /Only push-to-main artifacts can become canonical release authority/);
});

test('mobile formatter gate rejects real byte changes but tolerates false nonzero exits', () => {
  assert.match(mobile, /find lib test -type f -name '\*\.dart' -print0/);
  assert.match(mobile, /Dart formatter changed tracked mobile source bytes/);
  assert.match(
    mobile,
    /Dart formatter reported a nonzero exit but produced a byte-identical tree; continuing\./,
  );
});
