#!/bin/bash
# Test for the PRIMARY/CLIPBOARD sync extension.
#
# Usage: tests/run-test.sh gnome-40|gnome-45 [local|release|ego-curl|ego-dbus]
#
# The first argument picks how GNOME Shell runs:
# gnome-40: GNOME Shell (X11 mode) on Xvfb.
# gnome-45: GNOME Shell headless (Wayland mode); X11 clients reach it
#           through Xwayland.
# The second one picks where the extension comes from, so that the
# installation methods in README.md get tested, not only this checkout:
# local:    copy gnome-40/ or gnome-45/ from this checkout and enable it
#           before GNOME Shell starts (default)
# release:  the latest GitHub release ZIP, installed with
#           gnome-extensions install and enabled once GNOME Shell is up
# ego-curl: the README's curl one-liner, which downloads the ZIP that
#           extensions.gnome.org serves for the running GNOME Shell
# ego-dbus: the README's gdbus call, which makes the running GNOME Shell
#           download and install the extension from extensions.gnome.org
#           itself; the "Install extension?" dialog is accepted by typing
#           Return into the Shell
# Either way, it then sets one selection with xclip and checks that the
# other one follows. The release and extensions.gnome.org copies may be
# older than this checkout; the script reports whether they match.

set -u

usage() {
    echo "Usage: $0 gnome-40|gnome-45 [local|release|ego-curl|ego-dbus]"
    exit 2
}

EXT=${1:-}
METHOD=${2:-local}
case "$EXT" in
    gnome-40|gnome-45) ;;
    *) usage ;;
esac
case "$METHOD" in
    local|release|ego-curl|ego-dbus) ;;
    *) usage ;;
esac

# The test replaces the installed extension, rewrites the user's
# enabled-extensions setting and kills GNOME Shell, X servers and xclip,
# so only run it in a disposable container, as CI does (toolbox and
# distrobox share $HOME)
if [ -z "${CI:-}" ]; then
    echo "$0: only run this in a disposable container, with CI=1 set"
    exit 2
fi

UUID=gnome-wayland-clipboard-sync@kirxkirx.github.io
SCHEMA=org.gnome.shell.extensions.gnome-wayland-clipboard-sync
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO_URL=https://github.com/kirxkirx/gnome-wayland-clipboard-sync
SHELL_LOG=/tmp/gnome-shell.log

# Environment must be set before the D-Bus session starts, so that
# D-Bus-activated services (dconf) see the same XDG_RUNTIME_DIR.
if [ -z "${IN_DBUS_SESSION:-}" ]; then
    # Leftovers of a previous run; CI runs this script once per method
    pkill -x gnome-shell
    pkill -x Xwayland
    pkill -x Xvfb
    pkill -x xclip
    # The gjs service gnome-extensions talks to, bound to the old bus
    pkill -f org.gnome.Shell.Extensions
    sleep 1
    rm -f /tmp/.X11-unix/X*
    export IN_DBUS_SESSION=1
    export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$(id -u)
    rm -rf "$XDG_RUNTIME_DIR"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    export XDG_CURRENT_DESKTOP=GNOME
    if [ "$EXT" = gnome-40 ]; then
        export DISPLAY=:99
        export XDG_SESSION_TYPE=x11
    else
        unset DISPLAY WAYLAND_DISPLAY
        export XDG_SESSION_TYPE=wayland
    fi
    exec dbus-run-session -- "$0" "$@"
fi

XVFB_PID=""
SHELL_PID=""
INSTALL_PID=""
FAILED=0

