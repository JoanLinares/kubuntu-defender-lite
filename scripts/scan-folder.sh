#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 /ruta/de/carpeta" >&2
  exit 1
fi

TARGET_PATH="$1"

if [[ ! -e "${TARGET_PATH}" ]]; then
  echo "Error: la ruta no existe: ${TARGET_PATH}" >&2
  exit 1
fi

if [[ ! -d "${TARGET_PATH}" ]]; then
  echo "Error: la ruta debe ser una carpeta: ${TARGET_PATH}" >&2
  exit 1
fi

if ! command -v clamscan >/dev/null 2>&1; then
  echo "Error: clamscan no está instalado." >&2
  exit 1
fi

echo "Escaneo manual de carpeta: ${TARGET_PATH}"
echo "No se borrarán ni moverán archivos."
clamscan -r -i -- "${TARGET_PATH}"
