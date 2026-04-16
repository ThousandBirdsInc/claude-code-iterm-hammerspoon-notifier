# util-claude-hammerspoon

A small set of scripts that give Claude Code a **centered, clickable, context-rich on-screen notification** whenever a session stops or asks for input, with a global hotkey to jump back to the exact iTerm2 pane the notification came from.

## Why

Running Claude Code in the background, it's easy to miss when a turn finishes or when Claude is blocked on a permission prompt. macOS's native notifications are either inert (`osascript display notification` has no click handler) or fragile (`terminal-notifier` silently drops on macOS 26 Tahoe when posting under another app's bundle id). Instead this uses Hammerspoon's `hs.canvas` to draw a real overlay in the middle of the screen that:

- always renders regardless of notification permissions
- is clickable (or dismissible via hotkey)
- shows *which* Claude session it's from — project, branch, and a short excerpt of the last assistant message
- remembers the session GUID so a single global hotkey jumps you back to the right iTerm2 tab/split, even with multiple Claude sessions running

## Demo

![Demo of Claude Code notification overlay](demo.gif)

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

Multiple notifications queue side-by-side, centered on screen. The most recent (rightmost) panel has a bright orange border; older panels are dimmed. If a new notification arrives for a session that already has a panel, it replaces the existing one instead of duplicating.

Each panel captures mouse clicks and runs `focusItermSession(sid)`, which drives iTerm2 via AppleScript to walk its window/tab/session tree and `select` the session whose `unique id` matches the captured GUID. A global **⇧⌘J** hotkey (bound by Hammerspoon) focuses and dismisses the most recent panel.

Panels persist until you click them or dismiss them with the hotkey — there is no auto-dismiss timeout.

## Files

| File                       | Lives at                              | Purpose                                                                 |
|----------------------------|---------------------------------------|-------------------------------------------------------------------------|
| `claude-notify.sh`         | `~/.claude/scripts/claude-notify.sh`  | Hook entry point — parses stdin JSON, builds context, calls Hammerspoon |
| `focus-iterm-session.sh`   | `~/.claude/scripts/focus-iterm-session.sh` | Standalone AppleScript wrapper to focus an iTerm2 session by GUID    |
| `init.lua`                 | `~/.hammerspoon/init.lua`             | `claudeNotify` canvas renderer + `focusItermSession` + ⇧⌘J hotkey       |
| `install.sh`               | (run from repo)                       | Idempotent installer — copies scripts, merges init.lua, wires hooks     |

## Install

### Quick install (recommended)

```bash
./install.sh
```

The installer is idempotent (safe to re-run) and will:
- Copy scripts to `~/.claude/scripts/`
- Install or append the Hammerspoon config to `~/.hammerspoon/init.lua` (backs up existing files)
- Merge the required hooks into `~/.claude/settings.json` (backs up existing file)
- Reload Hammerspoon if it's running

### Prerequisites

- **Hammerspoon** — `brew install --cask hammerspoon`. Launch it once and grant Accessibility permissions.
- **Hammerspoon CLI (`hs`)** — required so shell scripts can talk to Hammerspoon. Run `hs.ipc.cliInstall()` from Hammerspoon's console, or use Preferences → Advanced → Install Command Line Tool.
- **jq** — `brew install jq` (used to parse hook stdin JSON).

### Post-install

1. **Grant Automation permission** the first time the hotkey/click fires: System Settings → Privacy & Security → Automation → allow Hammerspoon to control iTerm2.
2. Restart any running Claude Code sessions (hook changes are picked up on session start).

### Manual install

If you prefer not to use the installer, see the script for the exact steps — it copies two shell scripts, appends a block to `init.lua`, and merges two hook entries into `settings.json`.

## Usage

Run `claude` inside iTerm2 as normal. When Claude stops or needs input:

- A dark overlay with an orange border appears centered on your main screen. Multiple notifications stack side-by-side.
- **Click a panel** → iTerm2 comes forward and focuses the exact tab/split that notification came from. The panel is dismissed.
- **Press ⇧⌘J from any app** → focuses and dismisses the most recent (rightmost) panel.
- Panels **persist until dismissed** — no auto-timeout.

With multiple concurrent Claude sessions (different tabs, splits, windows), each notification captures that specific session's GUID, so clicking or using the hotkey always jumps to the right session.

## Customization

- **Hotkey:** change the modifiers/key in `init.lua`:
  ```lua
  hs.hotkey.bind({"cmd", "shift"}, "J", function() ... end)
  ```
- **Panel size / spacing:** change `PANEL_W`, `PANEL_H`, `PANEL_GAP` at the top of `init.lua`.
- **Canvas size / colors / font:** all driven by the `c[1]` … `c[7]` element table at the top of `claudeNotify`.
- **Excerpt length:** change `cut -c1-180` in `claude-notify.sh`.
- **Subtitle format:** edit the `PROJECT` / `BRANCH` / `SUBTITLE` section in `claude-notify.sh`. Currently it shows `<repo-basename>[/subpath] · <branch>`.
- **Silent fallback:** the script exits 0 and does nothing if `ITERM_SESSION_ID` is unset (you're not in iTerm2), `hs` is missing, or Hammerspoon isn't running — so hooks never block Claude.

## Caveats

- **iTerm2 only.** `ITERM_SESSION_ID` is the anchor; running `claude` in Terminal.app, Ghostty, or a VS Code terminal makes the hook no-op silently. Porting to other terminals would require a different way to identify and raise a specific pane.
- **macOS only.** The focus mechanism is iTerm2 AppleScript; the overlay is Hammerspoon.
- **Hammerspoon has to be running.** If it's not, the script silently no-ops. Consider adding Hammerspoon to Login Items.
- **`hs.canvas` draws at "overlay" level**, which sits above most app windows but below some system UI (e.g. macOS full-screen transitions). Good enough in practice.
