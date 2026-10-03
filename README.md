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

Sin la clave de subida (abajo) el release se firma con las claves de depuración y el manifiesto lo dice
(`"signing": "debug"`): vale para instalar a mano, no para Play Store. Ese APK lleva el token de depuración de App
Check (un APK instalado a mano no pasa Play Integrity): no se reparte fuera del equipo de pruebas.

## Google Play (AAB)

```bash
dart run tool/build_release.dart --play
```

Construye `blow-nights-<versión>+<versionCode>-<commit>.aab` con las mismas comprobaciones de procedencia, y además:

- **Firmado con la clave de subida** (`android/key.properties`); sin ella se niega a construir.
- **Ofuscado**; los símbolos quedan en `build/release/symbols/<nombre>/` (guárdalos con el AAB: sin ellos no se
  leen las trazas de los crashes).
- **Sin el token de depuración de App Check**: la app usa Play Integrity.
- El `.json` dice `"variant": "play"`, `"obfuscated": true` y el SHA-256 del AAB.

### Clave de subida (una vez, la custodia el responsable de la cuenta de Play)

```bash
keytool -genkeypair -v -keystore C:/ruta/fuera/del/repo/blownights-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Y `android/key.properties` (está en `.gitignore`, nunca se sube):

```properties
storeFile=C:/ruta/fuera/del/repo/blownights-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Guarda el `.jks` y las contraseñas en un gestor de contraseñas. Con Play App Signing, si se pierde la clave de subida
se puede pedir otra a Google; la clave que firma lo que descargan los usuarios la guarda Google.

### Después de la primera subida

En Play Console → Integridad de la app → Firma de apps salen las huellas SHA-1 y SHA-256 de la **clave de firma de
la app** (la de Google) y de la **clave de subida**. Hay que añadirlas en:

- Firebase → Configuración del proyecto → app Android `com.blownights.finder` (Google Sign-In, App Check con Play
  Integrity).
- Google Cloud → Credenciales → la clave de Places: restringida a apps Android, paquete `com.blownights.finder` y
  esas huellas, y solo a las APIs que usa.

Sin eso, la app descargada de Play falla al entrar con Google o al buscar direcciones aunque el APK de pruebas
funcione.
