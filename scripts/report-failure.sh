#!/usr/bin/env bash
# report-failure.sh WORKFLOW RUN_URL
#
# Says that a sync failed, where a person will see it: an issue on this repository, which GitHub
# mails to everyone watching it. One open issue per workflow; a later failure of the same workflow
# adds a comment to it, so a publisher that is down for a week is one thread, not fourteen.
# The next green run of that workflow closes it (--recovered, below); a failure after that opens a new one.
#
# Why an issue. A failed scheduled run used to tell nobody anything that reached further than the
# Actions tab, and the consumer found out six hours later from a failed import on two hosts. It
# needs no secret (the job's own token, with `issues: write`), so it works for every workflow
# from the day it is added. Relaying to the alerts room as well needs the relay's token as a
# repository secret and can be added here, in one place, when that exists.
#
# report-failure.sh --recovered WORKFLOW RUN_URL
#
# Run by every successful sync: closes that workflow's open issue with a comment naming the green
# run. Without it the issues outlived their failures (CS/RD2's of 2026-10-12 was still open after
# four green runs, Norway's after one), and an open issue stopped meaning "broken now".
#
# Never fails the job it reports on: it runs after the failure and must not hide it.
set -u
RECOVERED=""
if [ "${1:-}" = "--recovered" ]; then RECOVERED=1; shift; fi
WORKFLOW="${1:?usage: report-failure.sh [--recovered] WORKFLOW RUN_URL}"
RUN_URL="${2:-}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
LABEL="sync-failure"
TITLE="Sync failed: $WORKFLOW"
WHEN=$(date -u +'%Y-%m-%d %H:%M UTC')
BODY="The workflow **$WORKFLOW** failed on $WHEN.

Run: $RUN_URL

Nothing was published by the failed step, and a file the publish gate refused is not on the release: the release keeps what it had. Consumers stay on the last good data until this is fixed. The run's log names the file and the reason.

The next green run of this workflow closes this issue."

existing=$(gh issue list -R "$REPO" --state open --label "$LABEL" --search "in:title \"$TITLE\"" --json number,title \
  --jq ".[] | select(.title == \"$TITLE\") | .number" 2>/dev/null | head -n 1)

if [ -n "$RECOVERED" ]; then
  [ -n "$existing" ] || exit 0
  gh issue close "$existing" -R "$REPO" --comment "Recovered: the workflow ran green on $WHEN. Run: $RUN_URL" >/dev/null 2>&1 \
    && echo "Closed issue #$existing: the workflow ran green" || echo "::warning::report-failure: could not close issue #$existing"
  exit 0
fi

gh label create "$LABEL" -R "$REPO" --color B60205 --description "A scheduled sync failed" >/dev/null 2>&1 || true

if [ -n "$existing" ]; then
  gh issue comment "$existing" -R "$REPO" --body "Failed again on $WHEN. Run: $RUN_URL" >/dev/null 2>&1 \
    && echo "Commented on issue #$existing" || echo "::warning::report-failure: could not comment on issue #$existing"
else
  gh issue create -R "$REPO" --title "$TITLE" --label "$LABEL" --body "$BODY" >/dev/null 2>&1 \
    && echo "Opened an issue: $TITLE" || echo "::warning::report-failure: could not open an issue"
fi
exit 0
