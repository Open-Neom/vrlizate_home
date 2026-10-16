# Habitaciones del ecosistema

`VrHomeEcosystemRoom` describe una sala mediante identificador, título,
descripción, acento, icono semántico y propósito. `defaults` contiene Perfil,
Muro social, Estudio creador, EMXI, Gigmeout y Cyberneom. No incorpora cuentas,
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

`HomeEcosystemLayout` genera un pasillo y dos habitaciones por fila. Comparte
suelo, paredes y muebles con `HomeWalkSpace`; las puertas tienen 2.4 m de ancho
y 3 m de altura libre. Se llega caminando desde el lobby, se rodea la exhibición
de la galería y se atraviesa su puerta posterior. Cada sala tiene mobiliario,
acento, señalética sobre la puerta y terminal seleccionable mediante mirada,
toque o mando. La biblioteca y las experiencias existentes permanecen en Home.

El ala se agrega al mismo `Scene`. Al abrir una sala, Home suspende sus entradas
y desmonta su `StereoSceneView` antes de llamar al host; al regresar conserva
pose y mundo. No se mantienen dos superficies GPU activas por este lanzamiento.
El host decide si presenta contenido local, solicita acceso o conecta servicios.
Las salas no implican que esos servicios externos estén implementados o activos.

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
