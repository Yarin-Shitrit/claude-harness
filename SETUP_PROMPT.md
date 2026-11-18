# Setup prompt

Open `claude` inside this repo folder and paste this:

```text
Install the Claude Code harness in this repo into my ~/.claude.

1. Read README.md and install.sh so you know what they change.
2. Run ./install.sh --dry-run, then summarize for me what it will add or change and what it
   will back up. Mention anything already in my ~/.claude that would be overwritten (skills or agents
   with the same names).
3. Ask me which optional groups I want (team, video, extras), then run ./install.sh with the
   matching --no-* flags.
4. Verify: run `claude plugin list` and `claude mcp list`, count the skills in ~/.claude/skills, list
   ~/.claude/agents, and confirm the RTK hook is in ~/.claude/settings.json. Report anything that failed
   with its output.
5. Tell me which env vars I still need to set (GITHUB_PERSONAL_ACCESS_TOKEN, and GITLAB_* if I took
   the team group), and remind me to restart Claude Code.

Don't print or log any tokens.
```
