#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kubuntu-defender-lite"
MARKER_BEGIN="# BEGIN KUBUNTU-DEFENDER-LITE"
MARKER_END="# END KUBUNTU-DEFENDER-LITE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACKAGES=()

TARGET_USER=""
TARGET_HOME=""
TARGET_GROUP=""
LOG_DIR=""
SUDO_KEEPALIVE_PID=""
OS_PRETTY_NAME=""
OS_VERSION_ID=""
OS_CODENAME=""
INSTALL_PROFILE=""
INSTALL_PROFILE_SUPPORT=""
INSTALL_PROFILE_DESKTOP=""

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

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "no se encontró el comando requerido: $1"
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

set_common_package_profile() {
  PACKAGES=(
    ufw
    gufw
    clamav
    clamav-daemon
    clamtk
    auditd
    audispd-plugins
    apparmor-utils
    lynis
  )
}

select_install_profile() {
  local version_id="$1"
  local codename="$2"
  local expected_codename=""

  case "${version_id}" in
    24.04)
      INSTALL_PROFILE="Kubuntu/Ubuntu 24.04 LTS (Noble Numbat)"
      INSTALL_PROFILE_DESKTOP="Plasma 5"
      INSTALL_PROFILE_SUPPORT="Kubuntu 24.04 LTS: mantenimiento y seguridad hasta abril de 2027."
      expected_codename="noble"
      set_common_package_profile
      ;;
    26.04)
      INSTALL_PROFILE="Kubuntu/Ubuntu 26.04 LTS (Resolute Raccoon)"
      INSTALL_PROFILE_DESKTOP="Plasma 6"
      INSTALL_PROFILE_SUPPORT="Kubuntu 26.04 LTS: mantenimiento y seguridad hasta abril de 2029."
      expected_codename="resolute"
      set_common_package_profile
      ;;
    *)
      fail "versión no soportada: ${version_id:-desconocida}. Este instalador solo acepta Kubuntu/Ubuntu 24.04 LTS o 26.04 LTS."
      ;;
  esac

  if [[ -n "${codename}" && "${codename}" != "${expected_codename}" ]]; then
    echo "Aviso: VERSION_ID=${version_id}, pero VERSION_CODENAME=${codename}; se usará el perfil por VERSION_ID."
  fi
}

