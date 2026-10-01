import assert from "node:assert/strict";
import test from "node:test";

import {
  RpaContainmentErrorCode,
  createBoundedRpaSession,
} from "../src/rpa-bounded-executor.mjs";

const actionSet = {
  actionSetKey: "acceptance.browser_legacy",
  allowedActions: ["read_status", "download_receipt"],
  evidenceRequired: true,
  maxActionsPerSession: 2,
};

test("bounded RPA rejects undeclared actions before invoking handlers", async () => {
  let mutated = false;
  const session = createBoundedRpaSession({
    actionSet,
    handlers: {
      dangerous_click: async () => {
        mutated = true;
        return { evidence: { type: "mutation" } };
      },
    },
  });

  await assert.rejects(
    () => session.execute("dangerous_click"),
    (error) => error?.code === RpaContainmentErrorCode.actionNotAllowed,
  );
  assert.equal(mutated, false);
  assert.equal(session.attemptedActions, 0);
});

test("bounded RPA consumes a session attempt before execution and enforces the cap", async () => {
  const session = createBoundedRpaSession({
    actionSet,
    handlers: {
      read_status: async () => ({
        value: "ready",
        evidence: { type: "page_status", value: "ready" },
      }),
      download_receipt: async () => ({
        value: "receipt.txt",
        evidence: { type: "download", name: "receipt.txt" },
      }),
    },
  });

  const first = await session.execute("read_status");
  const second = await session.execute("download_receipt");
  assert.equal(first.value, "ready");
  assert.equal(second.value, "receipt.txt");
  assert.equal(session.remainingActions, 0);

  await assert.rejects(
    () => session.execute("read_status"),
    (error) => error?.code === RpaContainmentErrorCode.sessionLimitExceeded,
  );
});

test("bounded RPA fails closed when a permitted action omits evidence", async () => {
  const session = createBoundedRpaSession({
    actionSet,
    handlers: {
      read_status: async () => ({ value: "ready" }),
    },
  });

  await assert.rejects(
    () => session.execute("read_status"),
    (error) => error?.code === RpaContainmentErrorCode.evidenceRequired,
  );
  assert.equal(session.attemptedActions, 1);
});

test("bounded RPA rejects an empty allowlist contract", () => {
  assert.throws(
    () =>
      createBoundedRpaSession({
        actionSet: {
          actionSetKey: "invalid",
          allowedActions: [],
          evidenceRequired: true,
          maxActionsPerSession: 2,
        },
      }),
    (error) => error?.code === RpaContainmentErrorCode.invalidContract,
  );
});
