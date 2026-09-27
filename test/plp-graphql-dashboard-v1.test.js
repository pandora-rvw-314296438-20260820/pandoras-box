import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migration = await readFile(
  new URL('../supabase/migrations/20260921110000_plp_graphql_dashboard_reads_v1.sql', import.meta.url),
  'utf8',
);
const api = await readFile(
  new URL('../apps/pandora-mobile/lib/core/data/plp_graphql_api.dart', import.meta.url),
  'utf8',
);
const shell = await readFile(
  new URL('../apps/pandora-mobile/lib/app/plp_enterprise_shell.dart', import.meta.url),
  'utf8',
);
const activity = await readFile(
  new URL('../apps/pandora-mobile/lib/features/enterprise/plp_activity_screen.dart', import.meta.url),
  'utf8',
);
const operations = await readFile(
  new URL('../apps/pandora-mobile/lib/features/operations/operations_room_screen.dart', import.meta.url),
  'utf8',
);
const workspaces = await readFile(
  new URL('../apps/pandora-mobile/lib/features/enterprise/enterprise_workspace_home.dart', import.meta.url),
  'utf8',
);

test('PLP GraphQL read models are authenticated, bounded, and sanitized', () => {
  assert.match(migration, /create extension if not exists pg_graphql;/);
  assert.match(
    migration,
    /revoke execute on function graphql\.resolve\(text,jsonb,text,jsonb\)[\s\S]*from public, anon;/,
  );
  for (const view of [
    'enterprise_graphql_owner_dashboards_v1',
    'plp_graphql_overview_v1',
    'plp_graphql_guests_v1',
    'plp_graphql_operations_v1',
    'plp_graphql_activity_v1',
  ]) {
    assert.match(
      migration,
      new RegExp('revoke all on public\\.' + view + ' from public, anon;'),
    );
    assert.match(migration, new RegExp('grant select on public\\.' + view));
  }

  const guestStart = migration.indexOf(
    'create or replace view public.plp_graphql_guests_v1',
  );
  const guestEnd = migration.indexOf(
    'create or replace view public.plp_graphql_operations_v1',
  );
  const guestView = migration.slice(guestStart, guestEnd);
  assert.doesNotMatch(
    guestView,
    /\bg\.email\b|\bg\.phone\b|normalized_email/,
  );
  assert.match(guestView, /m\.user_id=auth\.uid\(\)/);
});

test('mobile dashboard reads use authenticated GraphQL without service credentials', () => {
  assert.match(api, /\/graphql\/v1/);
  assert.match(api, /'apikey': _publishableKey/);
  assert.match(api, /'Authorization': 'Bearer \$accessToken'/);
  assert.doesNotMatch(api, /service[_-]?role|sb_secret_/i);
  for (const collection of [
    'plp_graphql_overview_v1Collection',
    'plp_graphql_guests_v1Collection',
    'plp_graphql_operations_v1Collection',
    'plp_graphql_activity_v1Collection',
    'enterprise_graphql_owner_dashboards_v1Collection',
  ]) {
    assert.match(api, new RegExp(collection));
  }
});

test('Overview, Guests, Operations, Activity, and owner dashboards are wired', () => {
  assert.match(shell, /loadDashboardBundle\(\)/);
  assert.match(shell, /mergePlpGraphqlDashboardIntoBootstrap/);
  assert.match(shell, /graphqlOperationsContext/);
  assert.match(operations, /resortBusinessContext/);
  assert.match(activity, /PlpGraphqlApi\(\)\.loadBusinessActivity\(\)/);
  assert.match(
    activity,
    /Supabase\.instance\.client\.rpc\([\s\S]*'plp_pandora_activity_logs_v2'/,
  );
  assert.doesNotMatch(activity, /plp_recent_business_activity_v1/);
  assert.match(workspaces, /loadOwnerDashboards\(\)/);
  assert.match(workspaces, /workspace-dashboard-/);
});
