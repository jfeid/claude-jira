#!/usr/bin/env bash
# Sample data for trying the plugin or reviewing it without touching real
# logs: three days of made-up ABC-* timers in a project named acme-shop (from
# the worklog-timer plugin's own sample) and one worklog already logged.
#   bash tests/sample-data.sh DIR
# Then, in the same shell:
#   export TIMER_HOME=DIR JIRA_HOME=DIR/jira TIMER_PROJECT=acme-shop
#   jira.sh day yesterday; jira.sh month; jira.sh figures ABC-118
set -euo pipefail

dir="${1:?usage: bash tests/sample-data.sh DIR}"
timer_sample="$(dirname "$(command -v timer.sh 2>/dev/null || echo "${TIMER_BIN:?set TIMER_BIN or put timer.sh on PATH}")")/../tests/sample-data.sh"
if [ -r "$timer_sample" ]; then
    bash "$timer_sample" "$dir" >/dev/null
else
    echo "worklog-timer's tests/sample-data.sh not found next to timer.sh" >&2
    exit 1
fi
mkdir -p "$dir/jira/logs"
now=$(date +%s)
# ABC-118: 3h of its time logged as worklog 10001, started the day before yesterday.
printf 'ABC-118\t10800\t10001\t%s\t-\tInvestigation and fix of the export\t%s\n' \
    "$now" "$((now - 2 * 86400 - 4 * 3600 + 210 * 60))" > "$dir/jira/logs/acme-shop.tsv"
cat > "$dir/jira/config.json" <<'JSON'
{
  "cloudId": "00000000-0000-0000-0000-000000000000",
  "siteUrl": "https://example.atlassian.net",
  "commentLanguage": "English",
  "worklogLanguage": "English",
  "transitions": { "start": ["In Progress"], "close": ["Deployed", "Ready for testing"], "done": ["Done"] }
}
JSON
echo "Sample data in $dir"
echo "export TIMER_HOME='$dir' JIRA_HOME='$dir/jira' TIMER_PROJECT=acme-shop"
