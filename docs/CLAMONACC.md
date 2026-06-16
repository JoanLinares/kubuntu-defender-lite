# ClamOnAcc

ClamOnAcc es el componente de ClamAV para escaneo en tiempo real mediante acceso a archivos. Este proyecto lo usa de forma limitada para mantener bajo el consumo de RAM y evitar vigilar todo el sistema.

## Carpetas vigiladas

Se configuran rutas absolutas para el usuario objetivo:

* `~/Descargas`
* `~/Escritorio`
* `~/Documentos`
* `~/Downloads`
* `~/Desktop`
* `~/Documents`
* `~/Proyectos`
* `/media/$USER`

El instalador crea `~/Proyectos` si no existe y crea `/media/$USER` si no existe. No modifica, borra, mueve ni copia contenido dentro de esas carpetas.

## USBs

Kubuntu monta pendrives y discos externos en `/media/$USER`, por eso se vigila esa ruta. No se usa una carpeta artificial como `~/USB`.

## Bloqueo

La opción:

```text
OnAccessPrevention yes
```

hace que ClamOnAcc bloquee el acceso a archivos detectados como malware dentro de las rutas vigiladas.

El proyecto no borra malware automáticamente y no crea cuarentena automática por defecto.

El instalador no añade `ScanOnAccess yes` al bloque del proyecto. Esa opción aparece como obsoleta en versiones modernas de ClamAV; ClamOnAcc se ejecuta mediante su servicio systemd y las rutas se definen con `OnAccessIncludePath`.

El servicio systemd ejecuta `clamonacc` con `--foreground` para que systemd pueda seguir el proceso. Sin esa opción, `clamonacc` puede hacer fork al background y systemd puede mostrar el servicio como `inactive`.

## Rendimiento

No se vigila `/`, todo `/home`, `/tmp`, `/var`, `/usr` ni rutas grandes del sistema. Vigilar todo el sistema en tiempo real puede consumir muchos recursos y causar falsos positivos operativos.
