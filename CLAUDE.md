# claude-harness

This repo is a distributable Claude Code setup, not an app. `install.sh` copies `skills/`, `agents/` and
`hooks/` into `~/.claude` (or `$CLAUDE_CONFIG_DIR`), installs the plugins in `config/plugins.txt`, and
merges `config/settings.base.json` into the user's settings with `scripts/merge_settings.py`.

- When asked to install, follow SETUP_PROMPT.md: dry-run first, confirm the groups, then install.
- Never write tokens or personal settings (`settings.local.json`, MCP env values) into this repo.
- To test installer changes, run them against a throwaway directory:
  `CLAUDE_CONFIG_DIR=$(mktemp -d) ./install.sh`, never the real `~/.claude`.
- Skill groups are folders under `skills/` (`core`, `team`, `video`, `extras`). To add a skill, drop its
  folder into the right group. To add a plugin, add a `group plugin@marketplace` line to `config/plugins.txt`.
