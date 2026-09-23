#!/bin/bash
# Test for the PRIMARY/CLIPBOARD sync extension.
# Starts GNOME Shell (X11 mode) on Xvfb with the extension enabled, then
# sets one selection with xclip and checks that the other one follows.

set -u

UUID=primary-clipboard-sync@local
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
SHELL_LOG=/tmp/gnome-shell.log

# Environment must be set before the D-Bus session starts, so that
# D-Bus-activated services (dconf) see the same XDG_RUNTIME_DIR.
if [ -z "${IN_DBUS_SESSION:-}" ]; then
    export IN_DBUS_SESSION=1
    export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$(id -u)
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    export DISPLAY=:99
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=GNOME
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
    echo "---- last 100 lines of the gnome-shell log ----"
    tail -n 100 "$SHELL_LOG" 2>/dev/null
    exit 1
}

set_sel() {
    # xclip forks into the background and keeps serving the selection
    printf '%s' "$2" | xclip -selection "$1" >/dev/null 2>&1
}

get_sel() {
    xclip -o -selection "$1" 2>/dev/null
}

extension_state() {
    gnome-extensions info "$UUID" 2>/dev/null | sed -n 's/^ *State: *//p'
}

# expect_sync SRC DST TEXT: set SRC, expect DST to become TEXT
expect_sync() {
    local src=$1 dst=$2 text=$3 got="" i
    set_sel "$src" "$text"
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

# expect_no_sync SRC DST TEXT: set SRC, expect DST to stay different
expect_no_sync() {
    local src=$1 dst=$2 text=$3 got
    set_sel "$src" "$text"
    sleep 3
    got=$(get_sel "$dst")
    if [ "$got" = "$text" ]; then
        echo "FAIL (control): $src -> $dst synced with the extension disabled"
        FAILED=1
    else
        echo "PASS (control): no $src -> $dst sync with the extension disabled"
    fi
}

# Install the extension
EXTDIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
mkdir -p "$EXTDIR"
cp "$REPO_DIR/metadata.json" "$REPO_DIR/extension.js" "$EXTDIR/"

# Start the virtual X server
Xvfb :99 -screen 0 1280x1024x24 +extension GLX >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
for i in $(seq 1 30); do
    [ -e /tmp/.X11-unix/X99 ] && break
    sleep 0.5
done
[ -e /tmp/.X11-unix/X99 ] || die "Xvfb did not start"

# Enable the extension and start GNOME Shell
gsettings set org.gnome.shell enabled-extensions "['$UUID']"
gnome-shell --x11 >"$SHELL_LOG" 2>&1 &
SHELL_PID=$!

STATE=""
for i in $(seq 1 90); do
    kill -0 "$SHELL_PID" 2>/dev/null || die "gnome-shell exited"
    STATE=$(extension_state)
    [ "$STATE" = "ENABLED" ] && break
    [ "$STATE" = "ERROR" ] && die "extension is in ERROR state"
    sleep 1
done
[ "$STATE" = "ENABLED" ] || die "extension not enabled after 90 s (state: '$STATE')"
echo "GNOME Shell $(gnome-shell --version | awk '{print $3}') is up, extension enabled"

# Tests
expect_sync clipboard primary "clipboard to primary $$"
expect_sync primary clipboard "primary to clipboard $$"
expect_sync clipboard primary $'multi-line text\nsecond line'
expect_sync primary clipboard "second primary change $$"

# Control: with the extension disabled, nothing should sync
gnome-extensions disable "$UUID"
for i in $(seq 1 20); do
    [ "$(extension_state)" != "ENABLED" ] && break
    sleep 0.5
done
expect_no_sync clipboard primary "control text $$"

if [ "$FAILED" -ne 0 ]; then
    die "some tests failed"
fi
echo "All tests passed"
