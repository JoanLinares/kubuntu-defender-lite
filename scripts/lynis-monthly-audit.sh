#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Uso: $0 /ruta/de/logs usuario" >&2
  exit 1
fi

LOG_DIR="$1"
TARGET_USER="$2"

if ! id "${TARGET_USER}" >/dev/null 2>&1; then
  echo "Error: el usuario no existe: ${TARGET_USER}" >&2
  exit 1
fi

if ! command -v lynis >/dev/null 2>&1; then
  echo "Error: lynis no está instalado." >&2
  exit 1
fi

TARGET_GROUP="$(id -gn "${TARGET_USER}")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/lynis-${TIMESTAMP}.log"

mkdir -p -- "${LOG_DIR}"

{
  echo "Kubuntu Defender Lite - Lynis monthly audit"
  echo "Fecha: $(date -Is)"
  echo "Usuario objetivo: ${TARGET_USER}"
  echo
} > "${LOG_FILE}"

set +e
lynis audit system --quiet >> "${LOG_FILE}" 2>&1
LYNIS_STATUS="$?"
set -e

if [[ "$(id -u)" -eq 0 ]]; then
  chown "${TARGET_USER}:${TARGET_GROUP}" "${LOG_FILE}" 2>/dev/null || true
fi

exit "${LYNIS_STATUS}"
