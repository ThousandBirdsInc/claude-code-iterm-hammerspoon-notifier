# util-claude-hammerspoon

A small set of scripts that give Claude Code a **centered, clickable, context-rich on-screen notification** whenever a session stops or asks for input, with a global hotkey to jump back to the exact iTerm2 pane the notification came from.

## Why

Running Claude Code in the background, it's easy to miss when a turn finishes or when Claude is blocked on a permission prompt. macOS's native notifications are either inert (`osascript display notification` has no click handler) or fragile (`terminal-notifier` silently drops on macOS 26 Tahoe when posting under another app's bundle id). Instead this uses Hammerspoon's `hs.canvas` to draw a real overlay in the middle of the screen that:

- always renders regardless of notification permissions
- is clickable (or dismissible via hotkey)
- shows *which* Claude session it's from — project, branch, and a short excerpt of the last assistant message
- remembers the session GUID so a single global hotkey jumps you back to the right iTerm2 tab/split, even with multiple Claude sessions running

## How it works

Claude Code fires two hooks we care about:

| Event          | When it fires                                                                 |
|----------------|-------------------------------------------------------------------------------|
| `Stop`         | Claude finishes a turn (done, awaiting your next prompt)                      |
| `Notification` | Claude raises a user-facing notification — permission prompts, idle waits     |

Both hooks run `claude-notify.sh`, which:

1. Reads the hook's stdin JSON and extracts `message`, `cwd`, and `transcript_path`.
2. Captures `ITERM_SESSION_ID` (inherited from the iTerm2 shell) and strips the `w0t5p1:` prefix, leaving iTerm2's session GUID.
3. Derives a subtitle: `<repo-basename>[/subpath] · <branch>` if inside a git repo, otherwise `~/abbreviated/path`.
4. Extracts the last assistant text message from the JSONL transcript (via `jq`) and truncates it to ~180 chars as an excerpt.
5. Calls the Hammerspoon CLI: `hs -c "claudeNotify(title, msg, sid, subtitle, excerpt)"`.

Inside Hammerspoon, `claudeNotify` draws a centered `hs.canvas` overlay with:
- title (orange) — e.g. *"Claude Code — needs input"*
- subtitle (blue) — e.g. *"thousand-birds-landing · main"*
- message (white) — e.g. *"Claude needs your permission to use Bash"*
- excerpt (dim) — the last thing Claude said
- hint row — *"⇧⌘J to focus · click to focus"*

The canvas captures mouse clicks and runs `focusItermSession(sid)`, which drives iTerm2 via AppleScript to walk its window/tab/session tree and `select` the session whose `unique id` matches the captured GUID. The canvas also stores the sid in `_lastClaudeSid`, so a global **⇧⌘J** hotkey (bound by Hammerspoon) does the same focus action from any app.

Auto-dismisses after 8 seconds if you ignore it.

## Files

| File                       | Lives at                              | Purpose                                                                 |
|----------------------------|---------------------------------------|-------------------------------------------------------------------------|
| `claude-notify.sh`         | `~/.claude/scripts/claude-notify.sh`  | Hook entry point — parses stdin JSON, builds context, calls Hammerspoon |
| `focus-iterm-session.sh`   | `~/.claude/scripts/focus-iterm-session.sh` | Standalone AppleScript wrapper to focus an iTerm2 session by GUID    |
| `init.lua`                 | `~/.hammerspoon/init.lua`             | `claudeNotify` canvas renderer + `focusItermSession` + ⇧⌘J hotkey       |

## Install

1. **Install Hammerspoon** if you don't have it: `brew install --cask hammerspoon`. Launch it once and grant Accessibility permissions.
2. **Enable the Hammerspoon CLI** — it's required so shell scripts can send commands to the running Hammerspoon process. `init.lua` already calls `require("hs.ipc")`, but you may need to run `hs -c 'hs.ipc.cliInstall()'` once (or use Hammerspoon's menu: Preferences → Advanced → Install Command Line Tool).
3. **Copy the scripts into place:**
   ```bash
   mkdir -p ~/.claude/scripts
   cp claude-notify.sh focus-iterm-session.sh ~/.claude/scripts/
   chmod +x ~/.claude/scripts/claude-notify.sh ~/.claude/scripts/focus-iterm-session.sh
   cp init.lua ~/.hammerspoon/init.lua   # or merge into your existing init.lua
   ```
   Then reload Hammerspoon (menu bar → Reload Config, or restart the app).
4. **Grant Automation permission** the first time the hotkey/click fires: System Settings → Privacy & Security → Automation → allow Hammerspoon to control iTerm2.
5. **Wire the hooks** into `~/.claude/settings.json` (merge with whatever is already there):
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "$HOME/.claude/scripts/claude-notify.sh 'Claude Code' 'Session stopped — click to focus'"
             }
           ]
         }
       ],
       "Notification": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "$HOME/.claude/scripts/claude-notify.sh 'Claude Code — needs input' 'Permission or input required — click to focus'"
             }
           ]
         }
       ]
     }
   }
   ```
6. Restart any running Claude Code sessions (hook changes are picked up on session start).

## Usage

Run `claude` inside iTerm2 as normal. When Claude stops or needs input:

- A dark overlay with an orange border appears centered on your main screen.
- **Click it** → iTerm2 comes forward and focuses the exact tab/split the notification came from.
- **Press ⇧⌘J from any app** → same thing, no mouse needed.
- **Ignore it** → auto-dismisses after 8 seconds.

With multiple concurrent Claude sessions (different tabs, splits, windows), each notification captures that specific session's GUID, so the hotkey always jumps to the most-recently-notifying session.

## Customization

- **Hotkey:** change the modifiers/key in `init.lua`:
  ```lua
  hs.hotkey.bind({"cmd", "shift"}, "J", function() ... end)
  ```
- **Auto-dismiss timeout:** change `hs.timer.doAfter(8, dismiss)` in `init.lua`.
- **Canvas size / colors / font:** all driven by the `c[1]` … `c[7]` element table at the top of `claudeNotify`.
- **Excerpt length:** change `cut -c1-180` in `claude-notify.sh`.
- **Subtitle format:** edit the `PROJECT` / `BRANCH` / `SUBTITLE` section in `claude-notify.sh`. Currently it shows `<repo-basename>[/subpath] · <branch>`.
- **Silent fallback:** the script exits 0 and does nothing if `ITERM_SESSION_ID` is unset (you're not in iTerm2), `hs` is missing, or Hammerspoon isn't running — so hooks never block Claude.

## Caveats

- **iTerm2 only.** `ITERM_SESSION_ID` is the anchor; running `claude` in Terminal.app, Ghostty, or a VS Code terminal makes the hook no-op silently. Porting to other terminals would require a different way to identify and raise a specific pane.
- **macOS only.** The focus mechanism is iTerm2 AppleScript; the overlay is Hammerspoon.
- **Hammerspoon has to be running.** If it's not, the script silently no-ops. Consider adding Hammerspoon to Login Items.
- **`hs.canvas` draws at "overlay" level**, which sits above most app windows but below some system UI (e.g. macOS full-screen transitions). Good enough in practice.
# claude-code-iterm-hammerspoon-notifier
