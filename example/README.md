# Ejemplo independiente de vrlizate_home

Combina la interfaz de `vrlizate_home` con el controlador, descubrimiento y visor
de `vrlizate_apps`. Ejecuta entrada, temas, catálogo, lobby espacial y biblioteca
`.vrlz` sin importar `VRlizate_app`, sus demos, Firebase ni sus servicios.
Requiere la combinación Flutter GPU indicada en `../../flutter-toolchain.json`
y `vrlizate ^1.13.0` para sus APIs de sesión.

```sh
flutter pub get
flutter analyze --no-pub
FLUTTER_DART_DATA_ASSETS=false flutter test --no-pub
FLUTTER_DART_DATA_ASSETS=false flutter build apk --release --no-pub --target-platform android-arm64
dart tool/verify_android_shaders.dart build/app/outputs/flutter-apk/app-release.apk
```

**Probar sin visor → Galería portátil** abre el GLB incluido dentro de
`assets/stereo_gallery.vrlz`. **Biblioteca .vrlz** muestra la carpeta
`VRlizate-example/experiencias` dentro del directorio de documentos de la app.
La primera lectura no crea la carpeta ni instala paquetes. **Añadir ejemplos**
crea la carpeta e importa explícitamente una escena portátil y un descriptor
`gallery` que abre la galería ya compilada en este host.

**Añadir desde HTTPS** permite importar un paquete `.vrlz` o consultar un índice
JSON. Una importación no inicia automáticamente la experiencia.
**Usar carpeta local** vuelve al directorio después de consultar un índice web.

**Usar como visor** abre el lobby espacial con un catálogo aportado por este
host. El ejemplo no inicia un servidor de mandos; la app completa aporta esa
integración a través de `VrHomeSpatialBindings`. La lectura de carpetas, los
clientes HTTPS, el ciclo de vida y el lanzamiento pertenecen al host y Apps;
Home recibe valores y callbacks para presentar la biblioteca.

## Sesiones y navegación

Este ejecutable es el reproductor de referencia del SDK. Usa `MaterialApp` y el
`Navigator` estándar de Flutter para abrir el catálogo, la biblioteca y las
experiencias, conservar los resultados de las rutas y regresar a Home.
El SDK mínimo no requiere SINT ni los servicios de Open Neom.

Cada escena portátil y el lobby se montan en un `VrSessionHost` de `vrlizate`.
El host crea y cierra un controlador por sesión. Cambiar de ruta, minimizar la
aplicación o desactivar sus tickers suspende la sesión; al regresar se reanuda.
El visor conserva la propiedad de sus recursos GPU. Este adaptador para widgets
requiere renderizado que respete `TickerMode`; los motores nativos necesitan
callbacks explícitos para su bucle de renderizado.

Home continúa presentando datos y callbacks; Apps descubre y valida los paquetes.
Las pruebas de navegación usan un renderer sustituible para comprobar sesiones
sin inicializar GPU; el renderizado nativo se comprueba por separado.

## Dependencias portables

`pubspec_overrides.yaml` del SDK enlaza los módulos y los forks de soporte dentro
de la distribución. Conserva ese archivo al usar la plantilla. No necesita
`VRlizate_app`, `wordsphere_plugin` vecino ni overrides personales. Los overrides
de una dependencia no se heredan por otro host: un host propio debe incorporar
las entradas correspondientes de este archivo. No copia cachés ni credenciales.

Android SDK, JDK y Flutter se instalan por sus mecanismos habituales. El APK de
esta plantilla usa firma de depuración para validación local. No contiene una
clave de firma de publicación. Esta validación de compilación no certifica BLE,
sensado o una instalación iOS; el host mínimo no inicializa esos servicios.
