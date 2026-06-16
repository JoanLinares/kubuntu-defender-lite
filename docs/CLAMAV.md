# ClamAV

ClamAV es un antivirus libre basado en firmas. Detecta malware conocido y puede analizar archivos bajo demanda con `clamscan` o mediante el demonio `clamav-daemon`.

ClamAV no detecta absolutamente todo. Como cualquier antivirus basado en firmas, depende de que las firmas estén actualizadas y de que la amenaza sea conocida o detectable por sus reglas.

Este proyecto instala:

* `clamav`
* `clamav-daemon`
* `clamtk`

También activa `clamav-freshclam` para actualizar firmas.

## Comportamiento seguro

`kubuntu-defender-lite` no borra archivos detectados por defecto y no los mueve a cuarentena automática. Las detecciones quedan registradas en logs de ClamAV/ClamOnAcc para que el usuario pueda revisar qué ocurrió.

Para escaneos manuales:

```bash
./scripts/scan-folder.sh /ruta/de/carpeta
./scripts/scan-full.sh
```

El escaneo completo manual no se programa automáticamente.
