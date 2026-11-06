---
name: jira-workflow
description: Jira ticket workflow with time tracking. Start or close a ticket (read it, move its status, run the worklog timer, log the rounded time, draft the closing comment), plus show, status, log, comment, transition, done, mine, staging, a full-day worklog report (day) and a monthly billable-hours report (month). Use for /jira, or when the user asks to start or close a Jira ticket, log time to Jira, or compare timer time with Jira worklogs.
argument-hint: "<start|close|show|status|log|day|month|comment|transition|done|pause|resume|mine|staging|setup|help> [KEY|URL|DATE|MM-YYYY] [...]"
user-invocable: false
allowed-tools: Bash(jira.sh:*) Bash(timer.sh:*) mcp__plugin_atlassian_atlassian__getJiraIssue mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql mcp__plugin_atlassian_atlassian__atlassianUserInfo mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources
---

# Jira ticket workflow

Drive one Jira ticket through the working day: read it, move it to In
Progress, run the timer, log the rounded time, move it to the "deployed"
status and post the closing comment. Uses the Atlassian MCP tools, the
`timer.sh` tracker of the worklog-timer plugin and this plugin's helper
`jira.sh`. Both scripts are on the Bash tool's PATH while the plugins are
enabled; if the shell cannot find `jira.sh`, run
`${CLAUDE_PLUGIN_ROOT}/bin/jira.sh` instead.

## Arguments

$ARGUMENTS - `<action> [KEY|URL] [extra...]`

`KEY` is optional everywhere: when omitted it is the session's task (the
session's name, `/rename ABC-538`, or the last task named with the timer), so
every `/jira` call in that session targets ABC-538. A Jira issue URL is
accepted in place of the key.

- `/jira start [KEY] [--branch|--base]` - read the ticket (fields, comments, attachments), ask whether to work on a `KEY` branch or on the base branch and switch to it, move it to In Progress, start the timer, brief the user
- `/jira close [KEY]` - stop the timer, log the rounded time, move to the "deployed" status, preview the closing comment
- `/jira show [KEY]` - re-read the ticket without changing anything
- `/jira status [KEY]` - one-screen state: Jira status, timer, logged vs unlogged time
- `/jira log [KEY] [1h 30m]` - log work now without closing (timer figure, or the given duration)
- `/jira day [DATE] [--here]` - full-day worklog report: every ticket touched that day across all projects, timer vs Jira worklogs, then log the remainder in one batch after a preview
- `/jira month [MM-YYYY] [--here]` - month report in billable hours: `day` summed over every day of the month with records, per day and per ticket, timer vs Jira worklogs (read-only; current month by default)
- `/jira comment [KEY] <notes>` - draft a comment from the notes, preview, post on confirmation
- `/jira transition [KEY] <status>` - move to any available status
- `/jira done [KEY]` - move to Done (after the reporter verified)
- `/jira pause [KEY]` / `/jira resume [KEY]` - pause or resume the timer; without a key the session's ticket when it can be paused/resumed, otherwise a question
- `/jira mine` - my open tickets
- `/jira staging` - sync the staging label with git: tickets on the staging branch but not on the base branch get it, the rest lose it
- `/jira setup` - create or show the settings file
- `/jira help` - this list

No action given: run `status` when a key resolves, otherwise print the action list.

## Setup (every action)

1. Parse `$ARGUMENTS`: first word is the action, the next word is the key only
   if it looks like `ABC-123` or a Jira URL; everything else is extra input.
   Accept `open`/`begin` as aliases of `start`, `finish`/`stop` of `close`,
   `today`/`report` of `day`, `monthly` of `month`, `--master`/`--main` of
   `--base`.

2. Resolve the key (skip this step for `day`, `month`, `mine`, `staging`,
   `setup` and `help`, which take no key, and for `pause` and `resume` without
   an argument, which resolve through the timer; see below). Run it from
   inside the project, so the timer log and the ledger match the repository:

   ```bash
   jira.sh key [KEY]
   ```

   Non-zero exit means neither the argument nor the session's task holds a
   key: stop and ask for it. Apart from the branch question in `start`, that
   is the only blocking question in this workflow. When the key came from the
   argument and the session has no task, end the reply with:
   `Tip: /rename KEY so later /jira calls find it.`

