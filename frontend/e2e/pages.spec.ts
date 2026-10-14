import { expect, test } from "@playwright/test";

/** Every screen opens without a browser error — including when it has nothing to show yet. */
test("every page loads without errors", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(`${new URL(page.url()).pathname}: ${e.message}`));
  await page.goto("/login");
  await page.locator("#u").fill(process.env.E2E_ADMIN_ID ?? "");
  await page.locator("#p").fill(process.env.E2E_ADMIN_PASS ?? "");
  await page.getByRole("button", { name: /sign in/i }).click();
  await expect(page.locator(".side")).toBeVisible();
  for (const path of ["/", "/ask", "/library", "/upload", "/review", "/collections", "/deadlines", "/saved", "/reports", "/admin", "/profile"]) {
    await page.goto(path);
    await expect(page.locator(".pagehead, .chat, .dash").first(), path).toBeVisible();
  }
  expect(errors).toEqual([]);
});
