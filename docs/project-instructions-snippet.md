# Codex Alert Project Snippet

Use this snippet in any repo-level `AGENTS.md`, project instructions file, or local Codex guidance when you want the project to use Codex Alert by default.

```md
When you need my attention and the task has involved more than 10 minutes of active work, send a phone alert instead of relying on chat alone.

Use:

- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh send` for one-way alerts
- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh ask --wait` for questions that need 2-3 explicit response choices

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

Use `ask --wait` only when you genuinely need an answer before continuing. Default to yes/no for binary decisions, or add `--option` 2 or 3 times for richer choices.
```