3. Load the settings: `jira.sh config` prints `cloud_id`, `site_url`,
   `comment_language`, `worklog_language`, `base_branch`, `staging_branch`,
   `staging_label` and the config file, whose `transitions` holds the status
   preference lists. If it exits with "Missing", do `setup` first.

4. Load the Atlassian tools if they are not in the tool list yet, in ONE
   ToolSearch call:
   `select:mcp__plugin_atlassian_atlassian__getJiraIssue,mcp__plugin_atlassian_atlassian__transitionJiraIssue,mcp__plugin_atlassian_atlassian__addOrEditJiraIssueComment,mcp__plugin_atlassian_atlassian__executeRead,mcp__plugin_atlassian_atlassian__executeWrite,mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql,mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources,mcp__plugin_atlassian_atlassian__editJiraIssue,mcp__plugin_atlassian_atlassian__atlassianUserInfo`
   When those names are not found, the Atlassian MCP server may be connected
   under another name (a claude.ai connector): search for `getJiraIssue` and
   use the tools with the same suffixes. When there is no Atlassian MCP
   server at all, stop and say that this workflow needs one: the `atlassian`
   plugin from `claude-plugins-official`, or the Atlassian connector.

Always pass `cloudId` as a top-level argument. Do not call `discover`; the
operation names are below. Independent calls go in the same response.

| Need | Call |
|---|---|
| Issue fields | `getJiraIssue` with `view: "evidence"`, `fieldsByKeys: true`, `fields: ["summary","description","status","issuetype","priority","reporter","assignee","labels","created","updated","issuelinks","parent"]` |
| Attachment list | `getJiraIssue` with `view: "compact"`, `fieldsByKeys: true`, `fields: ["summary","attachment"]` → `fields.attachment[].{id, filename, size, mimeType}` (the evidence view drops this field, so it is a separate call) |
| Comments | `executeRead` name `listJiraIssueComments`, inputs `{issueIdOrKey, orderBy: "created", maxResults: 100}` |
| Available transitions | `executeRead` name `listJiraIssueTransitions`, inputs `{issueIdOrKey}` → `transitions[].{id, name, to.name}` |
| Move status | `transitionJiraIssue` with `transitionId` |
| Attachment file | `executeRead` name `downloadJiraIssueAttachment`, inputs `{attachmentId, outputPath}` → `mkdir -p` the directory, then run the returned `downloadCommand` in Bash within a few minutes (the URL expires) |
| Log work | `executeWrite` name `addOrEditJiraIssueWorklog`, inputs `{issueIdOrKey, timeSpent, started, comment}` → returns the worklog `id` |
| Existing worklogs | `executeRead` name `listJiraIssueWorklogs`, inputs `{issueIdOrKey}` → `worklogs[].{id, author.accountId, started, timeSpentSeconds, comment}` |
| My account id | `atlassianUserInfo` (no cloudId) → `account_id`; fetch once per session |
| Comment | `addOrEditJiraIssueComment` with `commentBody` (markdown) |
| Search | `searchJiraIssuesUsingJql` |
| Other fields (assignee, labels) | `editJiraIssue`, only when the user asks, and for the staging label in `staging` |

When a call fails because the operation name is unknown, call `discover`
once with the need from the table, then continue with the name it gives.

### Resolving a target status

Given a preference list from the config (`transitions.start`, `.close`,
`.done`): list the transitions, take the first list entry that equals a
transition's `to.name` (case-insensitive); failing that, the first
transition whose `to.name` starts with the first list entry (so "Deployed"
matches "Deployed for testing"); failing that, show the available
transitions and ask which one to use. If the issue already sits in the
target status, say so and skip the move. Never move to Done except through
`done` or an explicit `transition`. When the config has no `transitions`,
the lists are `["In Progress"]`, `["Deployed", "Ready for testing", "In Review", "Resolved"]`
and `["Done"]`.

## setup

1. `jira.sh config`. When it prints the settings, show them and say which
   file to edit (path in the first line) for the comment language, the
   status lists, the base and staging branches and excluded key prefixes.
   Stop.
2. When it exits with "Missing": call `getAccessibleAtlassianResources`.
   One site: use it. Several: ask which one (AskUserQuestion, one option per
   site URL). Then run `jira.sh init <cloudId> <siteUrl>` and show
   `jira.sh config`. Ask the user only about what they want to change; the
   defaults work for most Jira Cloud workflows.

