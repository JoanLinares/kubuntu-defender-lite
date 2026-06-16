#!/usr/bin/env bash
set -euo pipefail

if ! command -v clamscan >/dev/null 2>&1; then
  echo "Error: clamscan no está instalado." >&2
  exit 1
fi

echo "Escaneo completo manual del sistema."
echo "No se borrarán ni moverán archivos."
echo "Se excluirán /proc, /sys, /dev, /run, /snap y /tmp."

if ! sudo -v; then
  echo "Error: sudo falló. No se ha guardado ni leído ninguna contraseña." >&2
  exit 1
fi

sudo clamscan -r -i / \
  --exclude-dir='^/proc' \
  --exclude-dir='^/sys' \
  --exclude-dir='^/dev' \
  --exclude-dir='^/run' \
  --exclude-dir='^/snap' \
  --exclude-dir='^/tmp'
