const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const analytics = fs.readFileSync('apps/pandora-mobile/lib/core/analytics/owner_analytics.dart', 'utf8');
const create = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_create_experience.dart', 'utf8');
const conversation = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_build_conversation.dart', 'utf8');
const experience = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_experience_api.dart', 'utf8');
const runtime = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_runtime_api.dart', 'utf8');
const generator = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');

const requiredEvents = [
  'intent_sent', 'proposal_shown', 'build_clicked', 'build_admitted',
  'first_stream_event', 'first_code', 'file_complete', 'source_complete',
  'preview_ready', 'repair_started', 'repair_completed', 'stream_reconnected',
  'history_gap', 'publish_started', 'publish_verified', 'publish_failed',
  'source_paywall_viewed', 'source_access_granted', 'source_exported',
];

test('visible creation analytics exposes the complete bounded milestone vocabulary', () => {
  for (const event of requiredEvents) assert.match(analytics, new RegExp(`['"]${event}['"]`));
});

test('analytics has a fixed safe property contract and no arbitrary payload channel', () => {
  for (const key of ['project_id', 'build_job_id', 'stream_id', 'project_version_id', 'sequence', 'count', 'status', 'duration_ms']) {
    assert.match(analytics, new RegExp(`['"]${key}['"]`));
  }
  assert.doesNotMatch(analytics, /Map<String\s*,\s*Object\?>\??\s+(?:properties|payload|metadata)/);
  assert.doesNotMatch(analytics, /['"](?:intent_text|intentText|content_chunk|contentChunk|file_path|filePath|stdout|stderr|prompt|provider_response|providerResponse)['"]\s*:/);
});

test('intent proposal and build admission milestones follow authoritative transitions', () => {
  const submit = create.indexOf('final intentId = await experience.submitIntent(');
  const intent = create.indexOf('OwnerAnalyticsEvent.intentSent', submit);
  const proposal = create.indexOf('OwnerAnalyticsEvent.proposalShown');
  const clicked = create.indexOf('OwnerAnalyticsEvent.buildClicked');
  const request = create.indexOf('final start = await api.requestBuild(', clicked);
  const admitted = create.indexOf('OwnerAnalyticsEvent.buildAdmitted', request);
  assert.ok(submit >= 0 && intent > submit);
  assert.ok(proposal >= 0);
  assert.ok(clicked >= 0 && request > clicked && admitted > request);
  assert.match(create, /buildClickedAt:\s*clickedAt/);
  const intentCapture = create.slice(intent, intent + 500);
  assert.doesNotMatch(intentCapture, /intentText|originalIntent|objective/);
});

test('TTFC and source milestones are derived from real ordered stream events only', () => {
  assert.match(conversation, /\.\.sort\(\(left, right\) => left\.sequence\.compareTo\(right\.sequence\)\)/);
  assert.match(conversation, /case 'code_chunk':[\s\S]{0,220}\(event\.contentChunk \?\? ''\)\.isNotEmpty[\s\S]{0,220}OwnerAnalyticsEvent\.firstCode/);
  assert.match(conversation, /case 'file_completed':[\s\S]{0,240}OwnerAnalyticsEvent\.fileComplete/);
  assert.match(conversation, /case 'generation_completed':[\s\S]{0,240}OwnerAnalyticsEvent\.sourceComplete/);
  assert.match(conversation, /case 'preview_ready':[\s\S]{0,240}OwnerAnalyticsEvent\.previewReady/);
  assert.match(conversation, /occurredAt\.difference\(start\)/);
  const capture = conversation.slice(conversation.indexOf('void _captureMilestones'), conversation.indexOf('@override\n  void didChangeDependencies'));
  assert.doesNotMatch(capture, /event\.filePath/);
  assert.doesNotMatch(capture, /contentChunk:\s*/);
});

test('reconnect and retention-gap telemetry carries state but no expired source', () => {
  assert.match(conversation, /snapshot\.historyGapDueToRetention[\s\S]{0,220}OwnerAnalyticsEvent\.historyGap/);
  assert.match(conversation, /snapshot\.reconnecting && !_wasReconnecting[\s\S]{0,320}OwnerAnalyticsEvent\.streamReconnected/);
});

test('source access telemetry records outcomes without path query or source bytes', () => {
  assert.match(experience, /OwnerAnalyticsEvent\.sourcePaywallViewed/);
  assert.match(experience, /OwnerAnalyticsEvent\.sourceAccessGranted/);
  assert.match(experience, /OwnerAnalyticsEvent\.sourceExported/);
  const captureCalls = [...experience.matchAll(/OwnerAnalytics\.shared\.capture\([\s\S]{0,520}?\),\n\s*\);/g)]
    .map((match) => match[0])
    .filter((value) => /source(?:AccessGranted|PaywallViewed|Exported)/.test(value));
  assert.ok(captureCalls.length >= 3);
  for (const call of captureCalls) {
    assert.doesNotMatch(call, /\bpath:\s*path\b|\bquery:\s*query\b|contentChunk|sourceBytes|body:/);
  }
});

test('publish telemetry has explicit start success and failure outcomes', () => {
  const start = runtime.indexOf('OwnerAnalyticsEvent.publishStarted');
  const call = runtime.indexOf("operation: 'customerProject.publish'", start);
  const success = runtime.indexOf('OwnerAnalyticsEvent.publishVerified', call);
  const failure = runtime.indexOf('OwnerAnalyticsEvent.publishFailed', success);
  assert.ok(start >= 0 && call > start && success > call && failure > success);
});

test('source provider latency is measured monotonically and persisted without invented values', () => {
  assert.match(generator, /const providerStartedAt = performance\.now\(\)/);
  assert.match(generator, /responseHeadersAt = performance\.now\(\)/);
  assert.match(generator, /firstProviderByteAt = performance\.now\(\)/);
  assert.match(generator, /const providerCompletedAt = performance\.now\(\)/);
  assert.match(generator, /transportLatencyMs: Math\.max\(0, Math\.round\(responseHeadersAt - providerStartedAt\)\)/);
  assert.match(generator, /providerLatencyMs: measuredFirstByteAt === null[\s\S]{0,180}measuredFirstByteAt - responseHeadersAt/);
  assert.match(generator, /timeToFirstTokenMs: measuredFirstByteAt === null[\s\S]{0,180}measuredFirstByteAt - providerStartedAt/);
  assert.match(generator, /streamCompletionLatencyMs: measuredFirstByteAt === null[\s\S]{0,180}providerCompletedAt - measuredFirstByteAt/);
  assert.match(generator, /endToEndLatencyMs: Math\.max\(0, Math\.round\(providerCompletedAt - providerStartedAt\)\)/);
  for (const field of ['provider_latency_ms', 'transport_latency_ms', 'time_to_first_token_ms', 'stream_completion_latency_ms', 'end_to_end_latency_ms']) {
    assert.match(generator, new RegExp(`${field}: streamed\\.meta\\.`));
  }
  assert.match(generator, /started_at: streamed\.meta\.startedAt/);
  assert.match(generator, /completed_at: streamed\.meta\.completedAt/);
});
