"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const RECOVERED = Object.freeze({
  ownerId: "team_3yw1CN59ce4pj5SwyQGCAqN3",
  projectId: "prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk",
  owner: "mbanatao",
});

function productionClaims(overrides = {}) {
  return {
    environment: "production",
    project: "mcpmaster",
    owner_id: RECOVERED.ownerId,
    project_id: RECOVERED.projectId,
    owner: RECOVERED.owner,
    sub: "owner:mbanatao:project:mcpmaster:environment:production",
    ...overrides,
  };
}

test("projectos-control accepts only the recovered production Vercel identity", async () => {
  const { assertProductionVercelClaims } = await import(
    "../supabase/functions/projectos-control/identity-policy.mjs"
  );

  assert.doesNotThrow(() => assertProductionVercelClaims(
    productionClaims(),
    ["https://vercel.com/mbanatao"],
  ));

  assert.throws(() => assertProductionVercelClaims(
    productionClaims({
      owner_id: "team_IcdJUnzLi5wUN1GD8ALHyjF7",
      owner: "mbanatao-dc676069",
      sub: "owner:mbanatao-dc676069:project:mcpmaster:environment:production",
    }),
    ["https://vercel.com/mbanatao-dc676069"],
  ));
});

test("projectos-control rejects non-production or mismatched Vercel claims", async () => {
  const { assertProductionVercelClaims } = await import(
    "../supabase/functions/projectos-control/identity-policy.mjs"
  );

  assert.throws(() => assertProductionVercelClaims(
    productionClaims({ environment: "preview" }),
    ["https://vercel.com/mbanatao"],
  ));
  assert.throws(() => assertProductionVercelClaims(
    productionClaims({ project_id: "prj_wrong" }),
    ["https://vercel.com/mbanatao"],
  ));
  assert.throws(() => assertProductionVercelClaims(
    productionClaims(),
    ["https://vercel.com/not-mbanatao"],
  ));
});
