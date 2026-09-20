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

test('customer Activity Theatre shows business work instead of model routing', () => {
  assert.match(edge, /pandora-business-theatre/);
  assert.match(
    edge,
    /Checking bookings, arrivals, departures, and room availability\./,
  );
  assert.doesNotMatch(
    edge,
    /message:"Running the selected intelligence step\."/,
  );
  assert.doesNotMatch(
    edge,
    /message:"Selected a bounded fallback after an intelligence provider attempt failed\."/,
  );
});

test('Activity and Activity Logs are separate customer and audit surfaces', () => {
  assert.match(activity, /ActivityHistoryView/);
  assert.match(activity, /Activity Logs/);
  assert.match(activity, /pandora-business-theatre/);
  assert.match(activity, /Technical routing stays in Activity Logs\./);
  assert.match(activity, /_theatreVisible/);
});
