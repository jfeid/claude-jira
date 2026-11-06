#!/usr/bin/env bash
# End-to-end checks of bin/jira.sh against throwaway logs, so the script can be
# tested on every platform CI offers (Linux, macOS, Windows/Git Bash).
#   bash tests/jira-cli.sh
# Needs timer.sh from the worklog-timer plugin: TIMER_BIN, else timer.sh on
# PATH, else ../claude-timer/bin/timer.sh next to this repository.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
J="$HERE/bin/jira.sh"
if [ -z "${TIMER_BIN:-}" ]; then
    TIMER_BIN=$(command -v timer.sh 2>/dev/null || true)
    [ -z "$TIMER_BIN" ] && [ -x "$HERE/../claude-timer/bin/timer.sh" ] && TIMER_BIN="$HERE/../claude-timer/bin/timer.sh"
fi
[ -n "$TIMER_BIN" ] && [ -x "$TIMER_BIN" ] || { echo "timer.sh not found; set TIMER_BIN"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# A folder with a space, to catch unquoted paths.
export JIRA_HOME="$TMP/jira home" TIMER_HOME="$TMP/timer home"
export TIMER_BIN TIMER_PROJECT=ci TIMER_SESSION_ID=ci-session TZ=UTC
export CLAUDE_CONFIG_DIR="$TMP/claude"
unset CLAUDE_CODE_SESSION_ID CLAUDE_PID TIMER_SESSION_NAME KEY_PREFIX_INCLUDE KEY_PREFIX_EXCLUDE JIRA_SESSION_TASK

fails=0
out=""
run() {
    local name=$1 want=$2 code
    shift 2
    out=$("$J" "$@" 2>&1); code=$?
    if [ "$code" = "$want" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name: exit $code, expected $want"
        printf '%s\n' "$out" | sed 's/^/     /'
        fails=$((fails + 1))
    fi
}
has() {
    if printf '%s\n' "$out" | grep -qF -- "$1"; then
        echo "ok     has '$1'"
    else
        echo "FAIL   no '$1' in:"
        printf '%s\n' "$out" | sed 's/^/     /'
        fails=$((fails + 1))
    fi
}
hasnt() {
    if printf '%s\n' "$out" | grep -qF -- "$1"; then
        echo "FAIL   unexpected '$1' in:"
        printf '%s\n' "$out" | sed 's/^/     /'
        fails=$((fails + 1))
    else
        echo "ok     no '$1'"
    fi
}

# Timer log, UTC:
#   ABC-1  2026-09-07 09:00-10:10 (70m), 2026-09-08 14:00-14:20 (20m)
#   ABC-2  2026-09-07 23:30 - 2026-09-08 00:45 (30m + 45m, across midnight)
#   XYZ-9  2026-09-08 14:00-14:20 (another tracker's key)
mkdir -p "$TIMER_HOME/logs"
{
    printf 'ABC-1\tSTART\t1788771600\t-\nABC-1\tSTOP\t1788775800\t-\n'
    printf 'ABC-2\tSTART\t1788823800\t-\nABC-2\tSTOP\t1788828300\t-\n'
    printf 'ABC-1\tSTART\t1788876000\t-\nABC-1\tSTOP\t1788877200\t-\n'
    printf 'XYZ-9\tSTART\t1788876000\t-\nXYZ-9\tSTOP\t1788877200\t-\n'
} > "$TIMER_HOME/logs/ci.tsv"

echo "== keys"
run "key argument" 0 key ABC-12;                        has "ABC-12"
run "key lower case" 0 key abc-12;                      has "ABC-12"
run "key from URL" 0 key "https://acme.atlassian.net/browse/ABC-77?focus=1"; has "ABC-77"
run "key, nothing" 1 key;                               has "this session has no task"
run "key, not a key" 1 key hello;                       has "No Jira key"
JIRA_SESSION_TASK=ABC-5 run "key from session task" 0 key; has "ABC-5"
KEY_PREFIX_EXCLUDE="XYZ" run "excluded prefix" 1 key XYZ-1; has "excluded"
KEY_PREFIX_INCLUDE="XYZ" KEY_TRACKER=Plane run "include only" 1 key ABC-1; has "not a Plane key"

echo "== durations"
run "1h 30m" 0 parse-time "1h 30m";   has "5400"
run "1.5h" 0 parse-time 1.5h;         has "5400"
run "2d" 0 parse-time 2d;             has "57600"
run "bad" 1 parse-time 1x;            has "Cannot parse"

echo "== config"
run "config missing" 1 config;                          has "jira.sh init"
run "init bad cloud id" 1 init 'a b' https://acme.atlassian.net
run "init bad site" 1 init 1234-abcd http://acme
run "init" 0 init 1234-abcd https://acme.atlassian.net/; has "Wrote"
run "init again" 1 init 1234-abcd https://acme.atlassian.net; has "exists already"
run "config" 0 config;     has "site_url=https://acme.atlassian.net"; has "comment_language=English"; has "staging_label=on-staging"
run "url" 0 url abc-3;     has "https://acme.atlassian.net/browse/ABC-3"
# The config's excludePrefixes, read with jq or without it.
sed 's/"excludePrefixes": \[\]/"excludePrefixes": ["XYZ", "QQ"]/' "$JIRA_HOME/config.json" > "$TMP/c" && mv "$TMP/c" "$JIRA_HOME/config.json"
run "config prefixes" 0 config;                         has "exclude_prefixes=XYZ QQ"
run "excluded by config" 1 key XYZ-9
# The same settings read without jq: `command -v jq` answers "not found"
# (an exported function, since a PATH without jq breaks Git Bash on Windows).
command() { [ "$1 $2" = "-v jq" ] && return 1; builtin command "$@"; }
export -f command
run "config without jq" 0 config;                      has "exclude_prefixes=XYZ QQ"; has "site_url=https://acme.atlassian.net"
unset -f command

echo "== figures and ledger"
run "figures" 0 figures ABC-1
has "tracked_seconds=5400"; has "rounded_seconds=5400"; has "time_spent=1h 30m"
has "started=2026-09-07T09:00:00.000+0000"; has "timer_state=STOPPED"
run "mark-logged bad seconds" 1 mark-logged ABC-1 1h
run "mark-logged bad started" 1 mark-logged ABC-1 60 1 note "next week"
run "mark-logged" 0 mark-logged ABC-1 4500 10001 "Fix" "2026-09-07T09:00:00.000+0000"
has "ABC-1: 1h 15m recorded as logged (worklog 10001, started 2026-09-07 09:00)"
run "mark-logged +03:00" 0 mark-logged ABC-2 900 10002 "Review" "2026-09-08T03:00:00+03:00"
has "started 2026-09-08 00:00"
run "logged" 0 logged;               has "10001"; has "10002"
run "logged ABC-2" 0 logged ABC-2;   has "10002"; hasnt "10001"
run "figures after" 0 figures ABC-1; has "logged_seconds=4500"; has "unlogged_seconds=900"; has "time_spent=15m"

echo "== day"
run "day 2026-09-07" 0 day 2026-09-07
has "tickets=2"; has "[ABC-1]"; has "tracked_day_seconds=4200"; has "rounded_day=1h 15m"
has "logged_day_seconds=4500"; has "10001"
run "day 2026-09-08" 0 day 2026-09-08 --here
has "tickets=2"; has "[ABC-2]"; has "tracked_day_seconds=2700"; hasnt "XYZ-9"; has "10002"
run "day, nothing" 0 day 2026-09-01; has "tickets=0"; has "none"
run "day bad" 1 day "not a date at all"

echo "== month"
run "month 09-2026" 0 month 09-2026
has "days=2"; has "tickets=2"; has "tracked_seconds=9900"; has "billable_seconds=10800"
has "billable_hours=3.00"; has "logged_seconds=5400"; has "2026-09-07  Mon"; hasnt "XYZ-9"
run "month 2026-09 --here" 0 month 2026-09 --here; has "billable_seconds=10800"
run "month empty" 0 month 01-2020;  has "No time tracked or logged in 2020-01."
run "month bad" 1 month 13-2026

echo "== write failure"
mkdir -p "$TMP/ro"
: > "$TMP/ro/file"   # a file where the folder should be
JIRA_HOME="$TMP/ro/file" run "mark-logged cannot write" 1 mark-logged ABC-1 60; has "cannot write"

echo "== git"
if command -v git >/dev/null 2>&1; then
    export GIT_AUTHOR_NAME=ci GIT_AUTHOR_EMAIL=ci@example.com GIT_COMMITTER_NAME=ci GIT_COMMITTER_EMAIL=ci@example.com
    g() { git -C "$TMP/work" "$@" >/dev/null 2>&1; }
    git init -q --bare -b master "$TMP/origin.git" 2>/dev/null || { git init -q --bare "$TMP/origin.git"; git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/master; }
    git clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
    g checkout -q -b master
    g commit -q --allow-empty -m "Initial"
    g push -q origin master
    g checkout -q -b ABC-6;   g commit -q --allow-empty -m "Work on the export"; g push -q origin ABC-6
    g checkout -q -b staging master; g commit -q --allow-empty -m "abc-5 fix the login"
    g merge -q --no-ff -m "Merge ABC-6" ABC-6; g push -q origin staging
    g remote set-head origin master
    g fetch -q origin
    cd "$TMP/work" || exit 1
    run "base-branch" 0 base-branch;    has "master"
    run "staging-keys" 0 staging-keys;  has "ABC-5"; has "ABC-6"
    run "staging-keys bad ref" 1 staging-keys origin/nope; has "Unknown ref"
    run "context" 0 context ABC-5;      has "abc-5 fix the login"
    cd "$HERE" || exit 1
else
    echo "skip (no git)"
fi

echo
if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
