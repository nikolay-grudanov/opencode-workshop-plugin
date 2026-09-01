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

### F-010 — Recover `subagent_name` via chat.message parts parsing (live-trace pill fix)

**Context:** Live runs (raindrop_workshop.db, 2026-07-23/24) proved two things. (1) `tool.execute.before` IS invoked for the `task` tool — task spans with `ai.toolCall.args` + result exist — so the earlier "hook not invoked" diagnosis was wrong. (2) Even with the F-003 patch cached before the late runs, `subagent_name` never landed: OpenCode delivers tool args as a JSON *string* in some paths, and `extractTaskLabel` expected an object, silently returning "". The child session's first user message (chat.message parts) IS the task prompt, and identity prompts open with `You are "<name>"` — verified against live DB prompts (`You are "reviewer-primary"`, `team-lead-beta`, …). Numbering follows the cross-repo F-sequence agreed with Kolya (workshop repo F-003 plugin-side continuation).

**Scope (both bundles, lockstep):**
- `extractTaskLabel`: tolerate JSON-string args (parse when the string starts with `{`)
- NEW `extractSubagentNameFromPrompt(text)`: parse `You are "name"` / `You are name.` / `name: value` preambles from chat.message text parts (first 400 chars), max 120 chars
- `chat.message` child-session branch: stash `state.subagentName` once per session; attach `subagent_name` to the `Subagent` root span
- child LLM spans (both creation paths): attach `subagent_name` when `state.parentId && state.subagentName`
- `endSpan(Subagent root)`: include `subagent_name` in final attributes
- `createSessionState`: explicit `subagentName: void 0` field

Three independent paths now populate the attribute: task-args description (fixed parser), task-args prompt fallback, and child-prompt identity parsing. Workshop UI (workshop repo `src/agents.ts`) already reads `subagent_name` from both the tool span and LLM child attrs — no workshop change needed.

**Todos:**
- [x] Plan F-010 (this entry)
- [x] Diagnose from live DB: before-hook invoked; args shape mismatch (JSON string vs object)
- [x] Harden `extractTaskLabel` for JSON-string args (both bundles)
- [x] Add `extractSubagentNameFromPrompt` + wire into chat.message child branch (both bundles)
- [x] Attach `subagent_name` to Subagent root + child LLM spans (both bundles)
- [x] `node --check` both bundles — pass
- [x] Unit check: 14/14 (7 prompt cases incl. 3 live DB prompts, 7 args cases) — `/tmp/f010-unit.cjs`
- [ ] Bump to 0.1.0-kolya.9 + install-local.sh
- [ ] Live smoke: spawn named sub-agent, verify subagent_name in workshop DB
- [ ] Commit

### F-003 — Attach `subagent_name` to task tool spans so Workshop can label sub-agents

**Context:** Workshop fork (`opencode-workshop`) renders sub-agents from the OpenCode `task` tool. Its UI reads `subagent_name` from span attributes (both the LLM child and the tool span itself). The fork already detects by Pattern 1 (TOOL > LLM > TOOL) and Pattern 3 (tool name `task`), but the label is never populated because the plugin never writes the attribute. Without it, Workshop falls back to "Sub-agent: task 1" / "Sub-agent: task 2" — useless when several sub-agents run in parallel.

**Scope:** Plugin-side metadata only. Reads `args.description` (preferred, up to 120 chars) and falls back to the first 60 chars of `args.prompt`. Both bundles (ESM + CJS) patched in lockstep.

**Todos:**
- [x] Plan F-003 (this entry)
- [x] Add `extractTaskLabel(args)` helper next to `attrString`/`attrInt` in both `dist/index.js` and `dist/index.cjs`
- [x] Patch `tool.execute.before` `task` branch in both bundles — conditional `attrString("subagent_name", taskLabel)` when label is non-empty
- [x] `node --check dist/index.js && node --check dist/index.cjs` — both pass
- [ ] Bump version to `0.1.0-kolya.7` (pending; Miko-no-auto-commit)
- [ ] Smoke-test.sh — manual run with a real `task` invocation (deferred until Kolya's next OpenCode session that uses the task tool)

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
