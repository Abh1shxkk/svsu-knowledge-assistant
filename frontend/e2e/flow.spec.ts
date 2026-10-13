import { expect, test, type Page, type APIRequestContext } from "@playwright/test";

/**
 * The main journey across roles: an Uploader submits, an Administrator reviews and publishes,
 * a Viewer reads it. Accounts and documents are created through the API and removed afterwards.
 */
const API = process.env.E2E_API_URL ?? "http://127.0.0.1:8000";
const ADMIN = { id: process.env.E2E_ADMIN_ID ?? "", pass: process.env.E2E_ADMIN_PASS ?? "" };
const stamp = Date.now().toString(36);
const UPLOADER = { id: `e2e-up-${stamp}`, pass: "E2e-Password-1" };
const VIEWER = { id: `e2e-view-${stamp}`, pass: "E2e-Password-1" };
const TITLE = `E2E circular ${stamp}`;

let token = "";
const auth = () => ({ Authorization: `Bearer ${token}` });

async function api(request: APIRequestContext, method: "post" | "delete" | "get", path: string, data?: object) {
  const res = await request[method](API + path, { headers: auth(), data });
  expect(res.ok(), `${method} ${path}: ${await res.text()}`).toBeTruthy();
  return res.json();
}

async function signIn(page: Page, who: { id: string; pass: string }) {
  await page.context().clearCookies();
  await page.goto("/login");
  await page.evaluate(() => localStorage.clear());
  await page.goto("/login");
  await page.locator("#u").fill(who.id);
  await page.locator("#p").fill(who.pass);
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page.locator(".side")).toBeVisible();
}

/** Click a chip or checklist label unless its box is already ticked (the AI may have ticked it). */
async function tick(label: ReturnType<Page["locator"]>) {
  if (!(await label.locator("input").isChecked())) await label.click();
  await expect(label.locator("input")).toBeChecked();
}

test.beforeAll(async ({ request }) => {
  expect(ADMIN.id, "set E2E_ADMIN_ID and E2E_ADMIN_PASS").not.toBe("");
  token = (await (await request.post(API + "/login", { data: { login_id: ADMIN.id, password: ADMIN.pass } })).json()).token;
  for (const [who, role] of [[UPLOADER, "Uploader"], [VIEWER, "Viewer"]] as const) {
    await api(request, "post", "/accounts", { login_id: who.id, name: `E2E ${role}`, dept: "Examination", role, password: who.pass });
  }
});

test.afterAll(async ({ request }) => {
  const rec = await api(request, "get", "/records");
  for (const d of rec.documents.filter((x: { title: string }) => x.title.startsWith(`E2E circular ${stamp}`))) {
    await api(request, "delete", `/records/documents/${d.id}`);
  }
  for (const who of [UPLOADER, VIEWER]) await api(request, "delete", `/records/users/us-${who.id}`);
});

