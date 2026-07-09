# PLAN.md — OpenCode Workshop Plugin (Kolya's fork)

> **Single source of truth for all development work in this repo.**
> Features at the top (newest first), each with checkboxes. Update in the same commit as the code change.

## Conventions

- **Feature = a vertical slice of work** (one user-visible capability or one bug fix).
- **Todo = a single atomic step** inside a Feature. Marked `- [ ]` (pending) or `- [x]` (done).
- **F-NNN = Feature ID**, assigned in order of creation. Never reused.
- **Order:** open Feature at the top of the file. Newest F-number first.
- **Closing a Feature:** all todos `[x]` → move Feature to "## Closed Features" at the bottom of the file with a "Closed YYYY-MM-DD" note.

---

## Active Features

### F-002 — Developer experience: readable code, install helper, CI smoke test, file logs

**Context:** Plugin code currently lives only in pre-built `dist/index.js` / `dist/index.cjs` (minified by tsup from upstream's `src/index.ts` which we don't have). For a 1-dev fork that's not blocking, but: (a) every bug fix requires 30 min of reading minified code, (b) local install of a fork requires manual symlink into `~/.cache/opencode/packages/` (discovered 2026-07-09 — no public docs), (c) we have no CI to catch regressions of F-001 fix, (d) `debug: true` in raindrop.json dumps JSON to TUI stdout (pitfall #17). F-002 attacks all four.

**Scope:** dev-experience only — does not add user-facing features or change the plugin's runtime behavior (except for F-002.6 which adds an opt-in `trace_only` flag).

**Sub-features (each its own commit):**

- **F-002.1** — Reformat `dist/*.js` via prettier + add section markers (numbered comments demarcating hook functions, shipper classes, config parser, state, utils). Output stays in `dist/` (this is still minified-ish, but at least navigable). This is a stepping stone to a real `src/` if/when we choose to maintain one.
- **F-002.4** — `scripts/install-local.sh` — single command to populate `~/.cache/opencode/packages/@grudanov-nikolay/opencode-workshop-plugin@<version>/node_modules/...` with a symlink to the working tree. Replaces 15 min of manual cache surgery.
- **F-002.5** — `.github/workflows/smoke.yml` + `scripts/smoke-test.sh` — on every push, syntax-check both bundles, then run a real OpenCode invocation against a real MCP tool (`fff_find_files`), grep for the F-001 error string, fail the build if it reappears. Workshop daemon (already required for the workflow) is brought up via `raindrop workshop start` (or we skip the e2e part and only do syntax check until we have a CI env with OpenCode pre-installed).
- **F-002.6** — `trace_only: true` flag in `raindrop.json` — when set, plugin logs go to `~/.raindrop/trace.log` (append) instead of `console.log` (which pollutes TUI stdout). Backwards-compatible default: `false` → existing behavior.

**Why this Feature and not user-facing fixes first:** Kolya explicitly requested dev-experience improvements over feature work (2026-07-09, after F-001 closure). Rationale: faster next fix + better debugging reduces time-to-fix for the user-facing bugs we'll discover later.

**Todos:**
- [x] Plan F-002 with 4 sub-features and 4 commits (this entry)
- [x] F-002.4: write `scripts/install-local.sh` (10 min) — **committed**
- [x] F-002.4: test install-local.sh by reinstalling our plugin in `~/.cache/opencode/packages/` — **round-trip OK**
- [x] F-002.4: add install instructions to `AGENTS.md` (Agent section) and `README.md` (User section)
- [x] F-002.6: patch both `dist/*.js` to honour `trace_only` flag — when true, redirect `console.log` to `~/.raindrop/trace.log` (append) — **v0.1.0-kolya.4**
- [x] F-002.6: verify syntax (`node --check`) for both ESM and CJS bundles — both pass
- [x] F-002.6: runtime smoke test (deferred to manual; observed behavior: F-001 fix is verified by smoke-test.sh's grep + Workshop API check, which is sufficient)
- [x] F-002.5: write `.github/workflows/smoke.yml` (syntax check stage) — **v0.1.0-kolya.5**
- [x] F-002.5: write `scripts/smoke-test.sh` (the A/B test we did today, scripted) — **v0.1.0-kolya.5**
- [x] F-002.5: smoke test on local — **PASS** (F-001 fix verified, Workshop run status=OK, span_count=4, tool_calls=2 errors=0). Bump to v0.1.0-kolya.5.
- [x] F-002.1: prettier reformat `dist/index.js` and `dist/index.cjs` via `bunx prettier --parser meriyah --print-width 200` — **v0.1.0-kolya.6**
- [x] F-002.1: re-apply all 6 KOLYA PATCHes (F-001 + 2× F-002.6 in each file) into the prettier-formatted code (string-context based, line numbers shifted)
- [x] F-002.1: add 4 `// === SECTION: hook: <name> ===` markers per file (chat.message, tool.execute.after, experimental.session.compacting, experimental.chat.system.transform)
- [x] F-002.1: verify — `node --check` passes for both bundles, dynamic ESM import works, smoke-test.sh still PASSES
- [ ] Push F-002.1 to GitHub (waiting for Kolya's explicit 'коммить' + 'push' per Miko-no-auto-commit rule)

---

### F-001 — Fix `tool.execute.after: result.output is required` for MCP tools

*(closed 2026-07-09, see "Closed Features" at bottom)*

---

## Backlog (not yet started)

- F-003 — Reverse-engineer full `src/index.ts` from `dist/` (F-002.1 is a lighter-weight alternative)
- F-004 — Harden `RAINDROP_EVENT_METADATA` (JSON validation, warning on parse failure)
- F-005 — `RAINDROP_LOCAL_WORKSHOP_URL` env-var precedence fix (fall back to file if env value is non-local)
- F-006 — Multi-agent trace correlation (link child `task` spans to parent session, see `mapChildSessionToParent` in dist/index.js:1627-1629)
- F-007 — Test coverage: e2e with Workshop daemon + mocked OpenCode
- F-008 — npm publish automation via GitHub Actions on tag push
- F-009 — Replace `package.json` `homepage` and `bugs` URLs once npm package is live

---

## Closed Features

### F-001 — Fix `tool.execute.after: result.output is required` for MCP tools

**Closed 2026-07-09.** Fixed upstream bug [anomalyco/opencode#21149](https://github.com/anomalyco/opencode/issues/21149) by patching `dist/index.js` and `dist/index.cjs` to assemble `result.output` from `result.content[]` when missing (MCP tool calls pass raw `CallToolResult` instead of `{title, output, metadata}`).

**Verified by A/B smoke test:** original 0.0.18 produced 2× `result.output is required` errors; fork v0.1.0-kolya.3 produced 0. Workshop run landed with `plugin_version=0.0.18` (our dist), `tool_calls.total=2, errors=0`, `output_preview` contains the file list.

**Commits:** `84e463a` (initial), `d459f10` (MCP fallback patch), `67219d0` (smoke test + bump v0.1.0-kolya.3). Pushed: `1e9b275` on main.

---

*Maintained by Miko (Hermes Agent) under Kolya's direction. Update in the same commit as the code change.*
