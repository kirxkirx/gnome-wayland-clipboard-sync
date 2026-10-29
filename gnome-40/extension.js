// SPDX-License-Identifier: GPL-2.0-or-later
const { Meta, St } = imports.gi;

// Set SYNC_PRIMARY_TO_CLIPBOARD to false for one-way sync:
// Ctrl+C and web copy buttons then also feed middle-click,
// but selecting text no longer overwrites what Ctrl+V pastes.
const SYNC_PRIMARY_TO_CLIPBOARD = true;
const SYNC_CLIPBOARD_TO_PRIMARY = true;

class Extension {
    constructor() {
        this._selection = null;
        this._clipboard = null;
        this._handlerId = 0;
        this._serial = 0;
    }

    enable() {
        this._selection = global.display.get_selection();
        this._clipboard = St.Clipboard.get_default();
        this._handlerId = this._selection.connect('owner-changed',
            this._onOwnerChanged.bind(this));
    }

    disable() {
        if (this._handlerId) {
            this._selection.disconnect(this._handlerId);
            this._handlerId = 0;
        }
        this._selection = null;
        this._clipboard = null;
        // get_text() cannot be cancelled, so make copies that are still
        // reading drop their result
        this._serial++;
    }

    _getText(type) {
        // get_text() runs the callback before returning when the selection
        // holds no text, and a get_text() call made from inside that
        // callback crashes GNOME Shell with GJS 1.72.4 and later. Resolving
        // a Promise keeps the rest of _copy() out of the callback.
        return new Promise(resolve => {
            this._clipboard.get_text(type, (clipboard, text) => resolve(text));
        });
    }

    async _copy(fromType, toType) {
        const serial = this._serial;
        const text = await this._getText(fromType);
        if (serial !== this._serial || !text)
            return;
        // Only write when the destination differs; this also stops
        // our own write from echoing back to the source
        const current = await this._getText(toType);
        if (serial === this._serial && current !== text)
            this._clipboard.set_text(toType, text);
    }

    _onOwnerChanged(selection, selectionType, source) {
        if (!source || selectionType === Meta.SelectionType.SELECTION_DND)
            return;
        const mimetypes = source.get_mimetypes();
        // Ignore cleared selections (no types), so that they do not stop
        // a pending copy into them, as after Ctrl+X in GTK 4
        if (!mimetypes.length)
            return;
        // Copies that are still reading older content are now stale
        this._serial++;
        // Leave alone passwords that password managers mark as secret
        if (mimetypes.includes('x-kde-passwordManagerHint'))
            return;
        if (selectionType === Meta.SelectionType.SELECTION_PRIMARY &&
            SYNC_PRIMARY_TO_CLIPBOARD)
            this._copy(St.ClipboardType.PRIMARY, St.ClipboardType.CLIPBOARD);
        else if (selectionType === Meta.SelectionType.SELECTION_CLIPBOARD &&
                 SYNC_CLIPBOARD_TO_PRIMARY)
            this._copy(St.ClipboardType.CLIPBOARD, St.ClipboardType.PRIMARY);
    }
}

function init() {
    return new Extension();
}
