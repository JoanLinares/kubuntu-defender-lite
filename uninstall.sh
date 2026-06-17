#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kubuntu-defender-lite"
MARKER_BEGIN="# BEGIN KUBUNTU-DEFENDER-LITE"
MARKER_END="# END KUBUNTU-DEFENDER-LITE"

PACKAGES=(
  ufw
  gufw
  clamav
  clamav-daemon
  clamtk
  libnotify-bin
  auditd
  audispd-plugins
  apparmor-utils
  lynis
)

TARGET_USER=""
TARGET_HOME=""
TARGET_GROUP=""
LOG_DIR=""
QUARANTINE_DIR=""
QUARANTINE_LOG=""
SUDO_KEEPALIVE_PID=""

cleanup() {
  if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

fail() {
  echo "Error: $*" >&2
  exit 1
}

ask_yes_no() {
  local prompt="$1"
  local default_yes="${2:-no}"
  local answer

  while true; do
    read -r -p "$prompt " answer
    case "${answer}" in
      "")
        [[ "${default_yes}" == "yes" ]] && return 0 || return 1
        ;;
      [sS]|[sS][iI]|[yY]|[yY][eE][sS])
        return 0
        ;;
      [nN]|[nN][oO])
        return 1
        ;;
      *)
        echo "Responde con s o n."
        ;;
    esac
  done
}

request_sudo() {
  echo "Solicitando permisos con sudo de forma segura..."
  if ! sudo -v; then
    fail "sudo falló. No se ha guardado ni leído ninguna contraseña."
  fi

  while true; do
    sudo -n true 2>/dev/null || exit
    sleep 60
  done &
  SUDO_KEEPALIVE_PID="$!"
}

validate_user() {
  local user="$1"
  local home

  if ! id "${user}" >/dev/null 2>&1; then
    echo "El usuario '${user}' no existe en el sistema."
    return 1
  fi

  home="$(getent passwd "${user}" | cut -d: -f6)"
  if [[ -z "${home}" || "${home}" == "/" ]]; then
    echo "No se pudo determinar un home válido para '${user}'."
    return 1
  fi

  TARGET_USER="${user}"
  TARGET_HOME="${home}"
  TARGET_GROUP="$(id -gn "${TARGET_USER}")"
  LOG_DIR="${TARGET_HOME}/.local/share/${PROJECT_NAME}/logs"
  QUARANTINE_DIR="${TARGET_HOME}/.local/share/${PROJECT_NAME}/quarantine"
  QUARANTINE_LOG="${QUARANTINE_DIR}/quarantine.log"
  return 0
}

run_target_user_systemctl() {
  local uid
  uid="$(id -u "${TARGET_USER}")"

  if [[ "$(id -un)" == "${TARGET_USER}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    systemctl --user "$@"
  else
    sudo -u "${TARGET_USER}" XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user "$@"
  fi
}

select_target_user() {
  local candidate="${SUDO_USER:-${USER:-}}"
  local answer=""
  local manual_user=""

  if [[ "${candidate}" == "root" && -n "${LOGNAME:-}" && "${LOGNAME}" != "root" ]]; then
    candidate="${LOGNAME}"
  fi

  while true; do
    if [[ -n "${candidate}" ]]; then
      read -r -p "Usuario detectado: ${candidate}. ¿Es correcto? [S/n] " answer
      case "${answer}" in
        ""|[sS]|[sS][iI]|[yY]|[yY][eE][sS])
          if validate_user "${candidate}"; then
            return 0
          fi
          ;;
        [nN]|[nN][oO])
          read -r -p "Introduce el nombre de usuario: " manual_user
          if validate_user "${manual_user}"; then
            return 0
          fi
          ;;
        *)
          echo "Responde con s o n."
          ;;
      esac
    else
      read -r -p "No se pudo detectar el usuario normal. Introduce el nombre de usuario: " manual_user
      if validate_user "${manual_user}"; then
        return 0
      fi
    fi
  done
}

remove_clamd_block() {
  if [[ ! -f /etc/clamav/clamd.conf ]]; then
    echo "No existe /etc/clamav/clamd.conf; se omite."
    return 0
  fi

  echo "Quitando bloque KUBUNTU-DEFENDER-LITE de clamd.conf..."
  local tmp_file
  tmp_file="$(mktemp)"

  sudo awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' /etc/clamav/clamd.conf > "${tmp_file}"

  sudo install -o root -g root -m 0644 "${tmp_file}" /etc/clamav/clamd.conf
  rm -f -- "${tmp_file}"
}

reload_audit_rules() {
  if command -v augenrules >/dev/null 2>&1; then
    sudo augenrules --load || true
  else
    sudo systemctl restart auditd 2>/dev/null || true
  fi
}

