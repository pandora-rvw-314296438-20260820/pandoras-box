import { createHash } from 'node:crypto';

const TOOLCHAIN_POLICY_VERSION = '1.0.0';
const TOOLCHAINS = Object.freeze({
  node: Object.freeze({ version: '24', match: /^24\./ }),
  npm: Object.freeze({ version: 'bundled-node24', match: /^1[01]\./ }),
  pnpm: Object.freeze({ version: '10', match: /^10\./ }),
  yarn: Object.freeze({ version: '4', match: /^4\./ }),
  flutter: Object.freeze({ version: '3.47.0', match: /^3\.47\.0(?:\b|\s)/ }),
  java: Object.freeze({ version: '17.0.20+8', match: /17\.0\.20/ }),
  androidPlatform: Object.freeze({ version: 'android-36', match: /^android-36$/ }),
  androidBuildTools: Object.freeze({ version: '36.0.0', match: /^36\.0\.0$/ }),
});

function requiredToolchains(adapter) {
  if (!adapter?.id) throw new Error('INVALID_ADAPTER');
  if (adapter.id.startsWith('flutter-android')) return Object.freeze(['flutter', 'java', 'androidPlatform', 'androidBuildTools']);
  if (adapter.id.startsWith('flutter-')) return Object.freeze(['flutter']);
  if (adapter.id.startsWith('node-')) return Object.freeze(['node']);
  return Object.freeze([]);
}

function validateToolchainInventory(adapter, inventory = {}) {
  const required = requiredToolchains(adapter);
  for (const name of required) {
    const observed = String(inventory[name] ?? '');
    if (!TOOLCHAINS[name].match.test(observed)) {
      const error = new Error('TOOLCHAIN_VERSION_MISMATCH'); error.toolchain = name; error.expected = TOOLCHAINS[name].version; throw error;
    }
  }
  return Object.freeze(Object.fromEntries(required.map((name) => [name, String(inventory[name])])));
}

function toolchainDigest(inventory) {
  return createHash('sha256').update(JSON.stringify(Object.fromEntries(Object.entries(inventory ?? {}).sort(([a], [b]) => a.localeCompare(b))))).digest('hex');
}

export { TOOLCHAINS, TOOLCHAIN_POLICY_VERSION, requiredToolchains, toolchainDigest, validateToolchainInventory };
