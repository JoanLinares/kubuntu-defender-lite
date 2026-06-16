# Troubleshooting

## Ver estado general

```bash
./scripts/security-status.sh
```

## Si el instalador dice que la versión no está soportada

`install.sh` lee `/etc/os-release` y solo continúa con:

* `VERSION_ID=24.04`, perfil Kubuntu/Ubuntu 24.04 LTS Noble, Plasma 5.
* `VERSION_ID=26.04`, perfil Kubuntu/Ubuntu 26.04 LTS Resolute, Plasma 6.

Si estás en otra versión de Ubuntu/Kubuntu, el instalador se detiene antes de instalar paquetes o modificar `/etc`.

Kubuntu puede aparecer como Ubuntu base en `/etc/os-release`; eso es normal. La selección se hace por `VERSION_ID`.

## Ver servicios

```bash
systemctl status ufw --no-pager
systemctl status clamav-freshclam --no-pager
systemctl status clamav-daemon --no-pager
systemctl status clamonacc --no-pager
systemctl status auditd --no-pager
systemctl status kubuntu-defender-lite-lynis.timer --no-pager
```

## Logs de ClamAV

```bash
sudo tail -n 100 /var/log/clamav/clamav.log
sudo tail -n 100 /var/log/clamav/clamonacc.log
```

Para buscar detecciones:

```bash
sudo grep -Ei "FOUND|Infected files|virus|malware|OnAccess" /var/log/clamav/*.log
```

## Si ClamOnAcc consume demasiados recursos

Comprueba qué rutas están en el bloque `KUBUNTU-DEFENDER-LITE` de:

```text
/etc/clamav/clamd.conf
```

Este proyecto solo vigila carpetas normales del usuario y `/media/$USER`. No vigila todo `/` para evitar sobrecarga. Si añadiste rutas manualmente, retíralas con cuidado o ejecuta `./uninstall.sh` para quitar la configuración del proyecto.

## Si AppArmor muestra perfiles en complain

`complain` significa que AppArmor registra violaciones, pero normalmente no bloquea. Este proyecto no cambia perfiles a `enforce` automáticamente para evitar romper aplicaciones.

## Si freshclam falla temporalmente

Puede deberse a red, DNS, proxy o limitación temporal del servidor de firmas. Reintenta:

```bash
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl start clamav-freshclam
```

## Revisar auditd

```bash
sudo ausearch -k kubuntu-defender-lite-identity
sudo ausearch -k kubuntu-defender-lite-sudo
sudo ausearch -k kubuntu-defender-lite-clamav
sudo ausearch -k kubuntu-defender-lite-systemd
```

Recuerda que auditd registra eventos, pero normalmente no bloquea.

## Desinstalar

```bash
./uninstall.sh
```

El desinstalador no borra archivos personales ni contenido de `/media/$USER`. Pregunta antes de borrar logs y antes de desinstalar paquetes.

## Backups y snapshots

Este proyecto no crea backups de configuración, no crea archivos `.bak`, no crea snapshots y no hace copias de `/etc`, `/home` ni proyectos personales.
