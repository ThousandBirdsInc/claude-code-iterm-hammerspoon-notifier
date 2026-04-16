#!/bin/bash
GUID="$1"
[ -z "$GUID" ] && exit 0

/usr/bin/osascript <<EOF
tell application "iTerm2"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if (unique id of s as string) is "$GUID" then
          select w
          select t
          select s
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
EOF
