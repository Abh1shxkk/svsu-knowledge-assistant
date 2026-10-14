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
    // A box that overflows by only a few pixels shows a stray scrollbar for no reason.
    const stray = await page.evaluate(() => [...document.querySelectorAll<HTMLElement>("*")].filter((el) => {
      const cs = getComputedStyle(el);
      const scrolls = (o: string) => o === "auto" || o === "scroll";
      const over = (a: number, b: number) => a - b > 0 && a - b <= 4;
      return cs.scrollbarWidth !== "none" && ((scrolls(cs.overflowY) && over(el.scrollHeight, el.clientHeight))
        || (scrolls(cs.overflowX) && over(el.scrollWidth, el.clientWidth)));
    }).map((el) => `${el.tagName.toLowerCase()}.${el.className}`));
    for (const s of stray) errors.push(`${path}: stray scrollbar on ${s}`);
  }
  expect(errors).toEqual([]);
});
