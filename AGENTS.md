# Codex Alert Project Guidance

For work in this repository, use the installed `attention-alerts` skill more aggressively than the global default.

Project-specific escalation rule:

- if a task in this repo has involved more than 3 minutes of active work, send a phone alert instead of waiting for the usual 10-minute threshold
- send sooner when progress is blocked on a decision, approval, credentials, device interaction, or a manual verification step

Use:

- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh send` for one-way alerts
- `/Users/rog/Development/Codex\ alert/scripts/send_phone_alert.sh ask --wait` for yes/no questions

Always include:

- `--project "Codex Alert"`
- `--task` with the current task
- `--type` set to `blocked`, `decision`, `approval`, `review`, or `info`

Do not send alerts for routine progress chatter, but do send them readily for meaningful blockers or any substantial task in this repo that crosses the 3-minute mark.
