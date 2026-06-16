# Lynis

Lynis es una herramienta de auditoría de seguridad. Revisa configuración del sistema y genera recomendaciones.

No es antivirus, no bloquea malware y no sustituye a UFW, ClamAV, AppArmor ni auditd.

## Timer mensual

`kubuntu-defender-lite` crea un servicio y timer de systemd:

```text
/etc/systemd/system/kubuntu-defender-lite-lynis.service
/etc/systemd/system/kubuntu-defender-lite-lynis.timer
```

El timer usa:

```text
OnCalendar=monthly
Persistent=true
```

Esto ejecuta Lynis una vez al mes. Si el portátil estaba apagado cuando tocaba la ejecución, systemd la lanzará en el siguiente arranque disponible.

No se crea escaneo semanal y no se usan cron jobs.

## Logs

Los logs se guardan en:

```text
$HOME/.local/share/kubuntu-defender-lite/logs/
```

El servicio se ejecuta como root para que Lynis pueda hacer una auditoría completa y después ajusta el propietario del log al usuario objetivo.
