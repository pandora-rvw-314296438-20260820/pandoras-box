const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const intelligence = fs.readFileSync(
  "supabase/functions/pandora-intelligence-chat/index.ts",
  "utf8",
);
const drain = fs.readFileSync("api/plp-learning-drain.ts", "utf8");
const outboxMigration = fs.readFileSync(
  "supabase/migrations/20260919091000_plp_verified_learning_outbox_v1.sql",
  "utf8",
);
const outboxEdge = fs.readFileSync(
  "supabase/functions/pandora-plp-learning-outbox/index.ts",
  "utf8",
);
const vercel = JSON.parse(fs.readFileSync("vercel.json", "utf8"));
const scheduler = fs.readFileSync(
  "supabase/migrations/20260919130000_plp_learning_drain_scheduler_v1.sql",
  "utf8",
);

test("PLP only queues learning from verified execution paths", () => {
  assert.match(intelligence, /queuePlpVerifiedLearning/);
  assert.match(
    intelligence,
    /pandora-user-admin:\$\{directThreadId\}:verified.*queuePlpVerifiedLearning/s,
  );
  assert.match(
    intelligence,
    /dispatchReadback\.verified===true\?await queuePlpVerifiedLearning/,
  );
  assert.match(intelligence, /contractVersion:"pandora-continuous-execution-v2"/);
  assert.match(intelligence, /activityProjection:\{state:"result"/);
  assert.match(intelligence, /learning_kind:"outcome"/);
  assert.match(intelligence, /state:"pending"/);
});

test("model memory candidates are not treated as execution verification", () => {
  assert.match(intelligence, /memoryCandidates:v\.memoryCandidates/);
  const queueCalls = intelligence.match(/queuePlpVerifiedLearning\(/g) || [];
  assert.equal(queueCalls.length, 3);
  assert.doesNotMatch(
    intelligence,
    /memoryCandidates[^\n]{0,500}queuePlpVerifiedLearning/,
  );
});

test("outbox is service-role only and bounded", () => {
  assert.match(outboxMigration, /enable row level security/i);
  assert.match(
    outboxMigration,
    /revoke all on table public\.pandora_verified_learning_outbox from anon, authenticated/i,
  );
  assert.match(outboxMigration, /for update skip locked/i);
  assert.match(outboxMigration, /attempt_count < 5/i);
  assert.match(outboxMigration, /interval '5 minutes'/i);
});

test("outbox ingress accepts only exact Enterprise production OIDC", () => {
  assert.match(outboxEdge, /https:\/\/oidc\.vercel\.com\/mbanatao/);
  assert.match(outboxEdge, /https:\/\/vercel\.com\/mbanatao/);
  assert.match(
    outboxEdge,
    /owner:mbanatao:project:enterprise:environment:production/,
  );
  assert.match(outboxEdge, /jwtVerify/);
});

test("Vercel drain uses runtime workload OIDC and verified-learning gateway", () => {
  assert.match(drain, /getVercelOidcToken/);
  assert.doesNotMatch(drain, /process\.env\.VERCEL_OIDC_TOKEN/);
  assert.match(drain, /process\.env\.CRON_SECRET/);
  assert.match(drain, /memory_verified_learning_propose/);
  assert.match(drain, /x-pandora-workload-oidc/);
  assert.match(
    drain,
    /ivmvufhcsezyhczzondn\.supabase\.co\/functions\/v1\/pandora-machine-gateway/,
  );
});

test("Supabase schedules the bounded learning drain without Vercel Cron plan coupling", () => {
  assert.equal(vercel.functions["api/plp-learning-drain.ts"].maxDuration, 55);
  assert.equal(Array.isArray(vercel.crons) ? vercel.crons.length : 0, 0);
  assert.match(scheduler, /cron\.schedule/);
  assert.match(scheduler, /\* \* \* \* \*/);
  assert.match(scheduler, /plp_enterprise_cron_secret/);
  assert.match(scheduler, /enterprise-omega-five\.vercel\.app\/api\/plp-learning-drain/);
});
