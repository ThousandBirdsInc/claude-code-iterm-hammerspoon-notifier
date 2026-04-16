#!/bin/bash
TITLE="$1"
DEFAULT_MSG="$2"

SID="${ITERM_SESSION_ID#*:}"
[ -z "$SID" ] && exit 0

MSG="$DEFAULT_MSG"
CWD=""
TRANSCRIPT=""
EXCERPT=""
if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
  STDIN="$(cat)"
  STDIN_MSG="$(printf '%s' "$STDIN" | jq -r '.message // empty' 2>/dev/null)"
  [ -n "$STDIN_MSG" ] && MSG="$STDIN_MSG"
  CWD="$(printf '%s' "$STDIN" | jq -r '.cwd // empty' 2>/dev/null)"
  TRANSCRIPT="$(printf '%s' "$STDIN" | jq -r '.transcript_path // empty' 2>/dev/null)"
fi

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  EXCERPT="$(tail -n 200 "$TRANSCRIPT" 2>/dev/null | jq -rs '
    [.[] | select(.type=="assistant") | .message.content // [] | .[] | select(.type=="text") | .text]
    | last // ""
  ' 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-180)"
fi

[ -z "$CWD" ] && CWD="$PWD"
PROJECT=""
BRANCH=""
if [ -d "$CWD" ]; then
  REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$REPO_ROOT" ]; then
    PROJECT="$(basename "$REPO_ROOT")"
    REL="${CWD#$REPO_ROOT}"
    REL="${REL#/}"
    [ -n "$REL" ] && PROJECT="$PROJECT/$REL"
    BRANCH="$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || git -C "$CWD" rev-parse --short HEAD 2>/dev/null || true)"
  fi
fi
if [ -z "$PROJECT" ]; then
  PROJECT="${CWD/#$HOME/~}"
fi
if [ -n "$BRANCH" ]; then
  SUBTITLE="$PROJECT · $BRANCH"
else
  SUBTITLE="$PROJECT"
fi

HS="$(command -v hs)"
[ -z "$HS" ] && exit 0

esc() { printf "%s" "$1" | sed "s/'/\\\\'/g"; }
T="$(esc "$TITLE")"
M="$(esc "$MSG")"
S="$(esc "$SID")"
SUB="$(esc "$SUBTITLE")"
EX="$(esc "$EXCERPT")"

"$HS" -c "claudeNotify('$T', '$M', '$S', '$SUB', '$EX')" >/dev/null 2>&1 || true
exit 0
