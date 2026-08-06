#!/bin/zsh
# Spike #16 — drive Keynote to export a .pptx as PDF.
#
#   usage: ./convert.sh <input.pptx> <output.pdf>
#
# The order of the two steps is the whole finding.
#
#   open via LaunchServices   -> Keynote receives a sandbox extension token
#                                for the file and can read it
#   export via Apple Events   -> Keynote already holds access, so this works
#
# Doing the open over Apple Events instead -- `tell application "Keynote" to
# open POSIX file "..."` -- fails. A bare path carries no sandbox token, so
# Keynote puts up a modal "<name> can't be imported. The file couldn't be
# opened." and the AppleEvent **times out** rather than returning an error.
# A naive implementation therefore hangs for the full timeout and reports
# nothing useful. That is the trap this script exists to document.
#
# -g keeps Keynote off the foreground. Verified: the frontmost application is
# unchanged across a conversion.
set -u

if [[ $# -ne 2 ]]; then
  print -u2 "usage: $0 <input.pptx> <output.pdf>"
  exit 64
fi

IN="$1:A"
OUT="$2:A"
[[ -f "$IN" ]] || { print -u2 "no such file: $IN"; exit 66 }

# How KeynoteDeckLoader.canLoad(_:) should decide availability.
if ! open -Ra Keynote 2>/dev/null; then
  print -u2 "Keynote is not installed — canLoad should return false"
  exit 69
fi

rm -f "$OUT"
open -g -a Keynote "$IN"

# Wait for the document rather than sleeping a guessed interval.
opened=""
for _ in {1..60}; do
  opened=$(osascript -e 'with timeout of 5 seconds
tell application "Keynote"
  if (count of documents) > 0 then return name of front document
  return ""
end tell
end timeout' 2>/dev/null)
  [[ -n "${opened// /}" ]] && break
  /bin/sleep 0.5
done

if [[ -z "${opened// /}" ]]; then
  dialog=$(osascript -e 'tell application "System Events" to tell process "Keynote"
    set t to ""
    try
      repeat with d in (every window whose subrole is "AXDialog")
        repeat with e in (every static text of d)
          set t to t & (value of e as text) & " "
        end repeat
      end repeat
    end try
    return t
  end tell' 2>/dev/null)
  print -u2 "open failed. Keynote dialog: ${dialog:-<none>}"
  exit 70
fi

osascript -e 'with timeout of 300 seconds
tell application "Keynote"
  set d to front document
  set n to count of slides of d
  export d to POSIX file "'"$OUT"'" as PDF
  close d saving no
  return n
end tell
end timeout'
