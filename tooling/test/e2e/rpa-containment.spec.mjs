import assert from "node:assert/strict";

import { expect, test } from "@playwright/test";

import {
  RpaContainmentErrorCode,
  createBoundedRpaSession,
} from "../../../packages/pandora-integration/src/rpa-bounded-executor.mjs";

const actionSet = {
  actionSetKey: "acceptance.browser_legacy",
  allowedActions: ["read_status", "download_receipt"],
  evidenceRequired: true,
  maxActionsPerSession: 2,
};

test("Pandora contains a real legacy-browser RPA session to its declared actions", async ({
  page,
}) => {
  await page.setContent(`
    <main>
      <output id="status">ready</output>
      <output id="mutations">0</output>
      <a
        id="receipt"
        download="pandora-rpa-receipt.txt"
        href="data:text/plain,pandora-rpa-receipt"
      >Download receipt</a>
      <button
        id="danger"
        type="button"
        onclick="document.querySelector('#mutations').textContent = '1'"
      >Dangerous mutation</button>
    </main>
  `);

  const session = createBoundedRpaSession({
    actionSet,
    handlers: {
      read_status: async () => {
        const value = await page.locator("#status").innerText();
        return {
          value,
          evidence: { type: "browser_readback", value },
        };
      },
      download_receipt: async () => {
        const downloadPromise = page.waitForEvent("download");
        await page.locator("#receipt").click();
        const download = await downloadPromise;
        const name = download.suggestedFilename();
        return {
          value: name,
          evidence: { type: "browser_download", name },
        };
      },
      dangerous_click: async () => {
        await page.locator("#danger").click();
        return { evidence: { type: "browser_mutation" } };
      },
    },
  });

  const status = await session.execute("read_status");
  const receipt = await session.execute("download_receipt");

  expect(status.value).toBe("ready");
  expect(receipt.value).toBe("pandora-rpa-receipt.txt");
  expect(session.remainingActions).toBe(0);

  await assert.rejects(
    () => session.execute("read_status"),
    (error) => error?.code === RpaContainmentErrorCode.sessionLimitExceeded,
  );

  const denied = createBoundedRpaSession({
    actionSet,
    handlers: {
      dangerous_click: async () => {
        await page.locator("#danger").click();
        return { evidence: { type: "browser_mutation" } };
      },
    },
  });
  await assert.rejects(
    () => denied.execute("dangerous_click"),
    (error) => error?.code === RpaContainmentErrorCode.actionNotAllowed,
  );

  await expect(page.locator("#mutations")).toHaveText("0");
});
