#!/bin/sh
# dev-sync.sh — copy the installed tools from ~/bin (or ~/.local/bin) back
# into this repo's bin/, so edits made in-place can be committed.
#
# Usage:
#   ./dev-sync.sh              # auto-detect source dir
#   ./dev-sync.sh --from DIR   # explicit source dir

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS='brldoc brlfetch brlmon brl-erase brltools'

SRC=''
if [ "${1:-}" = '--from' ]; then
    SRC="${2:?--from needs a directory}"
elif [ -f "$HOME/bin/brldoc" ]; then
    SRC="$HOME/bin"
elif [ -f "$HOME/.local/bin/brldoc" ]; then
    SRC="$HOME/.local/bin"
elif [ -f /usr/local/bin/brldoc ]; then
    SRC='/usr/local/bin'
else
    echo "Could not find an installed brldoc to sync from. Pass --from DIR." >&2
    exit 1
fi

echo "==> Syncing from $SRC → $SELF_DIR/bin"
for t in $TOOLS; do
    if [ ! -f "$SRC/$t" ]; then
        echo "  - $t (missing in $SRC, skipped)"
        continue
    fi
    cp -f "$SRC/$t" "$SELF_DIR/bin/$t"
    chmod +x "$SELF_DIR/bin/$t"
    echo "  ✓ $t"
done
echo "Done. Don't forget to commit."
