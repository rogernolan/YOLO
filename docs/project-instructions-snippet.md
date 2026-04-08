# Codex Alert Project Snippet

Use this snippet in any repo-level `AGENTS.md`, project instructions file, or local Codex guidance when you want the project to use Codex Alert by default.

```md
When you need my attention and the task has involved more than 10 minutes of active work, send a phone alert instead of relying on chat alone.

Use:

- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh send` for one-way alerts
- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh ask --wait` for questions that need 2-3 explicit response choices

Decision rule:

- if progress depends on me choosing between concrete options, do not use `send`; use `ask --wait`
- when you already have a shortlist, top candidates, or a small menu of next steps, include those choices as explicit `--option` values instead of asking only in chat
- for blocking questions, prefer `ask --wait` immediately instead of asking only in chat first
- if I may be away, add a follow-up timeout when asking the blocking question so the helper can remind me without relying on the thread staying active
- if the task has crossed the alert threshold and is waiting on a choice, proactively send the `ask --wait` alert rather than waiting for another prompt

Quick decision rubric:

- if you cannot safely continue without my answer, use an alert
- if the question is only a clarification and progress can continue safely, use chat
- if I may be away and the answer is blocking, use `ask --wait` with helper-owned follow-up timing

Send an alert when:

- work is blocked on a decision
- work is blocked on approval
- work is blocked on credentials, login, payment, or device interaction
- a manual verification step is required
- a substantial long-running task finished and I should come back promptly

Do not send alerts for routine progress updates or minor clarifications.

Include:

- a short title
- a one-sentence body
- `--project` with the current repo or app name
- `--task` with the current task
- `--type` set to `blocked`, `decision`, `approval`, `review`, or `info`

Use `ask --wait` when you need an answer before continuing. Default to yes/no for binary decisions, or add `--option` 2 or 3 times for richer choices. If you are asking me to pick from a top 2-3 items, those items should be the options in the alert. Use chat-only questions for non-blocking clarifications that can safely wait.
```
