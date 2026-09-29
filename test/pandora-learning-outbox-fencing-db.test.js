const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migrationPath = path.join(
  root,
  'supabase/migrations/20260929013000_pandora_learning_outbox_fencing_v2.sql',
);
const migration = fs.readFileSync(migrationPath, 'utf8');

let PGlite;

async function expectSqlError(promise, code, marker) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code);
    assert.match(error.message, new RegExp(marker));
    return true;
  });
}

async function makeDb() {
  PGlite ??= (await import('@electric-sql/pglite')).PGlite;
  const db = new PGlite();
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role;
    create schema private;
  `);
  await db.exec(migration);
  return db;
}

async function seed(db, count = 1) {
  await db.query(`
    insert into public.pandora_verified_learning_outbox(
      organization_id,activity_job_id,idempotency_key,memory_project_id,
      learning_kind,learning_summary,promotion_basis,confidence,execution
    )
    select
      gen_random_uuid(),gen_random_uuid(),'synthetic-'||g,gen_random_uuid(),
      'outcome','synthetic fixture','review-gated fixture',0.8,
      '{"canonicalMemoryWritten":false}'::jsonb
    from generate_series(1,$1) g
  `, [count]);
}

async function claim(db, limit = 1) {
  const result = await db.query(
    'select * from public.pandora_claim_verified_learning_outbox_v2($1)',
    [limit],
  );
  return result.rows;
}

async function ack(db, row, {
  success,
  candidateId = null,
  reviewItemId = null,
  retryable = false,
  errorCode = null,
  token = row.claim_token,
  attempt = row.attempt_count,
} = {}) {
  return db.query(
    `select public.pandora_ack_verified_learning_outbox_v2(
      $1,$2,$3,$4,$5,$6,$7,$8
    ) as result`,
    [
      row.id,
      token,
      attempt,
      success,
      candidateId,
      reviewItemId,
      retryable,
      errorCode,
    ],
  );
}

test('claim v2 rejects null and out-of-range limits and never exceeds twenty', async () => {
  const db = await makeDb();
  try {
    await seed(db, 21);
    await expectSqlError(
      db.query('select * from public.pandora_claim_verified_learning_outbox_v2(null)'),
      '22023',
      'PANDORA_LEARNING_OUTBOX_LIMIT_INVALID',
    );
    await expectSqlError(
      db.query('select * from public.pandora_claim_verified_learning_outbox_v2(21)'),
      '22023',
      'PANDORA_LEARNING_OUTBOX_LIMIT_INVALID',
    );
    const rows = await claim(db, 20);
    assert.equal(rows.length, 20);
    assert.ok(rows.every((row) => row.state === 'processing'));
    assert.ok(rows.every((row) => row.attempt_count === 1));
    assert.ok(rows.every((row) => /^[0-9a-f-]{36}$/.test(row.claim_token)));
    assert.equal(new Set(rows.map((row) => row.claim_token)).size, 20);
    const pending = await db.query(
      "select count(*)::integer as count from public.pandora_verified_learning_outbox where state='pending'",
    );
    assert.equal(pending.rows[0].count, 1);
  } finally {
    await db.close();
  }
});

test('legacy claim and acknowledgement fail before leasing or mutating work', async () => {
  const db = await makeDb();
  try {
    await seed(db);
    await expectSqlError(
      db.query('select * from public.pandora_claim_verified_learning_outbox(1)'),
      '0A000',
      'PANDORA_LEARNING_OUTBOX_V1_DISABLED',
    );
    let state = await db.query(
      'select state,attempt_count,claim_token from public.pandora_verified_learning_outbox',
    );
    assert.deepEqual(state.rows[0], {
      state: 'pending',
      attempt_count: 0,
      claim_token: null,
    });

    const [row] = await claim(db);
    await expectSqlError(
      db.query(
        'select public.pandora_ack_verified_learning_outbox($1,true,$2,$3)',
        [
          row.id,
          '11111111-1111-4111-8111-111111111111',
          '22222222-2222-4222-8222-222222222222',
        ],
      ),
      '0A000',
      'PANDORA_LEARNING_OUTBOX_V1_DISABLED',
    );
    state = await db.query(
      'select state,attempt_count,claim_token from public.pandora_verified_learning_outbox',
    );
    assert.equal(state.rows[0].state, 'processing');
    assert.equal(state.rows[0].attempt_count, 1);
    assert.equal(state.rows[0].claim_token, row.claim_token);
  } finally {
    await db.close();
  }
});

test('success requires both Memory receipt UUIDs and keeps review distinct from promotion', async () => {
  const db = await makeDb();
  try {
    await seed(db);
    const [row] = await claim(db);
    const candidateId = '11111111-1111-4111-8111-111111111111';
    const reviewItemId = '22222222-2222-4222-8222-222222222222';

    await expectSqlError(
      ack(db, row, {success: true, candidateId}),
      '22023',
      'PANDORA_LEARNING_OUTBOX_RECEIPTS_REQUIRED',
    );
    await expectSqlError(
      ack(db, row, {success: true, reviewItemId}),
      '22023',
      'PANDORA_LEARNING_OUTBOX_RECEIPTS_REQUIRED',
    );
    await expectSqlError(
      ack(db, row, {
        success: true,
        candidateId,
        reviewItemId,
        retryable: true,
      }),
      '22023',
      'PANDORA_LEARNING_OUTBOX_SUCCESS_FIELDS_INVALID',
    );

    const result = await ack(db, row, {
      success: true,
      candidateId,
      reviewItemId,
    });
    assert.deepEqual(result.rows[0].result, {
      id: row.id,
      state: 'accepted',
      attemptCount: 1,
      memoryCandidateId: candidateId,
      memoryReviewItemId: reviewItemId,
    });
    const stored = await db.query(
      `select state,claim_token,lease_until,memory_candidate_id,
              memory_review_item_id,execution
       from public.pandora_verified_learning_outbox`,
    );
    assert.equal(stored.rows[0].state, 'accepted');
    assert.equal(stored.rows[0].claim_token, null);
    assert.equal(stored.rows[0].lease_until, null);
    assert.equal(stored.rows[0].execution.canonicalMemoryWritten, false);
  } finally {
    await db.close();
  }
});

test('reclaim rotates the capability and fences every stale token or attempt', async () => {
  const db = await makeDb();
  try {
    await seed(db);
    const [first] = await claim(db);
    await db.query(
      "update public.pandora_verified_learning_outbox set lease_until=clock_timestamp()-interval '1 second' where id=$1",
      [first.id],
    );
    const [second] = await claim(db);
    assert.equal(second.attempt_count, 2);
    assert.notEqual(second.claim_token, first.claim_token);

    const candidateId = '33333333-3333-4333-8333-333333333333';
    const reviewItemId = '44444444-4444-4444-8444-444444444444';
    await expectSqlError(
      ack(db, first, {success: true, candidateId, reviewItemId}),
      '55000',
      'PANDORA_LEARNING_OUTBOX_CLAIM_STALE',
    );
    await expectSqlError(
      ack(db, second, {
        success: true,
        candidateId,
        reviewItemId,
        attempt: 1,
      }),
      '55000',
      'PANDORA_LEARNING_OUTBOX_CLAIM_STALE',
    );
    let stored = await db.query(
      'select state,attempt_count,claim_token,memory_candidate_id from public.pandora_verified_learning_outbox',
    );
    assert.equal(stored.rows[0].state, 'processing');
    assert.equal(stored.rows[0].attempt_count, 2);
    assert.equal(stored.rows[0].claim_token, second.claim_token);
    assert.equal(stored.rows[0].memory_candidate_id, null);

    await ack(db, second, {success: true, candidateId, reviewItemId});
    stored = await db.query(
      'select state,attempt_count,claim_token from public.pandora_verified_learning_outbox',
    );
    assert.deepEqual(stored.rows[0], {
      state: 'accepted',
      attempt_count: 2,
      claim_token: null,
    });
  } finally {
    await db.close();
  }
});

test('expired claims cannot acknowledge and retryable failures preserve state distinctions', async () => {
  const db = await makeDb();
  try {
    await seed(db);
    let [row] = await claim(db);
    await db.query(
      "update public.pandora_verified_learning_outbox set lease_until=clock_timestamp()-interval '1 second' where id=$1",
      [row.id],
    );
    await expectSqlError(
      ack(db, row, {
        success: false,
        retryable: true,
        errorCode: 'transport_timeout',
      }),
      '55000',
      'PANDORA_LEARNING_OUTBOX_CLAIM_STALE',
    );

    [row] = await claim(db);
    await expectSqlError(
      ack(db, row, {
        success: false,
        candidateId: '55555555-5555-4555-8555-555555555555',
        retryable: true,
      }),
      '22023',
      'PANDORA_LEARNING_OUTBOX_FAILURE_RECEIPTS_INVALID',
    );
    await ack(db, row, {
      success: false,
      retryable: true,
      errorCode: 'provider_unavailable',
    });
    let stored = await db.query(
      'select state,attempt_count,claim_token,last_error_code from public.pandora_verified_learning_outbox',
    );
    assert.deepEqual(stored.rows[0], {
      state: 'pending',
      attempt_count: 2,
      claim_token: null,
      last_error_code: 'provider_unavailable',
    });

    [row] = await claim(db);
    await ack(db, row, {
      success: false,
      retryable: false,
      errorCode: 'contract_rejected',
    });
    stored = await db.query(
      'select state,attempt_count,claim_token,last_error_code,memory_candidate_id,memory_review_item_id from public.pandora_verified_learning_outbox',
    );
    assert.deepEqual(stored.rows[0], {
      state: 'failed',
      attempt_count: 3,
      claim_token: null,
      last_error_code: 'contract_rejected',
      memory_candidate_id: null,
      memory_review_item_id: null,
    });
  } finally {
    await db.close();
  }
});

test('legacy processing rows with NULL leases are reclaimed below the attempt bound', async () => {
  const db = await makeDb();
  try {
    await seed(db);
    await db.exec(
      'alter table public.pandora_verified_learning_outbox drop constraint pandora_verified_learning_outbox_claim_fence_check',
    );
    await db.query(
      "update public.pandora_verified_learning_outbox set state='processing',attempt_count=2,lease_until=null,claim_token=null",
    );
    const [row] = await claim(db);
    assert.equal(row.state, 'processing');
    assert.equal(row.attempt_count, 3);
    assert.match(row.claim_token, /^[0-9a-f-]{36}$/);
    assert.ok(row.lease_until);
  } finally {
    await db.close();
  }
});

test('exhausted pending or expired work terminates without reclaiming an active fifth lease', async () => {
  const db = await makeDb();
  try {
    await seed(db);
    let row;
    for (let attempt = 1; attempt <= 5; attempt += 1) {
      [row] = await claim(db);
      assert.equal(row.attempt_count, attempt);
      await db.query(
        "update public.pandora_verified_learning_outbox set lease_until=clock_timestamp()-interval '1 second' where id=$1",
        [row.id],
      );
    }

    assert.deepEqual(await claim(db), []);
    let stored = await db.query(
      `select state,attempt_count,claim_token,lease_until,last_error_code,
              memory_candidate_id,memory_review_item_id,delivered_at
       from public.pandora_verified_learning_outbox`,
    );
    assert.deepEqual(stored.rows[0], {
      state: 'failed',
      attempt_count: 5,
      claim_token: null,
      lease_until: null,
      last_error_code: 'delivery_attempts_exhausted',
      memory_candidate_id: null,
      memory_review_item_id: null,
      delivered_at: null,
    });

    await db.exec('truncate public.pandora_verified_learning_outbox');
    await seed(db);
    await db.query(
      "update public.pandora_verified_learning_outbox set attempt_count=4 where state='pending'",
    );
    [row] = await claim(db);
    assert.equal(row.attempt_count, 5);
    assert.deepEqual(await claim(db), []);
    stored = await db.query(
      'select state,attempt_count,claim_token from public.pandora_verified_learning_outbox',
    );
    assert.equal(stored.rows[0].state, 'processing');
    assert.equal(stored.rows[0].attempt_count, 5);
    assert.equal(stored.rows[0].claim_token, row.claim_token);

    await db.exec('truncate public.pandora_verified_learning_outbox');
    await seed(db, 21);
    await db.query(
      "update public.pandora_verified_learning_outbox set attempt_count=5 where state='pending'",
    );
    assert.deepEqual(await claim(db, 1), []);
    stored = await db.query(
      `select state,count(*)::integer as count
       from public.pandora_verified_learning_outbox
       group by state order by state`,
    );
    assert.deepEqual(stored.rows, [
      {state: 'failed', count: 1},
      {state: 'pending', count: 20},
    ]);
    const terminal = await db.query(
      `select attempt_count,claim_token,last_error_code
       from public.pandora_verified_learning_outbox
       where state='failed'`,
    );
    assert.deepEqual(terminal.rows[0], {
      attempt_count: 5,
      claim_token: null,
      last_error_code: 'delivery_attempts_exhausted',
    });
  } finally {
    await db.close();
  }
});

test('NULL HTTP status fails closed while the latest typed response contract is preserved', async () => {
  const db = await makeDb();
  try {
    const payload = {
      learning_kind: 'visible_creation_evidence_v1',
      source_event_id: 'source-1',
      visible_project_id: 'project-1',
      evidence_kind: 'verified',
      proof_stage: 'review',
    };
    const body = {
      ok: true,
      review_required: true,
      canonical_memory_written: false,
      source_event_id: 'source-1',
      visible_project_id: 'project-1',
      evidence_kind: 'verified',
      proof_stage: 'review',
      candidate_id: '66666666-6666-4666-8666-666666666666',
      review_item_id: '77777777-7777-4777-8777-777777777777',
    };
    const validate = (status, content = JSON.stringify(body)) => db.query(
      `select private.execution_learning_response_is_valid(
        $1::jsonb,$2,$3,null,false
      ) as valid`,
      [JSON.stringify(payload), status, content],
    );

    assert.equal((await validate(null)).rows[0].valid, false);
    assert.equal((await validate(200)).rows[0].valid, true);
    assert.equal((await validate(202)).rows[0].valid, true);
    assert.equal((await validate(200, 'not-json')).rows[0].valid, false);
    const legacyNull = await db.query(
      "select private.execution_learning_response_is_valid('{}'::jsonb,null,'{}',null,false) as valid",
    );
    assert.equal(legacyNull.rows[0].valid, false);
    const legacyOk = await db.query(
      "select private.execution_learning_response_is_valid('{}'::jsonb,200,'{}',null,false) as valid",
    );
    assert.equal(legacyOk.rows[0].valid, true);
  } finally {
    await db.close();
  }
});

test('migration preserves the existing privilege boundary and exposes no promotion operation', () => {
  assert.match(migration, /security definer\s+set search_path=''/);
  assert.match(
    migration,
    /revoke all on function public\.pandora_claim_verified_learning_outbox_v2\(integer\)[\s\S]*from public,anon,authenticated;/,
  );
  assert.match(
    migration,
    /grant execute on function public\.pandora_ack_verified_learning_outbox_v2[\s\S]*to service_role;/,
  );
  assert.match(
    migration,
    /revoke all on function private\.execution_learning_response_is_valid[\s\S]*from public,anon,authenticated;/,
  );
  const ackStart = migration.indexOf(
    'create or replace function public.pandora_ack_verified_learning_outbox_v2',
  );
  const rowLock = migration.indexOf('for update;', ackStart);
  const postLockClock = migration.indexOf('v_now := clock_timestamp();', ackStart);
  assert.ok(ackStart >= 0 && rowLock > ackStart);
  assert.ok(postLockClock > rowLock);
  assert.doesNotMatch(
    migration,
    /pandora_memory|canonical_memory_written\s*:?=|auto.?approv/i,
  );
});