Any other action that finds no config runs these steps first, then goes on.

## start

1. Setup as above.
2. In parallel: fetch the issue fields, fetch the attachment list, list the
   comments, run `timer.sh list` (to know whether the key already has time).
3. Attachments: for each entry in `fields.attachment` up to 10 MB, download
   it to `<scratchpad>/jira/KEY/<filename>` (the session's scratchpad
   directory, or a temporary folder) and read it: images and PDFs with the
   Read tool, text-like files (txt, log, md, csv, json, xml, sql, html, code)
   with `sed -n`. For `.docx` use
   `unzip -p FILE word/document.xml | sed 's/<[^>]*>/ /g'`; for `.xlsx` dump
   the sheets with `python3` and `openpyxl` when they are installed. Larger
   files and formats you cannot read (`.xls`, archives, binaries) are listed
   with a note that the user should paste what matters. A failed download is
   not fatal: list the file and move on.
4. Move to In Progress (`transitions.start`).
5. Start the timer: `timer.sh on KEY` (resumes if paused).
6. Branch. `BASE` is `base_branch` from `jira.sh config`. Skip the question
   when the extra input has `--branch` or `--base`, when the current branch
   is already `KEY`, or when the folder is not a git repository. Otherwise
   ask with AskUserQuestion, header `Branch`, question `Work on a KEY branch
   or on BASE?`, options `Branch KEY` (description: new branch from the latest
   origin/BASE) and `BASE` (description: commit straight to BASE). Then, in
   the project repository:
   - First `git status --porcelain --untracked-files=no`. With uncommitted
     changes do not switch anything: say so in the briefing and leave the
     choice for the user to apply.
   - `git fetch origin BASE`.
   - **Branch**: if `KEY` exists locally, `git switch KEY`; else if
     `git ls-remote --heads origin KEY` finds it, `git switch --track
     origin/KEY`; else `git switch --no-track -c KEY origin/BASE` (without
     `--no-track` git makes origin/BASE the upstream). Do not push now; the
     branch is pushed with the first commit (`git push -u origin KEY`).
   - **BASE**: `git switch BASE`, then `git merge --ff-only origin/BASE`.
     When it cannot fast-forward, say so and leave it.
   A git failure is not fatal: report it in the briefing and continue. When
   a sandbox blocks a git command (for example `could not lock config file`
   on `--track`), say so; the user decides whether to run it outside the
   sandbox.
7. Reply with the briefing below and stop. Do not investigate beyond a couple
   of greps or file reads needed to name the likely code area, and do not
   change code: the user directs the work after the briefing.

Later actions follow the choice: commits go to the current branch; on a `KEY`
branch, push with `git push -u origin KEY`, and merge into BASE only when the
user asks.

Briefing format:

```
**KEY - summary**
type · priority · reporter → assignee · old status → In Progress · <site_url>/browse/KEY

**Request** - what is asked or what breaks, in 2-5 sentences. Error text,
identifiers, dates and amounts go verbatim in a code block.

**Comments (N)** - one bullet per comment: date, author, gist. Decisions,
questions still open and changed requirements stand out. "None" when empty.

**Attachments (N)** - one bullet per file: name, type, size, what it shows
after reading it, or why it could not be read.

**Timer** - `KEY started`, or resumed with the total tracked so far.

**Branch** - `KEY` (new from origin/BASE @ <short sha>, existing, or tracking
origin/KEY) or `BASE` (up to date with origin/BASE @ <short sha>), or why
nothing was switched.

**Understanding** - the problem in one or two sentences, the likely code area,
acceptance criteria as you read them, open questions for the user.
```

If the assignee is someone else or empty, say so in the header line; do not
change it unless asked.

## close

1. Setup as above.
2. Stop the timer: `timer.sh off KEY`. "not active" is fine; the recorded
   total is used.
3. Figures: `jira.sh figures KEY`. It subtracts time already logged through
   this workflow (the ledger) and rounds the remainder UP to the quarter
   hour, giving `time_spent` (Jira syntax) and `started` (ISO 8601 of the
   first unlogged timer start).
