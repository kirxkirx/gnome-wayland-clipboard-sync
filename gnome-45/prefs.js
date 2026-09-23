// SPDX-License-Identifier: GPL-2.0-or-later
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class PrimaryClipboardSyncPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage();
        const group = new Adw.PreferencesGroup({
            title: 'Sync direction',
            description: 'Changes take effect immediately.',
        });
        page.add(group);

        const rows = [
            ['sync-clipboard-to-primary', 'Clipboard to primary selection',
                'Ctrl+C and copy buttons also feed middle-click paste'],
            ['sync-primary-to-clipboard', 'Primary selection to clipboard',
                'Selecting text also replaces what Ctrl+V pastes'],
        ];
        for (const [key, title, subtitle] of rows) {
            const row = new Adw.SwitchRow({title, subtitle});
            settings.bind(key, row, 'active', Gio.SettingsBindFlags.DEFAULT);
            group.add(row);
        }

        window.add(page);
        window._settings = settings;
    }
}
