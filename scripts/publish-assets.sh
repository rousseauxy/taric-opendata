#!/usr/bin/env bash
# publish-assets.sh [options] TAG FILE [FILE...]
#
# The one way a sync workflow puts a file on a release. Every asset passes the same gate before it
# is uploaded, whatever script fetched it:
#
#   - it is not empty;
#   - a .zip opens and holds at least one entry, a .gz passes its own check;
#   - it is not an HTML page under another name (a publisher that moves a file usually answers the
#     old address with 200 and an error page);
#   - it is not under half the size of the asset of the same name it would replace.
#
# Why one script. Each of those rules was learned from an incident and then written into the one
# sync script that had failed: on 2026-10-06 the Turkish regime archive was overwritten by an
# HTML error page, the fix went into sync-tr.ps1 and sync-nl.ps1, and sixteen other scripts kept
# publishing whatever they had been handed. scripts/lib/Http.psm1 did the same for retries after
# Norway's 522s, and the lint that came with it is why no script calls HTTP unguarded today. This
# is that, for publishing. lint.yml fails any workflow that calls `gh release upload` itself and
# is not on the shrinking list in scripts/publish-allowlist.txt.
#
# What it does with a file that passes:
#   - no asset of that name on the release: upload;
#   - an asset of that name with the same bytes: nothing;
#   - an asset of that name with other bytes: with --replace, keep a copy of the old one
#     (archive-superseded.sh) and overwrite; without it, leave the release as it is and say so,
#     because a dated file name that changes content is a publisher restating history, and that
#     is a person's decision.
#
# A file that fails the gate is not uploaded, the others still are, and the exit code is 1, so the
# job is red and the failure step reports it. The release keeps what it had.
#
# Options
#   --replace                 assets of these names are republished under a constant name
#   --title T --notes N       create the release when it does not exist yet
#   --full-pattern REGEX      which asset names are a full snapshot (delta sources)
#   --carry-full-from TAG     when the release holds no full snapshot after this run, copy the newest
#                             one from that release (the previous month), so a month never starts on
#                             deltas alone: the Netherlands served nothing for three days in
#                             September 2026 over exactly that
#   --manifest                write release-manifest.json (see below); off until every consumer
#                             ignores that name, because an extra asset moves a consumer's freshness
#                             marker once
#
# Environment: GITHUB_REPOSITORY, GH_TOKEN. PUBLISH_ALLOW_SHRINK=1 accepts a smaller replacement
# for one run, for the day a publisher really does halve a file.
set -u

REPLACE=""; TITLE=""; NOTES=""; FULL_PATTERN=""; CARRY_FROM=""; MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --replace) REPLACE=1; shift ;;
    --title) TITLE="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --full-pattern) FULL_PATTERN="$2"; shift 2 ;;
    --carry-full-from) CARRY_FROM="$2"; shift 2 ;;
    --manifest) MANIFEST=1; shift ;;
    --) shift; break ;;
    -*) echo "::error::publish-assets: unknown option $1"; exit 2 ;;
    *) break ;;
  esac
done
TAG="${1:?usage: publish-assets.sh [options] TAG FILE [FILE...]}"; shift
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3 || command -v python || true)"

refused=0
refuse() { echo "::error::publish-assets: $1 NOT published: $2"; refused=$((refused + 1)); }

# ── The gate ──────────────────────────────────────────────────────────────────────────────────
gate() {
  local file="$1" name; name=$(basename "$file")
  [ -s "$file" ] || { echo "the file is empty"; return 1; }
  case "${name,,}" in
    *.zip)
      [ -n "$PY" ] || { echo "no python to open the archive with"; return 1; }
      "$PY" - "$file" <<'PYEOF' || { echo "it does not open as a zip archive with at least one entry"; return 1; }
import sys, zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        sys.exit(0 if len(z.namelist()) > 0 else 1)
except Exception:
    sys.exit(1)
PYEOF
      ;;
    *.gz)
      gzip -t "$file" 2>/dev/null || { echo "it is not a valid gzip stream"; return 1; }
      ;;
  esac
  case "${name,,}" in
    *.html|*.htm) ;;
    *)
      if head -c 512 "$file" | tr -d '\000' | tr 'A-Z' 'a-z' | grep -q -E '<!doctype html|<html[ >]'; then
        echo "it is an HTML page, not the file its name says"; return 1
      fi
      ;;
  esac
  return 0
}

