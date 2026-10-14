import { createHmac } from "node:crypto";
import { expect, test, type Page } from "@playwright/test";

/**
 * Streaming answers, the fact-check warning, two-step verification (set-up, code, recovery code,
 * lock-out) and the "Needs a text check" list. The test account is removed afterwards.
 */
const API = process.env.E2E_API_URL ?? "http://127.0.0.1:8000";
const ADMIN = { id: process.env.E2E_ADMIN_ID ?? "", pass: process.env.E2E_ADMIN_PASS ?? "" };
const USER = { id: `e2e-2fa-${Date.now().toString(36)}`, pass: "E2e-Password-1" };

/** The 6-digit code an authenticator app would show for this key now (RFC 6238). */
function totp(secret: string) {
  const bits = [...secret.replace(/\s/g, "")].map((c) => "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".indexOf(c).toString(2).padStart(5, "0")).join("");
  const key = Buffer.from(bits.match(/.{8}/g)!.map((b) => parseInt(b, 2)));
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30_000)));
  const h = createHmac("sha1", key).update(counter).digest();
  return String((h.readUInt32BE(h[h.length - 1] & 15) & 0x7fffffff) % 1_000_000).padStart(6, "0");
}

async function signIn(page: Page, who: { id: string; pass: string }, code?: string) {
  await page.goto("/login");
  await page.evaluate(() => localStorage.clear());
  await page.goto("/login");
  await page.locator("#u").fill(who.id);
  await page.locator("#p").fill(who.pass);
  await page.getByRole("button", { name: /sign in/i }).click();
  if (code !== undefined) {
    await page.locator("#code").fill(code);
    await page.getByRole("button", { name: "Verify" }).click();
  }
  await expect(page.locator(".side")).toBeVisible();
}

async function adminHeaders(request: import("@playwright/test").APIRequestContext) {
  const login = await request.post(API + "/login", { data: { login_id: ADMIN.id, password: ADMIN.pass } });
  return { Authorization: `Bearer ${(await login.json()).token}` };
}

test.afterAll(async ({ request }) => {
  await request.delete(`${API}/records/users/us-${USER.id}`, { headers: await adminHeaders(request) });
});

test("answers stream in with progress, then show citations", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await signIn(page, ADMIN);
  await page.goto("/ask");
  await page.getByLabel("Your question").fill("Yuva Samvad kab aur kahan hai?");
  await page.getByLabel("Send").click();
  await expect(page.locator(".thinking")).toBeVisible();          // progress while it works
  await expect(page.locator(".ma .mh").last()).toBeVisible({ timeout: 90_000 });
  await expect(page.locator(".thinking")).toHaveCount(0);
  await expect(page.locator(".ma").last()).toContainText(/21/);   // 21.09.2026
  expect(errors).toEqual([]);
});

test("statements the fact check can't confirm are flagged", async ({ page }) => {
  await signIn(page, ADMIN);
  const answer = { source: "documents", label: "One source", banner: null, body: [{ p: "The total is **2056**." }], cites: [], follow: [],
    checks: ["The total is 2056"] };
  await page.route("**/ask/stream", (r) => r.fulfill({ contentType: "text/event-stream",
    body: `data: ${JSON.stringify({ status: "Searching the records…" })}\n\ndata: ${JSON.stringify({ done: answer })}\n\n` }));
  await page.goto("/ask");
  await page.getByLabel("Your question").fill("How many people in total?");
  await page.getByLabel("Send").click();
  await expect(page.locator(".factcheck")).toContainText("The total is 2056");
});

test("two-step verification: set up, sign in with a code and a recovery code, lock-out", async ({ page, request }) => {
  const created = await request.post(API + "/accounts", { headers: await adminHeaders(request),
    data: { login_id: USER.id, name: "E2E Two Step", dept: "Examination", role: "Viewer", password: USER.pass } });
  expect(created.ok()).toBeTruthy();

  await signIn(page, USER);
  await page.goto("/profile");
  await page.getByRole("button", { name: "Set up" }).click();
  const secret = (await page.locator(".mfa-key").textContent())!;
  await page.locator("#mfa-first").fill(totp(secret));
  await page.getByRole("button", { name: "Turn on" }).click();
  await expect(page.locator(".mfa-codes span")).toHaveCount(8);
  const codes = await page.locator(".mfa-codes span").allTextContents();
  await page.getByRole("button", { name: "I've saved them" }).click();
  await expect(page.locator(".pill.ok", { hasText: "On" })).toBeVisible();

  await signIn(page, USER, totp(secret));             // password, then the app's code
  await signIn(page, USER, codes[0]);                 // or a recovery code
  await page.goto("/profile");
  await expect(page.getByText("7 recovery codes left")).toBeVisible();

  await page.goto("/login");
  await page.evaluate(() => localStorage.clear());
  await page.goto("/login");
  for (let i = 0; i < 5; i++) {
    await page.locator("#u").fill(USER.id);
    await page.locator("#p").fill("wrong-password-1");
    await page.getByRole("button", { name: /sign in/i }).click();
    await expect(page.locator(".note.bad")).toBeVisible();
  }
  await page.locator("#p").fill(USER.pass);
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page.locator(".note.bad")).toContainText("Too many wrong attempts");
});

test("the text-check list shows scans with unsure words", async ({ page }) => {
  await signIn(page, ADMIN);
  await page.goto("/library?check=1");
  await expect(page.getByLabel(/Needs a text check/)).toBeChecked();
  const rows = page.locator(".drow");
  if (await rows.count()) await expect(rows.first().locator(".pill.warn")).toContainText("to check");
});
