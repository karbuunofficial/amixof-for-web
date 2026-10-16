#!/usr/bin/env node
/**
 * brand-scan: find "Stoat" / "Revolt" text that AMIXOF users could see.
 *
 *   node .cursor/skills/amixof-audit/scripts/brand-scan.mjs          # scan source
 *   node .cursor/skills/amixof-audit/scripts/brand-scan.mjs --json   # machine-readable
 *
 * What it checks
 *  1. English catalog messages that mention Stoat/Revolt AND are still used in source.
 *  2. User-facing attributes (alt, aria-label, title, placeholder, label) with Stoat/Revolt.
 *  3. index.html, manifests and fallback brand assets.
 *  4. The wordmark must not be imported with ?component-solid (it renders blank).
 *
 * Known-safe places are allow-listed below with the reason. To accept one more line, put
 * `brand-scan-ignore: <reason>` in a comment on that line or the line above it.
 * Exit code 1 when anything is found.
 */
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { execSync } from "node:child_process";

const ROOT = execSync("git rev-parse --show-toplevel").toString().trim();
const CLIENT = join(ROOT, "packages/client");
const BRAND = /\b(Stoat|Revolt)\b/;

/** Files whose Stoat text never renders on amixof.com. Keep reasons current. */
const ALLOW_FILES = new Map([
  ["packages/client/src/AndroidNag.tsx", "only runs on stoat.chat / localhost"],
]);

const SKIP_DIRS = new Set(["node_modules", "dist", "dist_injected", "styled-system", "catalogs", "locales", "assets", "test-results", "playwright-report", ".git"]);

/** Recursively list files under dir with one of the extensions. */
function walk(dir, exts, out = []) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, exts, out);
    else if (exts.some((e) => name.endsWith(e))) out.push(p);
  }
  return out;
}

const rel = (p) => relative(ROOT, p).split(sep).join("/");
const findings = [];
const add = (file, line, kind, text) => findings.push({ file: rel(file), line, kind, text: text.trim().slice(0, 160) });

const sources = walk(CLIENT, [".ts", ".tsx"]);
const sourceText = new Map(sources.map((f) => [f, readFileSync(f, "utf8")]));
const collapse = (s) => s.replace(/\s+/g, " ");
const collapsedSources = new Map([...sourceText].map(([f, t]) => [f, collapse(t)]));

const ignored = (lines, i) => /brand-scan-ignore/.test(lines[i] ?? "") || /brand-scan-ignore/.test(lines[i - 1] ?? "");

// 1. catalog messages still used in source
const po = join(CLIENT, "components/i18n/catalogs/en/messages.po");
if (existsSync(po)) {
  const msgids = [];
  const lines = readFileSync(po, "utf8").split("\n");
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^msgid "(.*)"$/);
    if (!m) continue;
    let id = m[1];
    while (lines[i + 1]?.startsWith('"')) id += lines[++i].slice(1, -1);
    if (BRAND.test(id)) msgids.push(id.replace(/\\"/g, '"'));
  }
  for (const id of msgids) {
    const needle = collapse(id).replace(/\{[^}]*\}/g, "\u0000").split("\u0000").sort((a, b) => b.length - a.length)[0].trim();
    if (needle.length < 6) continue;
    for (const [file, text] of collapsedSources) {
      if (ALLOW_FILES.has(rel(file))) continue;
      if (!text.includes(needle)) continue;
      const raw = sourceText.get(file).split("\n");
      const firstWord = needle.split(" ").slice(0, 3).join(" ");
      let line = raw.findIndex((l) => l.includes(firstWord));
      if (line >= 0 && ignored(raw, line)) continue;
      add(file, line + 1, "message", id);
    }
  }
}

// 2. user-facing attributes and bare JSX text in source
const ATTR = /\b(alt|aria-label|title|placeholder|label)=\{?["'`][^"'`]*\b(Stoat|Revolt)\b/;
const JSX_TEXT = />\s*[^<>{}]*\b(Stoat|Revolt)\b[^<>{}]*</;
for (const [file, text] of sourceText) {
  if (ALLOW_FILES.has(rel(file)) || !file.endsWith(".tsx")) continue;
  const lines = text.split("\n");
  lines.forEach((l, i) => {
    if (/^\s*(\/\/|\*|\/\*)/.test(l) || ignored(lines, i)) return;
    if (ATTR.test(l)) add(file, i + 1, "attribute", l);
    else if (JSX_TEXT.test(l) && !/<Trans>/.test(l)) add(file, i + 1, "jsx-text", l);
  });
}

// 3. html, manifests, fallback assets
const statics = [join(CLIENT, "index.html"), join(CLIENT, "vite.config.ts")];
for (const d of [join(CLIENT, "scripts/assets_fallback"), join(CLIENT, "public")]) {
  if (existsSync(d)) statics.push(...walk(d, [".html", ".json", ".webmanifest", ".svg", ".txt", ".xml"]));
}
for (const file of statics) {
  if (!existsSync(file)) continue;
  const lines = readFileSync(file, "utf8").split("\n");
  lines.forEach((l, i) => {
    if (ignored(lines, i)) return;
    if (file.endsWith("vite.config.ts")) {
      // only manifest-ish fields matter here
      if (/\b(name|short_name|description|title)\s*:\s*["'`][^"'`]*\b(Stoat|Revolt)\b/.test(l)) add(file, i + 1, "manifest", l);
    } else if (BRAND.test(l)) add(file, i + 1, "static", l);
  });
}

// 4. wordmark import mode
for (const [file, text] of sourceText) {
  text.split("\n").forEach((l, i) => {
    if (/wordmark\.svg\?component-solid/.test(l)) add(file, i + 1, "wordmark", l + "  ← use AmixofWordmark from @revolt/ui");
  });
}

if (process.argv.includes("--json")) {
  console.log(JSON.stringify(findings, null, 2));
} else if (findings.length === 0) {
  console.log(`brand-scan: clean (${sources.length} source files; allow-listed: ${[...ALLOW_FILES.keys()].join(", ")})`);
} else {
  console.log(`brand-scan: ${findings.length} finding(s)\n`);
  for (const f of findings) console.log(`${f.file}:${f.line}  [${f.kind}]  ${f.text}`);
  console.log("\nFix each one, or add `brand-scan-ignore: <reason>` next to it if it never renders on amixof.com.");
}
process.exit(findings.length ? 1 : 0);