cleanup() {
    pkill -x xclip 2>/dev/null
    [ -n "$INSTALL_PID" ] && kill "$INSTALL_PID" 2>/dev/null
    [ -n "$SHELL_PID" ] && kill "$SHELL_PID" 2>/dev/null
    [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null
}
trap cleanup EXIT

die() {
    echo "ERROR: $*"
    echo "---- last 200 lines of the gnome-shell log ----"
    tail -n 200 "$SHELL_LOG" 2>/dev/null
    exit 1
}

shell_alive() {
    kill -0 "$SHELL_PID" 2>/dev/null || die "gnome-shell exited"
}

set_sel() {
    # xclip forks into the background and keeps serving the selection
    printf '%s' "$2" | xclip -selection "$1" >/dev/null 2>&1
}

get_sel() {
    xclip -o -selection "$1" 2>/dev/null
}

extension_state() {
    # GNOME 46 and later report an enabled extension as ACTIVE
    gnome-extensions info "$UUID" 2>/dev/null |
        sed -n 's/^ *State: *//p' | sed 's/^ACTIVE$/ENABLED/'
}

set_pref() {
    gsettings --schemadir "$EXTDIR/schemas" set "$SCHEMA" "$1" "$2"
}

# readme_block REGEX: the indented code block in README.md whose first
# line matches REGEX, unindented, so that the README's own commands run
readme_block() {
    awk -v re="$1" '
        found && /^    / { sub(/^    /, ""); print; next }
        found { exit }
        /^    / && $0 ~ re { found = 1; sub(/^    /, ""); print }
    ' "$REPO_DIR/README.md"
}

# True once GNOME Shell answers extension queries on the session bus
shell_up() {
    gnome-extensions list >/dev/null 2>&1
}

wait_for_shell() {
    local i
    for i in $(seq 1 90); do
        shell_alive
        shell_up && return 0
        sleep 1
    done
    die "GNOME Shell did not come up within 90 s"
}

# wait_for_state STATE SECONDS: wait until the extension reports STATE,
# or ANY for any state at all (installed and seen by GNOME Shell)
wait_for_state() {
    local want=$1 i state=""
    for i in $(seq 1 "$2"); do
        shell_alive
        state=$(extension_state)
        case "$state" in
            ERROR|OUT*) die "extension is in $state state" ;;
            "$want") return 0 ;;
        esac
        [ "$want" = ANY ] && [ -n "$state" ] && return 0
        sleep 1
    done
    die "extension not $want after $2 s (state: '$state')"
}

# Type Return into GNOME Shell with a virtual keyboard, through
# org.gnome.Shell.Eval, which only works in unsafe mode. The numbers are
# Clutter.InputDeviceType.KEYBOARD_DEVICE, Clutter.KEY_Return and
# Clutter.KeyState.PRESSED/RELEASED, spelled out because the Eval scope
# of GNOME 45 and later has no Clutter import.
press_return() {
    local out
    out=$(gdbus call --session --dest org.gnome.Shell \
        --object-path /org/gnome/Shell --method org.gnome.Shell.Eval '
        const be = global.backend;
        const seat = be.get_default_seat ? be.get_default_seat()
            : global.stage.context ? global.stage.context.get_backend().get_default_seat()
            : imports.gi.Clutter.get_default_backend().get_default_seat();
        const dev = seat.create_virtual_device(1);
        dev.notify_keyval(0, 0xff0d, 1);
        dev.notify_keyval(0, 0xff0d, 0);
        "typed Return"' 2>&1)
    case "$out" in
        "(true,"*) return 0 ;;
        *) echo "Eval failed: $out"; return 1 ;;
    esac
}

# Say whether the installed copy is the code in this checkout. The
# release and extensions.gnome.org copies lag behind it by design.
compare_with_checkout() {
    local ver
    ver=$(sed -n 's/.*"version": *\([0-9][0-9]*\).*/\1/p' "$EXTDIR/metadata.json" | head -n 1)
    echo "Installed metadata.json version: ${ver:-none}"
    if diff -r -q -x metadata.json -x gschemas.compiled "$REPO_DIR/$EXT" "$EXTDIR" >/dev/null; then
        echo "Installed files match $EXT/ in this checkout (apart from metadata.json)"
    else
        echo "NOTICE: installed files differ from $EXT/ in this checkout:"
        diff -r -x metadata.json -x gschemas.compiled "$REPO_DIR/$EXT" "$EXTDIR" | sed 's/^/    /'
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            echo "::notice title=$METHOD on $EXT::installed version ${ver:-?} differs from $EXT/ in this checkout"
        fi
    fi
}

# expect_sync SRC DST TEXT: set SRC, expect DST to become TEXT
expect_sync() {
    local src=$1 dst=$2 text=$3 got="" i
    set_sel "$src" "$text"
    sleep 0.25
    shell_alive
    for i in $(seq 1 20); do
        got=$(get_sel "$dst")
        if [ "$got" = "$text" ]; then
            echo "PASS: $src -> $dst"
            return 0
        fi
        sleep 0.25
    done
    echo "FAIL: $src -> $dst: expected '$text', got '$got'"
    FAILED=1
}

