# vrlizate_home

Entrada, catálogo, biblioteca de paquetes y lobby espacial de VRLizate.
**Home presenta datos y acciones del anfitrión; no detecta archivos o catálogos
web, descarga paquetes, valida .vrlz ni decide qué runtime ejecutar.**

**vrlizate_apps** es el paquete hermano que administra formato, transporte,
descubrimiento local/web y estado de la biblioteca. La aplicación anfitriona
combina ambos paquetes y conserva sus experiencias, servicios y navegación.

## Superficies públicas

- **vrlizate_home.dart**: entrada, catálogo con búsqueda/filtros, biblioteca de
  paquetes y temas Aurora, Día y Medianoche. Widgets 2D sin inicializar GPU.
- **vrlizate_home_catalog.dart**: modelos de inventario y categorías sin GPU.
- **vrlizate_home_spatial.dart**: lobby 3D, biblioteca espacial, locomoción,
  colisión, puntero y contratos de integración con servicios del anfitrión.

Las APIs de paquetes y visores se importan desde vrlizate_apps. Home no contiene
implementaciones de formatos, HTTP, directorios, catálogo web o visor de paquetes;
tampoco depende de Apps. El ejecutable example/ sí depende de ambos.

~~~mermaid
flowchart LR
  Host[Aplicación anfitriona] -->|metadatos, estado y callbacks| Home[Home UI]
  Home -->|acción del usuario| Host
  Host -->|consulta e importa| Apps[vrlizate_apps]
  Apps -->|datos validados| Host
  Host -->|abre y espera retorno| Experience[Escena o experiencia integrada]
  Host -->|bindings y servicios prestados| Lobby[Home espacial]
~~~

## Habitaciones espaciales

`VrHomeSpatialBindings.ecosystemRooms` aporta el inventario. Los terminales
presentan `VrHomeRoomPresentation` mediante `onRoomAction(room, actionId)` dentro
de la misma escena estereoscópica. La acción null pide la presentación inicial;
los IDs siguientes pertenecen a acciones visibles y habilitadas. El anfitrión
conserva servicios y autorización. `roomChanges` señala invalidaciones externas
(de cuenta o permisos), no el progreso de cada petición; `onRoomClosed` detiene
trabajo/reproducción al cerrar, suspender o reemplazar la sala.

Los paneles quedan fijos en el mundo y aceptan mirada, láser, A y B. Cerrar no
cambia la posición. Los resultados tardíos se descartan; el Home no convierte
widgets Flutter ni visores nativos en texturas VR automáticamente.

Durante el recorrido, B significa **Detener**: cancela el salto y cualquier
apertura pendiente al llegar, conservando posición y orientación. Para volver
a caminar hay que soltar el stick primero. Con una ficha o el asistente abierto,
B cambia a **Cerrar**; ningún caso devuelve al usuario al origen de la plaza.
El mando remoto, el gamepad Bluetooth y sus equivalentes de teclado comparten
esta acción; las etiquetas del mando se actualizan al abrir o cerrar un panel.

El inventario predeterminado ocupa una plaza cubierta con ocho locales: galería
personal, lounge social, taller creador, librería EMXI, escucha Gigmeout, jardín
Cyberneom, Cine VR y Mi avatar. Las fachadas tienen marquesinas, categorías y escaparates
abiertos sobre antepechos sólidos; el paseo mantiene paso libre entre jardineras.
El anfitrión decide qué experiencia abre Cine VR, igual que las otras salas.

`HomeEcosystemLayout` comparte paredes y mobiliario con la colisión.
`HomeArchitectureBatch` agrupa la geometría por sala y acabado, conserva colores
por vértice y deja los terminales interactivos separados. La arquitectura incluye
formas curvas y biseladas, UV en metros y acabados compartidos de 256 px; el
detalle y las sombras dependen de la calidad. Los presupuestos geométricos se
comprueban en `test/home_architecture_batch_test.dart`, separados del texto,
terminales y modelos importados; no representan mediciones de FPS.

## Mi avatar: apariencia, escenario y recursos

`VrHomeSpatialBindings.avatarAppearance` recibe un
`ValueListenable<VrAvatarAppearance?>` propiedad del anfitrión. Home escucha
cambios semánticos, actualiza el escenario con `setAppearance(...)` y retira su
suscripción al cambiar bindings o disponer la vista. El anfitrión conserva el
perfil, su persistencia, la cuenta autenticada y las reglas de autorización;
estos datos privados no se transfieren al renderer. El editor puede actualizar
el valor al cambiar la apariencia, sin notificar cada frame de animación.
Un valor `null` recupera el piloto neutral, por ejemplo al cambiar de identidad.

