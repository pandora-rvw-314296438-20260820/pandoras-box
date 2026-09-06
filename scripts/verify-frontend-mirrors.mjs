import { readdir } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const canonical = 'apps/control-tower';

const canonicalFiles = await readdir(canonical, { recursive: true });
if (!canonicalFiles.length) {
  throw new Error('Canonical Control Tower source is empty.');
}

const { stdout } = await execFileAsync(
  'git',
  ['ls-files', '--', 'public/control-tower'],
  { encoding: 'utf8' },
);
const trackedMirror = stdout
  .split(/\r?\n/)
  .map((value) => value.trim())
  .filter(Boolean);

if (trackedMirror.length) {
  throw new Error(
    `Generated Control Tower output must not be committed: ${trackedMirror.join(', ')}`,
  );
}

console.log(
  `Control Tower has one tracked authority: ${canonical} (${canonicalFiles.length} entries)`,
);