# expect_no_sync SRC DST TEXT WHY: set SRC, expect DST to stay different
expect_no_sync() {
    local src=$1 dst=$2 text=$3 why=$4 got
    set_sel "$src" "$text"
    sleep 3
    shell_alive
    got=$(get_sel "$dst")
    if [ "$got" = "$text" ]; then
        echo "FAIL: $src -> $dst synced $why"
        FAILED=1
    else
        echo "PASS: no $src -> $dst sync $why"
    fi
}

# Install the extension (before GNOME Shell starts, except for ego-dbus)
EXTDIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
rm -rf "$EXTDIR"
gsettings set org.gnome.shell enabled-extensions "[]"

case "$METHOD" in
    local)
        mkdir -p "$EXTDIR"
        cp -r "$REPO_DIR/$EXT"/* "$EXTDIR/"
        if [ -d "$EXTDIR/schemas" ]; then
            glib-compile-schemas "$EXTDIR/schemas" || die "cannot compile schemas"
        fi
        # Already enabled at login, unlike the README flows below
        gsettings set org.gnome.shell enabled-extensions "['$UUID']"
        ;;
    release)
        TAG=$(curl -sSIL -o /dev/null -w '%{url_effective}' "$REPO_URL/releases/latest") ||
            die "cannot resolve the latest GitHub release"
        TAG=${TAG##*/}
        ZIP=gnome-wayland-clipboard-sync-$TAG-$EXT.zip
        echo "Latest GitHub release: $TAG, downloading $ZIP"
        curl -sSfL -o "/tmp/$ZIP" "$REPO_URL/releases/download/$TAG/$ZIP" ||
            die "cannot download $ZIP from the $TAG release"
        gnome-extensions install --force "/tmp/$ZIP" ||
            die "gnome-extensions install failed"
        ;;
    ego-curl)
        CMD=$(readme_block '^    curl -sSL -o /tmp/primary-clipboard-sync.zip')
        [ -n "$CMD" ] || die "curl one-liner not found in README.md"
        echo "Running the README one-liner:"
        echo "$CMD" | sed 's/^/    /'
        eval "$CMD" || die "the README one-liner failed (no extensions.gnome.org version for GNOME Shell $(gnome-shell --version | awk '{print $3}')?)"
        ;;
    ego-dbus)
        GDBUS_CMD=$(readme_block '^    gdbus call --session --dest org.gnome.Shell.Extensions')
        [ -n "$GDBUS_CMD" ] || die "gdbus call not found in README.md"
        ;;
esac
if [ "$METHOD" != ego-dbus ] && [ ! -f "$EXTDIR/metadata.json" ]; then
    die "nothing installed in $EXTDIR"
fi

# org.gnome.Shell.Eval, used to accept the install dialog, needs unsafe mode
SHELL_ARGS=()
[ "$METHOD" = ego-dbus ] && SHELL_ARGS+=(--unsafe-mode)

if [ "$EXT" = gnome-40 ]; then
    # Start the virtual X server and GNOME Shell on it
    Xvfb :99 -screen 0 1280x1024x24 +extension GLX >/tmp/xvfb.log 2>&1 &
    XVFB_PID=$!
    for i in $(seq 1 30); do
        [ -e /tmp/.X11-unix/X99 ] && break
        sleep 0.5
    done
    [ -e /tmp/.X11-unix/X99 ] || die "Xvfb did not start"
    gnome-shell --x11 "${SHELL_ARGS[@]}" >"$SHELL_LOG" 2>&1 &
    SHELL_PID=$!
else
    # Run under gdb, so that a crash leaves C and JS backtraces in the log
    gdb -q -batch \
        -ex 'handle SIGPIPE SIGUSR1 SIGUSR2 SIGHUP nostop noprint pass' \
        -ex run -ex bt -ex 'call (void) gjs_dumpstack()' \
        --args gnome-shell --headless --wayland --virtual-monitor 1280x1024 \
        "${SHELL_ARGS[@]}" >"$SHELL_LOG" 2>&1 &
    SHELL_PID=$!
