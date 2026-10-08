# 3DPong — aplicaciones nativas

Android e iOS exclusivamente, sin web, WebView, Capacitor ni Three.js.

- Android: Java, Android Views y renderizado 3D con OpenGL ES 2.0.
- iOS: Swift, UIKit y renderizado 3D con Metal/MetalKit.
- Servidor compartido: Node.js 24, WebSockets y SQLite para cuentas, Elo y matchmaking.

Ambas aplicaciones incluyen modo individual con rival automático, tres dificultades, controles táctiles, registro, inicio de sesión, ranking y enfrentamientos por nivel. Los temas siguen el modo claro/oscuro del sistema. Las sesiones nativas solo se mantienen en memoria; las contraseñas no se guardan en el dispositivo.

## Preparar esta nube

`./scripts/setup-cloud.sh` instala y activa SDK/JDK en `/workspace`, respeta TLS y checksums, configura el proxy JVM y ejecuta las pruebas y compilación de Android. Usa los checkouts existentes; no crea worktrees. iOS sigue requiriendo macOS/Xcode.

## Android

Abre `android/` en Android Studio. Requiere Android SDK 36, Build Tools 35.0.0 y JDK 21. En esta nube, si están instalados en `/workspace`, configura `ANDROID_HOME=/workspace/android-sdk`, `ANDROID_USER_HOME=/workspace/.android`, `GRADLE_USER_HOME=/workspace/.gradle` y `JAVA_HOME` con la carpeta del JDK.

```sh
npm run android:debug
```

El APK de depuración se genera en `android/app/build/outputs/apk/debug/app-debug.apk`. La publicación de APK/AAB necesita un identificador definitivo y clave privada de firma. La clave de depuración no sirve para publicar.

## iOS

Abre `ios/App/App.xcodeproj` en macOS con Xcode. Selecciona el esquema App, dispositivo y equipo de firma. El proyecto solo usa los frameworks del sistema y no necesita instalar paquetes Swift ni CocoaPods.

```sh
npm run ios:build
```

Este comando comprueba una compilación sin firma en macOS; Linux no tiene UIKit, Metal ni Xcode para ejecutarlo. Para App Store crea un Archive firmado desde Xcode. Metal requiere un dispositivo o simulador compatible.

## Servidor y multijugador

```sh
npm ci --cache /workspace/.npm-cache
npm test
npm run server
```

El servidor escucha en el puerto 3001; `GET /api/health` devuelve `{"ok":true}`. En cada aplicación introduce la dirección HTTPS real del backend, sin ruta, y crea o inicia sesión en una cuenta. HTTPS y WSS se validan mediante las APIs de red nativas; no se permiten conexiones sin cifrar ni se desactiva la validación de certificados. Para probar desde móviles necesita un servidor o proxy HTTPS accesible; aún no se ha desplegado uno.

Pulsa «Buscar rival» en dos aplicaciones. El matchmaking empieza en ±100 Elo y amplía el rango 10 puntos por segundo. La partida comienza tras tres segundos y termina al llegar a siete puntos. El servidor controla la pelota, las palas y los puntos; el cliente solo envía la posición deseada. Desconectarse concede la victoria al rival. No hay pausa online.

El servidor usa scrypt para las contraseñas y sesiones de siete días. SQLite guarda cuentas, sesiones, resultados y Elo en `.data/pong.sqlite`, excluido de Git. `DB_PATH` cambia la ruta y `PORT` el puerto. El ranking persiste al reiniciar, pero la cola y las partidas no. `ALLOWED_ORIGINS` controla clientes con cabecera Origin; los clientes nativos no la necesitan.

## Validación

`npm test` comprueba la física autoritativa y las cuentas, matchmaking, estados de partida, derrota por desconexión, persistencia de Elo y cierre de sesión. `scripts/check-native-physics.sh` compila y ejecuta pruebas de la simulación Java usada por Android (requiere JDK). La compilación de Android y las pruebas Java no verifican Metal ni sustituyen las pruebas de interacción en dispositivos reales. La simulación local de iOS está implementada en Swift y requiere su propia validación en Xcode.

## AWS

`docker build -f server/Dockerfile -t 3dpong-server .` construye el backend. Para esta versión SQLite, usa una instancia EC2 con Docker y disco EBS persistente montado en `/data` con permisos para UID 1000. Configura un proxy HTTPS/ALB con WebSockets y comprobación `/api/health`, restringiendo el puerto 3001. Solo se despliega el servidor, sin alojamiento web. Haz copias consistentes de SQLite y prueba la recuperación.

Para varias instancias será necesario PostgreSQL/RDS y coordinación de cola y partidas (por ejemplo Redis/ElastiCache y enrutamiento de sesiones). No se han creado recursos AWS ni cargos. Las credenciales AWS y claves de firma nunca deben guardarse en Git.

## Límites actuales

No hay recuperación de contraseña, correo verificado, reconexión a partidas, salas privadas ni historial visible. Reiniciar el servidor interrumpe partidas sin cambiar Elo. Falta validar renderizado y controles en dispositivos reales, compilar iOS en macOS y configurar el servidor HTTPS público antes de publicar.
