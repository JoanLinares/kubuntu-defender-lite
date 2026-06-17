#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kubuntu-defender-lite"
TARGET_USER="${SUDO_USER:-${USER:-}}"

if [[ "${TARGET_USER}" == "root" && -n "${LOGNAME:-}" && "${LOGNAME}" != "root" ]]; then
  TARGET_USER="${LOGNAME}"
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" 2>/dev/null | cut -d: -f6 || true)"
if [[ -z "${TARGET_HOME}" || "${TARGET_HOME}" == "/" ]]; then
  echo "Error: no se pudo determinar un home válido para ${TARGET_USER}." >&2
  exit 1
fi

TARGET_GROUP="$(id -gn "${TARGET_USER}")"
DATA_DIR="${TARGET_HOME}/.local/share/${PROJECT_NAME}"
QUARANTINE_DIR="${DATA_DIR}/quarantine"
QUARANTINE_LOG="${QUARANTINE_DIR}/quarantine.log"
LOG_FILES=(
  "/var/log/clamav/clamav.log"
  "/var/log/clamav/clamonacc.log"
)

declare -a DETECTION_NAMES=()
declare -a DETECTION_PATHS=()
declare -a DETECTION_SOURCES=()
declare -A SEEN_PATHS=()

SUDO_READY="no"

ensure_sudo() {
  if [[ "${SUDO_READY}" == "yes" ]]; then
    return 0
  fi

  echo "Se necesitan permisos para leer logs o mover archivos." >&2
  if ! sudo -v; then
    echo "Error: sudo falló. No se ha guardado ni leído ninguna contraseña." >&2
    exit 1
  fi
  SUDO_READY="yes"
}

ensure_quarantine_dir() {
  if [[ "$(id -u)" -eq 0 ]]; then
    install -d -o "${TARGET_USER}" -g "${TARGET_GROUP}" -m 0700 "${QUARANTINE_DIR}"
  else
    mkdir -p -- "${QUARANTINE_DIR}"
    chmod 700 -- "${QUARANTINE_DIR}"
    chown "${TARGET_USER}:${TARGET_GROUP}" "${QUARANTINE_DIR}" 2>/dev/null || true
  fi

  if [[ ! -e "${QUARANTINE_LOG}" ]]; then
    : > "${QUARANTINE_LOG}"
  fi
  chown "${TARGET_USER}:${TARGET_GROUP}" "${QUARANTINE_LOG}" 2>/dev/null || true
  chmod 600 -- "${QUARANTINE_LOG}" 2>/dev/null || true
}

read_log() {
  local log_file="$1"

  if [[ ! -e "${log_file}" ]]; then
    return 0
  fi

  if [[ -r "${log_file}" ]]; then
    cat -- "${log_file}"
  else
    ensure_sudo
    sudo cat -- "${log_file}"
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "${value}"
}

add_detection_from_line() {
  local line="$1"
  local source="$2"
  local before_found=""
  local file_path=""
  local detection=""

  [[ "${line}" == *FOUND* ]] || return 0

  before_found="${line%% FOUND*}"
  detection="${before_found##*: }"
  file_path="${before_found%: ${detection}}"
  file_path="${file_path##* -> }"
  file_path="$(trim "${file_path}")"
  detection="$(trim "${detection}")"

  if [[ -z "${file_path}" || -z "${detection}" || "${file_path}" == "${before_found}" ]]; then
    return 0
  fi

  if [[ -n "${SEEN_PATHS[${file_path}]:-}" ]]; then
    return 0
  fi

  SEEN_PATHS["${file_path}"]=1
  DETECTION_NAMES+=("${detection}")
  DETECTION_PATHS+=("${file_path}")
  DETECTION_SOURCES+=("${source}")
}

load_detections() {
  local log_file
  local line
  local source

  for log_file in "${LOG_FILES[@]}"; do
    source="$(basename "${log_file}")"
    while IFS= read -r line; do
      add_detection_from_line "${line}" "${source}"
    done < <(read_log "${log_file}" | grep -F "FOUND" || true)
  done
}

print_detections() {
  local i
  local status

  echo "Detecciones encontradas:"
  echo

  for i in "${!DETECTION_PATHS[@]}"; do
    if [[ -e "${DETECTION_PATHS[$i]}" ]]; then
      status="existe"
    else
      status="ya no existe"
    fi

    printf "%d) %s\n" "$((i + 1))" "${DETECTION_NAMES[$i]}"
    printf "   archivo -> %s\n" "${DETECTION_PATHS[$i]}"
    printf "   estado  -> %s\n" "${status}"
    echo
  done
}

