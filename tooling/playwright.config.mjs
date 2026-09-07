import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./test/e2e",
  timeout: 30_000,
  retries: process.env.CI ? 1 : 0,
  use: {
    headless: true,
    trace: "retain-on-failure",
  },
  reporter: process.env.CI ? [["line"]] : [["list"]],
});
