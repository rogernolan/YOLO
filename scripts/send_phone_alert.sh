#!/bin/zsh

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <title> <body> [sender] [urgency]" >&2
  exit 64
fi

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DERIVED_DATA_DIR="${PROJECT_DIR}/.derived-data"
APP_BINARY="${DERIVED_DATA_DIR}/Build/Products/Debug/CodexAlertCLI.app/Contents/MacOS/CodexAlertCLI"

TITLE=$1
BODY=$2
SENDER=${3:-Codex}
URGENCY=${4:-high}

xcodebuild \
  -project "${PROJECT_DIR}/CodexAlert.xcodeproj" \
  -scheme CodexAlertCLI \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -allowProvisioningUpdates \
  build >/dev/null

"${APP_BINARY}" send \
  --title "${TITLE}" \
  --body "${BODY}" \
  --sender "${SENDER}" \
  --urgency "${URGENCY}"
