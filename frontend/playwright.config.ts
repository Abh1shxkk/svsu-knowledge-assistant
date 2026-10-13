import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end tests in a real browser. Needs the backend (port 8000) and frontend (port 3000) running,
 * and an administrator login in E2E_ADMIN_ID / E2E_ADMIN_PASS. Tests run one at a time because they
 * share one database; every account and document they create is removed afterwards.
 */
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  timeout: 120_000,
  expect: { timeout: 30_000 },
  reporter: [["list"]],
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3000",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } }],
});
