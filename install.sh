#!/bin/sh
# brltools installer — Bedrock-only.
# Copies bin/* to a per-user dir (default: ~/.local/bin, or ~/bin if you
# already have brltools installed there), or to /usr/local/bin (--system).
# Symlinks the result into /usr/local/bin so `sudo <tool>` works either way,
# and ensures python-rich is available.
#
# Usage:
#   ./install.sh                 # per-user install (auto-pick destination)
#   ./install.sh --prefix DIR    # per-user install to a specific dir
#   ./install.sh --system        # system install into /usr/local/bin (sudo)
#   ./install.sh --no-deps       # skip the python-rich install step
#   ./install.sh --help

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS='brldoc brlfetch brlmon brl-erase brltools'

USER_INSTALL=1
INSTALL_DEPS=1
USER_BIN=''
SYS_BIN='/usr/local/bin'

c_cyan='\033[1;36m'
c_green='\033[1;32m'
c_yellow='\033[1;33m'
c_red='\033[1;31m'
c_dim='\033[2m'
c_off='\033[0m'

msg()  { printf "${c_cyan}==>${c_off} %s\n" "$*"; }
ok()   { printf "${c_green} ✓ ${c_off} %s\n" "$*"; }
warn() { printf "${c_yellow} ! ${c_off} %s\n" "$*"; }
err()  { printf "${c_red} ✗ ${c_off} %s\n" "$*" 1>&2; }
dim()  { printf "${c_dim}    %s${c_off}\n" "$*"; }

usage() {
    cat <<EOF
brltools installer

Usage: ./install.sh [--prefix DIR | --system] [--no-deps] [--help]

  --prefix DIR  install into DIR (per-user)
  --user        (default) install per-user. Auto-picks ~/bin if you already
                have brltools there, otherwise ~/.local/bin.
  --system      install directly to /usr/local/bin (needs root)
  --no-deps     skip the python-rich install step
  --help, -h    show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --user)     USER_INSTALL=1; shift ;;
        --system)   USER_INSTALL=0; shift ;;
        --no-deps)  INSTALL_DEPS=0; shift ;;
        --prefix)   USER_BIN="${2:?--prefix needs an argument}"; USER_INSTALL=1; shift 2 ;;
        --prefix=*) USER_BIN="${1#--prefix=}"; USER_INSTALL=1; shift ;;
        --help|-h)  usage; exit 0 ;;
        *)          err "unknown flag: $1"; usage; exit 2 ;;
    esac
done

# Auto-pick the per-user install dir if not set: prefer an existing
# ~/bin install over a fresh ~/.local/bin (avoids stranding an old copy).
if [ -z "$USER_BIN" ]; then
    if [ -f "$HOME/bin/brldoc" ] || [ -f "$HOME/bin/brltools" ]; then
        USER_BIN="$HOME/bin"
    else
        USER_BIN="$HOME/.local/bin"
    fi
fi

# ---------------------------------------------------------------------------
# Bedrock check — refuse to install on non-Bedrock systems
# ---------------------------------------------------------------------------
msg 'Verifying Bedrock Linux…'
if [ ! -d /bedrock ] || [ ! -d /bedrock/cross ] || ! command -v brl >/dev/null 2>&1; then
    err "Not running on Bedrock Linux. brltools is Bedrock-only."
    dim "See https://bedrocklinux.org for installation."
    exit 1
fi
if ! brl version 2>/dev/null | grep -q Bedrock; then
    err "'brl version' did not look like Bedrock."
    exit 1
fi
BEDROCK_VER=$(brl version 2>/dev/null | head -1)
ok "$BEDROCK_VER"

