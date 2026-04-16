-- Hammerspoon config

require("hs.ipc")

function focusItermSession(sid)
  if not sid or sid == "" then return end
  local script = string.format([[
tell application "iTerm2"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if (unique id of s as string) is "%s" then
          select w
          select t
          select s
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
]], sid)
  hs.osascript.applescript(script)
end

-- notification queue: each entry = { title, msg, sid, subtitle, excerpt, canvas, timer }
_claudeNotifyQueue = {}

local PANEL_W = 420
local PANEL_H = 230
local PANEL_GAP = 16
-- no auto-dismiss: panels stay until clicked or ⇧⌘J

local function renderAllPanels()
  local count = #_claudeNotifyQueue
  if count == 0 then return end

  local screen = hs.screen.mainScreen():frame()
  local totalW = count * PANEL_W + (count - 1) * PANEL_GAP
  local startX = screen.x + (screen.w - totalW) / 2
  local startY = screen.y + (screen.h - PANEL_H) / 2

  for i, entry in ipairs(_claudeNotifyQueue) do
    if entry.canvas then
      entry.canvas:delete()
      entry.canvas = nil
    end

    local isActive = (i == count)
    local x = startX + (i - 1) * (PANEL_W + PANEL_GAP)
    local dim = isActive and 1.0 or 0.45

    local c = hs.canvas.new({ x = x, y = startY, w = PANEL_W, h = PANEL_H })
      :level("overlay")
      :behavior({"canJoinAllSpaces"})

    local borderColor = isActive
      and { red = 1, green = 0.6, blue = 0.1, alpha = 0.9 }
      or  { white = 0.35, alpha = 0.6 }

    c[1] = {
      type = "rectangle",
      action = "fill",
      fillColor = { red = 0.05, green = 0.05, blue = 0.08, alpha = isActive and 0.94 or 0.82 },
      roundedRectRadii = { xRadius = 16, yRadius = 16 },
    }
    c[2] = {
      type = "rectangle",
      action = "stroke",
      strokeColor = borderColor,
      strokeWidth = isActive and 2.5 or 1.5,
      roundedRectRadii = { xRadius = 16, yRadius = 16 },
    }
    c[3] = {
      type = "text",
      text = entry.title,
      textColor = { red = 1 * dim, green = 0.75 * dim, blue = 0.2 * dim, alpha = 1 },
      textSize = 18,
      textAlignment = "center",
      frame = { x = 16, y = 14, w = PANEL_W - 32, h = 26 },
    }
    c[4] = {
      type = "text",
      text = entry.subtitle,
      textColor = { red = 0.55 * dim, green = 0.78 * dim, blue = 1 * dim, alpha = 1 },
      textSize = 12,
      textAlignment = "center",
      frame = { x = 16, y = 42, w = PANEL_W - 32, h = 16 },
    }
    c[5] = {
      type = "text",
      text = entry.msg,
      textColor = { white = 1, alpha = dim },
      textSize = 13,
      textAlignment = "center",
      frame = { x = 16, y = 62, w = PANEL_W - 32, h = 20 },
    }
    c[6] = {
      type = "text",
      text = entry.excerpt,
      textColor = { white = 0.8, alpha = dim },
      textSize = 11,
      textAlignment = "left",
      frame = { x = 18, y = 88, w = PANEL_W - 36, h = 100 },
    }

    local hintText = isActive
      and "⇧⌘J to focus  ·  click to focus"
      or "click to focus"
    c[7] = {
      type = "text",
      text = hintText,
      textColor = { white = 0.5, alpha = dim },
      textSize = 10,
      textAlignment = "center",
      frame = { x = 16, y = PANEL_H - 22, w = PANEL_W - 32, h = 14 },
    }

    local idx = i
    c:canvasMouseEvents(true, true, false, false)
    c:mouseCallback(function(canvas, event, id, mx, my)
      if event == "mouseUp" then
        dismissPanel(idx)
        focusItermSession(entry.sid)
      end
    end)

    c:show()
    entry.canvas = c
  end
end

function dismissPanel(index)
  local entry = _claudeNotifyQueue[index]
  if not entry then return end
  if entry.timer then entry.timer:stop() end
  if entry.canvas then entry.canvas:delete() end
  table.remove(_claudeNotifyQueue, index)
  renderAllPanels()
end

function dismissAllPanels()
  for _, entry in ipairs(_claudeNotifyQueue) do
    if entry.timer then entry.timer:stop() end
    if entry.canvas then entry.canvas:delete() end
  end
  _claudeNotifyQueue = {}
end

function claudeNotify(title, msg, sid, subtitle, excerpt)
  subtitle = subtitle or ""
  excerpt = excerpt or ""

  -- if this sid already has a panel, update it instead of adding a duplicate
  for i, entry in ipairs(_claudeNotifyQueue) do
    if entry.sid == sid then
      if entry.timer then entry.timer:stop() end
      if entry.canvas then entry.canvas:delete() end
      table.remove(_claudeNotifyQueue, i)
      break
    end
  end

  local entry = {
    title = title,
    msg = msg,
    sid = sid,
    subtitle = subtitle,
    excerpt = excerpt,
    canvas = nil,
    timer = nil,
  }

  table.insert(_claudeNotifyQueue, entry)
  renderAllPanels()

  entry.timer = nil
end

-- ⇧⌘J: focus the most recent (rightmost) panel's session
hs.hotkey.bind({"cmd", "shift"}, "J", function()
  local count = #_claudeNotifyQueue
  if count == 0 then return end
  local entry = _claudeNotifyQueue[count]
  dismissPanel(count)
  focusItermSession(entry.sid)
end)