remove_project_services() {
  echo "Desactivando servicios y timers del proyecto..."

  if [[ -f "${TARGET_HOME}/.config/systemd/user/kubuntu-defender-lite-notify.service" ]]; then
    run_target_user_systemctl disable --now kubuntu-defender-lite-notify.service 2>/dev/null || true
    sudo rm -f "${TARGET_HOME}/.config/systemd/user/default.target.wants/kubuntu-defender-lite-notify.service"
    sudo rm -f "${TARGET_HOME}/.config/systemd/user/kubuntu-defender-lite-notify.service"
    sudo rm -f "${TARGET_HOME}/.local/lib/${PROJECT_NAME}/scripts/clamav-detection-notify.sh"
    sudo rmdir "${TARGET_HOME}/.local/lib/${PROJECT_NAME}/scripts" 2>/dev/null || true
    sudo rmdir "${TARGET_HOME}/.local/lib/${PROJECT_NAME}" 2>/dev/null || true
    run_target_user_systemctl daemon-reload 2>/dev/null || true
  fi

  sudo systemctl disable --now clamonacc.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/clamonacc.service

  sudo systemctl disable --now kubuntu-defender-lite-lynis.timer 2>/dev/null || true
  sudo systemctl stop kubuntu-defender-lite-lynis.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/kubuntu-defender-lite-lynis.service
  sudo rm -f /etc/systemd/system/kubuntu-defender-lite-lynis.timer

  sudo rm -f /usr/local/lib/kubuntu-defender-lite/scripts/lynis-monthly-audit.sh
  sudo rmdir /usr/local/lib/kubuntu-defender-lite/scripts 2>/dev/null || true
  sudo rmdir /usr/local/lib/kubuntu-defender-lite 2>/dev/null || true

  sudo systemctl daemon-reload
}

remove_quarantine_if_requested() {
  if [[ ! -d "${QUARANTINE_DIR}" ]]; then
    echo "No hay directorio de cuarentena en ${QUARANTINE_DIR}."
    return 0
  fi

  if ask_yes_no "¿Quieres borrar los archivos en cuarentena? [s/N]" "no"; then
    sudo find "${QUARANTINE_DIR}" -mindepth 1 -maxdepth 1 -type f ! -name 'quarantine.log' -delete
    echo "Archivos de cuarentena borrados."
  else
    echo "Archivos de cuarentena conservados en ${QUARANTINE_DIR}."
  fi

  if [[ -f "${QUARANTINE_LOG}" ]]; then
    if ask_yes_no "¿Quieres borrar quarantine.log? [s/N]" "no"; then
      sudo rm -f -- "${QUARANTINE_LOG}"
      echo "quarantine.log borrado."
    else
      echo "quarantine.log conservado en ${QUARANTINE_LOG}."
    fi
  fi

  sudo rmdir "${QUARANTINE_DIR}" 2>/dev/null || true
  sudo rmdir "${TARGET_HOME}/.local/share/${PROJECT_NAME}/notify-state" 2>/dev/null || true
  sudo rmdir "${TARGET_HOME}/.local/share/${PROJECT_NAME}" 2>/dev/null || true
}

remove_audit_rules() {
  echo "Eliminando reglas auditd del proyecto..."
  sudo rm -f /etc/audit/rules.d/kubuntu-defender-lite.rules
  reload_audit_rules
}

restart_clamav_daemon() {
  if systemctl list-unit-files clamav-daemon.service >/dev/null 2>&1; then
    sudo systemctl restart clamav-daemon 2>/dev/null || true
  fi
}

remove_logs_if_requested() {
  if [[ -d "${LOG_DIR}" ]]; then
    if ask_yes_no "¿Quieres borrar los logs de ${LOG_DIR}? [s/N]" "no"; then
      sudo rm -rf -- "${LOG_DIR}"
      sudo rmdir "${TARGET_HOME}/.local/share/${PROJECT_NAME}" 2>/dev/null || true
    else
      echo "Logs conservados en ${LOG_DIR}."
    fi
  else
    echo "No hay directorio de logs del proyecto en ${LOG_DIR}."
  fi
}

remove_packages_if_requested() {
  if ask_yes_no "¿Quieres desinstalar los paquetes usados por este proyecto? [s/N]" "no"; then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${PACKAGES[@]}"
  else
    echo "Paquetes conservados."
  fi
}

print_summary() {
  cat <<EOF

Se eliminarán solo cambios creados por ${PROJECT_NAME}:
* /etc/systemd/system/clamonacc.service
* bloque KUBUNTU-DEFENDER-LITE en /etc/clamav/clamd.conf
* /etc/systemd/system/kubuntu-defender-lite-lynis.service
* /etc/systemd/system/kubuntu-defender-lite-lynis.timer
* /usr/local/lib/kubuntu-defender-lite/scripts/lynis-monthly-audit.sh
* servicio de usuario kubuntu-defender-lite-notify.service
* /etc/audit/rules.d/kubuntu-defender-lite.rules

No se borrarán archivos personales.
No se borrará ${TARGET_HOME}/Proyectos.
No se borrarán Documentos ni Descargas.
No se borrará ni modificará el contenido de /media/${TARGET_USER}.
EOF
}

main() {
  command -v sudo >/dev/null 2>&1 || fail "no se encontró sudo."
  command -v id >/dev/null 2>&1 || fail "no se encontró id."
  command -v getent >/dev/null 2>&1 || fail "no se encontró getent."
  command -v awk >/dev/null 2>&1 || fail "no se encontró awk."
  command -v mktemp >/dev/null 2>&1 || fail "no se encontró mktemp."

  request_sudo
  select_target_user
  print_summary

  if ! ask_yes_no "¿Quieres continuar con la desinstalación? [s/N]" "no"; then
    echo "Cancelado. No se han hecho cambios."
    exit 0
  fi

  remove_project_services
  remove_clamd_block
  restart_clamav_daemon
  remove_audit_rules
  remove_quarantine_if_requested
  remove_logs_if_requested
  remove_packages_if_requested

  echo
  echo "Desinstalación completada. No se han restaurado backups porque este proyecto no crea backups."
}

main "$@"
