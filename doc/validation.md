# Verificación local · 3 de octubre de 2026

Informe histórico anterior a la extracción de `vrlizate_apps`. Ver la
[validación actualizada del 4 de octubre](validation_2026-10-04.md).

Entorno: macOS Apple Silicon, Flutter 3.49.0-0.2.pre / a6d9dcd729,
Dart 3.14.0-147.0.dev. Comandos Flutter ejecutados en serie con
`FLUTTER_DART_DATA_ASSETS=false`.

| Comprobación | Resultado |
| --- | --- |
| Package: modelos, UI, bundles, HTTPS y launcher | 90 pruebas pasan; captura opt-in omitida en la ejecución normal |
| App: entrada, pairing y retorno al Home | 29 pasan; una captura opt-in omitida |
| App: biblioteca, temas, HUD, colisiones, locomoción, Itzli y cuartos | 90 pasan; una captura opt-in omitida |
| Ejemplo independiente: inicio ligero | 1 pasa |
| Captura opt-in de los widgets 2D | Pasa; seis PNG inspeccionados |
| Dart analyze: package, tool, tests y example/lib | Sin incidencias |
| Dart analyze: adapter, entrada, catálogo y tests de integración modificados | Sin incidencias |
| Ejemplo macOS profile, fuentes finales | Compila; app de 42.4 MB |

La suite de UI prueba 360×740 y 740×360, también con texto al 200%, selección de
tema, búsqueda/categorías, callbacks, errores y prevención de aperturas repetidas.
Las pruebas de transporte usan clientes inyectados: incluyen HTTPS, redirecciones,
límites reales, timeout y cancelación. No sustituyen una prueba contra un hosting
externo. Las de formato incluyen ZIP/GLB malformados, integridad e inmutabilidad.

El ejemplo real `example/assets/stereo_gallery.vrz` fue empaquetado y validado
con la CLI: 27 551 bytes; SHA-256 del contenedor:
`00ac4aa0344569df960e21b73502b587218b02b996faf8107dfebf34570b8488`.
La app incluye una copia idéntica.

## Evidencia visual

Las imágenes en `previews/` son capturas de los widgets reales a 390×844 con
callbacks de demostración. El catálogo usa metadatos de ejemplo. El test carga
Roboto e iconos del SDK para evitar la fuente Ahem de pruebas; no modifica las
fuentes del producto. No son capturas del visor 3D ni de un smartphone físico.

- [Aurora](previews/landing_aurora.png)
- [Día](previews/landing_daylight.png)
- [Medianoche](previews/landing_midnight.png)
- [Catálogo](previews/catalog_aurora.png)
- [Tarjetas de los dos cuartos](previews/catalog_aurora_rooms.png)

Para regenerarlas desde la raíz del paquete:

```sh
FLUTTER_DART_DATA_ASSETS=false flutter test test/vr_home_preview_test.dart \
  --dart-define=VR_HOME_PREVIEW_DIR=/ruta/absoluta/previews
```

## Límites de esta verificación

La inspección manual del ejemplo nativo quedó pendiente: la herramienta de UI
detectó el Mac bloqueado y solicitó desbloqueo. No se afirma haber comprobado
visualmente el lobby 3D o renderizado el archivo VRZ en GPU durante esta tarea.
La compilación nativa independiente sí terminó correctamente.

No se compiló la app completa con Firebase en esta fase ni se probó Android/iOS
en un teléfono real. No hay nuevas mediciones de FPS, memoria, temperatura o
consumo. Tampoco se desplegó hosting, publicó paquete o configuró un remoto Git.
