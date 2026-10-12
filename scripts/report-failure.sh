#!/usr/bin/env bash
# report-failure.sh WORKFLOW RUN_URL
#
# Says that a sync failed, where a person will see it: an issue on this repository, which GitHub
# mails to everyone watching it. One open issue per workflow; a later failure of the same workflow
# adds a comment to it, so a publisher that is down for a week is one thread, not fourteen.
# Close the issue when the cause is fixed; the next failure opens a new one.
#
# Why an issue. A failed scheduled run used to tell nobody anything that reached further than the
# Actions tab, and the consumer found out six hours later from a failed import on two hosts. It
# needs no secret (the job's own token, with `issues: write`), so it works for every workflow
# from the day it is added. Relaying to the alerts room as well needs the relay's token as a
# repository secret and can be added here, in one place, when that exists.
#
# Never fails the job it reports on: it runs after the failure and must not hide it.
set -u
WORKFLOW="${1:?usage: report-failure.sh WORKFLOW RUN_URL}"
RUN_URL="${2:-}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
LABEL="sync-failure"
TITLE="Sync failed: $WORKFLOW"
WHEN=$(date -u +'%Y-%m-%d %H:%M UTC')
BODY="The workflow **$WORKFLOW** failed on $WHEN.

Run: $RUN_URL

Nothing was published by the failed step, and a file the publish gate refused is not on the release: the release keeps what it had. Consumers stay on the last good data until this is fixed. The run's log names the file and the reason.

Close this issue when the cause is fixed."

gh label create "$LABEL" -R "$REPO" --color B60205 --description "A scheduled sync failed" >/dev/null 2>&1 || true

existing=$(gh issue list -R "$REPO" --state open --label "$LABEL" --search "in:title \"$TITLE\"" --json number,title \
  --jq ".[] | select(.title == \"$TITLE\") | .number" 2>/dev/null | head -n 1)

if [ -n "$existing" ]; then
  gh issue comment "$existing" -R "$REPO" --body "Failed again on $WHEN. Run: $RUN_URL" >/dev/null 2>&1 \
    && echo "Commented on issue #$existing" || echo "::warning::report-failure: could not comment on issue #$existing"
else
  gh issue create -R "$REPO" --title "$TITLE" --label "$LABEL" --body "$BODY" >/dev/null 2>&1 \
    && echo "Opened an issue: $TITLE" || echo "::warning::report-failure: could not open an issue"
fi
exit 0
