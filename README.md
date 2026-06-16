# kubuntu-defender-lite

`kubuntu-defender-lite` instala una protección ligera tipo "Windows Defender casero" para Kubuntu LTS Desktop. Está pensado para un usuario normal de Linux y prioriza simplicidad, reversibilidad, bajo consumo de RAM e idempotencia.

No es un EDR empresarial, no es un SIEM, no instala Wazuh ni OpenEDR, no añade reglas agresivas de firewall, no crea escaneos semanales, no borra malware automáticamente, no crea cuarentenas automáticas por defecto, no crea backups, no crea snapshots y no toca Steam, juegos ni SteamLibrary.

## Qué instala

* `ufw` y `gufw` para firewall básico.
* `clamav`, `clamav-daemon` y `clamtk` para antivirus.
* ClamOnAcc para protección en tiempo real limitada.
* `auditd` y `audispd-plugins` para registrar cambios sensibles.
* `apparmor-utils` para comprobar AppArmor.
* `lynis` con un timer mensual de systemd.

## Versiones soportadas

El instalador detecta la versión del sistema leyendo `/etc/os-release` antes de instalar paquetes. Kubuntu puede identificarse internamente como base Ubuntu, así que la decisión se toma por `VERSION_ID`.

Perfiles soportados:

* Kubuntu/Ubuntu 24.04 LTS, Noble Numbat, Plasma 5. Soporte de Kubuntu hasta abril de 2027.
* Kubuntu/Ubuntu 26.04 LTS, Resolute Raccoon, Plasma 6. Soporte de Kubuntu hasta abril de 2029.

Si detecta otra versión, el instalador se detiene antes de modificar el sistema. Para 24.04 y 26.04 se usa la misma pila ligera pedida: UFW, ClamAV, ClamOnAcc, auditd, comprobación de AppArmor y Lynis mensual. No añade paquetes extra por Plasma 5 o Plasma 6.

Antes de continuar muestra el sistema detectado y el perfil elegido.

## Qué bloquea

UFW bloquea conexiones entrantes y permite conexiones salientes. No se abren puertos automáticamente.

ClamOnAcc usa `OnAccessPrevention yes`, por lo que bloquea el acceso a archivos detectados como malware dentro de las carpetas vigiladas. No borra archivos detectados y no los mueve a cuarentena automática por defecto.

AppArmor solo bloquea cuando una aplicación tiene un perfil activo en `enforce`. Este proyecto no cambia perfiles de `complain` a `enforce` automáticamente.

## Qué solo registra

`auditd` registra cambios en zonas sensibles, pero normalmente no bloquea. AppArmor en modo `complain` también registra violaciones sin bloquear. Lynis audita y genera informes; no es antivirus.

## Carpetas vigiladas por ClamOnAcc

El instalador configura rutas absolutas para el usuario objetivo:

* `~/Descargas`
* `~/Escritorio`
* `~/Documentos`
* `~/Downloads`
* `~/Desktop`
* `~/Documents`
* `~/Proyectos`
* `/media/$USER`

Para USBs se vigila `/media/$USER`, porque Kubuntu monta ahí pendrives y discos externos. No se usa `~/USB`.

No se vigila todo `/`, todo `/home`, `/tmp`, `/var`, `/usr` ni otras rutas grandes para evitar pérdida de rendimiento. `scan-full.sh` existe solo para escaneos manuales.

El proyecto no toca el contenido de `~/Proyectos`, `Documentos`, `Descargas` ni `/media/$USER`.

## Sudo y contraseñas

El instalador usa `sudo -v` para que el sistema pida la contraseña de forma segura. Nunca pide contraseñas con `read -s`, nunca guarda contraseñas y nunca las escribe en logs.

Puede ejecutarse como:

```bash
./install.sh
```

o como:

```bash
sudo ./install.sh
```

Si se ejecuta con `sudo`, detecta el usuario normal mediante `SUDO_USER`.

## Backups, snapshots y reversibilidad

Este proyecto no crea backups de configuración, no crea archivos `.bak`, no crea snapshots y no hace copias de `/etc`, `/home` ni proyectos personales.

La reversibilidad se hace con `uninstall.sh`, que elimina los cambios realizados por este proyecto. Los paquetes y logs se eliminan solo si confirmas esa opción.

## Cifrado de disco

Si este Kubuntu está en un portátil o contiene datos personales o proyectos importantes, se recomienda activar cifrado de disco completo durante la instalación de Kubuntu. En Ubuntu/Kubuntu normalmente se usa LUKS.

El cifrado de disco protege tus datos si alguien roba el portátil o saca el SSD. No es antivirus, no bloquea malware mientras el sistema está encendido y desbloqueado, y complementa a ClamAV, UFW, AppArmor, auditd y Lynis.

Si se activa LUKS, normalmente se introduce la contraseña de cifrado una vez al arrancar. Después se usa la contraseña normal del usuario para iniciar sesión y usar `sudo`. Si se pierde la contraseña de cifrado, se puede perder el acceso a los datos.

El instalador no activa cifrado de disco, no modifica particiones, no toca LUKS, GRUB ni initramfs, no cifra carpetas existentes, no pide contraseñas de cifrado y no guarda claves.

## Instalar

```bash
git clone https://github.com/TU_USUARIO/kubuntu-defender-lite.git
cd kubuntu-defender-lite
chmod +x install.sh scripts/*.sh
./install.sh
```

Antes de modificar el sistema, el instalador muestra un resumen y pregunta:

```text
¿Quieres continuar? [s/N]
```

## Comprobar estado

```bash
./scripts/security-status.sh
```

## Escanear una carpeta manualmente

```bash
./scripts/scan-folder.sh /ruta/de/carpeta
```

Este comando no borra ni mueve archivos.

## Escaneo completo manual

```bash
./scripts/scan-full.sh
```

No se ejecuta automáticamente. Excluye `/proc`, `/sys`, `/dev`, `/run`, `/snap` y `/tmp`. No borra ni mueve archivos.

## Lynis mensual

Lynis se ejecuta una vez al mes mediante systemd timer con `Persistent=true`. Si el portátil estaba apagado, systemd lo ejecutará al siguiente arranque disponible.

Los logs se guardan en:

```text
$HOME/.local/share/kubuntu-defender-lite/logs/
```

No hay escaneo semanal programado ni cron jobs.

## Desinstalar

```bash
./uninstall.sh
```

El desinstalador no borra archivos personales, no borra `~/Proyectos`, no borra `~/Documentos`, no borra `~/Descargas` y no borra ni modifica el contenido de `/media/$USER`.
