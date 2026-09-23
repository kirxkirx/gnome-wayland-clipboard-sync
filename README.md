# Primary/Clipboard Sync

[![test](https://github.com/kirxkirx/gnome-wayland-clipboard-sync/actions/workflows/test.yml/badge.svg)](https://github.com/kirxkirx/gnome-wayland-clipboard-sync/actions/workflows/test.yml)

A tiny GNOME Shell extension that keeps the two X11/Wayland selection
buffers in sync:

- PRIMARY: filled by selecting text, pasted with the middle mouse button
- CLIPBOARD: filled by Ctrl+C and web "copy" buttons, pasted with Ctrl+V

With the extension enabled, selecting text, Ctrl+C, and copy buttons
(e.g. the clone URL button on GitHub) all end up in one buffer that can
be pasted with either the middle mouse button or Ctrl+V.

Unlike autocutsel or parcellite, it works under Wayland, because it runs
inside GNOME Shell, which owns both selections.

## Compatibility

Tested on GNOME Shell 40.10 (RHEL 9, Wayland session). Should work on
GNOME 40 to 44. GNOME 45 and later use a different extension format
and are not supported.

## Installation

    git clone https://github.com/kirxkirx/gnome-wayland-clipboard-sync.git
    EXTDIR=~/.local/share/gnome-shell/extensions/primary-clipboard-sync@local
    mkdir -p "$EXTDIR"
    cp gnome-wayland-clipboard-sync/metadata.json primary-clipboard-sync/extension.js "$EXTDIR/"

Log out and log back in (GNOME Shell cannot be restarted in place on
Wayland), then:

    gnome-extensions enable primary-clipboard-sync@local

## Configuration

By default the sync is two-way. As a side effect, selecting text
overwrites what Ctrl+V pastes. For one-way sync (Ctrl+C and copy buttons
also feed middle-click, but selecting does not affect Ctrl+V), edit
extension.js and set

    const SYNC_PRIMARY_TO_CLIPBOARD = false;

then log out and back in.

## Uninstall

    gnome-extensions disable primary-clipboard-sync@local
    rm -r ~/.local/share/gnome-shell/extensions/primary-clipboard-sync@local

## License

GPL-2.0-or-later
