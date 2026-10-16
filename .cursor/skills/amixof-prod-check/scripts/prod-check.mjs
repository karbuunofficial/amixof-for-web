#!/usr/bin/env node
/**
 * prod-check: open the site in a real browser and check what users see.
 *
 *   node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs                    # live site, signed out
 *   node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs --signed-in        # + home/friends/settings
 *   node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs --base http://localhost:4173
 *   … --pages /login,/login/auth   … --out .cursor/artifacts/my-run
 *
 * For each page × {390px, 1360px} × {light, dark} it checks: HTTP status, uncaught errors and
 * console errors, horizontal scroll, visible "Stoat"/"Revolt" text, and (on /login) that the
 * AMIXOF wordmark renders and is centred. Screenshots go to the output folder; look at them.
 * Signed-in mode needs AMIXOF_TEST_EMAIL / AMIXOF_TEST_PASSWORD (env or .cursor/amixof.env).
 * Exit code 1 if any check fails.
 */
import { execSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";

const ROOT = execSync("git rev-parse --show-toplevel").toString().trim();

// ---------- config ----------
const env = { ...process.env };
const confPath = join(ROOT, ".cursor/amixof.env");
if (existsSync(confPath)) {
  for (const line of readFileSync(confPath, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z0-9_]+)=(.*)$/);
    if (m && env[m[1]] === undefined) env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}
const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i > -1 ? process.argv[i + 1] : fallback;
};
const BASE = (arg("--base", env.AMIXOF_URL || "https://www.amixof.com")).replace(/\/$/, "");
const SIGNED_IN = process.argv.includes("--signed-in");
const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "").replace("T", "-");
const OUT = arg("--out", join(ROOT, ".cursor/artifacts", `prod-check-${stamp}`));
mkdirSync(OUT, { recursive: true });

const SIGNED_OUT_PAGES = (arg("--pages", "/login,/login/auth,/login/create,/login/reset,/login/resend")).split(",");
const SIGNED_IN_PAGES = ["/", "/friends", "/settings"];
const VIEWPORTS = [
  { name: "390", width: 390, height: 844, isMobile: true, hasTouch: true },
  { name: "1360", width: 1360, height: 900 },
];
const SCHEMES = ["light", "dark"];

// ---------- playwright ----------
let chromium;
for (const from of [join(ROOT, "packages/client/"), ROOT + "/"]) {
  try {
    const req = createRequire(from);
    ({ chromium } = req("@playwright/test"));
    break;
  } catch {
    try {
      ({ chromium } = createRequire(from)("playwright"));
      break;
    } catch {
      /* try next */
    }
  }
}
if (!chromium) {
  console.error("Playwright not found. Run: pnpm install --frozen-lockfile && pnpm --filter client exec playwright install chromium");
  process.exit(2);
}

// ---------- checks ----------
const results = [];
const record = (page, vp, scheme, check, ok, detail = "") =>
  results.push({ page, vp, scheme, check, ok, detail: String(detail).replace(/\s+/g, " ").slice(0, 300) });

