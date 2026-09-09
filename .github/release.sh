#!/usr/bin/env bash
# release.sh vX.Y.Z — tag green main and publish a GitHub release.
# The release-triggered Action (.github/workflows/release.yml) then re-runs the
# gate, cross-compiles all four targets, and attaches binaries + SHA256SUMS.
# Changelog = git log since the previous tag (task-ID commit style reads well).
set -euo pipefail
cd "$(dirname "$0")/.."

V="${1:?usage: release.sh vX.Y.Z}"
case "$V" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "tag must look like v0.1.0"; exit 1;; esac

[ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 1; }
git fetch origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD != origin/main"; exit 1; }

# never release red: last CI run on main must be green
gh run list --branch main --limit 1 --json conclusion -q '.[0].conclusion' | grep -qx success \
  || { echo "latest CI run on main is not green"; exit 1; }

PREV=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
RANGE=${PREV:+$PREV..HEAD}; RANGE=${RANGE:-HEAD}
NOTES=$(mktemp)
{ echo "## $V"
  echo ""
  echo "Suites at release: \`zig build test\` + corpus + programs green (CI-verified)."
  echo ""
  echo "### Changes${PREV:+ since $PREV}"
  # code-span each subject: commit text contains @tokens (@dev1, @col, Zig
  # builtins) that GitHub would render as USER MENTIONS in release notes and
  # list those real accounts as release "contributors" (bit us on v0.1.0)
  git log --oneline --no-merges $RANGE | sed 's/^/- `/; s/$/`/'
} > "$NOTES"

git tag -a "$V" -m "$V"
git push origin "$V"
gh release create "$V" --title "$V" --notes-file "$NOTES"
echo "release $V published — the Action is building and attaching binaries:"
echo "  gh run watch \$(gh run list --workflow release --limit 1 --json databaseId -q '.[0].databaseId')"
