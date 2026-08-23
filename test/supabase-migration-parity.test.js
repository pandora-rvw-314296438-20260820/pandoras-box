const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { existsSync, readFileSync, readdirSync } = require('node:fs');
const { basename, join } = require('node:path');
const test = require('node:test');

const repositoryRoot = join(__dirname, '..');
const migrationRoot = join(repositoryRoot, 'supabase', 'migrations');
const evidenceRoot = join(
  repositoryRoot,
  'docs',
  'supabase',
  'recovery',
  'jcyqixttuebxqqfkjonq',
);
const manifest = JSON.parse(
  readFileSync(join(evidenceRoot, 'migration-parity-manifest.json'), 'utf8'),
);
const recoveryReplayResult = JSON.parse(
  readFileSync(join(evidenceRoot, 'pglite-replay-result.json'), 'utf8'),
);
const currentReplayResult = JSON.parse(
  readFileSync(
    join(evidenceRoot, 'pglite-replay-result-20260817145929.json'),
    'utf8',
  ),
);

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function migrationSource(version) {
  const entry = manifest.history.find((candidate) => candidate.version === version);
  assert.ok(entry, `missing manifest entry ${version}`);
  return readFileSync(join(repositoryRoot, entry.active.path), 'utf8');
}

function chainSha256(filenames) {
  const chain = filenames
    .map((filename) => {
      const source = readFileSync(join(migrationRoot, filename));
      return `${filename}:${sha256(source)}`;
    })
    .join('\n') + '\n';
  return sha256(Buffer.from(chain));
}