La apariencia usa `VrAvatarSpecies`: humano (`human`), robot, orbe (`orb`),
zorro (`fox`), ajolote (`axolotl`) y brote (`sprout`). Permite dos colores opacos,
altura virtual de 1–2.2 m, escala de cabeza de 0.8–1.25, escala de rasgos de
0.6–1.4 y patrón liso, manchas o rayas. `VrAvatarNode`, de `vrlizate_scene`,
construye siluetas redondeadas con orejas/cola, branquias o follaje según la
especie. La altura es una personalización virtual, no calibración del cuerpo.

El escenario coloca los pies del avatar sobre la plataforma. Sus primitivas
usan +Y hacia arriba y +Z hacia el frente; la orientación del escenario se
resuelve sin aplicar el cambio de coordenadas del importador GLB. El renderer
comparte hasta seis geometrías inmutables entre avatares, y cada avatar posee
cuatro materiales PBR compartidos por sus piezas. Las piezas se agrupan por
forma/material con instancing. Editar colores o proporciones conserva esas
geometrías; las proporciones solo cambian matrices. Su reposo es un giro suave:
el avatar procedural todavía no tiene esqueleto, caminata ni saludo articulado.

**Piloto GLB neutral.** `HomeShowcase` también incorpora RobotExpressive (CC0)
y un conjunto original de sillón, mesa y planta (Apache-2.0). Cuando no hay una
apariencia elegida, `VrActorAnimation` mezcla los clips reales de reposo,
caminata en el sitio y saludo del robot. Al seleccionar un avatar personalizado
se pausa y desmonta el robot del escenario; no se le atribuyen esos clips al
avatar procedural. La colisión reserva escenario y mobiliario sin bloquear
el terminal ni cambiar la autorización del anfitrión.

La cercanía al escenario tiene dos niveles de histéresis:

| Transición | Distancia al centro del escenario |
|---|---|
| Activar y montar el subárbol | Menos de 18 m |
| Desactivar, pausar y desmontarlo | A partir de 22 m |
| Pasar el avatar procedural a detalle cercano | Menos de 8 m |
| Volver a detalle lejano | A partir de 12 m |

Entre umbrales se conserva el estado anterior. Lejos se eliminan pequeños
brillos, patrones y detalles de branquias, conservando los rasgos de la especie.
Desmontar separa realmente el subárbol de Scene: sus modelos y luces dejan de
participar en el recorrido/render de la escena. El objeto `HomeShowcase`
conserva referencias para reanudar al volver; no equivale a liberar toda su
memoria. Su callback de tick retorna mientras está inactivo.

Los GLB se reutilizan con `VrGlbTemplateCache(maxEntries: 2)`. Cada instancia
tiene nodos, skin, morph weights y reproducción independientes; geometría,
texturas, materiales y curvas de animación se comparten como recursos
**inmutables**. Para personalizar un material importado hay que reemplazar sus
slots por materiales propios, sin mutar la plantilla compartida. La caché
cuenta plantillas, incluidas cargas pendientes, no bytes ni clones activos.
`VirtualHomeView.didHaveMemoryPressure` llama a
`HomeShowcase.clearAssetCache()`: vacía las referencias retenidas y las próximas
instancias podrán importar los assets de nuevo. Los clones existentes siguen
siendo válidos y conservan sus recursos mientras tengan referencias.

`VirtualHomeWorldBuilder.showcaseReady` permite esperar las cargas;
`showcases[].loadErrors` distingue errores del fallback visual. Los hosts propios
deben llamar `observe(eye)` o pasar `eyePosition` a `tick/update`; `VirtualHomeView`
ya lo hace. El probe `example/lib/spatial_visual_probe.dart` captura la sala y
poses reproducibles en calidad media/alta. Los modelos son assets empaquetados;
no amplían el perfil estático de `.vrlw`. Procedencia, hashes y generador en
[assets/showcase/NOTICE.md](assets/showcase/NOTICE.md).

Estos cambios no habilitan multijugador ni sincronización remota de avatares.
Los presupuestos y pruebas de geometría no demuestran una mejora de FPS; el
rendimiento debe medirse en la escena y el dispositivo objetivo.

## Temas, catálogo y biblioteca

~~~dart
VrHomeLanding(
  theme: VrHomeThemeData.aurora,
  onThemeChanged: selectTheme,
  onExplore: null, // La app oficial elige experiencias dentro del visor.
  onViewer: openSpatialHome,
  onController: openController,
)
~~~

VrHomeThemeData permite definir una paleta sin modificar la app. El anfitrión
decide si persiste la selección. VrHomeCatalog recibe una lista de
VrHomeCatalogItem y onLaunch; no conoce implementaciones ni rutas de juegos.
El callback espera al retorno de la experiencia y la interfaz evita aperturas
duplicadas.

