#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kubuntu-defender-lite"
TARGET_USER="${SUDO_USER:-${USER:-}}"

if [[ "${TARGET_USER}" == "root" && -n "${LOGNAME:-}" && "${LOGNAME}" != "root" ]]; then
  TARGET_USER="${LOGNAME}"
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" 2>/dev/null | cut -d: -f6 || true)"
if [[ -z "${TARGET_HOME}" || "${TARGET_HOME}" == "/" ]]; then
  TARGET_HOME="${HOME:-}"
fi

STATE_DIR="${TARGET_HOME}/.local/share/${PROJECT_NAME}/notify-state"
STATE_FILE="${STATE_DIR}/seen-detections.txt"
NOTIFY_LOG="${STATE_DIR}/notify.log"
LOG_FILES=(
  "/var/log/clamav/clamav.log"
  "/var/log/clamav/clamonacc.log"
)

mkdir -p -- "${STATE_DIR}"
touch "${STATE_FILE}" "${NOTIFY_LOG}"
chmod 700 -- "${STATE_DIR}" 2>/dev/null || true
chmod 600 -- "${STATE_FILE}" "${NOTIFY_LOG}" 2>/dev/null || true

log_msg() {
  printf "%s | %s\n" "$(date -Is)" "$*" >> "${NOTIFY_LOG}"
}

line_hash() {
  printf "%s" "$1" | sha256sum | awk '{print $1}'
}

notify_detection() {
  local line="$1"
  local hash

  [[ "${line}" == *FOUND* ]] || return 0

  hash="$(line_hash "${line}")"
  if grep -Fxq "${hash}" "${STATE_FILE}" 2>/dev/null; then
    return 0
  fi

  printf "%s\n" "${hash}" >> "${STATE_FILE}"

  if command -v notify-send >/dev/null 2>&1; then
    if ! notify-send "Kubuntu Defender Lite" "Malware detectado. Ejecuta ./scripts/review-detections.sh para revisar y mover a cuarentena." 2>>"${NOTIFY_LOG}"; then
      log_msg "notify-send falló para una detección."
    fi
  else
    log_msg "notify-send no está disponible. Instala libnotify-bin."
  fi
}

watch_readable_logs() {
  local readable=()
  local log_file
  local line

  for log_file in "${LOG_FILES[@]}"; do
    if [[ -r "${log_file}" ]]; then
      readable+=("${log_file}")
    elif [[ -e "${log_file}" ]]; then
      log_msg "sin permisos para leer ${log_file}"
    else
      log_msg "todavía no existe ${log_file}"
    fi
  done

  if [[ "${#readable[@]}" -eq 0 ]]; then
    sleep 60
    return 0
  fi

  tail -n 0 -F "${readable[@]}" 2>>"${NOTIFY_LOG}" | while IFS= read -r line; do
    notify_detection "${line}"
  done
}

while true; do
  watch_readable_logs
done
