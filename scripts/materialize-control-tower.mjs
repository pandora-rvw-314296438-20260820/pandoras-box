import { cp, mkdir, readdir, rm } from 'node:fs/promises';
import path from 'node:path';

const source = path.resolve('apps/control-tower');
const target = path.resolve('public/control-tower');

async function countFiles(root) {
  let count = 0;
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const next = path.join(root, entry.name);
    if (entry.isDirectory()) count += await countFiles(next);
    else if (entry.isFile()) count += 1;
  }
  return count;
}

const sourceCount = await countFiles(source);
if (sourceCount < 1) throw new Error('Canonical Control Tower source is empty.');

await rm(target, { recursive: true, force: true });
await mkdir(path.dirname(target), { recursive: true });
await cp(source, target, { recursive: true, force: true });

const targetCount = await countFiles(target);
if (targetCount !== sourceCount) {
  throw new Error(
    `Control Tower materialization incomplete: ${targetCount}/${sourceCount}`,
  );
}

console.log(`Control Tower generated from canonical source: ${targetCount} files`);