4. Worklog. When `rounded_seconds` is 0, say there is nothing new to log and
   skip. Otherwise write it directly (invoking `close` is the request):
   `addOrEditJiraIssueWorklog` with `timeSpent`, `started` and a one-line
   `comment` in `worklog_language` describing the work, in the style
   `Investigation, fix (short link URL rotation), tests, staging and production deploy.`
   Only name phases that happened. Then record it:
   `jira.sh mark-logged KEY <rounded_seconds> <worklog id> "<note>" "<started>"`
   (the same `started` value that went to Jira, so `day` files the worklog
   under the day the work was done).
5. Move to the "deployed" status (`transitions.close`).
6. Draft the closing comment (style below) from this session's work. In a
   fresh session, gather the facts first with `jira.sh context KEY`
   (branch, commits mentioning the key, files touched, task docs under
   `docs/` and `notes/`) and re-read the issue; if the facts are still thin,
   say what is missing and ask before drafting.
7. Report, then show the comment in a fenced block and ask whether to post it
   as is, edit it, or skip it. Post with `addOrEditJiraIssueComment` only
   after an explicit yes. A reply that edits the text is a new preview, not a
   yes.

Report format:

```
**KEY closed**
| Step | Result |
|---|---|
| Timer | stopped · 1h 09m tracked · 1h 15m rounded |
| Worklog | 1h 15m logged · started 2026-09-07 11:24 · id 10189 |
| Status | In Progress → Deployed for testing |
| Comment | waiting for confirmation |
<site_url>/browse/KEY
```

## day

The end-of-day view: what was worked on, what Jira already holds for that
day, and what is still to log. Read-only until the user answers the final
question.

1. Setup steps 1, 3 and 4 only. No key is needed and none is asked for.
   Parse the extra input: `--here` restricts to the current repository's
   logs; anything else is the date (`today` by default, `yesterday`,
   `YYYY-MM-DD`, `"last friday"`).
2. Local figures: `jira.sh day [DATE] [--here]`. It prints a `key=value`
   header, a table, one `[KEY]` block per ticket with the seconds and the
   ready-made `time_spent` and `started` values, the timeline and the ledger
   rows for that day. `tickets=0` means no timer ran that day; still do step
   3, since worklogs may have been written by hand.
3. Jira figures, in parallel:
   - `searchJiraIssuesUsingJql` with
     `worklogAuthor = currentUser() AND worklogDate = "DATE" ORDER BY key`,
     `fields: ["summary","status"]`, `maxResults: 50`;
   - `searchJiraIssuesUsingJql` with `key in (K1, K2, ...)` for the timer
     keys, same fields (skip when the timer list is empty);
   - `atlassianUserInfo` for the account id, unless already known.
   Then `listJiraIssueWorklogs` for every issue the first search returned;
   keep the worklogs whose `author.accountId` is mine and whose `started`
   falls on DATE in local time; sum `timeSpentSeconds` per key.
4. Report:

   ```
   **Day report - Tuesday 2026-09-08** (all projects · generated 13:46)
   | Key | Summary | Status | Tracked | Rounded | Jira | To log |
   |---|---|---|---|---|---|---|
   | ABC-2187 | Summary cut at 50 chars | In Progress | 1h 32m | 1h 45m | - | 1h 45m |
   | ABC-2167 | ... | Deployed for testing | 20m | 30m | 30m | - |
   | ABC-2190 | logged by hand, no timer | Done | - | - | 45m | - |
   | **Total** | | | 2h 37m | 3h 45m | 2h 45m | 1h 45m |

   Timeline: 09:36-11:08 ABC-2187 · 12:32-12:52 ABC-2167 · ...
   Wall clock 2h 37m between 09:36 and 13:38 (span 4h 01m). ABC-2187 timer is paused.
   ```

   Tracked and Rounded come from the timer for that day. Jira is the sum of
   my worklogs started that day. To log is `unlogged_rounded_seconds` from
   the `[KEY]` block: the ticket's whole unlogged remainder, which can
   include earlier days; when it differs from Rounded, say so under the
   table. Rows with a Jira worklog but no timer get `logged by hand, no
   timer` as a note. Sort rows by first touch, hand-logged rows last.

   Under the table, a **Checks** list, only for what applies:
   - a running or paused timer (name it; the report does not stop it);
   - a key where the ledger holds more for the day than Jira does (the
     ledger is wrong; Jira is the truth; suggest which ledger row to delete);
   - a key where Jira holds more than the ledger (logged by hand; the
     remainder figure may then be too high; suggest `mark-logged` to align
     the ledger before logging);
   - a day total below the tracked wall clock by more than 30 minutes once
     everything is logged.
   When nothing applies, omit the list.