parse_selection() {
  local input="$1"
  local max="$2"
  local token
  local normalized
  declare -n out_ref="$3"
  declare -A selected=()

  out_ref=()
  normalized="${input//,/ }"

  for token in ${normalized}; do
    if [[ "${token}" == "0" ]]; then
      out_ref=()
      return 0
    fi

    if [[ ! "${token}" =~ ^[0-9]+$ ]]; then
      echo "Número no válido: ${token}" >&2
      return 1
    fi

    if (( token < 1 || token > max )); then
      echo "Número fuera de la lista: ${token}" >&2
      return 1
    fi

    if [[ -z "${selected[${token}]:-}" ]]; then
      selected["${token}"]=1
      out_ref+=("${token}")
    fi
  done

  return 0
}

safe_basename() {
  local path="$1"
  local name
  name="$(basename -- "${path}")"
  name="${name//[^A-Za-z0-9._-]/_}"
  [[ -n "${name}" ]] || name="archivo"
  printf "%s" "${name}"
}

move_to_quarantine() {
  local index="$1"
  local path="${DETECTION_PATHS[$index]}"
  local detection="${DETECTION_NAMES[$index]}"
  local source="${DETECTION_SOURCES[$index]}"
  local base
  local timestamp
  local dest
  local suffix=0

  if [[ -z "${path}" ]]; then
    echo "motivo -> ruta vacía"
    return 1
  fi

  if [[ ! -e "${path}" ]]; then
    echo "motivo -> el archivo ya no existe"
    return 1
  fi

  if [[ -d "${path}" ]]; then
    echo "motivo -> es un directorio"
    return 1
  fi

  if [[ -L "${path}" ]]; then
    echo "motivo -> es un symlink y no se moverá"
    return 1
  fi

  base="$(safe_basename "${path}")"
  timestamp="$(date +%F_%H-%M-%S)"
  dest="${QUARANTINE_DIR}/${timestamp}_${base}"

  while [[ -e "${dest}" ]]; do
    suffix=$((suffix + 1))
    dest="${QUARANTINE_DIR}/${timestamp}_${suffix}_${base}"
  done

  if mv -- "${path}" "${dest}" 2>/dev/null; then
    :
  else
    ensure_sudo
    sudo mv -- "${path}" "${dest}"
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    chown "${TARGET_USER}:${TARGET_GROUP}" "${dest}" 2>/dev/null || true
  elif [[ "${SUDO_READY}" == "yes" ]]; then
    sudo chown "${TARGET_USER}:${TARGET_GROUP}" "${dest}" 2>/dev/null || true
  fi
  chmod 600 -- "${dest}" 2>/dev/null || true

  printf "%s | moved | original=%s | quarantine=%s | detection=%s | source=%s\n" \
    "$(date -Is)" "${path}" "${dest}" "${detection}" "${source}" >> "${QUARANTINE_LOG}"

  printf "%s" "${dest}"
  return 0
}

main() {
  local answer=""
  local input=""
  declare -a selected_numbers=()
  declare -a moved_lines=()
  declare -a not_moved_lines=()
  local number
  local index
  local result

  ensure_quarantine_dir
  load_detections

  if [[ "${#DETECTION_PATHS[@]}" -eq 0 ]]; then
    echo "No se encontraron detecciones con FOUND en los logs de ClamAV."
    exit 0
  fi

  print_detections

  read -r -p "¿Quieres mover algún archivo a cuarentena? [s/N] " answer
  case "${answer}" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS]) ;;
    *)
      echo "No se ha movido ningún archivo."
      exit 0
      ;;
  esac

  read -r -p "Escribe los números a mover a cuarentena separados por comas o espacios. Ejemplo: 1,2,3,5,10. Escribe 0 para no mover ninguno: " input

  if ! parse_selection "${input}" "${#DETECTION_PATHS[@]}" selected_numbers; then
    exit 1
  fi

  if [[ "${#selected_numbers[@]}" -eq 0 ]]; then
    echo "No se ha movido ningún archivo."
    exit 0
  fi

  for number in "${selected_numbers[@]}"; do
    index=$((number - 1))
    if result="$(move_to_quarantine "${index}")"; then
      moved_lines+=("${number}) ${DETECTION_PATHS[$index]}" "   -> ${result}")
    else
      not_moved_lines+=("${number}) ${DETECTION_PATHS[$index]}" "   ${result}")
    fi
  done

  echo
  echo "Movidos a cuarentena:"
  if [[ "${#moved_lines[@]}" -eq 0 ]]; then
    echo "Ninguno."
  else
    printf "%s\n" "${moved_lines[@]}"
  fi

  echo
  echo "No movidos:"
  if [[ "${#not_moved_lines[@]}" -eq 0 ]]; then
    echo "Ninguno."
  else
    printf "%s\n" "${not_moved_lines[@]}"
  fi
}

main "$@"
