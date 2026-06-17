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

QUARANTINE_DIR="${TARGET_HOME}/.local/share/${PROJECT_NAME}/quarantine"
QUARANTINE_LOG="${QUARANTINE_DIR}/quarantine.log"

declare -a FILE_NAMES=()
declare -a FILE_PATHS=()

load_quarantine_files() {
  local file

  if [[ ! -d "${QUARANTINE_DIR}" ]]; then
    return 0
  fi

  while IFS= read -r -d '' file; do
    FILE_PATHS+=("${file}")
    FILE_NAMES+=("$(basename -- "${file}")")
  done < <(find "${QUARANTINE_DIR}" -mindepth 1 -maxdepth 1 -type f ! -name 'quarantine.log' -print0 2>/dev/null | sort -z)
}

print_files() {
  local i

  echo "Archivos en cuarentena:"
  echo
  for i in "${!FILE_PATHS[@]}"; do
    printf "%d) %s\n" "$((i + 1))" "${FILE_NAMES[$i]}"
    printf "   ruta -> %s\n" "${FILE_PATHS[$i]}"
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

is_safe_quarantine_file() {
  local path="$1"
  local parent

  [[ -n "${path}" ]] || return 1
  [[ -f "${path}" ]] || return 1
  [[ ! -L "${path}" ]] || return 1

  parent="$(dirname -- "${path}")"
  [[ "${parent}" == "${QUARANTINE_DIR}" ]] || return 1
  [[ "$(basename -- "${path}")" != "quarantine.log" ]] || return 1
}

delete_file() {
  local path="$1"

  if ! is_safe_quarantine_file "${path}"; then
    echo "Omitido por seguridad: ${path}"
    return 1
  fi

  rm -- "${path}"
  printf "%s | deleted | quarantine=%s\n" "$(date -Is)" "${path}" >> "${QUARANTINE_LOG}"
}

main() {
  local answer=""
  local input=""
  local confirm=""
  local number
  local index
  declare -a selected_numbers=()

  load_quarantine_files

  if [[ "${#FILE_PATHS[@]}" -eq 0 ]]; then
    echo "La cuarentena está vacía."
    exit 0
  fi

  print_files

  read -r -p "¿Quieres borrar archivos de la cuarentena? [s/N] " answer
  case "${answer}" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS]) ;;
    *)
      echo "No se ha borrado ningún archivo."
      exit 0
      ;;
  esac

  read -r -p "Escribe los números a borrar separados por comas o espacios. Ejemplo: 1,2,3,5,10. Escribe 0 para no borrar ninguno. Escribe ALL para borrar todos: " input

  if [[ "${input}" == "0" ]]; then
    echo "No se ha borrado ningún archivo."
    exit 0
  fi

  if [[ "${input}" == "ALL" ]]; then
    read -r -p "Esto borrará definitivamente todos los archivos de cuarentena. ¿Seguro? Escribe BORRAR para confirmar: " confirm
    if [[ "${confirm}" != "BORRAR" ]]; then
      echo "Cancelado. No se ha borrado ningún archivo."
      exit 0
    fi

    for index in "${!FILE_PATHS[@]}"; do
      delete_file "${FILE_PATHS[$index]}" || true
    done
    echo "Archivos de cuarentena borrados."
    exit 0
  fi

  if ! parse_selection "${input}" "${#FILE_PATHS[@]}" selected_numbers; then
    exit 1
  fi

  if [[ "${#selected_numbers[@]}" -eq 0 ]]; then
    echo "No se ha borrado ningún archivo."
    exit 0
  fi

  read -r -p "Esto borrará definitivamente los archivos seleccionados. ¿Continuar? [s/N] " confirm
  case "${confirm}" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS]) ;;
    *)
      echo "Cancelado. No se ha borrado ningún archivo."
      exit 0
      ;;
  esac

  for number in "${selected_numbers[@]}"; do
    index=$((number - 1))
    delete_file "${FILE_PATHS[$index]}" || true
  done

  echo "Archivos seleccionados borrados."
}

main "$@"
