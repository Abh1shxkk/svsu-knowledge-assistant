import { expect, test } from "@playwright/test";

/** Bulk import: files are sent, processed in the background, and appear in the library for review. */
const API = process.env.E2E_API_URL ?? "http://127.0.0.1:8000";
const stamp = Date.now().toString(36);
const NAMES = [`e2e-bulk-${stamp}-a.txt`, `e2e-bulk-${stamp}-b.txt`];

test.afterAll(async ({ request }) => {
  const login = await request.post(API + "/login", { data: { login_id: process.env.E2E_ADMIN_ID, password: process.env.E2E_ADMIN_PASS } });
  const headers = { Authorization: `Bearer ${(await login.json()).token}` };
  const rec = await (await request.get(API + "/records", { headers })).json();
  for (const d of rec.documents.filter((x: { file?: { name: string } }) => NAMES.includes(x.file?.name ?? ""))) {
    await request.delete(`${API}/records/documents/${d.id}`, { headers });
  }
});

test("a bulk import is processed in the background and lands in review", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/login");
  await page.locator("#u").fill(process.env.E2E_ADMIN_ID ?? "");
  await page.locator("#p").fill(process.env.E2E_ADMIN_PASS ?? "");
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page.locator(".side")).toBeVisible();

  await page.goto("/upload");
  await page.getByRole("tab", { name: "Bulk import" }).click();
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Choose files" }).click();
  await (await chooser).setFiles([
    { name: NAMES[0], mimeType: "text/plain", buffer: Buffer.from(`Library hours notice ${stamp}. The central library stays open from 8 AM to 8 PM on all working days during the examination period.`) },
    { name: NAMES[1], mimeType: "text/plain", buffer: Buffer.from(`Transport notice ${stamp}. University buses leave the main gate at 5:15 PM on weekdays and at 2 PM on Saturdays.`) },
  ]);
  // Both are read, described and indexed by the server's background worker.
  const newest = page.locator(".card", { hasText: "Imports" }).locator(".li").first();  // newest batch first
  await expect(newest.locator(".pill.ok", { hasText: "2 imported" })).toBeVisible({ timeout: 180_000 });
  await page.goto("/library?status=Pending");
  await expect(page.getByText(/notice|hours|transport|bus/i).first()).toBeVisible();
  expect(errors).toEqual([]);
});

test("administrators see the answer-quality card", async ({ page }) => {
  await page.goto("/login");
  await page.locator("#u").fill(process.env.E2E_ADMIN_ID ?? "");
  await page.locator("#p").fill(process.env.E2E_ADMIN_PASS ?? "");
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page.locator(".side")).toBeVisible();  // signed in before moving on
  await page.goto("/reports");
  await expect(page.getByRole("heading", { name: "Answer quality" })).toBeVisible();
});
