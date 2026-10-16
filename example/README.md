# Ejemplo independiente de vrlizate_home

Combina la interfaz de `vrlizate_home` con el controlador, descubrimiento y visor
de `vrlizate_apps`. Ejecuta entrada, temas, catálogo, lobby espacial y biblioteca
`.vrlz` sin importar `VRlizate_app`, sus demos, Firebase ni sus servicios.
Requiere Flutter 3.47 o posterior y `vrlizate ^1.13.0` para sus APIs de sesión.

```sh
flutter pub get
FLUTTER_DART_DATA_ASSETS=false flutter run --profile -d macos
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