# ── The release ───────────────────────────────────────────────────────────────────────────────
if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  [ $# -gt 0 ] || [ -n "$CARRY_FROM" ] || { echo "publish-assets: nothing to publish and no release $TAG; nothing done"; exit 0; }
  gh release create "$TAG" -R "$REPO" --title "${TITLE:-$TAG}" --notes "${NOTES:-Synced by taric-opendata.}" >/dev/null \
    || { echo "::error::publish-assets: could not create release $TAG"; exit 1; }
  echo "Created release $TAG"
fi

# One upload, tried four times: a release left half-updated by a dropped connection is worse than
# a slow job. Extra arguments (--clobber) are passed through.
upload() {
  local try
  for try in 1 2 3 4; do
    gh release upload "$@" -R "$REPO" >/dev/null 2>&1 && return 0
    [ "$try" = 4 ] || sleep $((try * 5))
  done
  return 1
}

assets() { gh api --paginate "repos/$REPO/releases/tags/$1" --jq '.assets[] | [.name, .size, (.digest // "-")] | @tsv' 2>/dev/null; }
existing=$(assets "$TAG")

for file in "$@"; do
  [ -f "$file" ] || continue
  name=$(basename "$file")

  if ! why=$(gate "$file"); then refuse "$name" "$why"; continue; fi

  row=$(printf '%s\n' "$existing" | awk -F'\t' -v n="$name" '$1 == n')
  if [ -z "$row" ]; then
    if upload "$TAG" "$file"; then echo "Published: $name"; else refuse "$name" "the upload failed"; fi
    continue
  fi

  old_size=$(printf '%s' "$row" | cut -f2); old_digest=$(printf '%s' "$row" | cut -f3)
  new_size=$(wc -c <"$file" | tr -d ' '); new_sha=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$old_digest" = "sha256:$new_sha" ]; then echo "Unchanged: $name"; continue; fi
  if [ "$old_digest" = "-" ] && [ "$old_size" = "$new_size" ] && [ -z "$REPLACE" ]; then echo "Already published: $name"; continue; fi

  if [ -z "$REPLACE" ]; then
    echo "::warning::publish-assets: $name is already on $TAG with other content ($old_size bytes there, $new_size here); left as it is. A dated file is not overwritten."
    continue
  fi
  if [ "${PUBLISH_ALLOW_SHRINK:-}" != "1" ] && [ "$old_size" -gt 1024 ] && [ $((new_size * 2)) -lt "$old_size" ]; then
    refuse "$name" "it is $new_size bytes against $old_size on the release, under half. Set PUBLISH_ALLOW_SHRINK=1 for one run if the publisher really cut it"
    continue
  fi
  "$HERE/archive-superseded.sh" "$TAG" "$file"
  if upload "$TAG" "$file" --clobber; then echo "Replaced: $name ($old_size -> $new_size bytes)"; else refuse "$name" "the upload failed"; fi
done

# ── A month never starts on deltas alone ──────────────────────────────────────────────────────
if [ -n "$FULL_PATTERN" ] && [ -n "$CARRY_FROM" ]; then
  if ! assets "$TAG" | cut -f1 | grep -q -E "$FULL_PATTERN"; then
    full=$(assets "$CARRY_FROM" | cut -f1 | grep -E "$FULL_PATTERN" | sort | tail -n 1)
    if [ -z "$full" ]; then
      echo "::warning::publish-assets: $TAG holds no full snapshot and $CARRY_FROM has none to carry forward; consumers will refuse this release until one arrives."
    else
      work=$(mktemp -d)
      if gh release download "$CARRY_FROM" -R "$REPO" --pattern "$full" --dir "$work" >/dev/null 2>&1 \
         && why=$(gate "$work/$full") && upload "$TAG" "$work/$full"; then
        echo "Carried forward the full snapshot $full from $CARRY_FROM: $TAG had none yet"
      else
        echo "::warning::publish-assets: could not carry $full forward from $CARRY_FROM to $TAG"
      fi
      rm -rf "$work"
    fi
  fi
fi

# ── What the release holds, as one small file ─────────────────────────────────────────────────
# Deterministic on purpose: no timestamp, so the same assets give the same bytes and the file is
# only replaced when something it describes changed.
if [ -n "$MANIFEST" ] && [ -n "$PY" ]; then
  work=$(mktemp -d)
  assets "$TAG" | FULL_PATTERN="$FULL_PATTERN" TAG="$TAG" "$PY" -c '
import json, os, re, sys
rows = [l.rstrip("\n").split("\t") for l in sys.stdin if l.strip()]
rows = sorted(r for r in rows if r[0] != "release-manifest.json")
pattern = os.environ.get("FULL_PATTERN") or None
fulls = sorted(r[0] for r in rows if pattern and re.search(pattern, r[0]))
doc = {"tag": os.environ["TAG"],
       "fullSnapshot": (fulls[-1] if fulls else None) if pattern else None,
       "declaresFullSnapshot": bool(pattern),
       "assets": [{"name": r[0], "size": int(r[1]), "digest": None if r[2] == "-" else r[2]} for r in rows]}
sys.stdout.write(json.dumps(doc, indent=1, sort_keys=True) + "\n")' >"$work/release-manifest.json"
  new_sha=$(sha256sum "$work/release-manifest.json" | cut -d' ' -f1)
  if assets "$TAG" | awk -F'\t' '$1 == "release-manifest.json" { print $3 }' | grep -q "sha256:$new_sha"; then :
  else upload "$TAG" "$work/release-manifest.json" --clobber && echo "Wrote release-manifest.json"; fi
  rm -rf "$work"
fi

if [ "$refused" -gt 0 ]; then
  echo "::error::publish-assets: $refused file(s) were refused and are NOT on $TAG; the release keeps what it had for them."
  exit 1
fi
exit 0
