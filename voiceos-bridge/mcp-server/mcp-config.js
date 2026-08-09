#!/usr/bin/env node
// How a headless `claude -p` agent reaches the crew tools.
//
//   node mcp-config.js            prints the --mcp-config JSON (absolute paths)
//   node mcp-config.js --tools    prints the --allowedTools list
//
// In `direct` mode the agents call crew_gmail_* themselves, which means each
// `claude -p` session needs its OWN MCP connection to this server. Claude Code
// does not find it by magic: without --mcp-config there is no crew tool in the
// session at all, and execution-direct.md tells the agent to "narrate what is
// true and carry on" — so a run with no tools looks exactly like a healthy one.
//
// --mcp-config takes a JSON *string* as well as a file, and that is what this
// prints, deliberately: the server path inside the config resolves against the
// spawning process's cwd, so a committed relative path is only correct from one
// directory. Absolute paths built here are correct from everywhere.
//
//   claude --mcp-config "$(node voiceos-bridge/mcp-server/mcp-config.js)" \
//          --allowedTools "$(node voiceos-bridge/mcp-server/mcp-config.js --tools)" \
//          --strict-mcp-config -p "..."

const { join } = require('node:path');

// The server name is what Claude Code prefixes tool names with, so changing it
// changes ALLOWED_TOOLS too. Keep the two in this one file.
const SERVER_NAME = 'crew';

const TOOLS = [
  'crew_gmail_list_inbox',
  'crew_gmail_archive',
  'crew_gmail_label',
  'crew_calendar_find_slot',
  'crew_calendar_book',
  'crew_calendar_list',
  'crew_send_sms',
  'crew_place_call',
  'crew_ask_user',
];

const config = () => ({
  mcpServers: {
    [SERVER_NAME]: {
      command: process.execPath, // this node, not whatever is on the agent's PATH
      args: [join(__dirname, 'server.js')],
      // CREW_BACKEND is inherited from the orchestrator's environment: fake by
      // default, google when the demo account exists. Nothing to change here.
    },
  },
});

// Three naming schemes exist in this project and they are all different:
//   crew_gmail_archive                     what the tool is called
//   mcp__crew__crew_gmail_archive          how Claude Code names it (--allowedTools)
//   custom_mcp_crew_crew_gmail_archive     how VoiceOS names it (B's finding 2)
// This is the middle one. A's own comment in server.js already uses the
// mcp__<server>__<tool> convention.
const allowedTools = () => TOOLS.map((t) => `mcp__${SERVER_NAME}__${t}`).join(',');

module.exports = { SERVER_NAME, TOOLS, config, allowedTools, json: () => JSON.stringify(config()) };

if (require.main === module) {
  process.stdout.write(process.argv.includes('--tools') ? allowedTools() : JSON.stringify(config()));
}
