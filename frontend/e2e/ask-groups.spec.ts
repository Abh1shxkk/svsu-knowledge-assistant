import { expect, test, type APIRequestContext } from "@playwright/test";

/** Collections group documents by department; opening one asks only those documents, listed beside the chat. */
const API = process.env.E2E_API_URL ?? "http://127.0.0.1:8000";
const stamp = Date.now().toString(36);
const DEPT = "Examination";
let token = "";

const doc = (id: string, dept: string, title: string, text: string) => ({
  id, title, ref: `SVSU/E2E/${id}`, type: "Circular", authority: "Registrar", dept, institution: "", date: "2026-10-01",
  effective: "2026-10-01", expiry: "", audience: ["Teaching Staff"], tags: ["Examination"], visibility: "All Staff", status: "Active",
  fileType: "txt", lang: "en", description: "", uploadedBy: "E2E", uploadedOn: "2026-10-01", related: [], revisionOf: null,
  supersededBy: null, versions: [], approvals: [], pages: [[{ id: "b1", text, kind: "p" }]],
});
const DOCS = [
  doc(`ga-${stamp}`, DEPT, `E2E invigilation ${stamp}`, `Invigilators must report ${stamp.length + 40} minutes before every examination session.`),
  doc(`gb-${stamp}`, DEPT, `E2E answer sheets ${stamp}`, "Answer sheets are collected by the controller of examinations within two hours."),
  doc(`gc-${stamp}`, "Finance", `E2E fee refund ${stamp}`, "Fee refunds are processed by the accounts office within thirty days."),
];

async function call(request: APIRequestContext, method: "put" | "delete", path: string, data?: object) {
  const res = await request[method](API + path, { headers: { Authorization: `Bearer ${token}` }, data });
  expect(res.ok(), await res.text()).toBeTruthy();
}

test.beforeAll(async ({ request }) => {
  const res = await request.post(API + "/login", { data: { login_id: process.env.E2E_ADMIN_ID, password: process.env.E2E_ADMIN_PASS } });
  token = (await res.json()).token;
  for (const d of DOCS) await call(request, "put", `/records/documents/${d.id}`, d);
});

test.afterAll(async ({ request }) => {
  for (const d of DOCS) await call(request, "delete", `/records/documents/${d.id}`);
});

test("ask only the documents of one department, listed beside the chat", async ({ page }) => {
  await page.goto("/login");
  await page.locator("#u").fill(process.env.E2E_ADMIN_ID ?? "");
  await page.locator("#p").fill(process.env.E2E_ADMIN_PASS ?? "");
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page.locator(".side")).toBeVisible();

  await page.goto("/collections");
  await page.locator(".csec", { hasText: "By department" }).locator(".coll.auto", { hasText: DEPT }).click();
  await expect(page).toHaveURL(/\/ask\?group=dept/);

  const list = page.locator(".dpick");
  await expect(list.filter({ hasText: `E2E invigilation ${stamp}` })).toBeVisible();
  await expect(list.filter({ hasText: `E2E answer sheets ${stamp}` })).toBeVisible();
  await expect(list.filter({ hasText: `E2E fee refund ${stamp}` })).toHaveCount(0);  // another department

  // Leave one out: the header and the count follow.
  const before = Number((await page.locator(".scopebtn").innerText()).match(/(\d+) document/)?.[1]);
  await list.filter({ hasText: `E2E answer sheets ${stamp}` }).locator("input").uncheck();
  await expect(page.locator(".scopebtn")).toContainText(`${before - 1} document`);

  await page.getByLabel("Your question").fill(`How many minutes before the session must invigilators report? (${stamp})`);
  await page.getByRole("button", { name: "Send" }).click();
  await expect(page.locator(".srcs")).toContainText(`E2E invigilation ${stamp}`, { timeout: 90_000 });
  await expect(list.filter({ hasText: `E2E invigilation ${stamp}` })).toHaveClass(/cited/);
});