# ---------------------------------------------------------------------------
# python-rich — required by every tool
# ---------------------------------------------------------------------------
ensure_rich() {
    if python3 -c 'import rich' 2>/dev/null; then
        ok 'python-rich already installed'
        return 0
    fi
    msg 'Installing python-rich…'
    INIT_STRATUM=$(brl deref init 2>/dev/null || echo '')
    INSTALLED=0

    # Try the init stratum's pm first (matches the running python3 most often)
    for try in pacman dnf apt-get zypper apk xbps-install emerge; do
        bin_path="/bedrock/strata/${INIT_STRATUM}/usr/bin/${try}"
        [ -n "$INIT_STRATUM" ] && [ -x "$bin_path" ] || continue
        case "$try" in
            pacman)       sudo strat "$INIT_STRATUM" pacman -S --noconfirm python-rich  && INSTALLED=1 ;;
            dnf)          sudo strat "$INIT_STRATUM" dnf -y install python3-rich          && INSTALLED=1 ;;
            apt-get)      sudo strat "$INIT_STRATUM" sh -c 'apt-get update && apt-get install -y python3-rich' && INSTALLED=1 ;;
            zypper)       sudo strat "$INIT_STRATUM" zypper --non-interactive install python3-rich && INSTALLED=1 ;;
            apk)          sudo strat "$INIT_STRATUM" apk add py3-rich                     && INSTALLED=1 ;;
            xbps-install) sudo strat "$INIT_STRATUM" xbps-install -Sy python3-rich        && INSTALLED=1 ;;
            emerge)       sudo strat "$INIT_STRATUM" emerge --quiet dev-python/rich       && INSTALLED=1 ;;
        esac
        [ "$INSTALLED" = 1 ] && break
    done

    if [ "$INSTALLED" = 0 ]; then
        warn "No pm-managed install succeeded — falling back to 'pip install --user rich'."
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install --user --break-system-packages rich 2>/dev/null \
                || pip3 install --user rich
            INSTALLED=1
        elif command -v pip >/dev/null 2>&1; then
            pip install --user --break-system-packages rich 2>/dev/null \
                || pip install --user rich
            INSTALLED=1
        fi
    fi

    if [ "$INSTALLED" = 0 ] || ! python3 -c 'import rich' 2>/dev/null; then
        err "Could not install python-rich. Install it manually then re-run."
        dim "  e.g.  sudo strat <stratum> <pm> install python-rich"
        dim "  or    pip install --user rich"
        exit 1
    fi
    ok 'python-rich ready'
}

if [ "$INSTALL_DEPS" = 1 ]; then
    ensure_rich
else
    dim '(--no-deps) skipping python-rich install'
fi

# ---------------------------------------------------------------------------
# Copy tools
# ---------------------------------------------------------------------------
if [ "$USER_INSTALL" = 1 ]; then
    TARGET="$USER_BIN"
    msg "Installing per-user → $TARGET"
    mkdir -p "$TARGET"
    for t in $TOOLS; do
        cp -f "$SELF_DIR/bin/$t" "$TARGET/$t"
        chmod +x "$TARGET/$t"
        ok "$t → $TARGET/$t"
    done

    case ":$PATH:" in
        *":$TARGET:"*) ;;
        *) warn "$TARGET is not in your \$PATH."
           dim 'add to your shell rc:  export PATH="$HOME/.local/bin:$PATH"' ;;
    esac

    msg "Symlinking into $SYS_BIN (sudo) so 'sudo <tool>' works…"
    for t in $TOOLS; do
        if sudo ln -sf "$TARGET/$t" "$SYS_BIN/$t"; then
            ok "$SYS_BIN/$t → $TARGET/$t"
        else
            warn "could not symlink $SYS_BIN/$t (sudo refused?)"
        fi
    done
else
    if [ "$(id -u)" -ne 0 ]; then
        err '--system install needs root. Re-run with sudo.'
        exit 1
    fi
    TARGET="$SYS_BIN"
    msg "Installing system-wide → $TARGET"
    mkdir -p "$TARGET"
    for t in $TOOLS; do
        cp -f "$SELF_DIR/bin/$t" "$TARGET/$t"
        chmod +x "$TARGET/$t"
        ok "$t → $TARGET/$t"
    done
fi

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------
msg 'Smoke-testing each tool (--run_test → friendly bail panel)…'
PASS=0; FAIL=0
for t in $TOOLS; do
    if [ "$t" = 'brltools' ]; then
        # brltools is bedrock-agnostic — just run it
        if "$TARGET/$t" >/dev/null 2>&1; then
            ok "$t runs"; PASS=$((PASS+1))
        else
            err "$t failed"; FAIL=$((FAIL+1))
        fi
        continue
    fi
    rc=0
    "$TARGET/$t" --run_test >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 2 ]; then
        ok "$t --run_test → exit 2 (expected)"; PASS=$((PASS+1))
    else
        err "$t --run_test → exit $rc (expected 2)"; FAIL=$((FAIL+1))
    fi
done

echo
if [ "$FAIL" = 0 ]; then
    printf "${c_green}All %d tools installed and smoke-tested.${c_off}\n" "$PASS"
    printf "Try:  ${c_cyan}brltools${c_off}\n"
else
    printf "${c_red}%d/%d tools failed — review the output above.${c_off}\n" "$FAIL" "$((PASS+FAIL))"
    exit 1
fi