/** Load a page and run every check on it. */
async function checkPage(context, path, vp, scheme) {
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
  page.on("console", (m) => {
    if (m.type() === "error") errors.push(`console: ${m.text().slice(0, 200)}`);
  });
  let status = 0;
  try {
    const resp = await page.goto(BASE + path, { waitUntil: "load", timeout: 45000 });
    status = resp ? resp.status() : 0;
  } catch (e) {
    record(path, vp.name, scheme, "loads", false, String(e).slice(0, 200));
    await page.close();
    return;
  }
  await page.waitForFunction(() => document.body && document.body.innerText.trim().length > 0, null, { timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1500);

  record(path, vp.name, scheme, "http status", status > 0 && status < 400, String(status));

  const m = await page.evaluate(() => {
    const doc = document.documentElement;
    const svg = document.querySelector('svg[aria-label="AMIXOF"]');
    let wordmark = null;
    if (svg) {
      const s = svg.getBoundingClientRect();
      const t = svg.querySelector("text")?.getBoundingClientRect();
      wordmark = { w: s.width, h: s.height, left: t ? t.left - s.left : null, right: t ? s.right - t.right : null, text: svg.textContent?.trim() };
    }
    return {
      scrollWidth: doc.scrollWidth,
      innerWidth: window.innerWidth,
      text: document.body.innerText,
      title: document.title,
      bg: getComputedStyle(document.body).backgroundColor,
      wordmark,
    };
  });

  record(path, vp.name, scheme, "no horizontal scroll", m.scrollWidth <= m.innerWidth + 1, `${m.scrollWidth} vs ${m.innerWidth}`);
  const leak = (m.text + " " + m.title).match(/.{0,40}\b(Stoat|Revolt)\b.{0,40}/);
  record(path, vp.name, scheme, "no Stoat/Revolt text", !leak, leak ? leak[0].replace(/\s+/g, " ") : `title "${m.title}"`);
  record(path, vp.name, scheme, "no page/console errors", errors.length === 0, errors.slice(0, 3).join(" | "));

  if (path === "/login") {
    const w = m.wordmark;
    const ok = !!w && w.text === "AMIXOF" && w.w > 0 && w.left !== null && Math.abs(w.left - w.right) <= Math.max(4, w.w * 0.04);
    record(path, vp.name, scheme, "wordmark visible + centred", ok, w ? `text=${w.text} w=${Math.round(w.w)} L=${Math.round(w.left)} R=${Math.round(w.right)}` : "svg[aria-label=AMIXOF] not found");
  }

  const file = join(OUT, `${(path.replace(/\//g, "_") || "_root").replace(/^_/, "") || "root"}-${vp.name}-${scheme}.png`);
  await page.screenshot({ path: file, fullPage: true });
  record(path, vp.name, scheme, "screenshot", true, file.replace(ROOT + "/", ""));
  await page.close();
}

/** Sign in with the test account inside this context. Returns true on success. */
async function signIn(context) {
  const email = env.AMIXOF_TEST_EMAIL;
  const password = env.AMIXOF_TEST_PASSWORD;
  if (!email || !password) {
    record("(sign in)", "-", "-", "test credentials present", false, "set AMIXOF_TEST_EMAIL / AMIXOF_TEST_PASSWORD in .cursor/amixof.env");
    return false;
  }
  const page = await context.newPage();
  try {
    await page.goto(BASE + "/login/auth", { waitUntil: "load", timeout: 45000 });
    await page.locator('input[type="email"]').fill(email);
    await page.locator('input[type="password"]').fill(password);
    await page.locator('button[type="submit"]').click();
    await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30000 });
    record("(sign in)", "-", "-", "signed in", true, page.url());
    return true;
  } catch (e) {
    const shot = join(OUT, "signin-failure.png");
    await page.screenshot({ path: shot }).catch(() => {});
    record("(sign in)", "-", "-", "signed in", false, `${String(e).slice(0, 160)} (captcha or MFA on the account will block this) — ${shot}`);
    return false;
  } finally {
    await page.close();
  }
}

let browser;
try {
  const executablePath = arg("--chromium", env.CHROMIUM_PATH) || undefined;
  browser = await chromium.launch({ executablePath });
} catch (e) {
  console.error(String(e).split("\n")[0]);
  console.error("Install the browser once with: pnpm --filter client exec playwright install chromium");
  process.exit(2);
}
try {
  for (const vp of VIEWPORTS) {
    for (const scheme of SCHEMES) {
      const context = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        isMobile: !!vp.isMobile,
        hasTouch: !!vp.hasTouch,
        colorScheme: scheme,
        serviceWorkers: "block",
      });
      for (const p of SIGNED_OUT_PAGES) await checkPage(context, p, vp, scheme);
      if (SIGNED_IN && (await signIn(context))) {
        for (const p of SIGNED_IN_PAGES) await checkPage(context, p, vp, scheme);
      }
      await context.close();
    }
  }
} finally {
  await browser.close();
}

// ---------- report ----------
const failed = results.filter((r) => !r.ok);
const lines = [`# prod-check ${BASE} (${new Date().toISOString()})`, "", `${results.length - failed.length} passed, ${failed.length} failed`, ""];
for (const r of results.filter((r) => r.check !== "screenshot")) {
  lines.push(`${r.ok ? "PASS" : "FAIL"}  ${r.page.padEnd(15)} ${r.vp.padEnd(5)} ${r.scheme.padEnd(6)} ${r.check}${r.detail ? ` — ${r.detail}` : ""}`);
}
lines.push("", `screenshots: ${OUT.replace(ROOT + "/", "")}`);
if (!SIGNED_IN) lines.push("signed-in screens: NOT checked (run with --signed-in)");
writeFileSync(join(OUT, "report.txt"), lines.join("\n") + "\n");
console.log(lines.join("\n"));
process.exit(failed.length ? 1 : 0);
