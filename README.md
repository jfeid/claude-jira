# ![Jira Worklog icon](docs/icon-40.png) Claude Code Jira workflow

[![test](https://github.com/jfeid/claude-jira/actions/workflows/test.yml/badge.svg)](https://github.com/jfeid/claude-jira/actions/workflows/test.yml)

Jira Worklog (`jira-worklog`) is a Claude Code plugin that takes one Jira
ticket through the working day: read it with its comments and attachments,
move it to In Progress, run a timer, log the time as a Jira worklog rounded
up to the quarter hour, move it on and draft the closing comment. Day and
month reports compare what the timer tracked with what Jira holds, and log
the remainder after you approve a preview.

It builds on two other pieces:

- [Worklog Timer](https://github.com/jfeid/claude-timer) (`worklog-timer`),
  the per-task timer. It is installed with this plugin as a dependency.
- An Atlassian MCP server for Jira Cloud: the `atlassian` plugin from
  Anthropic's official marketplace, or the Atlassian connector in claude.ai.

This plugin is not made by or affiliated with Atlassian.

## Install

At the prompt of a Claude Code terminal session:

```
/plugin marketplace add jfeid/claude-timer
/plugin install jira-worklog --marketplace jfeid/claude-jira
/plugin install atlassian@claude-plugins-official
```

The first line makes the timer's marketplace known, so the `worklog-timer`
dependency can install. Skip the last line if Jira is already connected
through the Atlassian connector. Pick user scope to load it in every
session. Then run `/jira setup` once: it finds your Jira site through the
Atlassian server and writes the settings file.

## Use

```
/jira start ABC-123            read the ticket, pick a branch, In Progress, start the timer, brief me
/jira close                    stop the timer, log the rounded time, move on, preview the closing comment
/jira show | status            re-read the ticket / Jira status, timer, logged and unlogged time
/jira log [1h 30m]             log work now without closing (timer remainder, or the given time)
/jira day [DATE] [--here]      one day: timer vs Jira worklogs per ticket, then log the rest after a preview
/jira month [MM-YYYY] [--here] billable hours per day and per ticket against Jira (read-only)
/jira comment <notes>          draft a comment, preview, post on yes
/jira transition <status>      move to any available status
/jira done                     move to Done
/jira pause | resume           the ticket's timer
/jira mine                     my open tickets
/jira staging                  keep a staging label in step with git
/jira setup | help
```

`/jira` hands what you typed to Claude, which loads the plugin's skill
(`jira-workflow`) and runs the action; the transcript shows `jira status`
from the plugin, then the skill. You can also ask in plain words ("close the
ticket and log the time", "what is left to log for yesterday?"), and the
same skill runs.

**The key** is optional: without one, `/jira` uses the session's task from
the timer, which is the session's name or the last task you named with the
timer. Name the session after the ticket and every call finds it:

```
/rename ABC-123            or start the session with: claude -n ABC-123
/jira start                reads and starts ABC-123
/jira close                closes ABC-123
```

A Jira URL works in place of the key.

**What it writes to Jira**, and when:

| Action | Writes |
|---|---|
| `start` | status → In Progress |
| `close` | worklog, status → the "deployed" status; the comment only after you say yes to the preview |
| `log` | worklog |
| `day` | worklogs for the tickets you pick from the preview |
| `transition`, `done` | status |
| `comment` | the comment, after you say yes to the preview |
| `staging` | adds or removes the staging label |

`show`, `status`, `month` and `mine` only read. Nothing else is created,
edited or deleted; assignee, priority, sprint and other labels are left as
they are unless you ask.

**Rounding.** Each worklog is the timer's unlogged time rounded up to the
quarter hour. A ledger (below) remembers what was logged, so the next `log`
or `close` takes only the remainder. `day` and `month` show where the timer
and Jira differ: worklogs entered by hand, days not logged yet, a timer left
running.

**Branches.** `start` asks whether to work on a `ABC-123` branch made from
the base branch or on the base branch itself, and switches to it when the
working tree is clean. It never pushes.

### Settings

`/jira setup` writes `~/.claude/jira/config.json`:

```json
{
  "cloudId": "…",
  "siteUrl": "https://example.atlassian.net",
  "commentLanguage": "English",
  "worklogLanguage": "English",
  "baseBranch": "",
  "staging": { "branch": "staging", "label": "on-staging" },
  "excludePrefixes": [],
  "transitions": {
    "start": ["In Progress"],
    "close": ["Deployed", "Ready for testing", "In Review", "Resolved"],
    "done": ["Done"]
  }
}
```

| Setting | Effect |
|---|---|
| `commentLanguage` | language of the comments drafted for the ticket |
| `worklogLanguage` | language of the one-line worklog notes |
| `baseBranch` | branch new work starts from and production is built from; empty: origin's default branch |
| `staging` | branch and label used by `/jira staging` |
| `excludePrefixes` | key prefixes that belong to another tracker; `/jira` refuses them and leaves them out of reports |
| `transitions` | target statuses, in order of preference; the first one your workflow offers wins, and "Deployed" also matches "Deployed for testing" |

Environment variables: `JIRA_HOME` (default `~/.claude/jira`) moves the
folder; `TIMER_HOME`, `TIMER_PROJECT` and `TIMER_QUARTER` are the timer's and
are honoured here too.

### The script

The plugin puts `jira.sh` on the Bash tool's PATH. It never talks to Jira;
it works out the figures the skill sends:

```
jira.sh figures ABC-123          tracked, logged, unlogged, rounded, Jira time and start
jira.sh day yesterday            one day across projects, with ready-made worklog values
jira.sh month 09-2026            billable hours per day and per ticket
jira.sh logged                   the ledger of worklogs written through /jira
jira.sh staging-keys             keys on staging but not on the base branch
jira.sh help                     every command
```

To let it run without a permission prompt outside the skill, add
`"Bash(jira.sh:*)"` to `permissions.allow` in `~/.claude/settings.json`. The
skill already allows it, and the read-only Atlassian calls, for itself.

## Data

The plugin's own code makes no network connections and has no server,
account, telemetry or update check. The Jira work goes through the Atlassian
MCP server you connect, under your Atlassian login. See
[PRIVACY.md](PRIVACY.md).

What it writes on your computer:

- `~/.claude/jira/config.json`: your Jira site, its cloud id and the
  settings above.
- `~/.claude/jira/logs/<project>.tsv`: the ledger, one line per worklog
  written through `/jira`: key, seconds, worklog id, when it was logged, the
  note, and the worklog's start. Plain text; it can be edited by hand.
- Attachments of a ticket you start, downloaded into the session's
  scratchpad (a temporary folder) to read them.

What it reads besides those: the timer's logs and session task through
`timer.sh`; in the current git repository, the branch, commits and file
names that mention the key, and file names under `docs/` and `notes/`. It
does not read Claude Code's session files, transcripts, history, memory,
settings or credentials.

Ticket content (description, comments, attachments) and the reports are
shown in your conversation, and Claude Code sends the conversation to
Anthropic, as with anything Claude reads.

## What the mod does

The `/jira` command comes from `hooks/register.ts`, a mod. It sends nothing
over the network and runs no programs. In detail:

- **What it registers:** the slash command `/jira`. A plugin skill would
  show as `/jira-worklog:<name>`, so the skill is named `jira-workflow` and
  hidden from the `/` menu, and the mod provides the plain name.
- **What it gives Claude:** for `/jira <args>`, a prompt `jira <args>`
  submitted as your own words, and a note only Claude reads, naming the
  skill to load and the arguments. Nothing else.
- **What it reads:** nothing: no files, environment variables or settings.
- **Hooks:** `session.start` registers the command; `command.run` answers
  `/jira` only. No hook makes or changes a permission decision.

## Requirements

- Claude Code 2.1.287 or later in the terminal (2.1.286 in the Desktop
  app's Code tab) for `/jira`, which is a mod. On versions without mods, ask
  Claude in plain words and the skill runs the same actions. claude.ai and
  Cowork do not install plugins with a `bin/` folder.
- The `worklog-timer` plugin, version 0.5 or later (installed as a
  dependency).
- An Atlassian MCP server connected to Jira Cloud, with permission to edit
  issues and log work in the projects you use.
- bash (3.2 or later) and the usual shell tools: present on Linux and
  macOS. On Windows, [Git for Windows](https://gitforwindows.org/), as for
  the timer. `jq` is used when present and not required.

Sandbox: with Claude Code's sandbox turned on, Claude's Bash tool cannot
write outside the project folder, so `jira.sh mark-logged` (and the timer)
fail to save. Allow both folders in `~/.claude/settings.json`:

```json
{
  "sandbox": {
    "filesystem": {
      "allowWrite": ["~/.claude/jira", "~/.claude/timer"]
    }
  }
}
```

`git fetch` and branch switches in `start` may also need the sandbox's
network or `.git/config` access; Claude says when a command was blocked.

Dates: with GNU `date` (Linux, Git Bash, or `gdate` from
`brew install coreutils` on macOS) `day` takes anything `date -d` reads,
such as `"last friday"`. With the macOS `date` it takes `today`,
`yesterday`, `tomorrow` or `YYYY-MM-DD`.

Used daily on Linux with Jira Cloud. CI runs the script's tests on Linux,
macOS and Windows (Git Bash). Reports from other setups are welcome in the
issues.

## Try it with sample data

`tests/sample-data.sh` writes made-up timers and one logged worklog into a
folder of its own, without touching your real files (it needs the timer's
`timer.sh`):

```
bash tests/sample-data.sh /tmp/jira-sample
export TIMER_HOME=/tmp/jira-sample JIRA_HOME=/tmp/jira-sample/jira TIMER_PROJECT=acme-shop
bin/jira.sh figures ABC-118        5h 50m tracked, 3h 00m logged, 3h 00m to log
bin/jira.sh month                  about 11.75 billable hours, 3h logged
```

The Jira steps need a Jira Cloud site you can write to; a free Atlassian
site works for trying it.

## Develop

```
claude --plugin-dir . --plugin-dir ../claude-timer   load both for one session
claude plugin validate --strict .
claude plugin test .               the mod's tests
bash tests/jira-cli.sh             jira.sh end to end (needs ../claude-timer or TIMER_BIN)
```

## Security and support

Questions and bugs: [GitHub issues](https://github.com/jfeid/claude-jira/issues).
Security reports: see [SECURITY.md](SECURITY.md).

## License

MIT
