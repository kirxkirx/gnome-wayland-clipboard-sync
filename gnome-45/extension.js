// SPDX-License-Identifier: GPL-2.0-or-later
import Meta from 'gi://Meta';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const TEXT_MIMETYPES = [
    'text/plain;charset=utf-8',
    'UTF8_STRING',
    'text/plain',
    'STRING',
];

export default class PrimaryClipboardSyncExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
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
        this._settings = null;
    }

    _getText(type) {
        // When a selection holds no text, get_text() runs the callback
        // before returning, which crashes GNOME Shell 49 to 51. So only
        // call it when the selection offers one of the text types that
        // St.Clipboard reads (supported_mimetypes in st-clipboard.c).
        const mimetypes = this._clipboard.get_mimetypes(type);
        if (!mimetypes.some(m => TEXT_MIMETYPES.includes(m)))
            return Promise.resolve(null);
        return new Promise(resolve => {
            this._clipboard.get_text(type, (clipboard, text) => resolve(text));
        });
    }

    async _copy(fromType, toType) {
        const text = await this._getText(fromType);
        if (!this._clipboard || !text)
            return;
        // Only write when the destination differs; this also stops
        // our own write from echoing back to the source
        const current = await this._getText(toType);
        if (this._clipboard && current !== text)
            this._clipboard.set_text(toType, text);
    }

    _onOwnerChanged(selection, selectionType, source) {
        if (!source)
            return;
        if (selectionType === Meta.SelectionType.SELECTION_PRIMARY &&
            this._settings.get_boolean('sync-primary-to-clipboard'))
            this._copy(St.ClipboardType.PRIMARY, St.ClipboardType.CLIPBOARD);
        else if (selectionType === Meta.SelectionType.SELECTION_CLIPBOARD &&
                 this._settings.get_boolean('sync-clipboard-to-primary'))
            this._copy(St.ClipboardType.CLIPBOARD, St.ClipboardType.PRIMARY);
    }
}
