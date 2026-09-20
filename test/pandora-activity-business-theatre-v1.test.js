import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const edge = await readFile(
  'supabase/functions/pandora-intelligence-chat/index.ts',
  'utf8',
);
const activity = await readFile(
  'apps/pandora-mobile/lib/features/activity/activity_screen.dart',
  'utf8',
);

test('customer Activity Theatre reports resort work, not model plumbing', () => {
  assert.match(edge, /pandora-business-theatre/);
  assert.match(edge, /Checking arrivals and arrival details\./);
  assert.match(edge, /Checking departures and departure details\./);
  assert.match(edge, /Checking room availability\./);
  assert.match(edge, /Checking bookings and reservation details\./);
  assert.match(edge, /Checking open guest requests\./);
  assert.match(edge, /Checking revenue and booking performance\./);
  assert.match(edge, /Checking open staff tasks and assigned work\./);
  assert.match(edge, /trivialActivityTurn/);
  assert.doesNotMatch(
    edge,
    /message:"Running the selected intelligence step\."/,
  );
  assert.doesNotMatch(
    edge,
    /message:"Selected a bounded fallback after an intelligence provider attempt failed\."/,
  );
});

test('Activity and Activity Logs are separate business and audit surfaces', () => {
  assert.match(activity, /ActivityHistoryView/);
  assert.match(activity, /Activity Logs/);
  assert.match(activity, /pandora-business-theatre/);
  assert.match(activity, /Technical routing stays in Activity Logs\./);
  assert.match(activity, /_theatreVisible/);
});
