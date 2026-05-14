#!/bin/sh
# brltools uninstaller — removes the 5 scripts from ~/.local/bin and the
# /usr/local/bin symlinks (or the system-installed copies, if any).
# Leaves python-rich in place.

set -eu

TOOLS='brldoc brlfetch brlmon brl-erase brltools'
USER_BIN="${HOME}/.local/bin"
SYS_BIN='/usr/local/bin'
LEGACY_BIN="${HOME}/bin"

c_cyan='\033[1;36m'
c_green='\033[1;32m'
c_yellow='\033[1;33m'
c_red='\033[1;31m'
c_off='\033[0m'

msg()  { printf "${c_cyan}==>${c_off} %s\n" "$*"; }
ok()   { printf "${c_green} ✓ ${c_off} %s\n" "$*"; }
warn() { printf "${c_yellow} ! ${c_off} %s\n" "$*"; }
err()  { printf "${c_red} ✗ ${c_off} %s\n" "$*" 1>&2; }

REMOVED=0; SKIPPED=0

msg 'Removing brltools from common install locations…'

for t in $TOOLS; do
    for dir in "$USER_BIN" "$SYS_BIN" "$LEGACY_BIN"; do
        target="$dir/$t"
        [ -e "$target" ] || [ -L "$target" ] || continue
        # /usr/local/bin needs root to write
        if [ "$dir" = "$SYS_BIN" ] && [ "$(id -u)" -ne 0 ]; then
            if sudo rm -f -- "$target"; then
                ok "removed $target (sudo)"; REMOVED=$((REMOVED+1))
            else
                warn "could not remove $target (sudo refused?)"; SKIPPED=$((SKIPPED+1))
            fi
        else
            if rm -f -- "$target"; then
                ok "removed $target"; REMOVED=$((REMOVED+1))
            else
                warn "could not remove $target"; SKIPPED=$((SKIPPED+1))
            fi
        fi
    done
done

echo
if [ "$REMOVED" = 0 ]; then
    warn 'Nothing to remove — brltools is not installed in any known location.'
else
    printf "${c_green}Removed %d file(s).${c_off}" "$REMOVED"
    if [ "$SKIPPED" -gt 0 ]; then
        printf " ${c_yellow}(%d skipped)${c_off}" "$SKIPPED"
    fi
    echo
    echo 'python-rich was NOT removed (other tools may need it).'
fi
