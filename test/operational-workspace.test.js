"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const workspaceModule = import("../supabase/functions/pandora-owner-api/operational-workspace.mjs");

test("staged import identity is deterministic and secret values are redacted", async () => {
  const { previewExternalImport } = await workspaceModule;
  const projectId = "project-1";
  const objects = [
    {
      kind: "repository",
      externalId: "owner/repo",
      name: "Repo",
      attributes: { token: "SHOULD_NEVER_BE_PERSISTED", visibility: "private" },
    },
    {
      kind: "project",
      externalId: "prj_123",
      name: "Runtime",
      attributes: { region: "iad1" },
    },
  ];

  const first = await previewExternalImport({
    projectId,
    sourceProvider: "github",
    objects,
    mappings: [],
  });
  const second = await previewExternalImport({
    projectId,
    sourceProvider: "github",
    objects: [...objects].reverse(),
    mappings: [],
  });

  assert.equal(first.fingerprint, second.fingerprint);
  assert.equal(first.executionReady, true);
  assert.equal(first.changes.creates.length, 2);
  assert.equal(first.externalMutationExecuted, false);
  assert.doesNotMatch(JSON.stringify(first), /SHOULD_NEVER_BE_PERSISTED/);
  assert.match(first.objects[0].attributesDigest, /^[0-9a-f]{64}$/);
});

test("exact external mapping becomes a noop instead of a duplicate mutation", async () => {
  const { previewExternalImport } = await workspaceModule;
  const result = await previewExternalImport({
    projectId: "project-2",
    sourceProvider: "github",
    objects: [{ kind: "repository", externalId: "owner/exact" }],
    mappings: [{
      id: "mapping-1",
      provider: "github",
      resourceType: "repository",
      externalId: "owner/exact",
      bindingState: "verified",
    }],
  });

  assert.equal(result.executionReady, true);
  assert.equal(result.conflicts.length, 0);
  assert.deepEqual(result.changes.creates, []);
  assert.deepEqual(result.changes.updates, []);
  assert.equal(result.changes.noops.length, 1);
});

test("ambiguous replacement fails closed until an exact target is chosen", async () => {
  const { previewExternalImport } = await workspaceModule;
  const result = await previewExternalImport({
    projectId: "project-3",
    sourceProvider: "vercel",
    objects: [{ kind: "project", externalId: "prj_new" }],
    mappings: [{
      id: "mapping-old",
      provider: "vercel",
      resourceType: "project",
      externalId: "prj_old",
      bindingState: "verified",
    }],
  });

  assert.equal(result.executionReady, false);
  assert.equal(result.changes.updates.length, 0);
  assert.equal(result.conflicts.length, 1);
  assert.equal(result.conflicts[0].kind, "ambiguous_mapping_change");
  assert.equal(result.conflicts[0].severity, "high");
});

test("explicit target updates are staged only for a verified matching resource", async () => {
  const { previewExternalImport } = await workspaceModule;
  const result = await previewExternalImport({
    projectId: "project-4",
    sourceProvider: "vercel",
    objects: [{
      kind: "project",
      externalId: "prj_new",
      targetRef: "mapping-old",
    }],
    mappings: [{
      id: "mapping-old",
      provider: "vercel",
      resourceType: "project",
      externalId: "prj_old",
      bindingState: "verified",
    }],
  });

  assert.equal(result.executionReady, true);
  assert.equal(result.externalMutationExecuted, false);
  assert.deepEqual(result.changes.updates, [{
    index: 0,
    mappingId: "mapping-old",
    fromExternalId: "prj_old",
    toExternalId: "prj_new",
  }]);
});

test("not-required resources stay out of the attention queue", async () => {
  const { deriveOperationalConflicts } = await workspaceModule;
  const conflicts = deriveOperationalConflicts({
    mappings: [{
      id: "optional-map",
      provider: "meta",
      resourceType: "page",
      externalId: "page_optional",
      bindingState: "not_required",
    }],
  });

  assert.deepEqual(conflicts, []);
});

test("object 360 derives provider, runtime, domain, and staged conflicts", async () => {
  const { deriveOperationalConflicts } = await workspaceModule;
  const conflicts = deriveOperationalConflicts({
    mappings: [{
      id: "repo-map",
      provider: "github",
      resourceType: "repository",
      externalId: "owner/repo",
      bindingState: "degraded",
    }, {
      id: "vercel-map",
      provider: "vercel",
      resourceType: "project",
      externalId: "prj_expected",
      bindingState: "verified",
    }],
    runtimes: [{
      id: "runtime-1",
      environment: "production",
      provider: "vercel",
      provider_project_id: "prj_drifted",
    }],
    domains: [{
      id: "domain-1",
      domain: "example.com",
      primary_domain: true,
      verified: false,
    }],
    storedConflicts: [{
      id: "stored-1",
      payload_redacted: {
        kind: "import_conflict",
        severity: "medium",
        title: "Import needs review",
        summary: "External object differs.",
        recommendation: "Review exact identity.",
      },
    }],
  });

  assert.equal(conflicts.length, 4);
  assert.equal(conflicts[0].severity, "high");
  assert.ok(conflicts.some((item) => item.kind === "resource_binding"));
  assert.ok(conflicts.some((item) => item.kind === "runtime_binding_mismatch"));
  assert.ok(conflicts.some((item) => item.kind === "domain_not_verified"));
  assert.ok(conflicts.some((item) => item.source === "staged_import"));
});


test("owner API and mobile project detail are wired to the operational workspace", () => {
  const root = path.resolve(__dirname, "..");
  const ownerApi = fs.readFileSync(
    path.join(root, "supabase/functions/pandora-owner-api/index.ts"),
    "utf8",
  );
  const models = fs.readFileSync(
    path.join(root, "apps/pandora-mobile/lib/core/models/pandora_models.dart"),
    "utf8",
  );
  const projectDetail = fs.readFileSync(
    path.join(root, "apps/pandora-mobile/lib/features/projects/project_detail_screen.dart"),
    "utf8",
  );

  assert.match(ownerApi, /loadOperationalWorkspace/);
  assert.ok(ownerApi.includes("^\\/projects\\/[^/]+\\/imports\\/preview$"));
  assert.match(ownerApi, /resolveOperationalConflict/);
  assert.match(ownerApi, /operationalAttentionCount/);
  assert.match(models, /class OperationalWorkspace/);
  assert.match(models, /operations: OperationalWorkspace\.fromJson/);
  assert.match(projectDetail, /title: 'System map'/);
  assert.match(projectDetail, /Pandora will not guess when provider truth/);
});
