import { createHash } from 'node:crypto';

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

function sourceDigest(source) {
  if (source?.kind === 'git_commit') return createHash('sha256').update(`git:${source.repository}:${source.commitSha}`).digest('hex');
  if (source?.kind === 'artifact_snapshot') return source.sha256;
  throw new Error('INVALID_SOURCE');
}

function validateSource(source) {
  if (!source || typeof source !== 'object' || Array.isArray(source)) throw new Error('INVALID_SOURCE');
  if (source.kind === 'git_commit') {
    if (!REPOSITORY.test(source.repository ?? '') || !SHA40.test(source.commitSha ?? '')) throw new Error('INVALID_GIT_SOURCE');
    return Object.freeze({ kind: 'git_commit', repository: source.repository, commitSha: source.commitSha });
  }
  if (source.kind === 'artifact_snapshot') {
    if (typeof source.artifactId !== 'string' || !source.artifactId || !SHA256.test(source.sha256 ?? '')) throw new Error('INVALID_ARTIFACT_SOURCE');
    return Object.freeze({ kind: 'artifact_snapshot', artifactId: source.artifactId, sha256: source.sha256 });
  }
  throw new Error('INVALID_SOURCE_KIND');
}

function createGitMaterializationPlan(source) {
  const exact = validateSource(source);
  if (exact.kind !== 'git_commit') throw new Error('GIT_SOURCE_REQUIRED');
  const remote = `https://github.com/${exact.repository}.git`;
  const gitConfig = ['-c', 'credential.helper=', '-c', 'core.hooksPath=.pandora/no-hooks', '-c', 'protocol.file.allow=never'];
  return Object.freeze({
    kind: 'git_commit',
    repository: exact.repository,
    commitSha: exact.commitSha,
    requiredHosts: Object.freeze(['github.com']),
    environment: Object.freeze({ GIT_CONFIG_NOSYSTEM: '1', GIT_TERMINAL_PROMPT: '0' }),
    commands: Object.freeze([
      Object.freeze({ executable: 'git', args: ['init', '.'] }),
      Object.freeze({ executable: 'git', args: [...gitConfig, 'remote', 'add', 'origin', remote] }),
      Object.freeze({ executable: 'git', args: [...gitConfig, 'fetch', '--depth=1', '--no-tags', 'origin', exact.commitSha] }),
      Object.freeze({ executable: 'git', args: [...gitConfig, 'checkout', '--detach', exact.commitSha] }),
      Object.freeze({ executable: 'git', args: [...gitConfig, 'rev-parse', 'HEAD'], verifyStdout: exact.commitSha }),
    ]),
    submodules: 'forbidden',
    hooks: 'disabled',
    credentialPersistence: 'disabled',
  });
}

function createArtifactMaterializationPlan(source) {
  const exact = validateSource(source);
  if (exact.kind !== 'artifact_snapshot') throw new Error('ARTIFACT_SOURCE_REQUIRED');
  return Object.freeze({
    kind: 'artifact_snapshot',
    artifactId: exact.artifactId,
    expectedSha256: exact.sha256,
    extraction: Object.freeze({ allowSymlinks: false, allowDevices: false, allowAbsolutePaths: false, allowParentTraversal: false }),
  });
}

function createMaterializationPlan(source) {
  const exact = validateSource(source);
  return exact.kind === 'git_commit' ? createGitMaterializationPlan(exact) : createArtifactMaterializationPlan(exact);
}

function assertMaterializedIdentity(plan, receipt) {
  if (!receipt || typeof receipt !== 'object') throw new Error('MATERIALIZATION_RECEIPT_REQUIRED');
  if (plan.kind === 'git_commit') {
    if (receipt.headSha !== plan.commitSha) throw new Error('MATERIALIZED_GIT_HEAD_MISMATCH');
  } else if (receipt.sha256 !== plan.expectedSha256) {
    throw new Error('MATERIALIZED_ARTIFACT_DIGEST_MISMATCH');
  }
  return true;
}

export { assertMaterializedIdentity, createArtifactMaterializationPlan, createGitMaterializationPlan, createMaterializationPlan, sourceDigest, validateSource };
