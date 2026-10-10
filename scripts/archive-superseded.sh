#!/usr/bin/env bash
# Keeps the copy a release asset is about to be overwritten with.
#
#   scripts/archive-superseded.sh TAG FILE [FILE...]
#
# Call it right before `gh release upload TAG FILE --clobber`. For each FILE: if release TAG
# already holds an asset of that name whose content differs, that asset is copied into the
# release "archive-TAG" as "<when it was uploaded>__<name>" first. Identical content, or no
# asset of that name yet, does nothing.
#
# Why: --clobber replaces the only copy. On 2026-10-06 the Turkish regime archive was overwritten
# by an HTML error page, and it could be restored only because the Ministry still served the
# original. A consumer also cannot replay a past import once the bytes it loaded are gone.
#
# The archive lives under its own tag on purpose. Consumers resolve a release by its exact tag
# and some take every asset in it, so a superseded copy beside the live one would be imported.
#
# Bounded: only the newest ARCHIVE_KEEP copies (default 5) of each name are kept.
#
# Never fails the caller. Publishing today's data matters more than keeping yesterday's, so a
# problem here is a warning on the run and the upload goes ahead.
set -u

TAG="${1:?usage: archive-superseded.sh TAG FILE [FILE...]}"; shift
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
KEEP="${ARCHIVE_KEEP:-5}"
ARCHIVE_TAG="archive-$TAG"

warn() { echo "::warning::archive-superseded: $*"; }

gh api "repos/$REPO/releases/tags/$TAG" --jq '.id' >/dev/null 2>&1 || exit 0   # no release yet

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ensure_archive_release() {
  gh release view "$ARCHIVE_TAG" -R "$REPO" >/dev/null 2>&1 && return 0
  gh release create "$ARCHIVE_TAG" -R "$REPO" --latest=false --prerelease \
    --title "Superseded assets of $TAG" \
    --notes "Copies of assets that were replaced in [$TAG](https://github.com/$REPO/releases/tag/$TAG), named by the time the replaced copy had been uploaded. Kept for recovery and replay, the newest $KEEP per file. Not a data release: nothing should sync from here." \
    >/dev/null
}

for file in "$@"; do
  [ -f "$file" ] || continue
  name=$(basename "$file")

  # "-" for a missing digest: an empty field would vanish when the line is split on tabs.
  existing=$(ASSET="$name" gh api "repos/$REPO/releases/tags/$TAG"     --jq '.assets[] | select(.name == env.ASSET) | [.id, (.digest // "-"), .updated_at] | @tsv' 2>/dev/null)
  [ -n "$existing" ] || continue                       # first upload of this name
  IFS=$'\t' read -r id digest updated <<<"$existing"

  new_sha=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$digest" = "sha256:$new_sha" ]; then continue; fi   # same bytes: nothing is lost

  old="$work/$name"
  if ! gh api -H "Accept: application/octet-stream" "repos/$REPO/releases/assets/$id" >"$old" 2>/dev/null || [ ! -s "$old" ]; then
    warn "could not download the current $name from $TAG; it will be overwritten without a copy"
    continue
  fi
  # Assets uploaded before GitHub recorded digests carry none; compare the bytes instead.
  if [ "$digest" = "-" ] && [ "$(sha256sum "$old" | cut -d' ' -f1)" = "$new_sha" ]; then rm -f "$old"; continue; fi

  stamp=$(printf '%s' "$updated" | tr -d ':-')          # 2026-10-06T03:52:53Z -> 20261006T035253Z
  kept="$work/${stamp}__${name}"
  mv "$old" "$kept"

  if ensure_archive_release && gh release upload "$ARCHIVE_TAG" "$kept" -R "$REPO" --clobber >/dev/null; then
    echo "Archived the superseded $name (uploaded $updated) to $ARCHIVE_TAG"
  else
    warn "could not archive the superseded $name to $ARCHIVE_TAG; it will be overwritten without a copy"
    rm -f "$kept"; continue
  fi
  rm -f "$kept"

  # Newest KEEP copies of this name stay. The stamp prefix sorts chronologically.
  gh api --paginate "repos/$REPO/releases/tags/$ARCHIVE_TAG" --jq '.assets[] | [.id, .name] | @tsv' 2>/dev/null \
    | awk -F'\t' -v suffix="__$name" 'length($2) > length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix' \
    | sort -t$'\t' -k2,2r | tail -n +"$((KEEP + 1))" \
    | while IFS=$'\t' read -r old_id old_name; do
        gh api -X DELETE "repos/$REPO/releases/assets/$old_id" --silent 2>/dev/null && echo "  dropped the oldest copy: $old_name"
      done
done
exit 0
