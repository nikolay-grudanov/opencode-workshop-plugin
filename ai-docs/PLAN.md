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

### F-001 — Fix `tool.execute.after: result.output is required` for MCP tools

**Context:** Upstream plugin 0.0.18 crashes on every MCP tool call because OpenCode passes raw `CallToolResult` (`{content: [{type, text}]}`) to the hook instead of the documented `{title, output, metadata}` shape. Upstream issue [anomalyco/opencode#21149](https://github.com/anomalyco/opencode/issues/21149) will not be fixed (PR #21150 auto-closed 2026-05-15). Symptom: Workshop loses all spans from MCP-using agents (GigaChat 3 Ultra via MLProxy, jupyter_executor, anything using MCP).

**Files to edit (v0.1.0-kolya.1 ships hand-edited dist because src/ not yet reconstructed):**
- `dist/index.js` — line 2143–2147 region (the `if (!("output" in result))` block)
- `dist/index.cjs` — same fix, CJS form
- `package.json` — version bump to `0.1.0-kolya.1`

**Fix sketch:**
```js
// instead of:
//   if (!("output" in result) || result.output === void 0)
//     throw new Error("tool.execute.after: result.output is required");
// use:
let resultOutput = result.output;
if (resultOutput === void 0 && Array.isArray(result.content)) {
  resultOutput = result.content
    .filter(c => c?.type === "text" && typeof c.text === "string")
    .map(c => c.text)
    .join("\n") || "(empty MCP content)";
}
if (resultOutput === void 0) resultOutput = "(no output)";
const toolResult = boundedStringify(resultOutput);
```

**Todos:**
- [x] Extract npm tarball 0.0.18 to working tree
- [x] Init git repo at `nikolay-grudanov/opencode-workshop-plugin`
- [x] Move `package/*` → repo root
- [x] Rewrite `package.json` (scope `@grudanov-nikolay`, version `0.1.0-kolya.1`, add `repository` + `author`)
- [x] Add `AGENTS.md` (this file's companion)
- [x] Add `ai-docs/PLAN.md` (this file)
- [x] Patch `dist/index.js` with the MCP-output fallback (around line 2143–2147) — **v0.1.0-kolya.2**
- [x] Patch `dist/index.cjs` with the same fix — **v0.1.0-kolya.2**
- [x] Syntax check both bundles (CJS via `node --check`, ESM via dynamic import) — both pass
- [ ] Local smoke test: `npm install file:../opencode-workshop-plugin` in a test project, run `opencode run` with an MCP tool, verify no crash
- [ ] Commit + push (with Kolya's explicit go-ahead)
- [ ] Bump version to `0.1.0-kolya.3` after smoke test passes

---

### F-002 — Reverse-engineer / reconstruct `src/index.ts` from `dist/`

**Context:** The dist files are minified bundles — they work, but they're impossible to maintain long-term. We need a readable `src/` so future Kolya (or another agent) can patch the plugin in 5 minutes instead of 30. This is the foundation for all later Features.

**Approach options:**
- A. **AST lift** — use `jscodeshift` or `swc` to convert `dist/index.js` → readable `src/index.ts`. Loses variable names (still minified) but keeps structure.
- B. **Hand rewrite from README + dist reading** — slow but produces a clean, named codebase. Estimated ~6 hours of work for ~85KB of bundled code.
- C. **Wait for upstream to open-source src** — low probability.

**Recommended:** B (hand rewrite, focused on the hooks and core pipeline first).

**Todos:**
- [ ] Decide approach (A / B / C) — needs Kolya input
- [ ] Create `src/index.ts` skeleton with the documented hooks (`tool.execute.after`, `experimental.session.compacting`, `experimental.chat.system.transform`, `chat.message`, `chat.params`, etc.)
- [ ] Wire `tsup` build (copy from upstream `package.json` tsup config we removed)
- [ ] Verify `pnpm build` produces byte-equivalent (or near-equivalent) `dist/`
- [ ] Delete hand-edited `dist/index.{js,cjs}` once `pnpm build` is wired
- [ ] Add `pnpm test` smoke test that boots Workshop daemon and streams a fake event

---

### F-003 — Per-project `eventName` via `RAINDROP_EVENT_METADATA` (hardened)

**Context:** Upstream reads `RAINDROP_EVENT_METADATA` env var (`{userId, eventName, properties}`) to set the per-project `eventName` in Workshop. We use this for `oc-kd` / `oc-diagram` / `oc-notraces` wrapper scripts. **Current problem:** env var may be set shell-wide and leak into the wrong project, and there's no validation of the JSON.

**Plan:**
- Validate `RAINDROP_EVENT_METADATA` is valid JSON; if not, log warning and ignore.
- Strip env var in a dedicated `unset RAINDROP_EVENT_METADATA` line of every wrapper script (already done for `oc-notraces`).
- Document the wrapper script pattern in `README.md`.

**Todos:**
- [ ] Audit `dist/index.js` for where `RAINDROP_EVENT_METADATA` is parsed
- [ ] Add JSON validation + warning on parse failure
- [ ] Update `README.md` with the wrapper pattern (`oc-kd`, `oc-diagram`, `oc-notraces`)
- [ ] Add `examples/wrapper-scripts/` with 3 reference scripts
- [ ] Local test: launch `oc-kd` in a kolya-dashboard-clone dir, verify Workshop UI shows `eventName=kolya-dashboard`

---

### F-004 — `RAINDROP_LOCAL_WORKSHOP_URL` env-var precedence fix

**Context:** Env var unconditionally overrides `raindrop.json` `local_workshop_url`. If a stale env var is set (e.g. from `raindrop workshop setup` adding it to `.env`), Workshop streaming silently breaks.

**Fix sketch (in `resolveLocalWorkshopUrl`, around dist/index.js:1203-1212):**
- If env var is unset → use file value (current behaviour)
- If env var is empty/`null`/`false` → null (disable) (current behaviour)
- If env var matches `http(s)://(localhost|127.0.0.1|0.0.0.0|::1)(:PORT)?/...` → use env value (explicit local opt-in)
- **Otherwise → log warning, fall back to file value**

**Todos:**
- [ ] Patch `resolveLocalWorkshopUrl` in `dist/index.{js,cjs}` (and later `src/`)
- [ ] Add env-var test: set `RAINDROP_LOCAL_WORKSHOP_URL=http://evil.example.com/v1` → verify workshop still streams to local
- [ ] Update CHANGELOG entry

---

## Backlog (not yet started)

- F-005 — Sync with upstream tarball releases (cron: check npm for new `@raindrop-ai/opencode-plugin` versions monthly, dump diff)
- F-006 — Multi-agent trace correlation (link child `task` spans to parent session, see `mapChildSessionToParent` in dist/index.js:1627-1629)
- F-007 — Test coverage: e2e with Workshop daemon + mocked OpenCode
- F-008 — npm publish automation via GitHub Actions on tag push
- F-009 — Replace `package.json` `homepage` and `bugs` URLs once npm package is live

---

## Closed Features

_(none yet — F-001 will land here once all todos are checked)_

---

*Maintained by Miko (Hermes Agent) under Kolya's direction. Update in the same commit as the code change.*
