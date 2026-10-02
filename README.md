# blow_nights

App de Blow Nights (Flutter): port de la web, con NFC, «Amigos cerca» y los paneles B2B.

## Release APK con trazabilidad

Cada APK que se instala o se distribuye tiene que poder relacionarse con el commit exacto que lo produjo. Se
construye siempre con:

```bash
dart run tool/build_release.dart
```

El script se niega a construir si el árbol tiene cambios sin commitear, si el commit no está en `origin` o si falta
`dart_defines.json` (token de App Check y clave de Places; no se versiona). Si todo está bien:

- Dentro del APK van la versión, el versionCode, el commit y la hora del build (se ven al final del perfil:
  `v1.0.1 (2) · 3f2a9c1 · 2026-10-02T19:12:04Z`). Un `flutter run` normal muestra «dev build».
- En `build/release/` quedan `blow-nights-<versión>+<versionCode>-<commit>.apk` y su `.json` con el commit, las
  versiones, la hora, la versión de Flutter, la firma, las claves de `dart_defines` usadas (nunca sus valores) y el
  **SHA-256 del APK** (no puede ir dentro del propio APK).
- Un versionCode ya usado por el release de otro commit para el build: sube `version:` en `pubspec.yaml`.

Mientras `android/app/build.gradle.kts` firme el release con las claves de depuración, el manifiesto lo dice
(`"signing": "debug"`): vale para instalar a mano, no para Play Store.
