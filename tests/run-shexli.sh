#!/bin/bash
# Run the Shexli static analyzer (recommended on the extensions.gnome.org
# upload page) on the given extension ZIPs or directories. Fails if it
# reports any error.
#
# Usage: tests/run-shexli.sh PATH...

set -u

FAILED=0
for path in "$@"; do
    # shexli needs an absolute path
    path=$(realpath "$path")
    echo "=== $path"
    shexli "$path"
    shexli --format json "$path" | EXT_PATH="$path" python3 -c '
import json, os, sys, zipfile
path = os.environ["EXT_PATH"]
if os.path.isdir(path):
    with open(os.path.join(path, "metadata.json")) as f:
        metadata = json.load(f)
else:
    metadata = json.loads(zipfile.ZipFile(path).read("metadata.json"))
# shexli 0.2.1, the latest on PyPI, treats any shell-version above 50 as
# a future release, although GNOME 51 is out. extensions.gnome.org runs a
# fixed copy (extensions-web issue 399), so ignore only that false positive.
ignored = []
if max(int(v.split(".")[0]) for v in metadata["shell-version"]) == 51:
    ignored.append("EGO-M-004")
errors = [f["rule_id"] for f in json.load(sys.stdin)["findings"]
          if f["severity"] == "error"]
for rule in errors:
    print(("ignored: " if rule in ignored else "ERROR: ") + rule)
sys.exit(any(rule not in ignored for rule in errors))
' || FAILED=1
done
exit $FAILED