fi

wait_for_shell
case "$METHOD" in
    local)
        wait_for_state ENABLED 90
        ;;
    release|ego-curl)
        # The README's "log out and log back in, then enable" step
        wait_for_state ANY 60
        gnome-extensions enable "$UUID" || die "gnome-extensions enable failed"
        wait_for_state ENABLED 30
        ;;
    ego-dbus)
        [ -z "$(extension_state)" ] || die "extension present before the D-Bus install"
        # Let the Shell finish starting before it opens a dialog
        sleep 3
        echo "Running the README gdbus call:"
        echo "$GDBUS_CMD" | sed 's/^/    /'
        eval "$GDBUS_CMD" >/tmp/install-call.out 2>&1 &
        INSTALL_PID=$!
        # The call returns once the "Install extension?" dialog is
        # answered; Install is its default button, so Return accepts it
        for i in $(seq 1 120); do
            kill -0 "$INSTALL_PID" 2>/dev/null || break
            shell_alive
            press_return || die "cannot type into GNOME Shell"
            sleep 1
        done
        if kill -0 "$INSTALL_PID" 2>/dev/null; then
            die "InstallRemoteExtension did not return within 120 s"
        fi
        wait "$INSTALL_PID"
        INSTALL_PID=""
        RESULT=$(cat /tmp/install-call.out)
        echo "InstallRemoteExtension returned: $RESULT"
        case "$RESULT" in
            *successful*) ;;
            *) die "InstallRemoteExtension did not succeed (no extensions.gnome.org version for GNOME Shell $(gnome-shell --version | awk '{print $3}')?)" ;;
        esac
        wait_for_state ENABLED 30
        ;;
esac
echo "GNOME Shell $(gnome-shell --version | awk '{print $3}') is up, extension enabled ($METHOD)"
[ "$METHOD" = local ] || compare_with_checkout

if [ "$EXT" = gnome-45 ]; then
    # Point xclip at the Xwayland server that GNOME Shell started
    for i in $(seq 1 30); do
        SOCKET=$(ls /tmp/.X11-unix/X* 2>/dev/null | head -n 1)
        [ -n "$SOCKET" ] && break
        sleep 0.5
    done
    [ -n "$SOCKET" ] || die "no Xwayland socket"
    export DISPLAY=:${SOCKET#/tmp/.X11-unix/X}
    AUTH=$(ls -t "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null | head -n 1)
    [ -n "$AUTH" ] && export XAUTHORITY=$AUTH
    echo "Using Xwayland on $DISPLAY"
fi

# Tests
expect_sync clipboard primary "clipboard to primary $$"
expect_sync primary clipboard "primary to clipboard $$"
expect_sync clipboard primary $'multi-line text\nsecond line'
expect_sync primary clipboard "second primary change $$"

# Copying non-text content (here an image) must not crash the Shell
printf '\x89PNG\r\n' | xclip -selection clipboard -t image/png >/dev/null 2>&1
sleep 2
shell_alive
echo "PASS: non-text clipboard content"

if [ "$EXT" = gnome-45 ]; then
    # One-way sync, switched in the preferences without a restart
    set_pref sync-primary-to-clipboard false
    sleep 1
    expect_sync clipboard primary "one-way A $$"
    expect_no_sync primary clipboard "one-way B $$" "with primary-to-clipboard off"
    # Copying the same text again must reach PRIMARY once more
    expect_sync clipboard primary "one-way A $$"
    set_pref sync-primary-to-clipboard true
    set_pref sync-clipboard-to-primary false
    sleep 1
    expect_no_sync clipboard primary "one-way C $$" "with clipboard-to-primary off"
    set_pref sync-clipboard-to-primary true
fi

# Control: with the extension disabled, nothing should sync
gnome-extensions disable "$UUID"
for i in $(seq 1 20); do
    [ "$(extension_state)" != "ENABLED" ] && break
    sleep 0.5
done
expect_no_sync clipboard primary "control text $$" "with the extension disabled"

if [ "$FAILED" -ne 0 ]; then
    die "some tests failed"
fi
echo "All tests passed ($METHOD install of $EXT)"
