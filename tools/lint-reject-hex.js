#!/usr/bin/env node
// Reject-hex lint: fails CI if any of the banned hex literals (gamer-RGB, etc.)
// appear outside vector-palette/. Backs the no-list defined in
// VEC-21 §3.4 art-direction and read from
// resources/[vector]/vector-palette/src/tokens.json::rejectHex.

"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..");
const TOKENS_PATH = path.join(
  REPO_ROOT,
  "resources",
  "[vector]",
  "vector-palette",
  "src",
  "tokens.json",
);
const PALETTE_RESOURCE_PREFIX = path.join("resources", "[vector]", "vector-palette");

// Directories we never scan. Generated paths, vendored content, and lockfiles.
const SKIP_DIRS = new Set([
  ".git",
  ".github",
  "node_modules",
  ".remember",
  "txData",
  "mariadb-data",
]);
const SKIP_DIR_BASENAMES = new Set(["vendor"]);
const SKIP_FILES = new Set(["package-lock.json", "yarn.lock", "pnpm-lock.yaml"]);
const SCAN_EXTENSIONS = new Set([
  ".lua",
  ".js",
  ".jsx",
  ".ts",
  ".tsx",
  ".css",
  ".scss",
  ".html",
  ".json",
  ".md",
  ".cfg",
  ".yml",
  ".yaml",
  ".sh",
]);

function loadRejectList() {
  const raw = fs.readFileSync(TOKENS_PATH, "utf8");
  const j = JSON.parse(raw);
  if (!Array.isArray(j.rejectHex) || j.rejectHex.length === 0) {
    process.stderr.write("lint-reject-hex: tokens.json has no rejectHex list\n");
    process.exit(2);
  }
  // Build a single case-insensitive regex that matches any literal in the list,
  // not embedded in a longer hex run (e.g. don't trip on `#FF0000FF`).
  const escaped = j.rejectHex.map((h) => h.replace(/[#]/g, "\\#"));
  return {
    list: j.rejectHex,
    re: new RegExp("(?<![0-9A-Fa-f])(?:" + escaped.join("|") + ")(?![0-9A-Fa-f])", "gi"),
  };
}

function isAllowedPath(rel) {
  return rel.startsWith(PALETTE_RESOURCE_PREFIX);
}

function* walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const ent of entries) {
    if (SKIP_DIRS.has(ent.name)) continue;
    if (ent.isDirectory()) {
      if (SKIP_DIR_BASENAMES.has(ent.name)) continue;
      yield* walk(path.join(dir, ent.name));
      continue;
    }
    if (!ent.isFile()) continue;
    if (SKIP_FILES.has(ent.name)) continue;
    const ext = path.extname(ent.name).toLowerCase();
    if (!SCAN_EXTENSIONS.has(ext)) continue;
    yield path.join(dir, ent.name);
  }
}

function main() {
  const { list, re } = loadRejectList();
  const offenders = [];
  for (const file of walk(REPO_ROOT)) {
    const rel = path.relative(REPO_ROOT, file);
    if (isAllowedPath(rel)) continue;
    // Don't lint this script's own source — it embeds the list for matching.
    if (rel === path.join("tools", "lint-reject-hex.js")) continue;
    const content = fs.readFileSync(file, "utf8");
    let match;
    re.lastIndex = 0;
    while ((match = re.exec(content)) !== null) {
      const before = content.slice(0, match.index);
      const line = before.split(/\r?\n/).length;
      offenders.push({ file: rel, line, hex: match[0] });
    }
  }
  if (offenders.length > 0) {
    process.stderr.write(
      "lint-reject-hex: rejected hex literals found outside vector-palette/.\n",
    );
    process.stderr.write("  no-list: " + list.join(" ") + "\n");
    for (const o of offenders) {
      process.stderr.write("  " + o.file + ":" + o.line + "  " + o.hex + "\n");
    }
    process.stderr.write(
      "  edit src/tokens.json (and the binding VEC-21 doc) instead of using these literals.\n",
    );
    process.exit(1);
  }
  process.stdout.write("lint-reject-hex: clean\n");
}

main();
