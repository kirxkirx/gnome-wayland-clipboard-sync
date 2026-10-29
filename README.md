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

The repository holds two versions of the extension, because GNOME 45
changed the extension format:

- `gnome-40/`: GNOME Shell 40 to 44. Tested on GNOME Shell 40.10
  (RHEL 9, Wayland session); CI runs it on Rocky Linux 9 and AlmaLinux 9
  (GNOME 40), Ubuntu 22.04 (GNOME 42) and Debian 12 (GNOME 43), with
  GNOME Shell in X11 mode on Xvfb.
- `gnome-45/`: GNOME Shell 45 to 51. CI runs it headless (Wayland) on
  Fedora 43, 44 and 45 (GNOME 49, 50 and 51).

Both use the same UUID, so install only the one that matches your
GNOME Shell version (`gnome-shell --version`).

## Installation

From a release: download the ZIP that matches your GNOME version
(`-gnome-40.zip` for GNOME 40 to 44, `-gnome-45.zip` for GNOME 45 and
later) from the
[latest release](https://github.com/kirxkirx/gnome-wayland-clipboard-sync/releases/latest)
and install it, e.g.

    gnome-extensions install --force gnome-wayland-clipboard-sync-*-gnome-40.zip

Or from source:

    git clone https://github.com/kirxkirx/gnome-wayland-clipboard-sync.git
    EXTDIR=~/.local/share/gnome-shell/extensions/gnome-wayland-clipboard-sync@kirxkirx.github.io
    mkdir -p "$EXTDIR"

For GNOME 40 to 44:

    cp gnome-wayland-clipboard-sync/gnome-40/* "$EXTDIR/"

For GNOME 45 and later:

    cp -r gnome-wayland-clipboard-sync/gnome-45/* "$EXTDIR/"
    glib-compile-schemas "$EXTDIR/schemas"

Either way, log out and log back in (GNOME Shell only looks for new
extensions when it starts, and it cannot be restarted in place on
Wayland), then:

    gnome-extensions enable gnome-wayland-clipboard-sync@kirxkirx.github.io

Running `enable` before logging back in fails with "Extension ... does
not exist". `gnome-extensions info gnome-wayland-clipboard-sync@kirxkirx.github.io`
should now show the state ENABLED (ACTIVE on GNOME 46 and later).

## Configuration

By default the sync is two-way. As a side effect, selecting text
overwrites what Ctrl+V pastes. For one-way sync (Ctrl+C and copy buttons
also feed middle-click, but selecting does not affect Ctrl+V), turn off
"Primary Selection to Clipboard":

- GNOME 45 and later: in the extension preferences
  (`gnome-extensions prefs gnome-wayland-clipboard-sync@kirxkirx.github.io`, or the
  Extensions app). Changes take effect immediately.
- GNOME 40 to 44: edit the installed copy,
  `~/.local/share/gnome-shell/extensions/gnome-wayland-clipboard-sync@kirxkirx.github.io/extension.js`,
  and set

      const SYNC_PRIMARY_TO_CLIPBOARD = false;

  then log out and back in. Reinstalling the extension undoes this.

Passwords that password managers mark as secret (KeePassXC,
`wl-copy --sensitive`) are not copied while the password manager holds
them. A password can still end up in the primary selection, and stay
there until you select other text or lock the screen, if the password
manager does not mark it (GNOME Secrets, for example), or if GNOME puts
its own unmarked copy of the clipboard back after the password manager
lets go of it without clearing it.

## Uninstall

    gnome-extensions disable gnome-wayland-clipboard-sync@kirxkirx.github.io
    rm -r ~/.local/share/gnome-shell/extensions/gnome-wayland-clipboard-sync@kirxkirx.github.io

## License

GPL-2.0-or-later
