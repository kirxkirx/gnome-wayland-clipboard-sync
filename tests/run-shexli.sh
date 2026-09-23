#!/bin/bash
# Run the Shexli static analyzer (recommended on the extensions.gnome.org
# upload page) on the given extension ZIPs or directories. Fails if it
# reports any error.
#
# Usage: tests/run-shexli.sh PATH...

set -u

# shexli 0.2.1 treats any shell-version above 50 as a future release,
# although GNOME 51 is out. Remove once shexli knows about GNOME 51.
IGNORED_ERRORS="EGO-M-004"

FAILED=0
for path in "$@"; do
    # shexli needs an absolute path
    path=$(realpath "$path")
    echo "=== $path"
    shexli "$path"
    shexli --format json "$path" | IGNORED_ERRORS="$IGNORED_ERRORS" python3 -c '
import json, os, sys
ignored = os.environ["IGNORED_ERRORS"].split()
errors = [f["rule_id"] for f in json.load(sys.stdin)["findings"]
          if f["severity"] == "error"]
for rule in errors:
    print(("ignored: " if rule in ignored else "ERROR: ") + rule)
sys.exit(any(rule not in ignored for rule in errors))
' || FAILED=1
done
exit $FAILED
