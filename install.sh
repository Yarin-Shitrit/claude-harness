#!/usr/bin/env bash
# Installs the shared Claude Code harness into ~/.claude (or $CLAUDE_CONFIG_DIR).
# Safe to re-run: it backs up what it touches and merges settings instead of overwriting them.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKIP=""
DRY=0
NO_RTK=0
NO_PLUGINS=0
ENABLED=""
FAILED=""

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --no-team      skip team skills (epic-refiner, spec-document, docsync, sanity-check, gitlab-review)
  --no-video     skip the video skills (hyperframes-*, media-use)
  --no-extras    skip extras (use-railway skill, Shopify plugin + MCP, Railway MCP)
  --no-rtk       skip the RTK token-saving hook
  --no-plugins   skip marketplace and plugin installs
  --dry-run      print what would happen, change nothing
  -h, --help     show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-team|--no-video|--no-extras) SKIP="$SKIP ${1#--no-}" ;;
    --no-rtk) NO_RTK=1 ;;
    --no-plugins) NO_PLUGINS=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
want() { case " $SKIP " in *" $1 "*) return 1 ;; *) return 0 ;; esac; }
run()  { if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

# ---------------------------------------------------------------- preflight
say "Preflight"
command -v claude >/dev/null || { echo "Claude Code CLI not found. Install it first: https://claude.com/claude-code"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required (xcode-select --install)."; exit 1; }
ok "claude $(claude --version 2>/dev/null | head -1)"
ok "config dir: $CLAUDE_DIR"

if [ "$NO_RTK" = 0 ]; then
  missing=""
  command -v rtk >/dev/null || missing="$missing rtk"
  command -v jq  >/dev/null || missing="$missing jq"
  if [ -n "$missing" ]; then
    if command -v brew >/dev/null; then
      echo "  installing with Homebrew:$missing"
      run brew install $missing || { warn "brew install failed, skipping the RTK hook"; NO_RTK=1; }
    else
      warn "missing:$missing and no Homebrew. Skipping the RTK hook (see https://github.com/rtk-ai/rtk)."
      NO_RTK=1
    fi
  fi
  [ "$NO_RTK" = 0 ] && [ "$DRY" = 0 ] && ok "$(rtk --version)"
fi

# ---------------------------------------------------------------- backup
say "Backup"
run mkdir -p "$CLAUDE_DIR/backups"
BACKUP="$CLAUDE_DIR/backups/harness-share-$(date +%Y%m%d-%H%M%S).tgz"
items=""
for i in settings.json CLAUDE.md RTK.md agents skills hooks; do
  [ -e "$CLAUDE_DIR/$i" ] && items="$items $i"
done
if [ -n "$items" ]; then
  run tar -czf "$BACKUP" -C "$CLAUDE_DIR" --exclude 'skills/synced' --exclude 'skills/.trash' $items
  ok "backed up:$items -> $BACKUP"
else
  ok "nothing to back up (fresh config)"
fi

# ---------------------------------------------------------------- plugins
if [ "$NO_PLUGINS" = 0 ]; then
  say "Plugin marketplaces"
  for m in anthropics/claude-plugins-official anthropics/claude-code nextlevelbuilder/ui-ux-pro-max-skill; do
    if run claude plugin marketplace add "$m" </dev/null >/dev/null 2>&1; then ok "$m"; else ok "$m (already added)"; fi
  done

  say "Plugins"
  while read -r group plugin <&3; do
    case "$group" in ''|'#'*) continue ;; esac
    want "$group" || continue
    if run claude plugin install "$plugin" -s user </dev/null >/dev/null 2>&1; then
      ok "$plugin"
    else
      warn "$plugin failed to install, retry later with: claude plugin install $plugin -s user"
      FAILED="$FAILED $plugin"
    fi
    ENABLED="$ENABLED $plugin"
  done 3< "$REPO/config/plugins.txt"
fi

# ---------------------------------------------------------------- skills
say "Skills -> $CLAUDE_DIR/skills"
run mkdir -p "$CLAUDE_DIR/skills"
for group in core team video extras; do
  want "$group" || { ok "skipped group: $group"; continue; }
  names=""
  for d in "$REPO/skills/$group"/*/; do
    name="$(basename "$d")"
    if [ "$DRY" = 0 ]; then
      rm -rf "$CLAUDE_DIR/skills/$name"
      cp -R "${d%/}" "$CLAUDE_DIR/skills/$name"
    fi
    names="$names $name"
  done
  ok "$group:$names"
done

# ---------------------------------------------------------------- agents
say "Agents -> $CLAUDE_DIR/agents"
run mkdir -p "$CLAUDE_DIR/agents"
run cp -R "$REPO/agents/." "$CLAUDE_DIR/agents/"
ok "coder, planner, researcher, reviewer, tester, ui-ux-reviewer"

# ---------------------------------------------------------------- RTK + CLAUDE.md
if [ "$NO_RTK" = 0 ]; then
  say "RTK hook + global CLAUDE.md"
  run mkdir -p "$CLAUDE_DIR/hooks"
  run rm -f "$CLAUDE_DIR/hooks/rtk-rewrite.sh" "$CLAUDE_DIR/hooks/.rtk-hook.sha256"
  run cp "$REPO/hooks/rtk-rewrite.sh" "$REPO/hooks/.rtk-hook.sha256" "$CLAUDE_DIR/hooks/"
  run chmod +x "$CLAUDE_DIR/hooks/rtk-rewrite.sh"
  run cp "$REPO/config/RTK.md" "$CLAUDE_DIR/RTK.md"
  if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    run cp "$REPO/config/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  elif ! grep -qx '@RTK.md' "$CLAUDE_DIR/CLAUDE.md"; then
    [ "$DRY" = 1 ] && echo "  [dry-run] append @RTK.md to $CLAUDE_DIR/CLAUDE.md" \
                   || printf '\n@RTK.md\n' >> "$CLAUDE_DIR/CLAUDE.md"
  fi
  ok "hook at $CLAUDE_DIR/hooks/rtk-rewrite.sh, @RTK.md in CLAUDE.md"
fi

# ---------------------------------------------------------------- settings
say "Settings -> $CLAUDE_DIR/settings.json"
merge_args=("$REPO/config/settings.base.json" "$CLAUDE_DIR/settings.json" --rtk-hook "$CLAUDE_DIR/hooks/rtk-rewrite.sh")
[ "$NO_RTK" = 1 ] && merge_args+=(--no-rtk)
# shellcheck disable=SC2206
[ -n "$ENABLED" ] && merge_args+=(--enable $ENABLED)
if [ "$DRY" = 1 ]; then
  preview="${TMPDIR:-/tmp}/harness-settings-preview.json"
  python3 "$REPO/scripts/merge_settings.py" "${merge_args[@]}" --dry-run > "$preview"
  echo "  [dry-run] merged settings preview: $preview"
else
  python3 "$REPO/scripts/merge_settings.py" "${merge_args[@]}"
fi

# ---------------------------------------------------------------- extra MCP servers
if want extras && [ "$NO_PLUGINS" = 0 ]; then
  say "Extra MCP servers"
  if claude mcp get shopify-dev-mcp </dev/null >/dev/null 2>&1; then
    ok "shopify-dev-mcp (already configured)"
  else
    run claude mcp add -s user shopify-dev-mcp -- npx -y @shopify/dev-mcp@latest </dev/null >/dev/null 2>&1 \
      && ok "shopify-dev-mcp" || warn "shopify-dev-mcp failed"
  fi
  if command -v railway >/dev/null; then
    claude mcp get railway </dev/null >/dev/null 2>&1 && ok "railway (already configured)" || {
      run claude mcp add -s user railway -- railway mcp </dev/null >/dev/null 2>&1 && ok "railway" || warn "railway MCP failed"; }
  else
    ok "railway MCP skipped (no railway CLI; brew install railway to add it later)"
  fi
fi

# ---------------------------------------------------------------- done
say "Done"
[ -n "$FAILED" ] && warn "plugins that failed:$FAILED"
cat <<EOF

Next steps
  1. Restart Claude Code (quit every running session) so the new skills, agents and hooks load.
  2. GitHub plugin: export GITHUB_PERSONAL_ACCESS_TOKEN=<your token> in ~/.zshrc
  3. Slack plugin: the first Slack tool call opens an OAuth login in the browser.
  4. Team skills that need env vars:
       gitlab-review : GITLAB_TOKEN, GITLAB_HOST, GITLAB_REVIEW_SERVICE_DIR
       sanity-check  : Docker + Node, the Keep repos checked out locally
  5. Check it: run 'claude', then /plugin (installed plugins) and /agents (custom agents).
     Ask "what skills do you have?" to see the full list.
EOF
[ -n "$items" ] && echo "Your previous config is backed up in: $BACKUP"