5. Logging the remainder. When every To log is zero, end with
   `Nothing left to log for DATE.` Otherwise show a preview:

   ```
   | Key | Time | Started | Worklog comment |
   |---|---|---|---|
   | ABC-2187 | 1h 45m | 2026-09-08 09:36 | Investigation and fix of ... |
   ```

   The comment is one line in `worklog_language` as in `close` step 4,
   drafted from this session; for a key this session did not touch, run
   `jira.sh context KEY` and draft from the commits; when that is still
   thin, put `?` and ask for the wording. Then ask:
   `Reply "log all", "log KEY,KEY" or "skip".` Do nothing until the answer
   is one of those; an edited comment is a new preview.
6. On `log ...`: for each chosen key, `addOrEditJiraIssueWorklog` with
   `timeSpent`, `started` and the comment, then
   `jira.sh mark-logged KEY <unlogged_rounded_seconds> <id> "<comment>" "<started>"`.
   Timers and statuses stay as they are. Report a results table (key, time,
   worklog id) and the new day total. A failed write stops the batch; report
   which keys were written and which were not.

## month

`day` summed over a month, with the total in billable hours. Read-only: it
logs nothing. Remainders are logged per day with `/jira day DATE`.

1. Setup steps 1, 3 and 4 only. No key. Parse the extra input: `--here`
   restricts to the current repository's logs; anything else is the month
   as `MM-YYYY` (also `M-YYYY`, `YYYY-MM`, `last`). No month means the
   current one.
2. Local figures: `jira.sh month [MM-YYYY] [--here]`. It prints a
   `key=value` header (`month`, `first_day`, `last_day`, `days`, `tickets`,
   `billable_seconds`, `billable_hours`, `logged_seconds`, ...), a `--- days`
   table (one row per day with timer records or ledger worklogs) and a
   `--- tickets` table (days worked, tracked, billable, ledger logged in the
   month, whole unlogged remainder, first and last day, timer state).
   BILLABLE is per ticket per day rounded up to the quarter and summed,
   which is what `day` shows as Rounded for each of those days. A bad month
   exits non-zero with a message; report it and stop.
3. Jira figures, in parallel:
   - `searchJiraIssuesUsingJql` with
     `worklogAuthor = currentUser() AND worklogDate >= "first_day" AND worklogDate <= "last_day" ORDER BY key`,
     `fields: ["summary","status"]`, `maxResults: 100`; fetch the next page
     while the response says more exist;
   - `searchJiraIssuesUsingJql` with `key in (K1, K2, ...)` for the timer
     keys missing from that result, same fields (skip when none are missing);
   - `atlassianUserInfo` for the account id, unless already known.
   Then `listJiraIssueWorklogs` for every issue the first search returned,
   in parallel batches; keep my worklogs whose `started` falls in the month
   in local time; sum `timeSpentSeconds` per key and per day.
