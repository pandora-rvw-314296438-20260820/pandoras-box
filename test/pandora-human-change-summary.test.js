
"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const verification = require("../packages/pandora-verification/src");

const U = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const D = (ch) => ch.repeat(64);

function version(overrides = {}) {
  return {
    id: U(1),
    organization_id: U(10),
    project_id: U(11),
    parent_version_id: null,
    artifact_digest_sha256: D("a"),
    model_claim: "Bookings now work and revenue will increase.",
    ...overrides,
  };
}

function file(path, sha, byteSize = 100, extra = {}) {
  return {
    file: path,
    sha256: D(sha),
    byteSize,
    dataBase64: "PHNlY3JldC1yYXctY29udGVudD4=",
    rawDiff: "@@ -1 +1 @@",
    ...extra,
  };
}

test("human change summary uses exact child lineage and canonical file hashes", () => {
  const current = version();
  const candidate = version({
    id: U(2),
    parent_version_id: current.id,
    artifact_digest_sha256: D("b"),
  });

  const summary = verification.createHumanChangeSummary({
    currentVersion: current,
    candidateVersion: candidate,
    currentFiles: [
      file("index.html", "1", 1200),
      file("assets/logo.png", "2", 400),
      file("src/components/Nav.js", "3", 700),
    ],
    candidateFiles: [
      file("index.html", "4", 1250),
      file("src/components/Nav.js", "3", 700),
      file("src/components/Hero.js", "5", 900),
    ],
  });

  assert.equal(summary.schema, "pandora.human-change-summary/1");
  assert.equal(summary.current_version_id, current.id);
  assert.equal(summary.candidate_version_id, candidate.id);
  assert.equal(summary.material_change_count, 3);
  assert.equal(summary.added_file_count, 1);
  assert.equal(summary.modified_file_count, 1);
  assert.equal(summary.removed_file_count, 1);
  assert.equal(
    summary.headline,
    "Updated interface components, main experience, and visual assets.",
  );
  assert.deepEqual(
    summary.exact_change_refs.map(({ path, status }) => ({ path, status })),
    [
      { path: "assets/logo.png", status: "REMOVED" },
      { path: "index.html", status: "MODIFIED" },
      { path: "src/components/Hero.js", status: "ADDED" },
    ],
  );

  const serialized = JSON.stringify(summary);
  assert.equal(serialized.includes("Bookings now work"), false);
  assert.equal(serialized.includes("revenue"), false);
  assert.equal(serialized.includes("PHNlY3JldC1yYXctY29udGVudD4="), false);
  assert.equal(serialized.includes("@@ -1 +1 @@"), false);
});

test("identical manifests produce an explicit no-material-change result", () => {
  const current = version();
  const candidate = version({
    id: U(2),
    parent_version_id: current.id,
    artifact_digest_sha256: D("b"),
  });
  const manifest = [file("index.html", "1", 1200), file("styles.css", "2", 400)];
  const summary = verification.createHumanChangeSummary({
    currentVersion: current,
    candidateVersion: candidate,
    currentFiles: manifest,
    candidateFiles: manifest,
  });

  assert.equal(summary.material_change_count, 0);
  assert.equal(summary.headline, "No material file changes detected.");
  assert.deepEqual(summary.changed_surfaces, []);
  assert.deepEqual(summary.exact_change_refs, []);
});

test("change summary fails closed on cross-project or non-child versions", () => {
  const current = version();

  assert.throws(
    () =>
      verification.createHumanChangeSummary({
        currentVersion: current,
        candidateVersion: version({
          id: U(2),
          parent_version_id: U(99),
          artifact_digest_sha256: D("b"),
        }),
        currentFiles: [],
        candidateFiles: [],
      }),
    /exact child/,
  );

  assert.throws(
    () =>
      verification.createHumanChangeSummary({
        currentVersion: current,
        candidateVersion: version({
          id: U(2),
          project_id: U(12),
          parent_version_id: current.id,
          artifact_digest_sha256: D("b"),
        }),
        currentFiles: [],
        candidateFiles: [],
      }),
    /same project/,
  );
});

test("change summary rejects unsafe or ambiguous manifest identity", () => {
  const current = version();
  const candidate = version({
    id: U(2),
    parent_version_id: current.id,
    artifact_digest_sha256: D("b"),
  });

  assert.throws(
    () =>
      verification.createHumanChangeSummary({
        currentVersion: current,
        candidateVersion: candidate,
        currentFiles: [file("../secret.txt", "1")],
        candidateFiles: [],
      }),
    /file path is invalid/,
  );

  assert.throws(
    () =>
      verification.createHumanChangeSummary({
        currentVersion: current,
        candidateVersion: candidate,
        currentFiles: [file("index.html", "1"), file("index.html", "2")],
        candidateFiles: [],
      }),
    /duplicate current manifest path/,
  );

  assert.throws(
    () =>
      verification.createHumanChangeSummary({
        currentVersion: current,
        candidateVersion: candidate,
        currentFiles: [{ file: "index.html", sha256: "bad", byteSize: 10 }],
        candidateFiles: [],
      }),
    /file sha256 is invalid/,
  );
});

test("customer-safe surfaces classify technical changes without inventing outcomes", () => {
  const current = version();
  const candidate = version({
    id: U(2),
    parent_version_id: current.id,
    artifact_digest_sha256: D("b"),
  });
  const summary = verification.createHumanChangeSummary({
    currentVersion: current,
    candidateVersion: candidate,
    currentFiles: [],
    candidateFiles: [
      file("src/api/booking.ts", "1"),
      file("content/home.json", "2"),
      file("package.json", "3"),
      file("src/theme.css", "4"),
    ],
  });

  assert.deepEqual(
    summary.changed_surfaces.map((surface) => surface.surface),
    ["app_logic", "content_and_data", "project_configuration", "visual_styling"],
  );
  assert.equal(summary.headline.includes("booking flow works"), false);
  assert.equal(summary.headline.includes("revenue"), false);
});
