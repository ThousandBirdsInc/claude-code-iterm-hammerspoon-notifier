#!/bin/bash
# Installer for util-claude-hammerspoon.
# Idempotent: safe to re-run. Prints what it's doing. Backs up files it modifies.

set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SCRIPTS="$HOME/.claude/scripts"
HS_DIR="$HOME/.hammerspoon"
HS_INIT="$HS_DIR/init.lua"
SETTINGS="$HOME/.claude/settings.json"

say()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!!\033[0m  %s\n" "$*"; }
fail() { printf "\033[1;31mxx\033[0m  %s\n" "$*" >&2; exit 1; }

# --- 1. prerequisites ------------------------------------------------------
say "Checking prerequisites"
[ -d /Applications/Hammerspoon.app ] || fail "Hammerspoon.app not found. Install with: brew install --cask hammerspoon"
command -v hs >/dev/null 2>&1 || warn "'hs' CLI not on PATH. You may need to run hs.ipc.cliInstall() from Hammerspoon's console, or Preferences → Advanced → Install Command Line Tool."
command -v jq >/dev/null 2>&1 || fail "'jq' is required. Install with: brew install jq"

# --- 2. copy scripts -------------------------------------------------------
say "Installing scripts to $CLAUDE_SCRIPTS"
mkdir -p "$CLAUDE_SCRIPTS"
cp "$SRC_DIR/claude-notify.sh"       "$CLAUDE_SCRIPTS/claude-notify.sh"
cp "$SRC_DIR/focus-iterm-session.sh" "$CLAUDE_SCRIPTS/focus-iterm-session.sh"
chmod +x "$CLAUDE_SCRIPTS/claude-notify.sh" "$CLAUDE_SCRIPTS/focus-iterm-session.sh"

# --- 3. install / merge init.lua ------------------------------------------
say "Installing Hammerspoon config"
mkdir -p "$HS_DIR"
MARKER="-- util-claude-hammerspoon"
if [ ! -f "$HS_INIT" ] || [ ! -s "$HS_INIT" ]; then
  cp "$SRC_DIR/init.lua" "$HS_INIT"
  say "Wrote fresh $HS_INIT"
elif grep -q "$MARKER" "$HS_INIT"; then
  say "init.lua already contains util-claude-hammerspoon block — leaving it alone"
  warn "If you want to refresh, delete the block between '$MARKER BEGIN' and '$MARKER END' and re-run."
else
  BACKUP="$HS_INIT.bak.$(date +%s)"
  cp "$HS_INIT" "$BACKUP"
  say "Backed up existing init.lua to $BACKUP"
  {
    printf "\n%s BEGIN\n" "$MARKER"
    cat "$SRC_DIR/init.lua"
    printf "\n%s END\n" "$MARKER"
  } >> "$HS_INIT"
  say "Appended util-claude-hammerspoon block to $HS_INIT"
fi

# --- 4. merge hooks into settings.json -------------------------------------
say "Merging hooks into $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
SETTINGS_BACKUP="$SETTINGS.bak.$(date +%s)"
cp "$SETTINGS" "$SETTINGS_BACKUP"

TMP="$(mktemp)"
jq '
  .hooks = (.hooks // {}) |
  .hooks.Stop = (
    (.hooks.Stop // []) +
    [{"hooks":[{"type":"command","command":"$HOME/.claude/scripts/claude-notify.sh '"'"'Claude Code'"'"' '"'"'Session stopped — click to focus'"'"'"}]}]
    | unique_by(.hooks[0].command)
  ) |
  .hooks.Notification = (
    (.hooks.Notification // []) +
    [{"hooks":[{"type":"command","command":"$HOME/.claude/scripts/claude-notify.sh '"'"'Claude Code — needs input'"'"' '"'"'Permission or input required — click to focus'"'"'"}]}]
    | unique_by(.hooks[0].command)
  )
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
say "Merged hooks (backup: $SETTINGS_BACKUP)"

# --- 5. reload Hammerspoon --------------------------------------------------
if command -v hs >/dev/null 2>&1 && pgrep -x Hammerspoon >/dev/null 2>&1; then
  say "Reloading Hammerspoon"
  hs -c 'hs.reload()' >/dev/null 2>&1 || warn "Reload via hs CLI failed. Reload manually: Hammerspoon menu → Reload Config."
else
  warn "Hammerspoon not running or 'hs' CLI unavailable — start Hammerspoon and reload its config manually."
fi

# --- 6. post-install notes --------------------------------------------------
cat <<'EOF'

Install complete.

Next steps:
  1. First time you click a notification or press ⇧⌘J, macOS will prompt for
     Automation permission for Hammerspoon → iTerm2. Approve it.
  2. Restart any running `claude` sessions so they pick up the new hooks.
  3. Test: run `claude` in iTerm2, trigger Stop or a permission prompt, switch
     away, and watch for the centered overlay.

Uninstall: remove the two scripts in ~/.claude/scripts/, delete the block
between '-- util-claude-hammerspoon BEGIN/END' in ~/.hammerspoon/init.lua
(or restore the .bak), and remove the hooks from ~/.claude/settings.json.
EOF
