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
