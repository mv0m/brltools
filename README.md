# brltools

A small toolset of Bedrock Linux–specific utilities. Five Python/rich scripts
that fill gaps the upstream Bedrock CLI doesn't:

| Tool        | Role                   | What it does                                                                 |
| ----------- | ---------------------- | ---------------------------------------------------------------------------- |
| `brldoc`    | audit & auto-fix       | Health-checks every Bedrock breakage point (strata, systemd, dbus, `.desktop` paths, pinning, `/etc`, orphans, updates, bootloader) and offers auto-fixes. |
| `brlfetch`  | fastfetch-style info   | Bedrock-exclusive system summary — strata + pkg counts, hijacked-from distro, bootloader, disk. JSON output for status bars.    |
| `brlmon`    | process monitor        | Live htop-style TUI with a `STRATUM` column — see which Bedrock stratum each process came from.                                 |
| `brl-erase` | fuzzy package remover  | Cross-stratum fuzzy package removal — `brl-erase chrome` finds and deletes every `chrome*` match in any stratum, with a triple-confirm for kernel/boot/libc names. |
| `brltools`  | index                  | This list, printable on demand. Run `brltools` with no args.                 |

All five refuse to run on non-Bedrock systems with a friendly bail panel.

---

## Install

```sh
git clone https://github.com/mv0m/brltools.git
cd brltools
./install.sh
```

The installer:
1. Verifies you're running Bedrock Linux (5-signal check — same one the tools themselves use).
2. Installs `python-rich` via your init stratum's package manager, falling back to `pip install --user rich` if no pm match.
3. Copies the five scripts to `~/.local/bin/` (default) and symlinks them into `/usr/local/bin/` via `sudo` so `sudo <tool>` keeps working.
4. Smoke-tests each tool via the hidden `--run_test` bail-out path.

Flags:

| Flag         | Behavior                                                                              |
| ------------ | ------------------------------------------------------------------------------------- |
| `--user`     | (default) Install to `~/.local/bin`, symlink into `/usr/local/bin`.                   |
| `--system`   | Install directly to `/usr/local/bin` (run with sudo).                                 |
| `--no-deps`  | Skip the `python-rich` install — useful if you manage Python deps yourself.           |
| `--help`     | Show usage.                                                                           |

## Uninstall

```sh
./uninstall.sh
```

Removes the five scripts from `~/.local/bin`, `~/bin`, and `/usr/local/bin`.
Leaves `python-rich` alone (other tools may use it).

---

## Requirements

- **Bedrock Linux** ≥ 0.7.x. All five tools 5-signal-check the host and bail otherwise.
- **Python ≥ 3.7** (uses `from __future__ import annotations` for older versions; tested through 3.13).
- **`python-rich`** — installed by `install.sh`.
- The active stratum needs basic CLI tools (`brl`, `strat`, `getent`, `systemctl`, `dbus-send`, `efibootmgr`). Stock Bedrock + a typical hijacked distro stratum has all of these.

---

## Tool docs

### `brldoc` — health audit & auto-fix

```sh
brldoc                 # run every check, prompt before each fix
brldoc -y              # auto-apply every fix (also auto-elevates)
brldoc --check         # read-only; show findings, do not fix
brldoc --only desktop  # audit only one category
brldoc --list          # list all available checks
brldoc -U              # skip checks, just update every stratum's packages
brldoc --deep          # add slow per-stratum package-integrity scans (sudo)
```

Checks cover:

- **strata health** (`brl status`, auto-fix with `brl repair`)
- **PID 1 systemd hang** (Bedrock-specific `do_wait` signature in `/proc/1/stack`)
- **systemd --user / --system** state + failed units
- **D-Bus** session + system bus reachability
- **XDG runtime dir** ownership and critical sockets
- **Cross-stratum /etc** — does `getent passwd <user>` resolve from every stratum?
- **Pinned binaries** in `/bedrock/cross/pin/bin`
- **Bootloader** — flags GRUB residue when systemd-boot is active (Bedrock prefers systemd-boot)
- **Duplicate packages** — detects when the same user-facing binary is installed in multiple strata; offers a simulation-aware removal of the routing loser
- **Desktop entries** — every `.desktop` Exec path; auto-rewrites stratum-broken ones via XDG user override
- **Orphaned packages** per stratum (`pacman -Qdtq`, `dnf --unneeded`, `apt autoremove`, `zypper unneeded`, `xbps -O`)
- **Pending updates** per stratum