test('active Supabase history preserves the captured 52-file recovery chain and appends governed changes', () => {
  const files = readdirSync(migrationRoot)
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .sort();
  const capturedFiles = [
    ...manifest.history.map((entry) => basename(entry.active.path)),
    basename(manifest.pending_change.path),
    basename(manifest.source_authority_change.path),
  ].sort();
  const capturedSet = new Set(capturedFiles);
  const appendedFiles = files.filter((filename) => !capturedSet.has(filename));
  const replaySnapshotLast = '20260817145929_add_vercel_async_git_link_queue.sql';
  const historicalCurrentFiles = files.filter((filename) => filename <= replaySnapshotLast);
  const postSnapshotFiles = files.filter((filename) => filename > replaySnapshotLast);

  assert.equal(manifest.invariants.historical_identity_count, 50);
  assert.equal(manifest.invariants.active_file_count, 52);
  assert.equal(manifest.invariants.applied_change_count, 2);
  assert.equal(manifest.history.length, 50);
  assert.equal(new Set(manifest.history.map((entry) => entry.version)).size, 50);
  assert.deepEqual(
    manifest.history.map((entry) => entry.version),
    [...manifest.history.map((entry) => entry.version)].sort(),
  );
  assert.equal(new Set(capturedFiles).size, manifest.invariants.active_file_count);
  assert.ok(capturedFiles.every((filename) => files.includes(filename)));
  assert.deepEqual(appendedFiles, [
    '20260817130000_projectos_memory_full_capacity_context_gate.sql',
    '20260817145550_add_vercel_control_adapter.sql',
    '20260817145659_add_vercel_git_binding_clear.sql',
    '20260817145929_add_vercel_async_git_link_queue.sql',
    '20260820090000_add_pandora_outcome_lifecycle_contracts.sql',
    '20260821024500_projectos_owner_read_completion.sql',
    '20260823143000_add_governed_owner_worker_dispatch.sql',
    '20260823150000_add_safe_execution_terminal_outcomes.sql',
    '20260823153000_harden_governed_worker_lease_and_key_binding.sql',
    '20260823153552_canonical_release_status_readback.sql',
    '20260823155000_add_governed_worker_reviewer_attestation.sql',
    '20260823160000_add_canonical_release_attestations.sql',
    '20260823163000_harden_execution_plan_context_immutability.sql',
    '20260823164000_harden_governed_worker_validation_boundaries.sql',
    '20260823170000_add_immutable_physical_android_receipts.sql',
    '20260823171000_harden_owner_worker_external_authority.sql',
  ]);
  assert.deepEqual(postSnapshotFiles, [
    '20260820090000_add_pandora_outcome_lifecycle_contracts.sql',
    '20260821024500_projectos_owner_read_completion.sql',
    '20260823143000_add_governed_owner_worker_dispatch.sql',
    '20260823150000_add_safe_execution_terminal_outcomes.sql',
    '20260823153000_harden_governed_worker_lease_and_key_binding.sql',
    '20260823153552_canonical_release_status_readback.sql',
    '20260823155000_add_governed_worker_reviewer_attestation.sql',
    '20260823160000_add_canonical_release_attestations.sql',
    '20260823163000_harden_execution_plan_context_immutability.sql',
    '20260823164000_harden_governed_worker_validation_boundaries.sql',
    '20260823170000_add_immutable_physical_android_receipts.sql',
    '20260823171000_harden_owner_worker_external_authority.sql',
  ]);
  assert.equal(historicalCurrentFiles.length, currentReplayResult.migration_count);
  assert.equal(
    currentReplayResult.migration_count,
    recoveryReplayResult.migration_count + appendedFiles.length - postSnapshotFiles.length,
  );
  assert.equal(manifest.live_chain.first, '20260724010000');
  assert.equal(manifest.live_chain.last, '20260813105011');
  assert.equal(manifest.live_chain.historical_recovery_last, '20260810104737');
  assert.equal(manifest.live_chain.migration_count, 52);
  assert.equal(manifest.pending_change.version, '20260812034825');
  assert.equal(manifest.pending_change.provider_version, '20260813014555');
  assert.equal(manifest.pending_change.live_at_capture, true);
  assert.equal(manifest.source_authority_change.version, '20260813105011');
  assert.equal(manifest.source_authority_change.provider_version, '20260813105011');
  assert.equal(manifest.source_authority_change.live_at_capture, true);

  for (const entry of manifest.history) {
    const payload = readFileSync(join(repositoryRoot, entry.active.path));
    assert.equal(payload.length, entry.active.bytes, entry.version);
    assert.equal(sha256(payload), entry.active.sha256, entry.version);
    assert.equal(entry.active.path.split('/').pop().slice(0, 14), entry.version);
    assert.equal(entry.live.sha256.length, 64);
    assert.ok(entry.live.bytes > 0);
  }

  const pending = readFileSync(join(repositoryRoot, manifest.pending_change.path));
  assert.equal(pending.length, manifest.pending_change.bytes);
  assert.equal(sha256(pending), manifest.pending_change.sha256);
  assert.equal(pending.length, manifest.pending_change.provider_bytes);
  assert.equal(sha256(pending), manifest.pending_change.provider_sha256);

  const sourceAuthority = readFileSync(
    join(repositoryRoot, manifest.source_authority_change.path),
  );
  assert.equal(sourceAuthority.length, manifest.source_authority_change.bytes);
  assert.equal(sha256(sourceAuthority), manifest.source_authority_change.sha256);
  const providerSourceAuthority = Buffer.from(
    sourceAuthority.toString('utf8').replace(/\n$/, ''),
  );
  assert.equal(providerSourceAuthority.length, manifest.source_authority_change.provider_bytes);
  assert.equal(
    sha256(providerSourceAuthority),
    manifest.source_authority_change.provider_sha256,
  );

  assert.equal(recoveryReplayResult.migration_count, manifest.invariants.active_file_count);
  assert.equal(chainSha256(capturedFiles), recoveryReplayResult.chain_sha256);
  assert.equal(
    chainSha256(historicalCurrentFiles),
    currentReplayResult.chain_sha256,
  );
  assert.equal(currentReplayResult.provider_equivalence, false);
  assert.equal(manifest.validation.authorization_smoke, 'pass');
  assert.deepEqual(currentReplayResult.assertions.authorization_smoke, {
    aal1_owner_without_session: 'approved',
    operator: 'denied',
    anonymous_owner: 'denied',
    high_risk_requester_as_approver: 'denied',
    audit_event_appended: true,
  });
  assert.deepEqual(currentReplayResult.assertions.source_authority, {
    owner_wildcard: 'mbanatao/*',
    historical_binding_count: 14,
    canonical_fxpass_binding: 'active',
    mixed_case_repository_insert: 'denied',
  });
});

