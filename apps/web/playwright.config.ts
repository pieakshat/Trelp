import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests",
  testMatch: "journeys.spec.ts",
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:3000",
    headless: true,
    channel: "chromium",
    viewport: { width: 1440, height: 960 },
    trace: "retain-on-failure",
  },
  webServer: process.env.PLAYWRIGHT_BASE_URL
    ? []
    : {
        command: "corepack pnpm dev --port 3000",
        url: "http://localhost:3000",
        reuseExistingServer: true,
        timeout: 60000,
      },
});
