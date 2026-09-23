// SPDX-License-Identifier: GPL-2.0-or-later
import Meta from 'gi://Meta';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

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

    _copy(fromType, toType) {
        this._clipboard.get_text(fromType, (clipboard, text) => {
            if (!this._clipboard || !text)
                return;
            // Only write when the destination differs; this also stops
            // our own write from echoing back to the source
            this._clipboard.get_text(toType, (clipboard2, current) => {
                if (this._clipboard && current !== text)
                    this._clipboard.set_text(toType, text);
            });
        });
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