test('credential-bearing historical payloads are replaced with database-only values', () => {
  assert.equal(manifest.invariants.raw_provider_payloads_committed, false);
  assert.equal(manifest.invariants.live_secret_or_verifier_literals_committed, false);
  assert.equal(manifest.invariants.historical_sensitive_exposure_remediated, false);
  assert.equal(manifest.invariants.coordinated_rotation_required, true);
  assert.equal(
    existsSync(join(evidenceRoot, 'recorded-payloads')) &&
      readdirSync(join(evidenceRoot, 'recorded-payloads')).length > 0,
    false,
  );
  assert.equal(
    existsSync(join(evidenceRoot, 'recorded-sql')) &&
      readdirSync(join(evidenceRoot, 'recorded-sql')).length > 0,
    false,
  );

  const cases = [
    ['20260728171559', 2],
    ['20260731092135', 1],
    ['20260807083337', 1],
  ];
  const quotedCredential = /'(?:[a-f0-9]{64}|[A-Za-z0-9+/_=-]{64,})'/;

  for (const [version, generatedValueCount] of cases) {
    const source = migrationSource(version);
    assert.equal(
      (source.match(/encode\(extensions\.gen_random_bytes\(32\), 'hex'\)/g) || []).length,
      generatedValueCount,
      version,
    );
    assert.match(source, /on conflict \([^)]*\) do nothing;/i);
    assert.doesNotMatch(source, quotedCredential);
    assert.match(source, /SEMANTIC REDACTION/);
  }
});

test('45 non-sensitive provider payloads retain their exact executable bodies', () => {
  const semanticCopies = manifest.history.filter(
    (entry) => entry.classification === 'semantic_copy',
  );
  assert.equal(semanticCopies.length, 45);
  assert.equal(
    manifest.history.filter((entry) => entry.classification.includes('foundation')).length,
    2,
  );
  assert.equal(
    manifest.history.filter(
      (entry) => entry.classification === 'secret_safe_semantic_reconstruction',
    ).length,
    3,
  );

  for (const entry of semanticCopies) {
    const active = readFileSync(join(repositoryRoot, entry.active.path), 'utf8');
    const separator = active.indexOf('\n\n');
    assert.ok(separator > 0, `${entry.version}: governed header missing`);
    const executableBody = active.slice(separator + 2);
    const possibleProviderHashes = new Set([
      sha256(Buffer.from(executableBody)),
      sha256(Buffer.from(executableBody.replace(/\n$/, ''))),
    ]);
    assert.ok(
      possibleProviderHashes.has(entry.live.sha256),
      `${entry.version}: executable body differs from the recorded provider payload`,
    );
  }
});

test('foundation limitations remain explicit in active recovery source', () => {
  const first = migrationSource('20260724010000');
  const second = migrationSource('20260724030000');

  assert.match(first, /Equivalence to the live historical statement is unprovable/);
  assert.match(first, /create type public\.member_role/);
  assert.match(second, /Reconstructed schema-shape hypothesis/);
  assert.match(second, /Positive grants are intentionally deferred/);
  assert.match(second, /REPLAY-SAFETY INVARIANT, NOT RECOVERED HISTORICAL DDL/);
  assert.doesNotMatch(second, /INACTIVE RECOVERY CANDIDATE/);
});

test('pending ordinary approval boundary is AAL1 owner/admin and fail-closed', () => {
  const source = readFileSync(join(repositoryRoot, manifest.pending_change.path), 'utf8');
  assert.doesNotMatch(source, /auth\.sessions/i);
  assert.doesNotMatch(source, /auth\.aal_level/i);
  assert.doesNotMatch(source, /current_session_id/i);
  assert.match(source, /array\['owner', 'admin'\]::public\.member_role\[\]/);
  assert.doesNotMatch(source, /array\[[^\]]*'operator'/);
  assert.match(source, /is_anonymous/);
  assert.match(source, /approval_row\.decision <> 'pending'/);
  assert.match(source, /approval_row\.expires_at <= timezone\('utc', now\(\)\)/);
  assert.match(source, /step_risk in \('R3'.*'R4'/);
  assert.match(source, /append_audit_event/);
});

test('database rollback restores the exact prior AAL2 executable body', () => {
  const prior = migrationSource('20260810083416');
  const priorBody = prior.slice(prior.indexOf('\n\n') + 2);
  const rollbackPath = join(
    evidenceRoot,
    'rollback',
    '20260812034825_restore_projectos_approval_aal2.sql',
  );
  const rollback = readFileSync(rollbackPath, 'utf8');
  const rollbackBody = rollback.slice(rollback.indexOf('\n\n') + 2);

  assert.equal(rollbackBody, priorBody);
  assert.match(rollbackBody, /auth\.sessions/);
  assert.match(rollbackBody, /current_session_id/);
  assert.match(rollbackBody, /'aal2'/i);
  assert.deepEqual(currentReplayResult.assertions.database_rollback_smoke, {
    restore_previous_aal2_definition: 'pass',
    reapply_aal1_definition: 'pass',
  });
});
