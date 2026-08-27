#!/bin/sh
# Release operations that work on both GitHub and Forgejo.
#
# Every sync workflow publishes its output as release assets. On GitHub that was
# `gh release ...`; on our own forge there is no `gh`, and gh only speaks GitHub's
# API, so installing it would not help. Rather than fork the workflows, this script
# takes the same arguments gh took and talks to whichever forge the job is actually
# running on:
#
#   github.com    -> delegates straight to gh, so behaviour there is unchanged
#   anything else -> Forgejo's release API, authenticated with the job's own token
#
# One copy of each workflow, then. A run on the forge publishes to the forge; a run
# on GitHub publishes to GitHub, exactly as before.
#
# Subcommands mirror gh where gh has one, and fill the gaps where it does not:
#
#   view TAG [--json assets --jq EXPR]   exits non-zero when the release is absent
#   create TAG --title T --notes N
#   upload TAG FILE... [--clobber]
#   download TAG [-p|--pattern GLOB] [-D|--dir DIR]
#   id TAG                               prints the numeric release id, or nothing
#   asset-list TAG                       prints "id<TAB>name" per asset
#   asset-delete TAG ASSET_ID
#
# The last three replace raw `gh api` calls, which could not simply be repointed:
# GitHub deletes an asset at /releases/assets/{id}, Forgejo at
# /releases/{release_id}/assets/{id}.

set -eu

usage() {
  echo "usage: release.sh {view|create|upload|download|id|asset-list|asset-delete} TAG [...]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
CMD=$1
shift

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"

# ---------------------------------------------------------------- GitHub path

case "$SERVER" in
  *github.com*)
    case "$CMD" in
      id)
        gh api "repos/$REPO/releases/tags/$1" --jq '.id' 2>/dev/null || true
        ;;
      asset-list)
        rel=$(gh api "repos/$REPO/releases/tags/$1" --jq '.id' 2>/dev/null || true)
        case "$rel" in (''|*[!0-9]*) exit 0 ;; esac
        gh api --paginate "repos/$REPO/releases/$rel/assets" --jq '.[] | [.id, .name] | @tsv'
        ;;
      asset-delete)
        gh api -X DELETE "repos/$REPO/releases/assets/$2" --silent
        ;;
      *)
        exec gh release "$CMD" "$@"
        ;;
    esac
    exit 0
    ;;
esac

# ---------------------------------------------------------------- Forgejo path

[ -n "$TOKEN" ] || { echo "release.sh: no token in GH_TOKEN or GITHUB_TOKEN" >&2; exit 1; }

# GITHUB_API_URL already carries the /api/v1 suffix on Forgejo; derive it if it does not.
API="${GITHUB_API_URL:-$SERVER/api/v1}"
case "$API" in */api/v1) ;; *) API="$SERVER/api/v1" ;; esac

BODY=$(mktemp)
cleanup() { rm -f "$BODY"; }
trap cleanup EXIT INT TERM

die() { echo "release.sh: $*" >&2; exit 1; }

# req METHOD PATH [curl args...]
#
# Prints the HTTP status; leaves the response body in $BODY. The status is
# returned on stdout rather than set in a variable on purpose: every caller runs
# this inside a command substitution, and a variable assigned in a subshell is
# invisible to the parent.
req() {
  _m=$1
  _p=$2
  shift 2
  curl -sS -o "$BODY" -w '%{http_code}' \
    --retry 3 --retry-delay 5 --retry-connrefused \
    -X "$_m" -H "Authorization: token $TOKEN" \
    "$API/repos/$REPO$_p" "$@"
}

# Fetches the release into $BODY. Returns non-zero when it does not exist.
fetch_release() {
  _st=$(req GET "/releases/tags/$1")
  [ "$_st" = "200" ]
}

