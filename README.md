# Claude Code harness (shared)

A ready-to-install copy of our Claude Code setup: the plugins, skills, subagents, settings and the
RTK token-saving hook. One script installs it into `~/.claude`. Your existing config is backed up
first and merged, not overwritten.

## Install

```bash
git clone <this-repo-url> ~/claude-harness && cd ~/claude-harness
./install.sh --dry-run   # optional: see what it will do
./install.sh             # takes about 2 minutes, mostly plugin downloads
```

Then quit every running `claude` session and start a new one.

Options: `--no-team`, `--no-video`, `--no-extras`, `--no-rtk`, `--no-plugins`. Run `./install.sh -h` for details.

**Or let Claude do it:** open `claude` in this folder and paste the prompt from [SETUP_PROMPT.md](SETUP_PROMPT.md).

### After installing

| What | Do this |
|---|---|
| GitHub plugin | Add `export GITHUB_PERSONAL_ACCESS_TOKEN=<token>` to `~/.zshrc`. Without it the GitHub MCP fails with "Authorization header is badly formatted". |
| Slack plugin | The first Slack tool call opens an OAuth login in the browser. |
| `gitlab-review` skill | Set `GITLAB_TOKEN`, `GITLAB_HOST`, and `GITLAB_REVIEW_SERVICE_DIR` (path to the review service checkout; ask for it, it isn't published yet). |
| `sanity-check` skill | Needs Docker, Node and the Keep repos checked out locally. |
| Check it worked | In `claude`: `/plugin` lists plugins, `/agents` lists agents, and asking "what skills do you have?" lists the skills. |

## What's inside

### Plugins (installed from their marketplaces, so they stay up to date)

| Plugin | What it gives you |
|---|---|
| **superpowers** | The process layer: brainstorming, writing-plans, executing-plans, subagent-driven-development, dispatching-parallel-agents, test-driven-development, systematic-debugging, requesting/receiving-code-review, verification-before-completion, using-git-worktrees, finishing-a-development-branch, writing-skills |
| **ui-ux-pro-max** | UI/UX design intelligence: styles, palettes, font pairings, UX guidelines, chart types, stack-specific UI |
| **frontend-design** | Art direction for new UI so it doesn't look templated |
| **playwright**, **chrome-devtools-mcp**, **browser-use** | Drive a real browser: screenshots, a11y and LCP debugging, Lighthouse, E2E checks |
| **github**, **slack** | GitHub and Slack MCP tools |
| **claude-md-management** | `/revise-claude-md` and the CLAUDE.md auditor |
| shopify-ai-toolkit *(extras)* | Shopify APIs, themes, functions |

### Skills (copied into `~/.claude/skills`)

| Group | Skills |
|---|---|
| core: UI/UX and skill authoring | `design-taste-frontend` (marketing pages), `redesign-existing-projects`, `web-design-guidelines`, `react-best-practices`, `skill-creator` |
| team | `epic-refiner`, `spec-document`, `docsync`, `sanity-check`, `gitlab-review` |
| video | `hyperframes` + 8 `hyperframes-*` skills, `media-use` |
| extras | `use-railway` |

### Subagents (copied into `~/.claude/agents`)

| Agent | Use it for |
|---|---|
| `planner`, `researcher`, `coder`, `tester`, `reviewer` | Role agents for splitting a big task across subagents. They contain some `mcp__claude-flow__*` snippets, which do nothing unless you install claude-flow. That's harmless. |
| `ui-ux-reviewer` | Read-only UI audit: hierarchy, states, a11y, RTL/Hebrew, responsive widths, charts, token consistency. Reports ranked findings and never edits files. |

### Settings (merged into `~/.claude/settings.json`)

- `model: opus`, `effortLevel: xhigh`, with per-model effort levels
- `permissions.defaultMode: auto`. Your own allow/deny lists are kept as they are.
- `skillListingBudgetFraction: 0.1`, so the long skill list still fits in context
- A few ui-ux-pro-max sub-skills switched off (`design`, `banner-design`, `ui-styling`, `design-system`, `brand`, `slides`)
- The RTK `PreToolUse` hook on Bash, added next to any hooks you already have

### RTK (Rust Token Killer)

`brew install rtk jq` (the installer does this when Homebrew is present). The hook rewrites shell commands
like `git status` into `rtk git status`, which compresses their output and saves 60-90% of tokens on dev
commands. `rtk gain` shows how much it has saved. To bypass it for one command, use `rtk proxy <cmd>`.

## How we work with it

The skills fire on their own when the task matches. You can also call one by name, like `/brainstorming`.

**Building a feature**
1. `superpowers:brainstorming`: turns the idea into a spec by asking one question at a time. Use it before any new work.
2. `superpowers:writing-plans`: turns the spec into small, testable tasks.
3. `superpowers:using-git-worktrees`: gives the work an isolated branch.
4. `superpowers:subagent-driven-development`: one fresh subagent per task, with a review between tasks. Use `executing-plans` if you'd rather implement it yourself in the session.
5. `superpowers:test-driven-development` during the work, then `superpowers:systematic-debugging` when something breaks.
6. `superpowers:requesting-code-review`, then `superpowers:verification-before-completion`: no "done" without evidence.
7. `superpowers:finishing-a-development-branch`: merge, open a PR, or clean up.

**Coordinating agents:** `superpowers:dispatching-parallel-agents` for independent work in parallel, and the
role agents above as the workers.

**UI work:** `brainstorming`, then `frontend-design` / `ui-ux-pro-max` for product UI (or `design-taste-frontend`
for marketing pages), then the `ui-ux-reviewer` agent and `web-design-guidelines` for an audit, and
`chrome-devtools-mcp:a11y-debugging` for accessibility.

**Writing your own skills:** `skill-creator` (with evals) or `superpowers:writing-skills`.

**Team docs:** `spec-document` for design docs, `epic-refiner` to get an epic ready, `docsync` for code-to-docs sync.

## Not included, on purpose

- **Credentials and tokens.** No MCP tokens, no GitHub PAT, no `settings.local.json`. Use your own.
- **Personal tooling.** The status line and notification hooks, memory, history and per-project settings.
- **Skills that come with your claude.ai account** (`docs`, `pdf`, `xlsx`, `pptx`, `deep-research` and others).
  They sync automatically when you log in with the same org.
- **Skills and agents we keep switched off** (the claude-flow swarm/sparc set and the Vercel deploy skills).

## Update or roll back

- **Update:** `git pull && ./install.sh`. Plugins update through `/plugin`. The vendored skills come from
  `heygen-com/hyperframes` (hyperframes, media-use), `Leonxlnx/taste-skill` (design-taste-frontend,
  redesign-existing-projects), `vercel-labs/agent-skills` (react-best-practices, web-design-guidelines) and
  `anthropics/skills` (skill-creator).
- **Roll back:** every run writes `~/.claude/backups/harness-share-<timestamp>.tgz`. Restore it with
  `tar -xzf <file> -C ~/.claude`.
