# Privacy

Jira Worklog (`jira-worklog`) is a Claude Code plugin by Giannis Feidaros
([jfeid](https://github.com/jfeid)). This is what it handles.

## Who sees your Jira data

The plugin has no server, account, telemetry, analytics or update check, and
its script (`jira.sh`) makes no network connections. The developer receives
nothing.

The Jira work goes through the Atlassian MCP server you connect (the
`atlassian` plugin or the Atlassian connector), under your own Atlassian
login and Atlassian's terms. Through it, Claude reads the tickets you name,
their comments, attachments and worklogs, your open tickets and your
account id, and writes status changes, worklogs, comments you approved and
the staging label, as listed in the README. Attachments are downloaded from
the link Atlassian returns.

What Claude reads (ticket text, comments, attachments) and the reports are
part of your Claude Code conversation, which Claude Code sends to Anthropic
under the terms you use Claude Code with.

## What it stores

On your computer only, under `~/.claude/jira/` (or `JIRA_HOME`):

- **Settings** (`config.json`): your Jira site URL, its cloud id, and your
  preferences (languages, branches, statuses, excluded key prefixes).
- **Ledger** (`logs/<project>.tsv`): for each worklog written through the
  plugin, the ticket key, the seconds logged, the Jira worklog id, when it
  was logged, the one-line note and the worklog's start time. The project
  name is the folder name of the git repository.

Attachments are downloaded into the session's scratchpad (a temporary
folder) so Claude can read them, and are not copied anywhere else.

Notes and comments are what Claude drafts and you approve. If they contain
a customer's name or other personal data, the ledger keeps the note like
any other.

## What it reads

The files above; the timer's logs and the session's task through the
worklog-timer plugin's `timer.sh`; in the current git repository, the
branch, the commits and file names that mention a ticket key, and file
names under `docs/` and `notes/`; the environment variables listed in the
README. It does not read Claude Code's session files, transcripts, history,
memory, settings or credentials. It handles no Atlassian credentials: the
MCP server does the sign-in.

The `/jira` command (a mod) reads nothing. It passes what you typed after
`/jira` to Claude as a prompt, with a note naming the skill to load.

## Keeping and deleting

The files are kept until you delete them.

- Delete a ledger line: edit `logs/<project>.tsv`.
- Delete everything: remove `~/.claude/jira/` (or your `JIRA_HOME`).
- Uninstalling the plugin leaves the files in place.

Worklogs, comments and statuses written to Jira stay in Jira; manage them
there.

## Contact

Giannis Feidaros, [jfeid on GitHub](https://github.com/jfeid),
info@maxweb.gr. Questions can also go to the
[GitHub issues](https://github.com/jfeid/claude-jira/issues).
