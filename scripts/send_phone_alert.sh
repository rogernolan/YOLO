#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DATA_DIR="${PROJECT_DIR}/.derived-data"
APP_BINARY="${DERIVED_DATA_DIR}/Build/Products/Debug/CodexAlertCLI.app/Contents/MacOS/CodexAlertCLI"
GLOBAL_ENV_FILE="${HOME}/.config/codex-alert/.env"
LOCAL_ENV_FILE="${PROJECT_DIR}/.env.local"

load_env_file() {
  local env_file="$1"
  if [[ -f "${env_file}" ]]; then
    set -a
    source "${env_file}"
    set +a
  fi
}

load_env_file "${GLOBAL_ENV_FILE}"
load_env_file "${LOCAL_ENV_FILE}"

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
  build >/dev/null 2>&1 || {
    if [[ -x "${APP_BINARY}" ]]; then
      echo "Warning: CodexAlertCLI rebuild failed; using existing binary at ${APP_BINARY}" >&2
    else
      echo "Error: CodexAlertCLI rebuild failed and no existing binary is available at ${APP_BINARY}" >&2
      exit 65
    fi
  }

"${APP_BINARY}" "${COMMAND}" "${CLI_ARGS[@]}"
