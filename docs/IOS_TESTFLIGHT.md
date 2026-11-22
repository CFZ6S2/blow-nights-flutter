# App de iPhone: de la cuenta de Apple a TestFlight

La app de iPhone es la misma que la de Android (misma versión de `pubspec.yaml`). No hace falta Mac: GitHub
compila, firma y sube la app con el proceso **iOS TestFlight** (`.github/workflows/ios-testflight.yml`).

Ya está hecho en el código:

- Identificador de la app: `com.blownights.finder` (el mismo que en Android y en Google Play).
- App de iPhone dada de alta en Firebase `blownights` (`ios/Runner/GoogleService-Info.plist`).
- Textos de permisos (cámara, ubicación, fotos, micrófono, Bluetooth, NFC), entrar con Google y con Apple,
  avisos (push) e icono.
- Premium, pase y toques **no se venden en iPhone** (Apple obliga a cobrarlos con su sistema); entradas, copas y
  cashless siguen con Stripe, que Apple sí permite porque se consumen fuera de la app.
- «Amigos cerca» no funciona en iPhone: la pantalla ya lo dice.

## 1. Cuenta de desarrollador de Apple

1. Hacerla **como empresa** a nombre de TCS Global Solutions LLC en <https://developer.apple.com/programs/enroll/>
   (99 $/año). Pide un número **D-U-N-S** de la empresa: si no lo tenéis, Apple lo tramita gratis y tarda unos días.
2. Apuntar el **Team ID** (Account → Membership details, 10 letras y números).

## 2. Registrar la app en Apple

1. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → `+` → App IDs → App.
   Bundle ID explícito `com.blownights.finder`. Marcar: **Push Notifications**, **Sign in with Apple** y **App Attest**.
2. **Keys** → `+` → marcar **Apple Push Notifications service (APNs)** → descargar el `.p8` (solo se puede bajar una
   vez). Este es para los avisos.
3. App Store Connect (<https://appstoreconnect.apple.com>) → Apps → `+` → Nueva app: iOS, nombre «Blow Nights»,
   idioma principal español, Bundle ID `com.blownights.finder`, SKU `blownights`.

## 3. Firebase (proyecto `blownights`)

1. Configuración del proyecto → **Cloud Messaging** → app de iOS → subir la clave APNs (`.p8` del paso 2.2, su Key ID y
   el Team ID). Sin esto no llegan los avisos al iPhone.
2. **App Check** → Apps → app de iOS → registrar **App Attest** (pide el Team ID). Ahora App Check no obliga, así que la
   app funciona igual sin este paso, pero conviene dejarlo hecho.

## 4. Llave para que GitHub suba la app

1. App Store Connect → Usuarios y acceso → **Integraciones** → App Store Connect API → generar una llave con rol
   **Admin** (con menos permisos GitHub no puede crear los certificados él solo). Descargar el `.p8` y apuntar el
   **Key ID** y el **Issuer ID**.
2. En GitHub, repo `CFZ6S2/blow-nights-flutter` → Settings → Secrets and variables → Actions → New repository secret:

   | Nombre | Valor |
   | --- | --- |
   | `APPLE_TEAM_ID` | Team ID |
   | `ASC_KEY_ID` | Key ID de la llave del paso 4.1 |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8_BASE64` | el `.p8` del paso 4.1 en base64 (PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))`) |
   | `PLACES_API_KEY` | el mismo valor que en `dart_defines.json` |

## 5. Subir la app

1. GitHub → Actions → **iOS TestFlight** → Run workflow (rama `main`). Tarda unos 20-30 minutos.
2. Cuando acaba, la versión aparece en App Store Connect → la app → **TestFlight** (Apple la revisa unos minutos).
3. Probadores internos (hasta 100 personas con acceso a App Store Connect): se añaden y les llega al momento.
   Probadores externos (hasta 10.000, con un enlace público, como la prueba abierta de Google Play): la primera
   versión pasa una revisión de Apple de 1-2 días.
4. En el iPhone: instalar la app **TestFlight** de la App Store y abrir la invitación o el enlace.

Para cada versión nueva: subir el número de `pubspec.yaml` (como para Android) y volver a lanzar el proceso. Apple no
acepta dos veces el mismo número de compilación (el de detrás del `+`).

## Si el proceso falla

- «Missing repository secret»: falta uno de los secretos del paso 4.2.
- Error de firma o de perfil: comprobar que la llave del paso 4.1 tiene rol Admin y que el identificador del paso 2.1
  existe con las tres casillas marcadas.
- «bundle version must be higher»: el número de compilación ya se usó; subirlo en `pubspec.yaml`.
