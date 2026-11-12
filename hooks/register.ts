// The /jira command of the jira-worklog plugin.
//
// The workflow itself is the plugin's skill, which needs a model turn. A
// plugin skill shows as /jira-worklog:<name>, so the skill is named
// jira-workflow (it does not claim /jira) and this mod registers a plain
// /jira that hands the typed arguments to Claude with the skill to load.

import type { Register } from 'claude-code'

export const SKILL = 'jira-worklog:jira-workflow'

const ACTIONS = 'start|close|show|status|log|day|month|comment|transition|done|pause|resume|mine|staging|setup|help'

// The prompt the person sees under /jira, and the note only Claude reads.
export function handOff(args: string): { prompt: string; note: string } {
  const a = args.trim()
  return {
    prompt: a ? `jira ${a}` : 'jira',
    note:
      `The person ran /jira${a ? ` ${a}` : ''}. Load the ${SKILL} skill with the Skill tool, ` +
      `passing ${a ? `the arguments "${a}"` : 'no arguments'}, and follow it.`,
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    try {
      await $.command.register({
        name: 'jira',
        description: 'Jira ticket workflow: start, close, status, log, day and month reports',
        argumentHint: `[${ACTIONS}] [KEY|URL|DATE|MM-YYYY] [--done]`,
      })
    } catch (err) {
      // Another command already owns /jira; the skill still answers plain requests.
      $.ui.log(`jira-worklog: /jira not registered: ${String(err)}`)
    }
    return started
  })

  // The note is recorded after the command's row. The prompt starts Claude's
  // turn; the engine refuses a submit from inside this hook (it would wait on
  // the run this hook holds), so it goes from a timer once the hook returned.
  on('command.run', { command: 'jira' }, async ($, e) => {
    const { prompt, note } = handOff(e.args)
    $.clock.after(1, () => {
      void $.prompt.submit({ text: prompt, asUser: true }).catch(err =>
        $.ui.log(`jira-worklog: /jira could not start a turn: ${String(err)}`),
      )
    })
    return { context: [note] }
  }).catch(($, e, next) => next(e))
}
