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

## Notificaciones de detecciones

El servicio de notificaciones es un servicio de usuario systemd:

```bash
systemctl --user status kubuntu-defender-lite-notify.service --no-pager
```

Para comprobar que KDE muestra notificaciones:

```bash
notify-send "Kubuntu Defender Lite" "Prueba de notificación"
```

Si no aparece la notificación en KDE/Wayland:

* Comprueba que `libnotify-bin` está instalado.
* Ejecuta la prueba `notify-send` dentro de tu sesión gráfica, no desde una TTY.
* Revisa que el servicio de usuario está activo.
* Revisa el log local:

```bash
cat ~/.local/share/kubuntu-defender-lite/notify-state/notify.log
```

El servicio solo avisa. No borra ni mueve archivos.

## Revisar detecciones y cuarentena

Revisar detecciones:

```bash
./scripts/review-detections.sh
```

Ver cuarentena:

```bash
ls -lh ~/.local/share/kubuntu-defender-lite/quarantine/
```

Borrar manualmente archivos de cuarentena:

```bash
./scripts/delete-quarantine-files.sh
```

Si un archivo detectado ya no existe, `review-detections.sh` lo mostrará como "ya no existe" y no lo moverá.

Si un archivo no se puede mover por permisos, ejecuta de nuevo:

```bash
sudo ./scripts/review-detections.sh
```

El script detecta el usuario normal con `SUDO_USER` y no pide ni guarda contraseñas manualmente.

## Si ClamOnAcc aparece como inactive

La protección en tiempo real no está funcionando mientras `clamonacc` esté `inactive`. Revisa primero el error exacto:

```bash
sudo systemctl status clamonacc --no-pager -l
sudo journalctl -u clamonacc -n 80 --no-pager
systemctl status clamav-daemon --no-pager -l
ls -l /var/run/clamav/
```

En Kubuntu 26.04 y ClamAV moderno, el servicio del proyecto debe arrancar `clamonacc` en primer plano:

```text
ExecStart=/usr/sbin/clamonacc --foreground --fdpass --log=/var/log/clamav/clamonacc.log
```

Si el servicio no tiene `--foreground`, systemd puede marcarlo como `inactive` porque `clamonacc` hace fork al background.

Si ves un aviso como `Ignoring deprecated option ScanOnAccess`, revisa el bloque del proyecto:

```bash
sudo grep -n "ScanOnAccess\|OnAccess\|KUBUNTU-DEFENDER-LITE" /etc/clamav/clamd.conf
```

El bloque `KUBUNTU-DEFENDER-LITE` no debe contener `ScanOnAccess yes`. Las líneas esperadas son `OnAccessIncludePath`, `OnAccessPrevention yes`, `OnAccessExcludeUname clamav` y `OnAccessMaxFileSize 100M`.

Después de corregir el bloque o volver a ejecutar el instalador actualizado:

```bash
sudo systemctl restart clamav-daemon
sudo systemctl restart clamonacc
./scripts/security-status.sh
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
