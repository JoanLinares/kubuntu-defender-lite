#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kubuntu-defender-lite"
TARGET_USER="${SUDO_USER:-${USER:-}}"

if [[ "${TARGET_USER}" == "root" && -n "${LOGNAME:-}" && "${LOGNAME}" != "root" ]]; then
  TARGET_USER="${LOGNAME}"
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" 2>/dev/null | cut -d: -f6 || true)"
if [[ -z "${TARGET_HOME}" ]]; then
  TARGET_HOME="${HOME:-}"
fi

LOG_DIR="${TARGET_HOME}/.local/share/${PROJECT_NAME}/logs"

service_state() {
  local service="$1"
  local active="no instalado"
  local enabled="no instalado"

  if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
    active="$(systemctl is-active "${service}.service" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "${service}.service" 2>/dev/null || true)"
  fi

  printf "%-22s activo: %-12s habilitado: %s\n" "${service}" "${active}" "${enabled}"
}

print_clamonacc_hint() {
  local active=""

  if ! systemctl list-unit-files clamonacc.service >/dev/null 2>&1; then
    return
  fi

  active="$(systemctl is-active clamonacc.service 2>/dev/null || true)"
  if [[ "${active}" == "active" ]]; then
    return
  fi

  cat <<'EOF'

Aviso ClamOnAcc:
clamonacc no está active, así que la protección en tiempo real no está funcionando ahora mismo.
Revisa:
  sudo systemctl status clamonacc --no-pager -l
  sudo journalctl -u clamonacc -n 80 --no-pager

En Kubuntu 26.04/ClamAV moderno el servicio debe ejecutar clamonacc con --foreground.
EOF
}

print_ufw() {
  echo
  echo "UFW"
  if ! command -v ufw >/dev/null 2>&1; then
    echo "ufw no está instalado."
    return
  fi

  if sudo -n true 2>/dev/null; then
    sudo ufw status verbose || true
  else
    ufw status verbose 2>/dev/null || echo "Sin permisos para consultar UFW. Ejecuta con sudo o autentica sudo primero."
  fi
}

print_apparmor() {
  echo
  echo "AppArmor"
  if ! command -v aa-status >/dev/null 2>&1; then
    echo "aa-status no está instalado."
    return
  fi

  local output
  output="$(aa-status 2>/dev/null || true)"
  if [[ -z "${output}" ]] && sudo -n true 2>/dev/null; then
    output="$(sudo aa-status 2>/dev/null || true)"
  fi

  if [[ -z "${output}" ]]; then
    echo "No se pudo consultar AppArmor."
    return
  fi

  printf "%s\n" "${output}" | grep -E "apparmor module is loaded|apparmor filesystem is mounted|profiles are in (enforce|complain) mode" || true
}

print_latest_lynis_log() {
  echo
  echo "Lynis"
  if [[ ! -d "${LOG_DIR}" ]]; then
    echo "No hay directorio de logs: ${LOG_DIR}"
    return
  fi

  local latest
  latest="$(find "${LOG_DIR}" -maxdepth 1 -type f -name 'lynis-*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

  if [[ -n "${latest}" ]]; then
    echo "Último log: ${latest}"
    tail -n 5 "${latest}" 2>/dev/null || true
  else
    echo "Todavía no hay logs de Lynis."
  fi
}

print_log_matches() {
  local file="$1"
  local label="$2"
  local lines=""
  local matches=""

  echo
  echo "${label}"
  if [[ ! -e "${file}" ]]; then
    echo "No existe ${file}."
    return
  fi

  if [[ -r "${file}" ]]; then
    lines="$(tail -n 300 "${file}" 2>/dev/null || true)"
  elif sudo -n true 2>/dev/null; then
    lines="$(sudo tail -n 300 "${file}" 2>/dev/null || true)"
  else
    echo "Sin permisos para leer ${file}. Ejecuta con sudo o autentica sudo primero."
    return
  fi

  matches="$(printf "%s\n" "${lines}" | grep -Ei "FOUND|Infected files|virus|malware|OnAccess" | tail -n 20 || true)"
  if [[ -n "${matches}" ]]; then
    printf "%s\n" "${matches}"
  else
    echo "Sin detecciones recientes en las últimas líneas del log."
  fi
}

echo "Kubuntu Defender Lite - estado de seguridad"
echo "Usuario detectado: ${TARGET_USER}"

print_ufw

echo
echo "Servicios"
service_state "clamav-freshclam"
service_state "clamav-daemon"
service_state "clamonacc"
service_state "auditd"
print_clamonacc_hint

print_apparmor
print_latest_lynis_log
print_log_matches "/var/log/clamav/clamav.log" "Detecciones ClamAV"
print_log_matches "/var/log/clamav/clamonacc.log" "Detecciones ClamOnAcc"