Update flow has a per-stratum progress bar with phase labels (downloading/installing/verifying/…) and surfaces known-but-harmless errors (e.g. `grub2-editenv` failures on systemd-boot hosts) so users aren't scared by output that is expected.

### `brlfetch` — system summary

```sh
brlfetch         # full panel: logo + OS + hijacked-from + strata + pkg counts + bootloader + cpu/gpu/mem/disk
brlfetch -m      # compact 5-field view (good for shell-startup)
brlfetch -j      # machine-readable JSON (for status bars / dashboards)
```

`brlfetch -m` is fast enough (~80 ms) for a `~/.zshrc` or `~/.bashrc` startup line. Drop in:

```sh
brlfetch -m 2>/dev/null
```

A small Easter egg: `brlfetch <distro>` (arch, fedora, debian, gentoo, alpine, …) renders the panel as if the system were that distro — small logos, plausible package counts, distro-shaped kernel suffix. `brlfetch -h` does not reveal the persona list; unknown names silently fall back to Bedrock. Disable with `--no-disguise`.

### `brlmon` — process monitor

```sh
brlmon           # live TUI, refresh every 1.5s
brlmon -f arch   # only show processes from the 'arch' stratum
brlmon -s mem    # sort by memory
brlmon --no-kernel
```

Keybinds: `c`/`m`/`t`/`p`/`n`/`s`/`u` sort by cpu/mem/cpu-time/pid/name/stratum/user, `r` reverse, `f` cycle stratum filter, `k` toggle kernel threads, `space` pause, `q` quit. Arrow keys + `PgUp`/`PgDn` + `g`/`G` scroll. The header chips show per-stratum CPU% next to the proc count.

Stratum detection is mountinfo-based: brlmon reads the source-root field of each PID's `/` mount in `/proc/<pid>/mountinfo`. Sandboxed processes with empty mountinfo (firefox content-procs, etc.) walk `ppid` until they find a readable one.

### `brl-erase` — fuzzy cross-stratum package removal

```sh
brl-erase chrome             # delete every chrome* match in any stratum
brl-erase firefox -y         # skip the first confirm (kernel matches still triple-confirm)
brl-erase --regex '^vim'     # treat pattern as a Python regex
brl-erase -l firefox         # list matches and exit (no prompt, no sudo)
brl-erase -d less            # dry-run: print the sudo commands that would run
```

A removal that triggers any of `DANGEROUS_PATTERNS` (kernel, grub, systemd-boot, glibc, systemd, pam, bash, coreutils, …) forces a 3-step confirmation panel — any *No* aborts. Each pm gets its cascade-aware remove command (`pacman -Rcs`, `apt-get --auto-remove purge`, etc.).

### `brltools` — index

```sh
brltools             # print the toolset table
brltools --version   # show each tool's path/size/mtime
```

---

## Optional shell integration

Add to `~/.zshrc` or `~/.bashrc` for a Bedrock-aware welcome message:

```sh
brlfetch -m 2>/dev/null
```

If brlfetch is missing the line silently no-ops.

---

## Troubleshooting

- **"Theres nothing hijacked …"** — the 5-signal Bedrock check failed. Tools bail intentionally rather than misbehave on non-Bedrock hosts. Pass `--run_test` to any tool to preview the bail panel.
- **`python-rich` import errors** — `install.sh` should have handled this; if it didn't, run `pip install --user rich` or your distro's `python3-rich` package.
- **brlmon shows mostly `bedrock` stratum** — that's expected for processes started from the init stratum (they share the global mount namespace). Strata-specific processes show their actual stratum.
- **brldoc's bootloader check says "unknown"** — needs `efibootmgr` (`sudo strat <stratum> <pm> install efibootmgr`). It's an EFI-system check; the tool gracefully no-ops on BIOS.

---

## License

TBD — drop your preferred LICENSE in this directory.

## Contributing

Issues and PRs welcome. The tools are intentionally single-file Python scripts
with minimal dependencies (just rich), so contributing is "edit the script,
re-run `./install.sh`."

If you edit the installed copies in-place (e.g. iterating on `~/bin/brldoc`),
run `./dev-sync.sh` from the repo root to pull those edits back into
`bin/` before committing.
