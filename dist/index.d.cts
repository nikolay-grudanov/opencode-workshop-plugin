import { PluginInput, Hooks } from '@opencode-ai/plugin';

/**
 * Raindrop plugin for OpenCode.
 *
 * Automatically traces every coding session — messages, tool calls, and LLM
 * completions — to your Raindrop dashboard.
 *
 * Setup:
 *   1. Add "@raindrop-ai/opencode-plugin" to the "plugin" array in opencode.json
 *   2. Set RAINDROP_WRITE_KEY in your environment
 *
 * Optional config file: ~/.config/opencode/raindrop.json or .opencode/raindrop.json
 */
declare function plugin(input: PluginInput): Promise<Hooks>;

export { plugin as default };
