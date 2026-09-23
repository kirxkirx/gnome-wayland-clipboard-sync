#!/bin/bash
# Test for the PRIMARY/CLIPBOARD sync extension.
#
# Usage: tests/run-test.sh gnome-40|gnome-45
#
# gnome-40: starts GNOME Shell (X11 mode) on Xvfb.
# gnome-45: starts GNOME Shell headless (Wayland mode); X11 clients reach
#           it through Xwayland.
# Either way, it sets one selection with xclip and checks that the other
# one follows.

set -u

EXT=${1:-}
case "$EXT" in
    gnome-40|gnome-45) ;;
    *) echo "Usage: $0 gnome-40|gnome-45"; exit 2 ;;
esac

UUID=gnome-wayland-clipboard-sync@kirxkirx.github.io
SCHEMA=org.gnome.shell.extensions.gnome-wayland-clipboard-sync
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
SHELL_LOG=/tmp/gnome-shell.log

# Environment must be set before the D-Bus session starts, so that
# D-Bus-activated services (dconf) see the same XDG_RUNTIME_DIR.
if [ -z "${IN_DBUS_SESSION:-}" ]; then
    export IN_DBUS_SESSION=1
    export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$(id -u)
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
FAILED=0

cleanup() {
    pkill -x xclip 2>/dev/null
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
    # GNOME 45 and later report an enabled extension as ACTIVE
    gnome-extensions info "$UUID" 2>/dev/null |
        sed -n 's/^ *State: *//p' | sed 's/^ACTIVE$/ENABLED/'
}

set_pref() {
    gsettings --schemadir "$EXTDIR/schemas" set "$SCHEMA" "$1" "$2"
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

# Install the extension
EXTDIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
rm -rf "$EXTDIR"
mkdir -p "$EXTDIR"
cp -r "$REPO_DIR/$EXT"/* "$EXTDIR/"
if [ -d "$EXTDIR/schemas" ]; then
    glib-compile-schemas "$EXTDIR/schemas" || die "cannot compile schemas"
fi

gsettings set org.gnome.shell enabled-extensions "['$UUID']"

if [ "$EXT" = gnome-40 ]; then
    # Start the virtual X server and GNOME Shell on it
    Xvfb :99 -screen 0 1280x1024x24 +extension GLX >/tmp/xvfb.log 2>&1 &
    XVFB_PID=$!
    for i in $(seq 1 30); do
        [ -e /tmp/.X11-unix/X99 ] && break
        sleep 0.5
    done
    [ -e /tmp/.X11-unix/X99 ] || die "Xvfb did not start"
    gnome-shell --x11 >"$SHELL_LOG" 2>&1 &
    SHELL_PID=$!
else
    # Run under gdb, so that a crash leaves C and JS backtraces in the log
    gdb -q -batch \
        -ex 'handle SIGPIPE SIGUSR1 SIGUSR2 SIGHUP nostop noprint pass' \
        -ex run -ex bt -ex 'call (void) gjs_dumpstack()' \
        --args gnome-shell --headless --wayland --virtual-monitor 1280x1024 \
        >"$SHELL_LOG" 2>&1 &
    SHELL_PID=$!
fi

STATE=""
for i in $(seq 1 90); do
    shell_alive
    STATE=$(extension_state)
    [ "$STATE" = "ENABLED" ] && break
    case "$STATE" in
        ERROR|OUT*) die "extension is in $STATE state" ;;
    esac
    sleep 1
done
[ "$STATE" = "ENABLED" ] || die "extension not enabled after 90 s (state: '$STATE')"
echo "GNOME Shell $(gnome-shell --version | awk '{print $3}') is up, extension enabled"

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
echo "All tests passed"
