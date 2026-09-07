import { test, expect } from "@playwright/test";

test("Pandora browser verification toolchain launches Chromium", async ({ page }) => {
  await page.setContent('<main data-pandora-toolchain="ready">Pandora toolchain ready</main>');
  await expect(page.locator('[data-pandora-toolchain="ready"]')).toHaveText("Pandora toolchain ready");
});
