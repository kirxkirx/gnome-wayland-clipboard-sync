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
        this._seq = 0n;
    }

    enable() {
        this._selection = global.display.get_selection();
        this._clipboard = St.Clipboard.get_default();
        this._handlerId = this._selection.connect('owner-changed',
            this._onOwnerChanged.bind(this));
    }

    disable() {
        ++this._seq;
        if (this._handlerId) {
            this._selection.disconnect(this._handlerId);
            this._handlerId = 0;
        }
        this._selection = null;
        this._clipboard = null;
    }

    _copy(fromType, toType, seq) {
        this._clipboard.get_text(fromType, (clipboard, text) => {
            if (!this._clipboard || !text || seq !== this._seq)
                return;
            // Only write when the destination differs; this also stops
            // our own write from echoing back to the source
            this._clipboard.get_text(toType, (clipboard2, current) => {
                if (this._clipboard && seq === this._seq && current !== text)
                    this._clipboard.set_text(toType, text);
            });
        });
    }

    _onOwnerChanged(selection, selectionType, source) {
        if (selectionType !== Meta.SelectionType.SELECTION_PRIMARY &&
            selectionType !== Meta.SelectionType.SELECTION_CLIPBOARD)
            return;
        // Shell callbacks run on one thread: increment before any async reads.
        // Even clearing a selection must invalidate older pending transfers.
        const seq = ++this._seq;
        if (!source)
            return;
        if (selectionType === Meta.SelectionType.SELECTION_PRIMARY &&
            SYNC_PRIMARY_TO_CLIPBOARD)
            this._copy(St.ClipboardType.PRIMARY, St.ClipboardType.CLIPBOARD, seq);
        else if (selectionType === Meta.SelectionType.SELECTION_CLIPBOARD &&
                 SYNC_CLIPBOARD_TO_PRIMARY)
            this._copy(St.ClipboardType.CLIPBOARD, St.ClipboardType.PRIMARY, seq);
    }
}

function init() {
    return new Extension();
}
