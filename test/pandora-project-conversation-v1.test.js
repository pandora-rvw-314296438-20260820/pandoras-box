const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const {
  UUID, RAW_INTENT, migrationPaths, makeDb, seedCore, signIn, resetRole, seedLifecycle,
} = require('./helpers/pandora-project-conversation-v1-db');

test('migration contract keeps conversation derived and Build-it separate from Publish', () => {
  const source = migrationPaths.map((migrationPath) => readFileSync(migrationPath, 'utf8')).join('\n');
  assert.doesNotMatch(source, /create table[^;]+conversation/i);
  assert.match(source, /pandora_build_authorization_receipts/);
  assert.match(source, /approved_spec_sha256/);
  assert.match(source, /publishAuthorized', false/);
  assert.match(source, /pandora_get_project_conversation_v1/);
  assert.match(source, /\(ai\.occurred_at, ai\.conversation_item_id\)[\s\S]*< \(p_before_occurred_at, p_before_item_id\)/);
  assert.match(source, /i\.intent_text[\s\S]*'intentText', i\.intent_text/);
  assert.match(source, /private\.pandora_control_plane_project_org_matches/);
  assert.match(source, /ORGANIZATION_ACCESS_REQUIRED/);
});

test('Build it binds exact intent, spec hash and actor and cannot authorize Publish', async () => {
  const db = await makeDb();
  await seedCore(db);
  await signIn(db);

  const first = await db.query(
    `select public.pandora_authorize_project_build_v1($1, $2, $3) as receipt`,
    [UUID.project, UUID.spec, 'build-auth-0001'],
  );
  const receipt = first.rows[0].receipt;
  assert.equal(receipt.projectId, UUID.project);
  assert.equal(receipt.sourceIntentId, UUID.intent);
  assert.equal(receipt.projectSpecId, UUID.spec);
  assert.equal(receipt.approvedSpecSha256, 'a'.repeat(64));
  assert.equal(receipt.authorizedBy, UUID.user);
  assert.equal(receipt.publishAuthorized, false);
  assert.equal(receipt.buildJobId, null);

  const replay = await db.query(
    `select public.pandora_authorize_project_build_v1($1, $2, $3) as receipt`,
    [UUID.project, UUID.spec, 'build-auth-0001'],
  );
  assert.equal(replay.rows[0].receipt.authorizationId, receipt.authorizationId);

  await assert.rejects(
    db.query(
      `select public.pandora_authorize_project_build_v1($1, $2, $3)`,
      [UUID.otherProject, UUID.otherSpec, 'build-auth-0002'],
    ),
    /ORGANIZATION_ACCESS_REQUIRED/,
  );

  await resetRole(db);
  await db.close();
});

test('Build admission binding fails closed on lineage mismatch and becomes immutable', async () => {
  const db = await makeDb();
  await seedCore(db);
  await signIn(db);
  const authResult = await db.query(
    `select public.pandora_authorize_project_build_v1($1, $2, $3) as receipt`,
    [UUID.project, UUID.spec, 'build-auth-0003'],
  );
  const authorizationId = authResult.rows[0].receipt.authorizationId;
  await resetRole(db);

  await db.exec(`
    insert into public.pandora_build_jobs(
      id, organization_id, project_id, project_spec_id, source_intent_id,
      requested_by, job_kind, status, current_stage, idempotency_key, created_at
    ) values (
      '${UUID.job}', '${UUID.org}', '${UUID.project}', '${UUID.spec}', '${UUID.intent}',
      '${UUID.user}', 'build', 'queued', 'received', 'build-job-0001', now() - interval '17 minutes'
    );
  `);

  await db.exec('set role service_role;');
  const bound = await db.query(
    `select public.pandora_bind_build_authorization_service_v1($1, $2) as receipt`,
    [authorizationId, UUID.job],
  );
  assert.equal(bound.rows[0].receipt.buildJobId, UUID.job);
  assert.ok(bound.rows[0].receipt.admittedAt);
  await db.exec('reset role;');

  const wrongJob = '60000000-0000-4000-8000-000000000099';
  await db.exec(`
    insert into public.pandora_build_jobs(
      id, organization_id, project_id, project_spec_id, source_intent_id,
      requested_by, job_kind, status, current_stage, idempotency_key
    ) values (
      '${wrongJob}', '${UUID.org}', '${UUID.project}', '${UUID.spec}', '${UUID.intent}',
      '${UUID.otherUser}', 'build', 'queued', 'received', 'build-job-wrong-0001'
    );
  `);
  await db.exec('set role service_role;');
  await assert.rejects(
    db.query(
      `select public.pandora_bind_build_authorization_service_v1($1, $2)`,
      [authorizationId, wrongJob],
    ),
    /BUILD_AUTHORIZATION_JOB_LINEAGE_INVALID|BUILD_AUTHORIZATION_ALREADY_BOUND/,
  );
  await assert.rejects(
    db.query(
      `update public.pandora_build_authorization_receipts set approved_spec_sha256=$1 where id=$2`,
      ['c'.repeat(64), authorizationId],
    ),
    /BUILD_AUTHORIZATION_IMMUTABLE/,
  );
  await db.exec('reset role;');
  await db.close();
});

test('conversation derives exact chronological lineage and omits unlinked lifecycle rows', async () => {
  const db = await makeDb();
  await seedCore(db);
  await signIn(db);
  const authResult = await db.query(
    `select public.pandora_authorize_project_build_v1($1, $2, $3) as receipt`,
    [UUID.project, UUID.spec, 'history-auth-0001'],
  );
  const authorizationId = authResult.rows[0].receipt.authorizationId;
  await resetRole(db);
  await seedLifecycle(db, authorizationId);
  await signIn(db);

  const page = await db.query(
    `select * from public.pandora_get_project_conversation_v1($1, 50, null, null)`,
    [UUID.project],
  );
  const kinds = page.rows.map((row) => row.kind);
  assert.ok(kinds.includes('USER_INTENT'));
  assert.ok(kinds.includes('PANDORA_PROPOSAL'));
  assert.ok(kinds.includes('USER_BUILD_AUTHORIZATION'));
  assert.ok(kinds.includes('BUILD_ADMITTED'));
  assert.ok(kinds.includes('VERIFICATION_RECEIPT'));
  assert.ok(kinds.includes('PREVIEW_READY'));
  assert.ok(kinds.includes('PUBLISH_RECEIPT'));

  const intentItem = page.rows.find((row) => row.kind === 'USER_INTENT');
  assert.equal(intentItem.display_payload.intentText, RAW_INTENT);
  const authItem = page.rows.find((row) => row.kind === 'USER_BUILD_AUTHORIZATION');
  assert.equal(authItem.source_intent_id, UUID.intent);
  assert.equal(authItem.project_spec_id, UUID.spec);
  assert.equal(authItem.build_job_id, UUID.job);
  assert.equal(authItem.display_payload.publishAuthorized, false);

  const verificationRows = page.rows.filter((row) => row.kind === 'VERIFICATION_RECEIPT');
  assert.equal(verificationRows.length, 1, 'mismatched spec verification must be omitted');
  const previewRows = page.rows.filter((row) => row.kind === 'PREVIEW_READY');
  assert.equal(previewRows.length, 1, 'source-mismatched deployment must be omitted');
  assert.ok(page.rows.every((row) => row.organization_id === UUID.org && row.project_id === UUID.project));

  await resetRole(db);
  await db.close();
});

test('keyset pagination has no duplicate or missing boundary items when newer history arrives', async () => {
  const db = await makeDb();
  await seedCore(db);
  await signIn(db);
  const authResult = await db.query(
    `select public.pandora_authorize_project_build_v1($1, $2, $3) as receipt`,
    [UUID.project, UUID.spec, 'cursor-auth-0001'],
  );
  await resetRole(db);
  await seedLifecycle(db, authResult.rows[0].receipt.authorizationId);
  await signIn(db);

  const newest = await db.query(
    `select * from public.pandora_get_project_conversation_v1($1, 3, null, null)`,
    [UUID.project],
  );
  assert.equal(newest.rows.length, 3);
  const cursor = newest.rows[0];

  await resetRole(db);
  await db.exec(`
    insert into public.pandora_project_intents(
      organization_id, project_id, requester_id, intent_kind, intent_text,
      normalized_summary, source, idempotency_key, received_at, created_at
    ) values (
      '${UUID.org}', '${UUID.project}', '${UUID.user}', 'change', 'Make checkout clearer.',
      'Make checkout clearer.', 'customer', 'newer-history-0001', now() + interval '1 minute', now() + interval '1 minute'
    );
  `);
  await signIn(db);

  const older = await db.query(
    `select * from public.pandora_get_project_conversation_v1($1, 50, $2, $3)`,
    [UUID.project, cursor.occurred_at, cursor.conversation_item_id],
  );
  const newestIds = new Set(newest.rows.map((row) => row.conversation_item_id));
  assert.ok(older.rows.every((row) => !newestIds.has(row.conversation_item_id)));

  const allBeforeInsert = [...older.rows, ...newest.rows];
  assert.equal(new Set(allBeforeInsert.map((row) => row.conversation_item_id)).size, allBeforeInsert.length);
  assert.ok(allBeforeInsert.some((row) => row.kind === 'USER_INTENT'));
  assert.ok(allBeforeInsert.some((row) => row.kind === 'PANDORA_PROPOSAL'));

  await resetRole(db);
  await db.close();
});

test('rollback history appears only with exact live verified rollback lineage', async () => {
  const db = await makeDb();
  await seedCore(db);
  await db.exec(`
    insert into public.pandora_build_jobs(
      id, organization_id, project_id, project_spec_id, source_intent_id,
      requested_by, job_kind, status, current_stage, idempotency_key, created_at
    ) values (
      '${UUID.job}', '${UUID.org}', '${UUID.project}', '${UUID.spec}', '${UUID.intent}',
      '${UUID.user}', 'build', 'succeeded', 'preview_ready', 'undo-build-0001', now() - interval '15 minutes'
    );
    insert into public.pandora_project_versions(
      id, organization_id, project_id, sequence_no, project_spec_id, build_job_id,
      source_sha256, verification_run_id, lifecycle_status, created_at
    ) values (
      '${UUID.version}', '${UUID.org}', '${UUID.project}', 1, '${UUID.spec}', '${UUID.job}',
      '${'d'.repeat(64)}', '${UUID.verification}', 'live', now() - interval '14 minutes'
    ), (
      '${UUID.version2}', '${UUID.org}', '${UUID.project}', 2, '${UUID.spec}', '${UUID.job}',
      '${'e'.repeat(64)}', null, 'live', now() - interval '12 minutes'
    );
    insert into public.pandora_verification_runs(
      id, organization_id, project_id, project_spec_id, project_version_id, build_job_id,
      source_digest, artifact_digest, target_environment, status, created_at
    ) values (
      '${UUID.verification}', '${UUID.org}', '${UUID.project}', '${UUID.spec}', '${UUID.version}', '${UUID.job}',
      '${'d'.repeat(64)}', '${'f'.repeat(64)}', 'preview', 'PASS', now() - interval '13 minutes'
    );
  `);

  const actionHash = '9'.repeat(64);
  await db.exec(`
    insert into public.pandora_tool_calls(
      id, organization_id, project_id, project_spec_id, build_job_id, project_version_id,
      tool_name, tool_version, action_hash, decision, environment, status, requested_at
    ) values (
      '${UUID.toolCall}', '${UUID.org}', '${UUID.project}', '${UUID.spec}', '${UUID.job}', '${UUID.version}',
      'rollback_project', '1', '${actionHash}', 'ALLOW', 'production', 'succeeded', now() - interval '5 minutes'
    );
    insert into public.pandora_project_deployments(
      id, organization_id, project_id, version_id, provider, environment, provider_project_id,
      provider_deployment_id, status, source_sha256, authorization_ref, verification_ref,
      verification_state, ready_at, created_at
    ) values (
      '${UUID.rollbackDeployment}', '${UUID.org}', '${UUID.project}', '${UUID.version}', 'vercel', 'production', 'provider-project',
      'rollback-prod-1', 'ready', '${'d'.repeat(64)}', 'worker-c:${actionHash}', '${UUID.verification}',
      'live_verified', now() - interval '4 minutes', now() - interval '4 minutes'
    );
    insert into public.pandora_publish_receipts(
      id, organization_id, project_id, version_id, production_deployment_id, source_sha256,
      previous_production_version_id, status, published_at, created_at
    ) values (
      '${UUID.rollbackPublish}', '${UUID.org}', '${UUID.project}', '${UUID.version}', '${UUID.rollbackDeployment}', '${'d'.repeat(64)}',
      '${UUID.version2}', 'live_verified', now() - interval '3 minutes', now() - interval '4 minutes'
    );
    insert into public.pandora_runtime_environments(
      organization_id, project_id, environment, current_version_id, current_deployment_id, verification_state
    ) values (
      '${UUID.org}', '${UUID.project}', 'production', '${UUID.version}', '${UUID.rollbackDeployment}', 'live_verified'
    );
  `);

  await signIn(db);
  const page = await db.query(
    `select * from public.pandora_get_project_conversation_v1($1, 50, null, null)`,
    [UUID.project],
  );
  const undo = page.rows.filter((row) => row.kind === 'UNDO_RECEIPT');
  assert.equal(undo.length, 1);
  assert.equal(undo[0].project_version_id, UUID.version);
  assert.equal(undo[0].deployment_id, UUID.rollbackDeployment);
  assert.equal(undo[0].display_payload.restoredVersion, 1);
  assert.equal(undo[0].display_payload.previousVersion, 2);
  assert.equal(
    page.rows.filter((row) => row.kind === 'PUBLISH_RECEIPT' && row.deployment_id === UUID.rollbackDeployment).length,
    0,
    'rollback deployment must not duplicate as an ordinary publish receipt',
  );

  await resetRole(db);
  await db.exec(`update public.pandora_project_deployments set authorization_ref='worker-c:${'8'.repeat(64)}' where id='${UUID.rollbackDeployment}'`);
  await signIn(db);
  const afterBreak = await db.query(
    `select * from public.pandora_get_project_conversation_v1($1, 50, null, null)`,
    [UUID.project],
  );
  assert.equal(afterBreak.rows.filter((row) => row.kind === 'UNDO_RECEIPT').length, 0);

  await resetRole(db);
  await db.close();
});
