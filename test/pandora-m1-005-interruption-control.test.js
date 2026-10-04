'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const root = join(__dirname, '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');
const migration = read('supabase','migrations','20260915001000_pandora_activity_controls_v1.sql');
const activity = read('supabase','functions','pandora-intelligence-chat','activity.ts');
const edge = read('supabase','functions','pandora-intelligence-chat','index.ts');
const mobileApi = read('apps','pandora-mobile','lib','core','data','pandora_activity_stream_api.dart');
const intelligence = read('apps','pandora-mobile','lib','core','data','pandora_intelligence_api.dart');
const details = read('apps','pandora-mobile','lib','features','simple','chat','pandora_chat_activity_details.dart');
const composer = read('apps','pandora-mobile','lib','features','simple','chat','pandora_chat_composer.dart');
const chat = read('apps','pandora-mobile','lib','features','simple','ask_pandora_screen.dart');

test('durable controls are owner-scoped, idempotent and service-applied', () => {
  assert.match(migration, /create table if not exists public\.pandora_activity_controls/);
  assert.match(migration, /unique \(job_id, request_id\)/);
  assert.match(migration, /control_type in \('cancel','redirect','constraint'\)/);
  assert.match(migration, /requested_by=auth\.uid\(\)/);
  assert.match(migration, /pandora_activity_control_request_v1/);
  assert.match(migration, /pandora_activity_control_claim_v1/);
  assert.match(migration, /pandora_activity_control_finish_v1/);
  assert.match(migration, /pandora_activity_control_apply_v1/);
  assert.match(migration, /pandora_activity_control_credential_material_rejected/);
  assert.match(migration, /grant execute on function public\.pandora_activity_control_request_v1[\s\S]*to authenticated/);
  assert.match(migration, /grant execute on function public\.pandora_activity_control_claim_v1[\s\S]*to service_role/);
  assert.match(migration, /grant execute on function public\.pandora_activity_control_apply_v1[\s\S]*to service_role/);
  assert.doesNotMatch(migration, /grant (insert|update|delete) on table public\.pandora_activity_(controls|events) to authenticated/i);
});

test('accepted controls create canonical user-control evidence without public raw instructions', () => {
  assert.match(activity, /claimActivityControls/);
  assert.match(activity, /finishActivityControl/);
  assert.match(activity, /emitAcceptedActivityControl/);
  assert.match(activity, /type: 'user_control'/);
  assert.match(activity, /relation: 'accepted_control'/);
  assert.match(activity, /control: \{ type: 'cancel', requestId: control\.requestId, acceptedAt: control\.acceptedAt \}/);
  assert.match(activity, /state: 'cancelled'/);
  assert.doesNotMatch(activity, /message:\s*control\.instruction/);
});

test('runtime rechecks live controls and supersedes stale provider output', () => {
  assert.match(edge, /function controlledMessage/);
  assert.match(edge, /function drainActivityControls/);
  assert.ok((edge.match(/drainActivityControls\(/g) ?? []).length >= 4);
  assert.match(edge, /superseded_by_user_control/);
  assert.match(edge, /index=-1;continue/);
  assert.match(edge, /CONTROL_REVISION_LIMIT/);
  assert.match(edge, /REQUEST_CANCELLED/);
  assert.match(edge, /cred\(instruction\)/);
});

test('per-turn Details supports pre-response controls and composer Stop retains generation identity', () => {
  assert.match(mobileApi, /enum PandoraActivityControlType \{ cancel, redirect, constraint \}/);
  assert.match(mobileApi, /pandora_activity_control_request_v1/);
  assert.match(intelligence, /Future<void> controlActivityJob/);
  assert.match(details, /_current\(token\)/);
  assert.match(details, /_routes\[token\.attemptId\] != _ChatExecutionRoute\.cloud/);
  assert.match(details, /turn\.reply\.isEmpty/);
  assert.match(details, /PandoraActivityControlType\.redirect/);
  assert.match(details, /PandoraActivityControlType\.constraint/);
  assert.match(details, /controlActivityJob\([\s\S]*jobId: jobId,[\s\S]*requestId: requestId/);
  assert.match(details, /presentContextRoute\(route\)/);
  assert.match(chat, /cancelChatTurn\(/);
  assert.match(composer, /current\.generationIdentity == expectedGeneration/);
  assert.match(composer, /widget\.state\.value\.canSend/);
  assert.match(composer, /widget\.state\.value\.canDictate/);
  assert.doesNotMatch(chat, /_submitting && _activeActivityJobId/, 'overlapping global lifecycle flags cannot return');
});
