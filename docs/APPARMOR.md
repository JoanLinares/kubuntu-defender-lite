# AppArmor

AppArmor limita lo que pueden hacer aplicaciones concretas mediante perfiles de seguridad. Es una capa de contención, no un antivirus.

Este proyecto instala `apparmor-utils` si hace falta y comprueba el estado con:

```bash
aa-status
```

No cambia perfiles existentes de `complain` a `enforce`, no modifica perfiles de forma agresiva y no intenta endurecer el sistema de forma masiva.

## Modos

`enforce` significa que AppArmor bloquea acciones según el perfil cargado.

`complain` significa que AppArmor registra violaciones, pero normalmente no bloquea.

Si ves perfiles en `complain`, no significa necesariamente que haya un problema. Puede ser una decisión de la distribución o del administrador del sistema.
