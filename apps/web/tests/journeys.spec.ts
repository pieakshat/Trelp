import { expect, test } from "@playwright/test";

test("live devnet state drives dashboard, activity, and interactive transparency", async ({
  page,
}) => {
  await page.goto("/transparency");
  await expect(
    page.getByRole("heading", { name: "Every number has an address." }),
  ).toBeVisible();
  await expect(page.locator(".transparencyHeroValue strong")).toContainText(
    "1M USDC",
  );
  await expect(page.locator(".transparencyRangeStats")).toContainText("1M");
  await expect(
    page.getByRole("img", { name: /range from tick -120 to tick 120/ }),
  ).toBeVisible();
  const rangeBoundary = page.locator(".rangeBoundary");
  const fitBoundary = await rangeBoundary.getAttribute("d");
  await page.getByRole("button", { name: "Detail" }).click();
  await expect(page.getByRole("button", { name: "Detail" })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await expect(
    page.getByRole("img", {
      name: "On-chain tranche capital history by block",
    }),
  ).toBeVisible();
  await page
    .getByRole("toolbar", { name: "Capital chart series" })
    .getByRole("button", { name: "Senior", exact: true })
    .click();
  await expect(
    page
      .getByRole("toolbar", { name: "Capital chart series" })
      .getByRole("button", { name: "Senior", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(rangeBoundary).not.toHaveAttribute("d", fitBoundary ?? "");
  await page.getByRole("button", { name: /^Junior:/ }).click();
  await expect(
    page
      .locator(".distributionGaugeLegend")
      .getByRole("button", { name: /^Junior / }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator(".distributionGaugeValue")).toHaveText(
    /^\d+(\.\d+)?%$/,
  );

  await page.goto("/dashboard");
  await expect(
    page.getByRole("heading", { name: "Your vault, at a glance." }),
  ).toBeVisible();
  await page.goto("/activity");
  const activityRows = page.getByRole("table").locator("tbody tr");
  await expect(activityRows.first()).toBeVisible();
  expect(await activityRows.count()).toBeGreaterThanOrEqual(2);
  await expect(page.getByRole("table")).toContainText("700K USDC");
  await expect(page.getByRole("table")).toContainText("300K USDC");
});

test("curator page exposes only gated contract operations", async ({
  page,
}) => {
  await page.goto("/create");
  await expect(
    page.getByRole("heading", { name: "Curator operations" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Rebalance range" }),
  ).toBeDisabled();
  await expect(
    page.getByRole("button", { name: "Call buffer" }),
  ).toBeDisabled();
  await expect(page.locator("main")).not.toContainText(/local draft/i);
});

test("resources contain vault documentation instead of brand downloads", async ({
  page,
}) => {
  await page.goto("/resources");
  await expect(
    page.getByRole("heading", { name: "Vault documentation" }),
  ).toBeVisible();
  await expect(page.locator("main")).not.toContainText("Trelp asset kit");
  await expect(page.locator("main")).not.toContainText("SVG");
});

test("mobile navigation, devnet wallet, resources, and unknown routes remain usable", async ({
  page,
  request,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/dashboard");
  await expect(page.locator(".appTopbar")).toHaveCSS(
    "background-color",
    "rgb(158, 28, 41)",
  );
  await expect(
    page.getByRole("heading", { name: "Capital deployment" }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Protocol lifecycle" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Manage wallet connection" }).click();
  await expect(page.getByText("Anvil test wallet")).toBeVisible();
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Open navigation" }).click();
  await page.getByRole("link", { name: "Resources", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Resources", exact: true }),
  ).toBeVisible();
  for (const path of [
    "/documents/trelp-vault-factsheet.pdf",
    "/brand/trelp-mark.svg",
  ]) {
    const response = await request.get(path);
    expect(response.ok()).toBe(true);
  }
  await page.goto("/vaults/missing");
  await expect(
    page.getByRole("heading", { name: "Vault not configured" }),
  ).toBeVisible();
});

test("mobile portfolio does not scroll the whole document horizontally", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/portfolio");
  await expect(
    page.getByRole("heading", { name: "Portfolio", exact: true }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    ),
  ).toBe(0);
});

test("dashboard uses compact values and a proportional capital strip", async ({
  page,
}) => {
  await page.goto("/dashboard");
  await expect(
    page.getByRole("heading", { name: "Your vault, at a glance." }),
  ).toBeVisible();
  await expect(page.locator(".dashboardMetrics")).toContainText("1M USDC");
  await expect(
    page.locator('.dashboardMetrics .tokenAmount img[src*="usdc.svg"]'),
  ).toHaveCount(3);
  await expect(page.locator("main")).not.toContainText("1,000,000");
  await expect(
    page.getByRole("link", { name: "Dashboard", exact: true }),
  ).toHaveCSS("background-color", "rgba(255, 255, 255, 0.1)");
  const segments = page.locator(".dashboardHeroStack > span");
  const senior = await segments.nth(0).boundingBox();
  const junior = await segments.nth(1).boundingBox();
  expect(senior).not.toBeNull();
  expect(junior).not.toBeNull();
  if (senior && junior)
    expect(senior.width / junior.width).toBeCloseTo(7 / 3, 1);
  await page.setViewportSize({ width: 390, height: 844 });
  const juniorLabel = await segments.nth(1).locator("strong").boundingBox();
  const juniorPercent = await segments.nth(1).locator("b").boundingBox();
  expect(juniorLabel).not.toBeNull();
  expect(juniorPercent).not.toBeNull();
  if (juniorLabel && juniorPercent)
    expect(juniorLabel.y + juniorLabel.height).toBeLessThanOrEqual(
      juniorPercent.y,
    );
});

test("workspace branding uses only the square Trelp mark", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("link", { name: "Trelp home" })).toHaveCount(2);
  await page.goto("/dashboard");
  const logo = page.getByRole("link", { name: "Trelp home" });
  await expect(logo).toHaveText("");
  const box = await logo.boundingBox();
  expect(box).not.toBeNull();
  if (box) expect(box.width / box.height).toBeLessThan(1.2);
});

test("execution health stays compact and identifies live contract data", async ({
  page,
}) => {
  await page.goto("/dashboard");
  const health = page
    .locator("section")
    .filter({ hasText: "Execution health" });
  await expect(health.getByText("Live contract")).toBeVisible();
  const box = await health.boundingBox();
  expect(box).not.toBeNull();
  if (box) expect(box.height).toBeLessThan(360);
});

test("vault route is neutral, compact, and keeps the live 70/30 split", async ({
  page,
}) => {
  await page.goto("/vaults/eth-usdc");
  await expect(page.getByRole("heading", { name: "The vault." })).toBeVisible();
  await expect(page.locator("main")).not.toContainText(/devnet/i);
  await expect(page.locator(".detailStats")).toContainText("1M USDC");
  const segments = page.locator(".capitalStackGraph > span");
  const senior = await segments.nth(0).boundingBox();
  const junior = await segments.nth(1).boundingBox();
  expect(senior).not.toBeNull();
  expect(junior).not.toBeNull();
  if (senior && junior)
    expect(senior.width / junior.width).toBeCloseTo(7 / 3, 1);
  await page.setViewportSize({ width: 390, height: 844 });
  const juniorLabel = await segments.nth(1).locator("strong").boundingBox();
  const juniorPercent = await segments.nth(1).locator("b").boundingBox();
  expect(juniorLabel).not.toBeNull();
  expect(juniorPercent).not.toBeNull();
  if (juniorLabel && juniorPercent)
    expect(juniorLabel.y + juniorLabel.height).toBeLessThanOrEqual(
      juniorPercent.y,
    );
});

test("deposit amount uses one focus ring around the complete control", async ({
  page,
}) => {
  await page.goto("/vaults/eth-usdc");
  const amount = page.getByLabel("Deposit amount");
  await amount.click();
  await expect(amount).toHaveCSS("outline-style", "none");
  await expect(page.locator(".depositInput")).not.toHaveCSS(
    "box-shadow",
    "none",
  );
});

test("deposit amount rejects non-numeric text", async ({ page }) => {
  await page.goto("/vaults/eth-usdc");
  const amount = page.getByLabel("Deposit amount");
  await amount.fill("abc");
  await expect(amount).toHaveValue("");
  await amount.fill("12.5");
  await expect(amount).toHaveValue("12.5");
});

test("deposit card owns the Senior and Junior selector", async ({ page }) => {
  await page.goto("/vaults/eth-usdc");
  const deposit = page.locator(".depositPanel");
  const selector = deposit.getByRole("group", { name: "Select tranche" });
  await expect(selector).toBeVisible();
  await selector.getByRole("button", { name: "Junior · first loss" }).click();
  await expect(deposit).toContainText("Your junior claims");
  await expect(
    deposit.getByRole("button", { name: "Deposit into junior" }),
  ).toBeVisible();
});

test("app chrome and primary actions share one burgundy", async ({ page }) => {
  await page.goto("/vaults/eth-usdc");
  const colors = await page
    .locator(".appSidebar, .appTopbar, .vaultHero, .depositPanel .uiButton")
    .evaluateAll((elements) =>
      elements.map((element) => getComputedStyle(element).backgroundColor),
    );
  expect(new Set(colors)).toEqual(new Set(["rgb(158, 28, 41)"]));
});

test("deposit stays disabled until the risk notice is accepted", async ({
  page,
}) => {
  await page.goto("/vaults/eth-usdc");
  await page.getByLabel("Deposit amount").fill("1");
  const deposit = page.getByRole("button", { name: "Deposit into senior" });
  await expect(deposit).toBeDisabled();
  await page.getByLabel(/I understand that both tranches/).check();
  await expect(deposit).toBeEnabled();
});

test("sidebar destinations use readable type and subtle separators", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/dashboard");
  await page.getByRole("button", { name: "Open navigation" }).click();
  const links = page.locator(".appSidebar nav a");
  const styles = await links.evaluateAll((elements) =>
    elements.map((element) => {
      const style = getComputedStyle(element);
      return {
        border: style.borderBottomStyle,
        fontWeight: Number(style.fontWeight),
      };
    }),
  );
  expect(styles.every(({ border }) => border === "solid")).toBe(true);
  expect(styles.every(({ fontWeight }) => fontWeight >= 600)).toBe(true);
  await expect(page.locator(".appSidebar")).toHaveCSS(
    "border-right-style",
    "solid",
  );
});

test("workspace pages show the live market identity and wallet context", async ({
  page,
}) => {
  for (const path of ["/portfolio", "/activity", "/transparency", "/create"]) {
    await page.goto(path);
    await expect(
      page.locator('main img[src*="ethereum.svg"]').first(),
    ).toBeVisible();
    await expect(
      page.locator('main img[src*="usdc.svg"]').first(),
    ).toBeVisible();
  }
  await page.goto("/activity");
  await expect(page.locator(".dataTable .trancheMark").first()).toBeVisible();
  expect(
    await page.locator(".dataTable .trancheMark").count(),
  ).toBeGreaterThanOrEqual(2);
  await page.goto("/portfolio");
  await expect(page.locator("main")).toContainText("0x7099…79C8");
  await page.goto("/settings");
  await expect(page.locator("main")).toContainText("0x7099…79C8");
});

test("portfolio and activity values carry their token identity", async ({
  page,
}) => {
  await page.goto("/portfolio");
  await expect(
    page.locator(".metricRibbon .tokenAmount img").first(),
  ).toBeVisible();
  await expect(
    page.locator(".dataTable .tokenAmount img").first(),
  ).toBeVisible();
  await page.goto("/activity");
  await expect(
    page.locator(".dataTable .tokenAmount img").first(),
  ).toBeVisible();
});

test("workspace token values use compact notation from one thousand", async ({
  page,
}) => {
  await page.goto("/portfolio");
  await expect(page.locator("main")).toContainText("5K USDC");
  await expect(page.locator("main")).not.toContainText("5,000.06");
});

test("returns stay explicitly pending before contract terms exist", async ({
  page,
}) => {
  await page.goto("/transparency");
  await expect(
    page.getByRole("columnheader", { name: "Return" }),
  ).toBeVisible();
  await expect(page.locator(".transparencyTrancheTable")).toContainText(
    "Pending activation",
  );
});

test("a confirmed deposit shows its on-chain receipt", async ({ page }) => {
  await page.goto("/vaults/eth-usdc");
  await page.getByLabel("Deposit amount").fill("0.01");
  await page.getByLabel(/I understand that both tranches/).check();
  await page.getByRole("button", { name: "Deposit into senior" }).click();
  const receipt = page.locator(".transactionReceipt");
  await expect(receipt).toContainText("Deposit confirmed on-chain");
  await expect(receipt).toContainText("Block");
  await expect(receipt).toContainText("Gas used");
  await expect(receipt.locator("code")).toHaveText(
    /^0x[0-9a-f]{4}…[0-9a-f]{4}$/i,
  );
});
