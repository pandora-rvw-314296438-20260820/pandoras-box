import { cp, mkdir, readdir, rm } from 'node:fs/promises';
import path from 'node:path';

const source = path.resolve('apps/control-tower');
const target = path.resolve('public/control-tower');
const brandSource = path.resolve(
  'apps/pandora-mobile/assets/brand/pandora-product-mark-ui-1024.png',
);
const brandTarget = path.resolve(
  'public/assets/brand/pandora-product-mark-ui-1024.png',
);

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

// Keep the owner web shell on the same reviewed product mark as the mobile app.
await mkdir(path.dirname(brandTarget), { recursive: true });
await cp(brandSource, brandTarget, { force: true });

// Serve the canonical, tested event model without a second tracked source copy.
await cp(path.resolve('packages/pandora-operations-inference/theatre.mjs'), path.join(target, 'operations-theatre-runtime.mjs'));
const targetCount = await countFiles(target);
if (targetCount !== sourceCount + 1) {
  throw new Error(
    `Control Tower materialization incomplete: ${targetCount}/${sourceCount}`,
  );
}

console.log(`Control Tower generated from canonical source: ${targetCount} files`);
