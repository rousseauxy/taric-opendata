#!/usr/bin/env bash
# Fails when a workflow uploads to a release by itself instead of through scripts/publish-assets.sh,
# unless it is on the shrinking list in scripts/publish-allowlist.txt. Also fails on a stale line in
# that list, so the list cannot outlive the reason for it.
set -u
cd "$(dirname "$0")/.."
allow=$(grep -v '^#' scripts/publish-allowlist.txt | grep -v '^\s*$' || true)
bad=0
for f in .github/workflows/*.yml; do
  name=$(basename "$f")
  if grep -q 'gh release upload' "$f"; then
    if ! printf '%s\n' "$allow" | grep -q -x "$name"; then
      echo "::error file=$f::$name calls 'gh release upload' itself. Publish through scripts/publish-assets.sh: it is what refuses an error page served under an archive's name."
      bad=1
    fi
  elif printf '%s\n' "$allow" | grep -q -x "$name"; then
    echo "::error file=scripts/publish-allowlist.txt::$name no longer uploads by itself; delete its line from the allowlist."
    bad=1
  fi
done
for name in $allow; do
  [ -f ".github/workflows/$name" ] || { echo "::error file=scripts/publish-allowlist.txt::$name is listed and does not exist."; bad=1; }
done
[ "$bad" = 0 ] && echo "Every workflow publishes through the gate or is on the allowlist ($(printf '%s\n' "$allow" | grep -c .) left)."
exit $bad