check_os() {
  [[ -r /etc/os-release ]] || fail "no se puede leer /etc/os-release."

  # shellcheck disable=SC1091
  . /etc/os-release

  local id="${ID:-}"
  local id_like="${ID_LIKE:-}"
  local version_id="${VERSION_ID:-}"
  local codename="${VERSION_CODENAME:-}"
  local pretty_name="${PRETTY_NAME:-Linux}"

  OS_PRETTY_NAME="${pretty_name}"
  OS_VERSION_ID="${version_id}"
  OS_CODENAME="${codename}"

  if [[ "${id}" != "ubuntu" && "${id}" != "kubuntu" && " ${id_like} " != *" ubuntu "* ]]; then
    fail "este instalador está pensado para Kubuntu/Ubuntu 24.04 LTS o 26.04 LTS. Detectado: ${pretty_name}"
  fi

  select_install_profile "${version_id}" "${codename}"

  echo "Sistema detectado: ${OS_PRETTY_NAME}"
  echo "Perfil de instalación seleccionado: ${INSTALL_PROFILE} - ${INSTALL_PROFILE_DESKTOP}"
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
  return 0
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

watch_paths_summary() {
  cat <<EOF
* ${TARGET_HOME}/Descargas
* ${TARGET_HOME}/Escritorio
* ${TARGET_HOME}/Documentos
* ${TARGET_HOME}/Downloads
* ${TARGET_HOME}/Desktop
* ${TARGET_HOME}/Documents
* ${TARGET_HOME}/Proyectos
* /media/${TARGET_USER}
EOF
}

print_summary() {
  cat <<EOF

Recomendación: si este Kubuntu está en un portátil o contiene datos importantes, activa cifrado de disco/LUKS durante la instalación del sistema. Este instalador no modifica particiones ni configura cifrado.

Resumen antes de modificar el sistema
------------------------------------
Sistema detectado: ${OS_PRETTY_NAME}
Perfil elegido: ${INSTALL_PROFILE} - ${INSTALL_PROFILE_DESKTOP}
Soporte: ${INSTALL_PROFILE_SUPPORT}

Usuario objetivo: ${TARGET_USER}
Home: \`${TARGET_HOME}\`

Carpetas vigiladas:
EOF
  watch_paths_summary
  cat <<EOF

Paquetes a instalar:
* ufw
* gufw
* clamav
* clamav-daemon
* clamtk
* auditd
* audispd-plugins
* apparmor-utils
* lynis

Servicios a activar:
* ufw
* clamav-freshclam
* clamav-daemon
* clamonacc
* auditd

Configuraciones a modificar:
* /etc/clamav/clamd.conf
* /etc/systemd/system/clamonacc.service
* reglas de auditd
* timer mensual de Lynis

EOF
}

install_packages() {
  echo "Instalando paquetes desde los repositorios oficiales con el perfil: ${INSTALL_PROFILE}..."
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"
}

ensure_directories() {
  echo "Preparando directorios del proyecto sin tocar contenidos personales..."

  if [[ ! -d "${TARGET_HOME}/Proyectos" ]]; then
    sudo -u "${TARGET_USER}" mkdir -p -- "${TARGET_HOME}/Proyectos"
  fi

  if [[ ! -d "/media/${TARGET_USER}" ]]; then
    sudo mkdir -p -- "/media/${TARGET_USER}"
  fi

  sudo install -d -o "${TARGET_USER}" -g "${TARGET_GROUP}" -m 0750 "${LOG_DIR}"
}

configure_ufw() {
  echo "Configurando firewall UFW básico..."
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw --force enable
}

update_clamav_signatures() {
  echo "Actualizando firmas de ClamAV con freshclam..."
  sudo systemctl stop clamav-freshclam 2>/dev/null || true

  if ! sudo freshclam; then
    echo "Aviso: freshclam falló. Puede ser temporal por red o bloqueo del servidor de firmas."
  fi

  sudo systemctl enable --now clamav-freshclam
}

build_onaccess_paths() {
  local candidates=(
    "${TARGET_HOME}/Descargas"
    "${TARGET_HOME}/Escritorio"
    "${TARGET_HOME}/Documentos"
    "${TARGET_HOME}/Downloads"
    "${TARGET_HOME}/Desktop"
    "${TARGET_HOME}/Documents"
    "${TARGET_HOME}/Proyectos"
    "/media/${TARGET_USER}"
  )
  local path

  ONACCESS_PATHS=()
  for path in "${candidates[@]}"; do
    if [[ -d "${path}" ]]; then
      ONACCESS_PATHS+=("${path}")
    fi
  done
}

configure_clamd() {
  echo "Configurando ClamOnAcc en /etc/clamav/clamd.conf..."
  [[ -f /etc/clamav/clamd.conf ]] || fail "no existe /etc/clamav/clamd.conf. Revisa la instalación de clamav-daemon."

  build_onaccess_paths

  local tmp_file
  tmp_file="$(mktemp)"

  sudo awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' /etc/clamav/clamd.conf > "${tmp_file}"

  {
    echo
    echo "${MARKER_BEGIN}"
    echo "ScanOnAccess yes"
    echo "OnAccessPrevention yes"
    echo "OnAccessExcludeUname clamav"
    echo "OnAccessMaxFileSize 100M"
    for path in "${ONACCESS_PATHS[@]}"; do
      echo "OnAccessIncludePath ${path}"
    done
    echo "${MARKER_END}"
  } >> "${tmp_file}"

  sudo install -o root -g root -m 0644 "${tmp_file}" /etc/clamav/clamd.conf
  rm -f -- "${tmp_file}"
}

configure_clamonacc_service() {
  echo "Instalando servicio systemd de ClamOnAcc..."
  sudo install -o root -g root -m 0644 "${SCRIPT_DIR}/config/clamonacc.service" /etc/systemd/system/clamonacc.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now clamav-daemon
  sudo systemctl restart clamav-daemon
  sudo systemctl enable --now clamonacc

  echo "Estado de clamonacc:"
  if ! sudo systemctl status clamonacc --no-pager; then
    echo "Aviso: clamonacc no aparece activo. Revisa los mensajes anteriores y /var/log/clamav/clamonacc.log."
  fi
}

configure_auditd() {
  echo "Configurando auditd con reglas propias del proyecto..."
  sudo systemctl enable --now auditd
  sudo install -o root -g root -m 0640 "${SCRIPT_DIR}/config/audit.rules" /etc/audit/rules.d/kubuntu-defender-lite.rules

  if command -v augenrules >/dev/null 2>&1; then
    sudo augenrules --load
  else
    sudo systemctl restart auditd
  fi
}

check_apparmor() {
  echo "Comprobando AppArmor..."
  if sudo aa-status >/tmp/kubuntu-defender-lite-aa-status.txt 2>&1; then
    grep -E "profiles are in (enforce|complain) mode|apparmor module is loaded|apparmor filesystem is mounted" /tmp/kubuntu-defender-lite-aa-status.txt || true
  else
    cat /tmp/kubuntu-defender-lite-aa-status.txt
    echo "Aviso: AppArmor no parece estar activo o aa-status no pudo comprobarlo."
  fi
  rm -f /tmp/kubuntu-defender-lite-aa-status.txt

  cat <<'EOF'
AppArmor:
* enforce = bloquea según el perfil cargado.
* complain = registra violaciones, normalmente no bloquea.
AppArmor no es un antivirus y este instalador no cambia perfiles de forma agresiva.
EOF
}

configure_lynis_timer() {
  echo "Configurando timer mensual de Lynis..."
  local helper_dir="/usr/local/lib/${PROJECT_NAME}/scripts"
  local helper_path="${helper_dir}/lynis-monthly-audit.sh"
  local service_tmp
  local timer_tmp

  sudo install -d -o root -g root -m 0755 "${helper_dir}"
  sudo install -o root -g root -m 0755 "${SCRIPT_DIR}/scripts/lynis-monthly-audit.sh" "${helper_path}"

  service_tmp="$(mktemp)"
  timer_tmp="$(mktemp)"

  cat > "${service_tmp}" <<EOF
[Unit]
Description=Kubuntu Defender Lite monthly Lynis audit
After=network-online.target

[Service]
Type=oneshot
ExecStart=${helper_path} ${LOG_DIR} ${TARGET_USER}
EOF

  cat > "${timer_tmp}" <<'EOF'
[Unit]
Description=Run Kubuntu Defender Lite Lynis audit monthly

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

  sudo install -o root -g root -m 0644 "${service_tmp}" /etc/systemd/system/kubuntu-defender-lite-lynis.service
  sudo install -o root -g root -m 0644 "${timer_tmp}" /etc/systemd/system/kubuntu-defender-lite-lynis.timer
  rm -f -- "${service_tmp}" "${timer_tmp}"

  sudo systemctl daemon-reload
  sudo systemctl enable --now kubuntu-defender-lite-lynis.timer
}

print_final_status() {
  cat <<EOF

Instalación completada.

Resumen:
* UFW bloquea conexiones entrantes y permite salientes.
* ClamAV está instalado con freshclam y clamav-daemon activados.
* ClamOnAcc vigila carpetas normales del usuario y /media/${TARGET_USER}.
* OnAccessPrevention yes bloquea acceso a malware detectado, pero no borra ni mueve archivos.
* auditd registra cambios sensibles; normalmente no bloquea.
* AppArmor se ha comprobado sin cambiar perfiles agresivamente.
* Lynis queda programado una vez al mes con systemd timer.
* Logs de Lynis: ${LOG_DIR}

Comprueba el estado con:
  ./scripts/security-status.sh
EOF

  echo
  echo "Estado de servicios principales:"
  systemctl --no-pager --full status clamav-freshclam clamav-daemon auditd 2>/dev/null || true
}

main() {
  need_command sudo
  need_command id
  need_command getent
  need_command awk
  need_command mktemp
  need_command install

  request_sudo
  check_os
  select_target_user

  print_summary
  if ! ask_yes_no "¿Quieres continuar? [s/N]" "no"; then
    echo "Cancelado. No se han hecho cambios."
    exit 0
  fi

  install_packages
  ensure_directories
  configure_ufw
  update_clamav_signatures
  configure_clamd
  configure_clamonacc_service
  configure_auditd
  check_apparmor
  configure_lynis_timer
  print_final_status
}

main "$@"
