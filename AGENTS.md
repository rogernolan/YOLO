# Codex Alert Project Guidance

For work in this repository, use the installed `attention-alerts` skill more aggressively than the global default.

Project-specific escalation rule:

- if a task in this repo has involved more than 3 minutes of active work, send a phone alert instead of waiting for the usual 10-minute threshold
- send sooner when progress is blocked on a decision, approval, credentials, device interaction, or a manual verification step

Use:

- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh send` for one-way alerts
- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh ask --wait` for questions that need 2-3 explicit response choices

Decision rule:

- if progress depends on Rog choosing between concrete options, do not use `send`; use `ask --wait`
- when you already have a shortlist, top candidates, or a small menu of next steps, include those choices as explicit `--option` values instead of asking only in chat
- for blocking questions, prefer `ask --wait` immediately instead of asking only in chat first
- if Rog may be away, add a follow-up timeout when asking the blocking question so the helper can remind him without relying on the thread staying active
- if the task has crossed the alert threshold and is waiting on a choice, proactively send the `ask --wait` alert rather than waiting for another prompt

Quick decision rubric:

- if you cannot safely continue without Rog's answer, use an alert
- if the question is only a clarification and progress can continue safely, use chat
- if Rog may be away and the answer is blocking, use `ask --wait` with helper-owned follow-up timing

Always include:

- `--project "Codex Alert"`
- `--task` with the current task
- `--type` set to `blocked`, `decision`, `approval`, `review`, or `info`

Do not send alerts for routine progress chatter, but do send them readily for meaningful blockers or any substantial task in this repo that crosses the 3-minute mark.
