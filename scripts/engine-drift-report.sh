#!/usr/bin/env bash
# shellcheck disable=SC2016 # Backticks in printf formats are Markdown code spans.
# Turns a scheduled patch-check result into GitHub issue state, so a Darktide
# patch that breaks BetterBots' engine contracts produces one notification per
# new decompiled-source version instead of one per scheduled run.
#
#   patch-check failed, no open drift issue        -> open one (mentions the owner)
#   patch-check failed, open issue, new source SHA -> comment with the new errors
#   patch-check failed, SHA already reported       -> nothing
#   patch-check passed, open drift issue           -> comment and close it
#
# Writes `reported=true|false` to $GITHUB_OUTPUT (when set) so the workflow can
# fail the run only when it reported something new.
#
# Required environment: CHECK_STATUS, UPSTREAM_SHA, UPSTREAM_SUBJECT, LOG_FILE,
# RUN_URL, NOTIFY_USER. Uses `gh` with GH_TOKEN for the current repository.
set -euo pipefail

: "${CHECK_STATUS:?}" "${UPSTREAM_SHA:?}" "${UPSTREAM_SUBJECT:?}" "${LOG_FILE:?}" "${RUN_URL:?}" "${NOTIFY_USER:?}"

LABEL="engine-drift"
UPSTREAM_REPO="https://github.com/Aussiemon/Darktide-Source-Code"
marker="<!-- engine-drift-sha: $UPSTREAM_SHA -->"
reported=false

set_output() {
	if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
		echo "reported=$reported" >> "$GITHUB_OUTPUT"
	fi
	echo "engine-drift: reported=$reported"
}

failure_details() {
	local errors
	errors=$(grep -E '^ERROR:' "$LOG_FILE" || true)
	if [[ -z "$errors" ]]; then
		# Setup failures (missing checkout, missing tools) print no ERROR lines.
		errors=$(tail -n 40 "$LOG_FILE")
	fi
	printf '```\n%s\n```\n' "$errors"
}

source_line() {
	printf 'Decompiled source: [%s](%s/commit/%s) (`%s`)\n' \
		"$UPSTREAM_SUBJECT" "$UPSTREAM_REPO" "$UPSTREAM_SHA" "${UPSTREAM_SHA:0:8}"
}

open_issue=$(gh issue list --label "$LABEL" --state open --limit 1 --json number --jq '.[0].number // empty')

if [[ "$CHECK_STATUS" == "0" ]]; then
	if [[ -n "$open_issue" ]]; then
		gh issue comment "$open_issue" --body "$(
			printf '`make patch-check` passes again.\n\n'
			source_line
			printf '\nRun: %s\n' "$RUN_URL"
		)"
		gh issue close "$open_issue"
		echo "engine-drift: closed #$open_issue"
	fi
	set_output
	exit 0
fi

if [[ -z "$open_issue" ]]; then
	gh issue create \
		--label "$LABEL" \
		--title "Engine drift: patch-check fails on ${UPSTREAM_SUBJECT}" \
		--body "$(
			printf '@%s The scheduled `make patch-check` against the latest decompiled Darktide source failed.\n\n' "$NOTIFY_USER"
			source_line
			printf 'Run: %s\n\n' "$RUN_URL"
			failure_details
			printf '\nReproduce locally with `make patch-check-refresh`. This issue closes itself once the scheduled check passes.\n\n%s\n' "$marker"
		)"
	reported=true
	set_output
	exit 0
fi

# Fetch separately so a failed `gh` read aborts (set -e) instead of looking like
# "marker not found" and re-posting a version that was already reported.
thread=$(gh issue view "$open_issue" --json body,comments --jq '[.body, .comments[].body] | join("\n")')
if ! grep -qF "$marker" <<< "$thread"; then
	gh issue comment "$open_issue" --body "$(
		printf '@%s patch-check still fails on a newer decompiled source.\n\n' "$NOTIFY_USER"
		source_line
		printf 'Run: %s\n\n' "$RUN_URL"
		failure_details
		printf '\n%s\n' "$marker"
	)"
	reported=true
fi

set_output
