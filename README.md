# `@grudanov-nikolay/opencode-workshop-plugin`

Kolya's fork of `@raindrop-ai/opencode-plugin` — the observability plugin for [Raindrop Workshop](https://www.raindrop.ai) that streams OpenCode sessions, events, and spans into the local Workshop daemon on `http://localhost:5899`.

**Why this fork exists:** the upstream plugin crashes on every MCP tool call with `tool.execute.after: result.output is required` (upstream issue [anomalyco/opencode#21149](https://github.com/anomalyco/opencode/issues/21149) — fix PR #21150 was auto-closed 2026-05-15). This fork patches both ESM and CJS bundles to assemble `result.output` from `result.content[]` when missing.

| | |
|---|---|
| **Upstream** | `@raindrop-ai/opencode-plugin@0.0.18` (npm-only, no public git) |
| **This fork** | `@grudanov-nikolay/opencode-workshop-plugin@0.1.0-kolya.3` |
| **Repo** | https://github.com/nikolay-grudanov/opencode-workshop-plugin |
| **License** | MIT |
| **Verified** | A/B smoke test against upstream on `fff_find_files` MCP tool — 0 errors, 2 tool calls landed in Workshop with status=OK |

## Install

```bash
pnpm add @grudanov-nikolay/opencode-workshop-plugin @opencode-ai/plugin
```

If your integration also uses the OpenCode SDK directly, install `@opencode-ai/sdk` as well.

Then add to your project or `~/.config/opencode/opencode.json`:

```json
{
  "plugin": ["@grudanov-nikolay/opencode-workshop-plugin@0.1.0-kolya.3"]
}
```

For per-project `eventName` (so Workshop UI splits runs by project), set:

```json
{
  "local_workshop_url": "http://127.0.0.1:5899/v1",
  "project_id": "support-prod"
}
```

or via env: `RAINDROP_PROJECT_ID=support-prod`.

## Local development

If you're working on the plugin itself, OpenCode 1.17.x loads plugins only from its own cache — `npm link` and `package.json` `file:` references are ignored. Use the install helper:

```bash
git clone https://github.com/nikolay-grudanov/opencode-workshop-plugin.git
cd opencode-workshop-plugin
./scripts/install-local.sh
```

Then add to `~/.config/opencode/opencode.json`:

```json
{
  "plugin": ["@grudanov-nikolay/opencode-workshop-plugin@0.1.0-kolya.3"]
}
```

To pick up code changes after editing `dist/`:

```bash
./scripts/install-local.sh --reinstall   # or just restart OpenCode — symlink is hot
```

## What's different from upstream

1. **MCP `tool.execute.after` fix** — for MCP tool calls (GigaChat via MLProxy, jupyter_executor, anything using MCP), OpenCode passes raw `CallToolResult` (`{content: [{type, text}]}`) instead of the documented `{title, output, metadata}` shape. Upstream throws; this fork assembles `result.output` from `result.content[]` and continues.

2. **Verified against original** — A/B smoke test on real MCP tool: original 0.0.18 produced 2× `result.output is required` errors; this fork produced 0.

3. **Drop-in replacement** — same npm name shape, same OpenCode plugin interface, same event payload format. Just swap the package name in your config.

See [`ai-docs/PLAN.md`](ai-docs/PLAN.md) for the full development plan (F-001 closed, F-002 in progress with install helper, CI smoke test, and prettier reformat).

## Notes

- `@opencode-ai/plugin` is required (peer dependency).
- `@opencode-ai/sdk` is an optional peer dependency.
- The plugin source is in `dist/` (minified bundles). F-002.1 will add section markers; F-003 in the backlog will produce a readable `src/index.ts`.

## License

MIT — same as upstream. See [`LICENSE`](LICENSE).