4. Report:

   ```
   **Month report - September 2026** (all projects · 16 days · generated 15:00)

   **Billable: 107h 00m (107.00 h)** · tracked 98h 51m · in Jira 103h 00m (103.00 h) · to log 5h 45m

   | Date | Day | Tickets | Tracked | Billable | Jira | Diff |
   |---|---|---|---|---|---|---|
   | 2026-09-01 | Tue | 2 | 4h 35m | 5h 00m | 4h 45m | -15m |
   | 2026-09-07 | Mon | 5 | 6h 45m | 7h 15m | 7h 15m | - |
   | **Total** | | 43 | 98h 51m | 107h 00m | 103h 00m | -4h 00m |

   | Key | Summary | Status | Days | Tracked | Billable | Jira | To log |
   |---|---|---|---|---|---|---|---|
   | ABC-2149 | Summary cut at 50 chars | In Progress | 3 | 12h 57m | 13h 15m | 13h 00m | - |
   | ABC-2190 | logged by hand, no timer | Done | - | - | - | 45m | - |
   | **Total** | | | | 98h 51m | 107h 00m | 103h 00m | 5h 45m |
   ```

   Tracked and Billable come from `jira.sh month`. Jira is the sum of my
   worklogs started in the month (per day in the first table, per ticket in
   the second). Diff is Jira minus Billable, `-` when equal. To log is the
   UNLOGGED column: the ticket's whole remainder, which can include other
   months. Rows with Jira worklogs but no timer get `logged by hand, no
   timer`. Days with neither timer nor Jira time are left out. Ticket rows
   follow the script's order (first day worked), hand-logged rows last. With
   more than 25 tickets, list the top 25 by Billable and fold the rest into
   one `+N more` row, so the totals stay exact.

   Under the tables, a **Checks** list, only for what applies:
   - a running or paused timer (name it; the report does not stop it);
   - days where Jira is below Billable by 15 minutes or more, as one line
     with the dates, and `Run /jira day DATE to log the remainder.`;
   - days or keys where Jira is above Billable (logged by hand, or the
     ledger files a worklog under another day than Jira does);
   - a key where the ledger holds more for the month than Jira does (the
     ledger is wrong; Jira is the truth);
   - a ticket with less than a minute tracked on a day, which still bills a
     quarter for that day (a timer started by mistake; `timer.sh cancel` or
     edit the log if it should not count).
   When nothing applies, omit the list.

5. End with the billable total for the month in hours, e.g.
   `September 2026: 107.00 billable hours over 16 days.` Do not offer to log
   from here.

## Other actions

- `show` - the `start` reads and briefing without the transition, the timer,
  the branch or attachment downloads (list them; download on request).
  Header shows the current status only.
- `status` - `getJiraIssue` (compact) plus `jira.sh figures KEY`; print one
  small table: Jira status, assignee, last updated, timer state, tracked,
  logged, unlogged (rounded), browse URL. No writes.
- `log [time]` - `jira.sh figures KEY`; use the given duration
  (`jira.sh parse-time "1h 30m"` for the seconds) or the rounded remainder.
  Zero means nothing to log. Otherwise write the worklog as in `close` step 4
  and run `mark-logged` with the seconds actually logged and the `started`
  value. The timer keeps its state.
- `comment <notes>` - draft from the notes (or from the session when no
  notes are given), preview, post on an explicit yes.
- `transition <status>` - list transitions, match `<status>` against `name`
  and `to.name` (case-insensitive, substring). One match: move and report
  old → new. None or several: show the list and ask.
- `done` - move to `transitions.done`. Warn when the timer for the key is
  still running or has unlogged time (suggest `/jira close` or `/jira log`).
- `pause` / `resume` - with an argument, resolve it through `jira.sh key ARG`
  and run `timer.sh pause KEY` / `resume KEY`. Without one, run `jira.sh key`
  for the session's ticket: when it gives a key whose timer (`timer.sh list`)
  is running (for `pause`) or paused (for `resume`), run `timer.sh pause KEY`
  / `resume KEY`. Otherwise run the timer with no task: it acts on the
  session's task when that is running (for `pause`) or paused (for
  `resume`), and otherwise exits 2 with the reason and the tasks that
  qualify. On exit 2 ask which of them to act on (AskUserQuestion, one
  option per task plus `All` when there are several), then re-run with the
  chosen keys or `--all`. Do not ask for a key when the session has none;
  the question is which timer, not which ticket. Echo the timer output in
  both cases.
- `mine` - `searchJiraIssuesUsingJql` with
  `assignee = currentUser() AND statusCategory != Done ORDER BY status ASC, updated DESC`,
  `maxResults: 30`. Table: key, status, summary (cut at 70 chars), updated
  date. Mark the row whose key is the session's ticket with `*`.
- `help` - print the action list from the Arguments section.

## staging

Keeps the staging label (`staging_label`, default `on-staging`) equal to
what git says is on the staging branch and not yet on the base branch. Git
is the truth; the label is the view of it in Jira. Run it from inside the
project repository; a deploy script or command can run it after each deploy.

1. Setup steps 1, 3 and 4 only. No key.
2. `git fetch origin`, then `jira.sh staging-keys`: one key per line, the
   set that should carry the label. `Unknown ref: origin/<branch>` means the
   project has no such branch: say so and stop.
