const METADATA_HOSTS = new Set([
  '169.254.169.254',
  'metadata.google.internal',
  'metadata.azure.internal',
  'instance-data.ec2.internal',
]);

function canonicalHost(value) {
  const input = value.includes('://') ? value : `https://${value}`;
  let url;
  try { url = new URL(input); } catch { throw new Error('INVALID_NETWORK_DESTINATION'); }
  if (url.username || url.password) throw new Error('INVALID_NETWORK_DESTINATION');
  return url.hostname.toLowerCase().replace(/\.$/, '');
}

function networkDecision(policy, destination) {
  const host = canonicalHost(destination);
  if (METADATA_HOSTS.has(host) || host.startsWith('169.254.')) return { allowed: false, reason: 'metadata_blocked', host };
  if (!policy || policy.mode === 'deny') return { allowed: false, reason: 'default_deny', host };
  const allow = new Set((policy.allow ?? []).map(canonicalHost));
  return allow.has(host) ? { allowed: true, reason: 'allowlist', host } : { allowed: false, reason: 'not_allowlisted', host };
}

export { METADATA_HOSTS, canonicalHost, networkDecision };
