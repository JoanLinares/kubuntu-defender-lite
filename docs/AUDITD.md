# auditd

`auditd` registra eventos de seguridad del sistema. Este proyecto lo usa para observar cambios en archivos y directorios sensibles.

Normalmente `auditd` no bloquea acciones. Su papel aquí es registrar eventos para que puedas revisar qué cambió y cuándo.

## Rutas vigiladas

Las reglas del proyecto se guardan en:

```text
/etc/audit/rules.d/kubuntu-defender-lite.rules
```

Rutas registradas:

* `/etc/passwd`
* `/etc/shadow`
* `/etc/group`
* `/etc/sudoers`
* `/etc/sudoers.d/`
* `/etc/clamav/`
* `/etc/systemd/system/`

El instalador reemplaza solo su archivo de reglas y no modifica destructivamente otros archivos de auditd.

## Consultar eventos

Ejemplo:

```bash
sudo ausearch -k kubuntu-defender-lite-identity
sudo ausearch -k kubuntu-defender-lite-sudo
sudo ausearch -k kubuntu-defender-lite-clamav
sudo ausearch -k kubuntu-defender-lite-systemd
```