test("upload, review and publish across roles", async ({ page }) => {
  // Uploader submits a document.
  await signIn(page, UPLOADER);
  await expect(page.locator(".nav")).not.toContainText("Review & Approvals");
  await page.goto("/upload");
  await expect(page.getByRole("link", { name: "Review queue" })).toHaveCount(0);
  await page.locator('input[type="file"]').setInputFiles({
    name: "circular.txt", mimeType: "text/plain",
    buffer: Buffer.from(`Subject: Invigilation duty ${stamp}\n\nAll invigilators shall report 45 minutes before the examination.\n\nMobile phones are not allowed in examination halls.`),
  });
  await expect(page.locator("#u-title")).toBeVisible({ timeout: 90_000 });
  await page.locator("#u-title").fill(TITLE);
  await page.locator("#u-ref").fill(`SVSU/E2E/${stamp}`);
  for (const id of ["#u-type", "#u-authority", "#u-dept"]) await page.locator(id).selectOption({ index: 1 });
  await page.locator("#u-date").fill("2026-10-01");
  // The chips hide the native inputs, so set them directly (and keep any the AI already ticked).
  await tick(page.locator(".chips").nth(0).locator("label").first());
  await tick(page.locator(".chips").nth(1).locator("label").first());
  await tick(page.locator("label.chk", { has: page.locator('input[name="uvis"]') }).nth(1));  // All Staff
  await page.locator("#u-effective").fill("2026-10-01");
  await page.getByRole("button", { name: "Submit for approval" }).click();
  await expect(page.getByText("was submitted for approval")).toBeVisible({ timeout: 60_000 });
  await expect(page.getByRole("link", { name: "Open review queue" })).toHaveCount(0);
  // Their own pending document is in their Library.
  await page.goto("/library");
  await expect(page.getByText(TITLE)).toBeVisible();

  // A Viewer can't see it yet.
  await signIn(page, VIEWER);
  await page.goto("/library");
  await expect(page.locator(".card").first()).toBeVisible();
  await expect(page.getByText(TITLE)).toHaveCount(0);

  // The administrator reviews: the checklist must be complete before publishing.
  await signIn(page, ADMIN);
  await page.goto("/review");
  await page.locator(".ritem", { hasText: TITLE }).click();
  await expect(page.locator(".checks").first()).toContainText("Required fields complete", { timeout: 30_000 });
  await page.getByRole("button", { name: /Approve/ }).click();
  await expect(page.locator(".toast").last()).toContainText("Tick every item");
  for (const box of await page.locator(".checks label.c").all()) await tick(box);
  await page.getByRole("button", { name: /Approve/ }).click();
  await expect(page.locator(".toast").last()).toContainText("Approved");

  // Now the Viewer sees it, reads its text, and can't change it.
  await signIn(page, VIEWER);
  await page.goto("/library");
  await page.getByText(TITLE).click();
  await expect(page.getByRole("heading", { name: TITLE })).toBeVisible();
  await expect(page.getByRole("button", { name: "Edit" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Withdraw" })).toHaveCount(0);
  await page.getByRole("tab", { name: "Preview" }).click();
  await expect(page.locator(".paper").first()).toContainText("45 minutes");
  await expect(page.locator(".wm")).toHaveCount(0);  // no SAMPLE watermark on real documents

  // The Uploader can no longer edit it once published.
  await signIn(page, UPLOADER);
  await page.goto("/library");
  await page.getByText(TITLE).click();
  await expect(page.getByRole("heading", { name: TITLE })).toBeVisible();
  await expect(page.getByRole("button", { name: "Edit" })).toHaveCount(0);
});

test("deadlines: viewers set reminders but can't mark done", async ({ page }) => {
  await signIn(page, ADMIN);
  await page.goto("/deadlines");
  await page.getByRole("button", { name: "Add deadline" }).first().click();
  await page.locator("#ad-t").fill(`E2E deadline ${stamp}`);
  await page.locator("#ad-d").fill("2099-01-15");
  const option = page.locator("#ad-doc option", { hasText: TITLE });
  await page.locator("#ad-doc").selectOption(await option.getAttribute("value") ?? "");
  await page.locator(".modal").getByRole("button", { name: "Add deadline" }).click();
  await expect(page.locator(".toast").last()).toContainText("Deadline added", { timeout: 30_000 });

  await signIn(page, VIEWER);
  await page.goto("/deadlines");
  await page.getByRole("button", { name: "All" }).click();
  const row = page.locator(".li", { hasText: `E2E deadline ${stamp}` });
  await expect(row).toBeVisible();
  await expect(row.getByRole("button", { name: /Done/ })).toHaveCount(0);
  await row.getByRole("button", { name: "Set a reminder" }).click();
  await page.getByRole("button", { name: "Save reminder" }).click();
  await expect(page.locator(".toast").last()).toContainText("Reminder set");
});

test("people can't open pages their role doesn't allow", async ({ page }) => {
  await signIn(page, VIEWER);
  for (const path of ["/upload", "/review", "/reports", "/admin"]) {
    await page.goto(path);
    await expect(page.getByText("You don't have access to this page")).toBeVisible();
  }
});
