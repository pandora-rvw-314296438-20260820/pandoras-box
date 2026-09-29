"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const test=require("node:test");
const sql=fs.readFileSync("supabase/migrations/20260929134500_facebook_g2_audit_acceptance_v1.sql","utf8");

test("G2 audit is read-only and service-role only",()=>{
  assert.match(sql,/pandora_facebook_g2_audit_v1/);
  assert.match(sql,/PANDORA_G2_AUDIT_SERVICE_ROLE_REQUIRED/);
  assert.match(sql,/revoke all on function/);
  assert.doesNotMatch(sql,/insert into|update\s+public\.|delete from|daily_budget|lifetime_budget/i);
});

test("G2 audit makes required edge cases explicit",()=>{
  for(const token of [
    "lateReceiptCount","refundCoverage","consentWithdrawal","providerOutboxLeakCount",
    "mixed_currency_requires_separate_reporting","timezone","missingIsZero","discrepancyFlags"
  ]) assert.ok(sql.includes(token),token);
  assert.match(sql,/received_at>occurred_at\+interval '15 minutes'/);
  assert.match(sql,/event_name='refund_settled'/);
  assert.match(sql,/consent->>'marketing'/);
  assert.match(sql,/crossCurrencyAggregationAllowed',false/);
});

test("synthetic traffic cannot silently become a business KPI or winner claim",()=>{
  assert.match(sql,/businessKpiRows/);
  assert.match(sql,/excludedFromBusinessKpis/);
  assert.match(sql,/causalWinnerClaimed',false/);
  assert.match(sql,/roasWinnerClaimed',false/);
  assert.match(sql,/provider_cost_data_missing_or_not_delivered/);
});
