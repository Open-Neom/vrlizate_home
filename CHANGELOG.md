## 1.0.0 - 2026-10-20

- Promover `vrlizate_home` a la versión estable `1.0.0` bajo la estructura modular Open Neom (`lib/utils/constants/`, `lib/utils/enums/`, `lib/domain/models/`, `lib/ui/`).
- Desactivar el enfoque central con clic automático por tiempo (`showReticle: false`, `onGazeSelect: null`) inmediatamente al detectar un smartphone Joystick o gamepad conectado, permitiendo observar letreros y tarjetas libremente sin entrar por accidente y seleccionando explícitamente con el botón `A`.
- Habilitar giro horizontal (`horizontalLook: true`) en el stick derecho del smartphone Joystick dentro de `VirtualHomeScene`.
- **Expansión dinámica del Mall 3D con mundos `.vrlw` (`VrHomeEcosystemRoom.expandWithWorldCatalog`, `VrHomeRoomPurpose.portableWorld`, `VrHomeRoomIcon.world`):** cada paquete `.vrlw` del catálogo añade automáticamente su propio local ("storefront") en la Plaza de Experiencias con arco de portal 3D (`world_compass_stage`, `world_portal_pillar`, `world_portal_orb`), letrero y terminal interactiva para entrar directamente al mundo `.vrlw`.
- **Menú Principal y Panel de Opciones VR 3D invocables desde cualquier lugar con el Joystick:**
  - Botón `L` (`btnL`, `stickClick`, o `L1`/`R1`/`Start`/`Select` en gamepad físico) invoca u oculta la Biblioteca Principal 3D (`_summonOrToggleMainMenu`) justo frente a la posición y mirada actual del usuario sin tener que regresar a la entrada (`z = 0`).
  - Botones `X` / `Y` traen automáticamente el Menú Principal frente al usuario si se encuentra recorriendo el Mall y cambian de categoría.
  - Botón `R` (`btnR`) o acción `'options'` del dock abre el modal 3D `createVrHomeOptionsPanel` frente al usuario para cambiar Ambiente (`Look`), Calidad/Resolución, Recentrar vista, Sensores 3D, Compartir vista (Cast), Mando QR, Calibrar lentes o saltar a Plaza Mall.
- Añadir `VrHomeLoadingSplashOverlay` y soporte para galería `VrHomeRoomPurpose.openSourceGames`.
- Añadir `VrHomeConstants` y `VrHomeTranslationConstants`, extrayendo todos los textos e identificadores de interfaz.
- Añadir `VrHomeZoneKind`, `VrHomeRoomBlueprint` y `VrHomeMallBlueprint` para configuración declarativa y validada de salas y plazas espaciales.

## 0.1.0

- Giro progresivo al mantener el joystick izquierdo en el borde: pasos iniciales
  hacia atrás, elección de sentido según el recorrido del pulgar y parada al
  alcanzar el rumbo. Conserva colisiones, aceleración y mirada independiente;
  WASD sigue siendo desplazamiento. Pausa, desconexión y watchdog cancelan el
  destino y exigen soltar antes de continuar.

- Salas del ecosistema con propuestas y acciones dentro de la escena estéreo;
  mirada, láser y mando; invalidación de contenido al cambiar la sesión.
- Contratos neutrales de presentación/acciones, cierre y cambios del anfitrión;
  no se transfieren al Home tokens, URLs firmadas ni servicios de negocio.
- Inicio opcional en modo visor y acceso espacial al pasillo de salas.

- Entrada y catálogo extraídos de VRLizate App, con tres temas y callbacks del host.
- Lobby espacial con catálogo inyectado y servicios prestados.
- Biblioteca de paquetes como UI pura: metadatos, avisos, disponibilidad y acciones
  suministradas por el anfitrión; protección frente a aperturas simultáneas.
- Formato .vrlz, descubrimiento local/web, transporte y visor trasladados al
  paquete hermano vrlizate_apps. Home no depende de Apps ni realiza estas
  operaciones.
- Ejemplo independiente que integra ambos paquetes, conserva temas y Home 3D,
  importa desde HTTPS o consulta índices JSON, y añade ejemplos solo por acción
  explícita.
- Pruebas de presentación, callbacks, estados y adaptación a escala de texto 200%.