3. The Jira project is the prefix of those keys (`ABC-1991` → `ABC`); with
   no keys, the prefix of the session's key; with neither, ask. Then
   `searchJiraIssuesUsingJql` with
   `project = P AND (labels = LABEL OR key in (K1, K2, ...)) ORDER BY key`
   (drop the `key in` part when the set is empty),
   `fields: ["summary","status","labels"]`, `view: "full"`, `maxResults: 100`.
4. Add the label to keys in the set that lack it; remove it from labelled
   keys outside the set. `editJiraIssue` sets labels as a whole list, so
   write the issue's current labels plus or minus the label, never
   `["LABEL"]` over other labels. No preview: the label only mirrors git.
5. Report:

   ```
   **on-staging - ABC** (git: origin/staging vs origin/main)
   | Key | Summary | Status | Label |
   |---|---|---|---|
   | ABC-1991 | Summary cut at 50 chars | Deployed for testing | added |
   | ABC-2135 | ... | Deployed for testing | kept |
   | ABC-2190 | ... | Done | removed (on production) |
   ```

   Under it, a **Checks** list, only for what applies:
   - a labelled ticket in Done: closed in Jira but not on production yet;
   - a labelled ticket in To Do: work on staging the status does not show;
   - a key from git that Jira does not know (typo in a commit message).

## Comment style

Comments are written in `comment_language` (from `jira.sh config`), plain
and operator style: short sentences, facts, no greeting, no sign-off, no
emoji, no praise, no marketing words. Write for the reporter, who is usually
not a developer: describe behaviour, not classes or files. Keep it under
about 15 lines. Bullets only for lists of changes or steps. Never post
without a preview and an explicit yes.

Closing comment shape. It starts directly with the heading: no introductory
paragraph restating what happened or what was asked, since the ticket
already says that. Translate the headings into `comment_language`.

```
**Fix**          (or **Implementation** for a new feature or change)

<What changed, in plain sentences or bullets.>

<What the user sees now, what to check, whether they need to do anything
(for example send again), where it was deployed (staging / production).>
```

State only what actually happened (tests run, staging or production deploy,
data fixed). When something is unknown, leave it out or ask.

## Rules

- **Writes to Jira** happen only through the steps above: transitions and
  worklogs in `start`, `close`, `log`, `transition`, `done`, and in `day`
  after the user picks keys from the preview; comments after a confirmed
  preview; the staging label in `staging`. Nothing else is created, edited
  or deleted, and other people's comments and worklogs are never touched.
- **No scope creep**: assignee, priority, labels, sprint and links stay as
  they are unless the user asks in that message. The one exception is the
  staging label, which `staging` keeps in step with git.
- **Language**: comments in `comment_language`, worklog notes in
  `worklog_language`, replies to the user in the language they write in.
- **Timer**: the worklog-timer rules apply. Time rounds UP to the next
  quarter hour, reviewing counts, and the tracked total is re-read right
  before logging. Every worklog written here is followed by
  `jira.sh mark-logged`, so later `log`/`close` calls log only the
  remainder. `jira.sh logged` lists the ledger.
- **Attachments** are downloaded into the scratchpad or a temporary folder
  only, never re-uploaded and never committed.
- **Failures**: retry a failed MCP call once. If it still fails, stop, say
  which step failed and what already changed (timer started, status moved,
  worklog written), so the user can finish by hand. If the ticket cannot be
  read at all, ask the user to paste its content and continue from there.
- **Secrets**: attachments and comments may contain credentials or personal
  data; quote only what the task needs.
- **Session name**: do not look for the session's name yourself and never
  read transcripts for it; `jira.sh key` gets the session's task from
  `timer.sh`.

## Files

- `/jira` - this plugin's mod (`hooks/register.ts`) hands the typed
  arguments to this skill
- `jira.sh` - this plugin's helper (`key`, `figures`, `day`, `month`,
  `parse-time`, `mark-logged`, `logged`, `context`, `url`, `base-branch`,
  `staging-keys`, `init`, `config`, `session-name`); `jira.sh help` lists them
- `~/.claude/jira/config.json` - settings (`JIRA_HOME` moves the folder)
- `~/.claude/jira/logs/<project>.tsv` - worklog ledger (key, seconds,
  worklog id, epoch, timestamp, note, started epoch)
- `~/.claude/timer/logs/<project>.tsv` - timer log written by `timer.sh`
