// SPDX-License-Identifier: GPL-2.0-or-later
// Run with: node --test tests/test-sync-order.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {test} = require('node:test');
const vm = require('node:vm');

function createHarness(version) {
    const pending = [];
    const writes = [];
    const values = {primary: 'initial', clipboard: 'initial'};
    const settings = {
        'sync-primary-to-clipboard': true,
        'sync-clipboard-to-primary': true,
    };
    let listener = null;
    const selection = {
        connect(_signal, callback) {
            listener = callback;
            return 1;
        },
        disconnect() {
            listener = null;
        },
    };
    function change(type, text) {
        values[type] = text;
        listener?.(selection, type, text === null ? null : {});
    }
    const clipboard = {
        get_mimetypes(type) {
            return values[type] === null ? [] : ['text/plain'];
        },
        get_text(type, callback) {
            const text = values[type];
            pending.push(() => callback(clipboard, text));
        },
        set_text(type, text) {
            writes.push([type, text]);
            change(type, text);
        },
    };
    const Meta = {SelectionType: {
        SELECTION_PRIMARY: 'primary',
        SELECTION_CLIPBOARD: 'clipboard',
    }};
    const St = {
        ClipboardType: {PRIMARY: 'primary', CLIPBOARD: 'clipboard'},
        Clipboard: {get_default: () => clipboard},
    };
    const filename = path.join(__dirname, '..', version, 'extension.js');
    let source = fs.readFileSync(filename, 'utf8');
    const sandbox = {
        global: {display: {get_selection: () => selection}},
        imports: {gi: {Meta, St}},
    };
    if (version === 'gnome-45') {
        // Replace GI imports only; execute the actual extension logic unchanged.
        source = source.replace(/^import .*;\n/gm, '')
            .replace('export default class', 'class');
        Object.assign(sandbox, {Meta, St, Extension: class {
            getSettings() {
                return {get_boolean: key => settings[key]};
            }
        }});
        source += '\nglobalThis.extension = new PrimaryClipboardSyncExtension();';
    } else {
        source += '\nglobalThis.extension = init();';
    }
    vm.runInNewContext(source, sandbox, {filename});
    const extension = sandbox.extension;
    extension.enable();

    async function complete(callback) {
        callback();
        // Let the GNOME 45 implementation resume after each await.
        await Promise.resolve();
    }
    async function drain() {
        let remaining = 30;
        while (pending.length) {
            assert.ok(remaining-- > 0, 'sync must settle without an echo loop');
            await complete(pending.shift());
        }
    }
    return {pending, writes, values, settings, change, extension, complete, drain};
}

for (const version of ['gnome-40', 'gnome-45']) {
    test(`${version}: both directions settle without echo writes`, async () => {
        const h = createHarness(version);
        h.change('primary', 'A');
        await h.drain();
        assert.deepEqual(h.values, {primary: 'A', clipboard: 'A'});
        h.change('clipboard', 'B');
        await h.drain();
        assert.deepEqual(h.values, {primary: 'B', clipboard: 'B'});
        assert.deepEqual(h.writes, [['clipboard', 'A'], ['primary', 'B']]);
    });

    for (const stage of ['source', 'destination']) {
        test(`${version}: discard stale ${stage} read after newer sync`, async () => {
            const h = createHarness(version);
            h.change('primary', 'A');
            if (stage === 'destination')
                await h.complete(h.pending.shift());
            const stale = h.pending.shift();
            h.change('primary', 'B');
            await h.drain();
            await h.complete(stale);
            await h.drain();
            assert.deepEqual(h.values, {primary: 'B', clipboard: 'B'});
            assert.deepEqual(h.writes, [['clipboard', 'B']]);
        });
    }

    test(`${version}: opposite-direction event supersedes pending sync`, async () => {
        const h = createHarness(version);
        h.change('primary', 'A');
        await h.complete(h.pending.shift());
        const stale = h.pending.shift();
        h.change('clipboard', 'B');
        await h.drain();
        await h.complete(stale);
        await h.drain();
        assert.deepEqual(h.values, {primary: 'B', clipboard: 'B'});
        assert.deepEqual(h.writes, [['primary', 'B']]);
    });

    for (const type of ['primary', 'clipboard']) {
        test(`${version}: clearing ${type} invalidates pending sync`, async () => {
            const h = createHarness(version);
            h.change('primary', 'A');
            await h.complete(h.pending.shift());
            h.change(type, null);
            await h.drain();
            assert.deepEqual(h.writes, []);
            assert.equal(h.values[type], null);
        });
    }

    test(`${version}: unrelated selection does not invalidate text sync`, async () => {
        const h = createHarness(version);
        h.change('primary', 'A');
        h.change('dnd', 'drag data');
        await h.drain();
        assert.equal(h.values.clipboard, 'A');
        assert.deepEqual(h.writes, [['clipboard', 'A']]);
    });

    for (const stage of ['source', 'destination']) {
        test(`${version}: ${stage} callback cannot survive disable/re-enable`, async () => {
            const h = createHarness(version);
            h.change('primary', 'A');
            if (stage === 'destination')
                await h.complete(h.pending.shift());
            h.extension.disable();
            h.extension.enable();
            await h.drain();
            assert.equal(h.values.clipboard, 'initial');
            assert.deepEqual(h.writes, []);
        });
    }
}

test('gnome-45: event in disabled direction still invalidates older sync', async () => {
    const h = createHarness('gnome-45');
    h.settings['sync-clipboard-to-primary'] = false;
    h.change('primary', 'A');
    await h.complete(h.pending.shift());
    h.change('clipboard', 'B');
    await h.drain();
    assert.deepEqual(h.values, {primary: 'A', clipboard: 'B'});
    assert.deepEqual(h.writes, []);
});
