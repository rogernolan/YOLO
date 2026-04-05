#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DATA_DIR="${PROJECT_DIR}/.derived-data"
APP_BINARY="${DERIVED_DATA_DIR}/Build/Products/Debug/CodexAlertCLI.app/Contents/MacOS/CodexAlertCLI"

COMMAND=send
if [[ $# -gt 0 && ( "$1" == "send" || "$1" == "ask" ) ]]; then
  COMMAND="$1"
  shift
fi

CLI_ARGS=("$@")

if [[ ${#CLI_ARGS[@]} -eq 0 ]]; then
  echo "Usage: $0 [send|ask] --title <title> --body <body> [additional codex-alert options]" >&2
  exit 64
fi

xcodebuild \
  -project "${PROJECT_DIR}/CodexAlert.xcodeproj" \
  -scheme CodexAlertCLI \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -allowProvisioningUpdates \
  build >/dev/null

"${APP_BINARY}" "${COMMAND}" "${CLI_ARGS[@]}"