VrHomePackageLibrary recibe una lista de VrHomePackageItem, ubicación,
avisos, errores, estado de carga y callbacks. Presenta etiquetas como «Escena
portátil» y «Demo integrada» sin interpretar el formato ni inspeccionar el
sistema. Cada elemento puede incluir una razón visible de indisponibilidad.

~~~dart
VrHomePackageLibrary(
  items: packageCards,
  location: sourceLabel,
  issues: notices,
  busy: operationInProgress,
  error: operationError,
  onLaunch: launchKnownPackage,
  onRefresh: refreshSource,
  onImport: showImportDialog,
  onInstallExamples: installExamplesExplicitly,
  onUseLocal: returnToLocalFolder,
  onCopyLocation: copySourceLabel,
)
~~~

Montar o reanudar este widget no inicia operaciones. El anfitrión llama al
controlador de Apps en los momentos adecuados y resuelve la selección contra sus
runtimes permitidos. Si un escaneo está incompleto, el host debe marcar las
entradas como indisponibles. La UI no puede deducirlo a partir del texto de un
aviso.

## Ejemplo de anfitrión

example/lib/main.dart combina Home, VrlzLibraryController de Apps y el visor
opcional VrlzSceneViewer. Mantiene los tres temas y el lobby 3D. Su biblioteca
usa la carpeta de documentos de la aplicación:

~~~text
VRlizate-example/experiencias/
~~~

El ejemplo muestra la ubicación real y permite copiarla. Actualiza al entrar,
reanudar la aplicación y regresar de una experiencia. «Añadir ejemplos» instala
explícitamente una escena portable desde assets/stereo_gallery.vrlz y un
descriptor gallery que abre la galería ya incluida en el ejecutable. No instala
paquetes automáticamente al iniciar.

«Añadir desde HTTPS» permite importar un paquete .vrlz en esa carpeta o
consultar un índice JSON mediante Apps. La importación no ejecuta el contenido.
Desde un índice se puede volver a la carpeta local. Los paquetes se validan de
nuevo antes de abrirse; los runtimes integrados distintos de gallery no están
incluidos en este anfitrión de ejemplo.

El visor y los controles son capacidades compiladas del host. Un descriptor
integrado no contiene un juego portable ni añade código Dart o plugins a la app.
Los límites y contratos del formato pertenecen a la documentación de
[vrlizate_apps](../vrlizate_apps/README.md).

## Desarrollo independiente

Este paquete es un repositorio local separado y todavía no está publicado en
pub.dev. Las rutas de pubspec_overrides.yaml describen el workspace con sus
paquetes hermanos.

~~~sh
flutter pub get
FLUTTER_DART_DATA_ASSETS=false flutter test
cd example
flutter pub get
FLUTTER_DART_DATA_ASSETS=false flutter run --profile -d macos
~~~

Ejecute los builds de este workspace secuencialmente si comparten la caché de
shaders de Flutter Scene. El ejemplo usa el código fuente de Home y Apps por
dependencias path; no mantiene copias de sus implementaciones. Android declara
Flutter GPU e INTERNET; macOS declara Flutter GPU y cliente de red. La
disponibilidad gráfica debe verificarse en el dispositivo objetivo.

## Propiedad y ciclo de vida

- Home posee su presentación y navegación interna del lobby. Suspende su
  superficie cuando el anfitrión abre una experiencia y recupera la interacción
  al volver.
- Apps posee la validación, descubrimiento y transporte de paquetes. Su
  controlador no construye widgets ni ejecuta experiencias.
- El anfitrión conserva rutas, permisos, persistencia, conexiones de mando,
  registro de runtimes y la coordinación de su ciclo de vida.
- Los servicios prestados al lobby siguen perteneciendo al anfitrión. Home
  cancela sus suscripciones y libera sus objetos sin disponer conexiones ajenas.
- Los identificadores son estables; títulos, colores y rutas de archivo no
  seleccionan clases ejecutables.

Las fachadas de VRlizate_app/lib/virtual_home mantienen compatibilidad con la
presentación extraída. Los resultados y límites de comprobaciones locales
anteriores están en [doc/validation.md](doc/validation.md); no equivalen a una
certificación de todos los dispositivos o runtimes.

Validación de la extracción y recorrido nativo: [informe del 4 de octubre](doc/validation_2026-10-04.md).

El recorrido con stick tiene aceleración progresiva: 1.6 → 4.8 m/s en 2.4 s
al mantener una inclinación de al menos 0.7. Las inclinaciones pequeñas permiten
ajustes lentos. Soltar el stick, cambiar bruscamente de dirección, detenerse
con B, abrir un panel o quedar bloqueado contra una pared reinicia la velocidad.
Las colisiones y la altura de los ojos se conservan durante el desplazamiento.
