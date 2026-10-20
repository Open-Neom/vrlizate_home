# Habitaciones del ecosistema

`VrHomeEcosystemRoom` describe una sala mediante identificador, título,
descripción, acento, icono semántico y propósito. `defaults` contiene Perfil,
Muro social, Estudio creador, EMXI, Gigmeout, Cyberneom, Cine VR y Mi avatar. No incorpora cuentas,
Firebase, SINT, reproducción, publicación ni servicios Open Neom.

`VrHomeEcosystemLobby` presenta las salas sin GPU ni visor. `onOpenRoom` pertenece
al host y completa cuando termina su navegación. Mientras espera evita aperturas
duplicadas; el host puede aportar `unavailableReasons`, `onBack` y
`onExperiences`. `VrHomeLanding.onEcosystem` añade opcionalmente la entrada
«Entrar a mi casa» y respeta el estado `busy`.

## Espacio físico

`VrHomeSpatialBindings.ecosystemRooms` habilita un ala detrás de la galería
existente. `onOpenRoom(context, room)` conecta cada terminal con las funciones
del host. Sin salas se conserva exactamente el plano anterior.

`HomeEcosystemLayout` genera una plaza de 24 m de ancho y dos habitaciones por fila. Comparte
suelo, paredes y muebles con `HomeWalkSpace`; las puertas tienen 3.2 m de ancho
y 3 m de altura libre. Se llega caminando desde el lobby, se rodea la exhibición
de la galería y se atraviesa su puerta posterior. Cada sala tiene mobiliario,
acento, señalética sobre la puerta y terminal seleccionable mediante mirada,
toque o mando. La biblioteca y las experiencias existentes permanecen en Home.

El ala se agrega al mismo `Scene`. Al abrir una sala, Home suspende sus entradas
y desmonta su `StereoSceneView` antes de llamar al host; al regresar conserva
pose y mundo. No se mantienen dos superficies GPU activas por este lanzamiento.
El host decide si presenta contenido local, solicita acceso o conecta servicios.
Las salas no implican que esos servicios externos estén implementados o activos.

## Galería opcional de juegos abiertos

El host puede añadir `VrHomeEcosystemRoom.openSourceGames` a su inventario:

```dart
ecosystemRooms: const [
  ...VrHomeEcosystemRoom.defaults,
  VrHomeEcosystemRoom.openSourceGames,
],
```

La sala tiene el ID estable `open_source_games`, el propósito `openSourceGames`
y el icono `gamepad`. Sigue siendo opt-in: no altera los ocho defaults ni la
posición de sus puertas. Usa identidad púrpura y turquesa, escenario, pantalla
de exhibición, escultura curva de un mando y tres gabinetes de arcade. La
aproximación central, las salidas y el espacio para el panel del host permanecen
libres. Toda la decoración entra en los batches estáticos por sala/material;
no añade reproducción ni actualizaciones por cuadro.

El propósito también se puede reutilizar para salas con otro ID/título: por
ejemplo, una galería separada con una habitación por juego. Se comprueban 23
habitaciones con inventario impar, puertas en ambos lados, recorridos hasta
sus terminales, tres rutas longitudinales y ausencia de una puerta fantasma al
final. La geometría de la decoración permanece dentro de cada habitación y el
presupuesto se limita a menos de 3.000 triángulos y seis batches por sala.

Catálogo, estado de integración, licencias, enlace al directorio/repositorio del
creador y lanzamiento pertenecen al presenter del host. Una sala o gabinete no
demuestra que el juego original esté portado. El SDK no instala runtimes ni
ejecuta código Dart descargado por el mero hecho de mostrar este propósito.

Las pruebas comprueban todos los recorridos con el mismo motor de colisiones,
el rechazo de paredes y jambas, la preservación del plano original y las acciones
2D a texto ampliado. El aspecto GPU y rendimiento en teléfono requieren su
verificación nativa correspondiente.

Validación local: análisis Dart limpio y 43 pruebas funcionales de Home
aprobadas en dos lotes, incluidas seis nuevas de interfaz y cinco de geometría.
Las pruebas de geometría se ejecutaron con concurrencia 1. Además pasó la
prueba opcional de capturas (`vr_home_preview_test.dart`), con la interfaz real
a 390 × 844 píxeles y callbacks de navegación simulados.

Se inspeccionaron las capturas de [entrada desde Home](previews/ecosystem/landing_ecosystem.png),
[perfil, muro y estudio](previews/ecosystem/ecosystem_entrance.png) y
[EMXI, Gigmeout y Cyberneom](previews/ecosystem/ecosystem_cyberneom.png).
Los textos y acciones son legibles, sin desbordamientos; el desplazamiento
permite alcanzar las seis habitaciones. Estas capturas validan la interfaz 2D,
no el renderizado de las habitaciones 3D ni el rendimiento de un teléfono.
