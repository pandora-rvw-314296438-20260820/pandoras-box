import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve('supabase/migrations');
const manifest = JSON.parse(
  await readFile('docs/migrations/migration-authority-manifest.json', 'utf8'),
);
const files = (await readdir(root)).filter((name) => name.endsWith('.sql')).sort();
if (!files.length) throw new Error('No migrations found.');

const counts = {
  provider_receipt: 0,
  historical_control: 0,
  executable_authority: 0,
};

for (const name of files) {
  const source = await readFile(path.join(root, name), 'utf8');
  const receipt =
    source.includes('history-only') ||
    source.includes('Canonical executable authority:') ||
    source.includes('Replay mode: history_receipt_noop');
  const historical =
    !receipt && /(?:temporary|remove_temporary|retire_|recovery|probe)/i.test(name);

  if (receipt) {
    counts.provider_receipt += 1;
    const target = source.match(
      /Canonical executable authority:\s*(supabase\/migrations\/[^\s]+)/,
    );
    if (target) {
      try {
        await readFile(path.resolve(target[1]), 'utf8');
      } catch {
        throw new Error(
          `Migration receipt ${name} points to missing authority ${target[1]}`,
        );
      }
    }
  } else if (historical) {
    counts.historical_control += 1;
  } else {
    counts.executable_authority += 1;
  }
}

const classified = Object.values(counts).reduce((sum, value) => sum + value, 0);
if (classified !== files.length) {
  throw new Error(`Migration authority classification incomplete: ${classified}/${files.length}`);
}
if (
  manifest.schemaVersion !== 1 ||
  manifest.sourceDirectory !== 'supabase/migrations'
) {
  throw new Error('Migration authority manifest metadata is invalid.');
}

console.log(JSON.stringify({ migrations: files.length, ...counts }));