case "$CMD" in

  view)
    [ $# -ge 1 ] || usage
    tag=$1; shift
    jqexpr=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --jq)   jqexpr=$2; shift 2 ;;
        --json) shift 2 ;;          # the whole release object is fetched regardless
        *)      shift ;;
      esac
    done
    fetch_release "$tag" || exit 1
    if [ -n "$jqexpr" ]; then
      jq -r "$jqexpr" < "$BODY"
    else
      printf '%s\n' "$tag"
    fi
    ;;

  create)
    [ $# -ge 1 ] || usage
    tag=$1; shift
    title=$tag
    notes=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title)      title=$2; shift 2 ;;
        --notes)      notes=$2; shift 2 ;;
        --notes-file) notes=$(cat "$2"); shift 2 ;;
        *)            shift ;;
      esac
    done
    payload=$(jq -n --arg t "$tag" --arg n "$title" --arg b "$notes" \
      '{tag_name: $t, name: $n, body: $b}')
    st=$(req POST "/releases" -H 'Content-Type: application/json' -d "$payload")
    case "$st" in
      201)     printf '%s\n' "$tag" ;;
      409|422) printf '%s\n' "$tag" ;;   # created concurrently between view and create
      *)       die "create $tag failed (HTTP $st): $(cat "$BODY")" ;;
    esac
    ;;

  upload)
    [ $# -ge 1 ] || usage
    tag=$1; shift
    clobber=0
    files=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --clobber) clobber=1 ;;
        -*)        ;;                    # flags we do not implement are ignored
        *)         files="$files $1" ;;
      esac
      shift
    done
    fetch_release "$tag" || die "no release $tag to upload to"
    rid=$(jq -r '.id' < "$BODY")
    existing=$(jq -r '.assets[] | [.name, (.id|tostring)] | @tsv' < "$BODY")
    for f in $files; do
      [ -f "$f" ] || die "no such file: $f"
      name=$(basename "$f")
      old=$(printf '%s\n' "$existing" | awk -F'\t' -v n="$name" '$1 == n { print $2; exit }')
      if [ -n "$old" ]; then
        [ "$clobber" = "1" ] || die "asset $name already exists (pass --clobber to replace)"
        req DELETE "/releases/$rid/assets/$old" >/dev/null
      fi
      st=$(req POST "/releases/$rid/assets?name=$name" -F "attachment=@$f")
      case "$st" in
        200|201) echo "uploaded $name" ;;
        *)       die "upload of $name failed (HTTP $st): $(cat "$BODY")" ;;
      esac
    done
    ;;

  download)
    [ $# -ge 1 ] || usage
    tag=$1; shift
    pattern='*'
    dir="."
    while [ $# -gt 0 ]; do
      case "$1" in
        -p|--pattern) pattern=$2; shift 2 ;;
        -D|--dir)     dir=$2; shift 2 ;;
        *)            shift ;;
      esac
    done
    fetch_release "$tag" || die "no release $tag"
    mkdir -p "$dir"
    # Select first, download second, so the match count survives the loop: a
    # `while read` fed by a pipe runs in a subshell and cannot report back.
    matches=$(mktemp)
    jq -r '.assets[] | [.name, .browser_download_url] | @tsv' < "$BODY" \
    | while IFS="$(printf '\t')" read -r name url; do
        # shellcheck disable=SC2254  # $pattern is a glob and is meant to expand
        case "$name" in
          $pattern) printf '%s\t%s\n' "$name" "$url" ;;
        esac
      done > "$matches"
    if [ ! -s "$matches" ]; then
      rm -f "$matches"
      exit 1
    fi
    while IFS="$(printf '\t')" read -r name url; do
      curl -sS -L --retry 3 --retry-delay 5 \
        -H "Authorization: token $TOKEN" -o "$dir/$name" "$url"
      echo "downloaded $name"
    done < "$matches"
    rm -f "$matches"
    ;;

  id)
    [ $# -ge 1 ] || usage
    if fetch_release "$1"; then jq -r '.id' < "$BODY"; fi
    ;;

  asset-list)
    [ $# -ge 1 ] || usage
    if fetch_release "$1"; then jq -r '.assets[] | [.id, .name] | @tsv' < "$BODY"; fi
    ;;

  asset-delete)
    [ $# -ge 2 ] || usage
    fetch_release "$1" || die "no release $1"
    rid=$(jq -r '.id' < "$BODY")
    st=$(req DELETE "/releases/$rid/assets/$2")
    case "$st" in
      204|200) ;;
      *)       die "delete of asset $2 failed (HTTP $st)" ;;
    esac
    ;;

  *)
    usage
    ;;
esac
