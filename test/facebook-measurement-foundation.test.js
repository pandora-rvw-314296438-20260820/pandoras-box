"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const sql = fs.readFileSync(
  path.join(root, "supabase/migrations/20260929070000_pandora_facebook_measurement_foundation_v1.sql"),
  "utf8",
);
const http = fs.readFileSync(path.join(root, "src/pandora-tracking-http.js"), "utf8");

test("measurement release does not seed privacy approval or spend authority", () => {
  assert.match(sql, /create table if not exists public\.pandora_growth_privacy_authorizations/);
  assert.doesNotMatch(sql, /insert into public\.pandora_growth_privacy_authorizations/i);
  assert.match(sql, /PANDORA_GROWTH_OUTCOME_PRIVACY_HOLD/);
  assert.match(sql, /PANDORA_META_CONVERSION_PRIVACY_HOLD/);
  assert.match(sql, /provider_matching/);
  assert.match(sql, /server_outcomes/);
  assert.doesNotMatch(sql, /create campaign|daily_budget|lifetime_budget|budget_amount/i);
});

test("Meta asset binding is provider-read verified before local IDs are written", () => {
  assert.match(sql, /pandora_meta_verify_measurement_binding_v1/);
  assert.match(sql, /account_id,name,currency,account_status,timezone_name/);
  assert.match(sql, /adspixels\?fields=id,name/);
  assert.match(sql, /campaign_id,name,status/);
  assert.match(sql, /adset_id,name,status/);
  assert.match(sql, /PANDORA_META_MEASUREMENT_REBIND_DENIED/);
  assert.match(sql, /set provider_campaign_id=p_meta_campaign_id/);
  assert.ok(
    sql.indexOf("PANDORA_META_MEASUREMENT_AD_MISMATCH")
      < sql.indexOf("set provider_campaign_id=p_meta_campaign_id"),
  );
});

test("authoritative outcome money stays in integer minor units", () => {
  assert.match(sql, /amount_minor bigint/);
  assert.match(sql, /moneyProjection','minor_units_only/);
  assert.match(sql, /v_amount:=case when p_event \? 'money'/);
  assert.match(sql, /v_event_type:=case p_event->>'event_name'/);
  assert.match(sql, /when 'payment_settled' then 'sale'/);
  assert.match(sql, /when 'refund_settled' then 'refund'/);
  assert.match(sql, /v_event_type,p_event->>'event_name','server'/);
  assert.match(sql, /v_tenant,v_campaign_id,v_click_id,v_event_type/);
  assert.match(sql, /p_event->>'event_id',null,null/);
});

test("cost import makes missing provider data explicit instead of zero", () => {
  assert.match(sql, /pandora_meta_import_campaign_costs_v1/);
  assert.match(sql, /omittedUnknownRows/);
  assert.match(sql, /'missingIsZero',false/);
  assert.match(sql, /on conflict\(tenant_id,provider,external_record_id\) do update/);
});

test("conversion delivery requires privacy, match keys, stable event ID, and bounded retries", () => {
  assert.match(sql, /coalesce\(\(e\.consent->>'marketing'\)::boolean,false\) is true/);
  assert.match(sql, /e\.is_test is false/);
  assert.match(sql, /PANDORA_META_CONVERSION_MATCH_REQUIRED/);
  assert.match(sql, /'event_id',v_outbox\.event_id/);
  assert.match(sql, /attempt_count between 0 and 5/);
  assert.match(sql, /when v_attempt>=5 then 'dead_letter'/);
  assert.match(sql, /meta_event_name in \('Lead','Schedule','Purchase'\)/);
});

test("growth API key scope is not silently added to existing keys", () => {
  assert.match(sql, /pandora_tracking_issue_growth_api_key_v1/);
  assert.match(sql, /array\['outcome:write','conversion:write','cost:write','report:read'\]/);
  assert.match(sql, /PANDORA_GROWTH_KEY_PRIVACY_HOLD/);
});

test("tracking HTTP outcome route uses trusted scope and explicit privacy header", () => {
  assert.match(http, /validateOutcomeEvent\(req\.body, scope\)/);
  assert.match(http, /authenticate\(req, "outcome:write"\)/);
  assert.match(http, /x-pandora-privacy-policy/);
  assert.match(http, /requireGrowthPrivacy\(scope, policyVersion, "server_outcomes"\)/);
  assert.match(http, /rpc\/pandora_ingest_growth_outcome_v1/);
});

test("controlled CAPI follow-up fences test traffic to exact non-business campaign", () => {
  const controlled = fs.readFileSync(
    path.join(root, "supabase/migrations/20260929121500_facebook_controlled_capi_acceptance_v1.sql"),
    "utf8",
  );
  assert.match(controlled, /c\.metadata->>'purpose'='controlled-test'/);
  assert.match(controlled, /c\.metadata->'business_kpi' is not distinct from 'false'::jsonb/);
  assert.match(controlled, /c\.metadata->'delivery_authorized' is not distinct from 'false'::jsonb/);
  assert.match(controlled, /b\.tracking_campaign_id=v_event\.campaign_id/);
  assert.match(controlled, /where c\.metadata->'business_kpi' is distinct from 'false'::jsonb/);
  assert.match(controlled, /PANDORA_META_CONVERSION_PRIVACY_HOLD/);
  assert.doesNotMatch(controlled, /daily_budget|lifetime_budget|campaigns.*POST/i);
});
