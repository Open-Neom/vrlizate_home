# Validación de separación Home / Apps · 4 de octubre de 2026

Entorno: macOS Apple Silicon, Flutter 3.49.0-0.2.pre / a6d9dcd729,
Dart 3.14.0-147.0.dev. Validación local; no despliegue ni publicación.

| Comprobación | Resultado |
| --- | --- |
| Apps: formato/ZIP/GLB, HTTPS, índice web, directorio, controller, launcher y generador de índice | 176 pruebas pasan |
| Home: presentación, temas, inventario y biblioteca | 32 pasan; captura opt-in omitida |
| App: descriptores, dispatch, ownership, entrada, pairing, biblioteca y controles del Home | 74 pruebas distintas pasan en ejecuciones dirigidas; 2 capturas opt-in omitidas |
| Ejemplo: entrada, lectura con ventana inactive e instalación explícita/idempotente | 3 pasan |
| Análisis Apps, Home, ejemplo y archivos App modificados en esta fase | Sin incidencias |
| CLI de índice sobre los assets reales | 31 entradas; ID y SHA-256 coinciden con sus archivos |
| Compilación final del ejemplo macOS profile | Correcta; 43.1 MB |

Las últimas regresiones verifican imports simultáneos desde isolates reales,
marcadores residuales, lecturas parciales, respuestas tardías, volver atrás durante
la transición de una ruta y comunicación visible de conflictos de importación.
Los tests de Home incluyen vertical/horizontal a texto al 200% y comprueban que
montar/reanudar la UI no inicia acciones del host.

## Inspección nativa

La app independiente se abrió mediante la herramienta de UI. Se observó la
entrada Aurora, la biblioteca con ruta absoluta, las tarjetas «Demo integrada» y
«Escena portátil», y la escena GLB renderizada realmente por Flutter Scene.
Se abrió el archivo local, se volvió a la biblioteca y se abrió la misma galería
por el descriptor builtin del ejemplo. Ambas vías funcionaron.

La revisión detectó y corrigió dos problemas: una ventana macOS visible pero
inactive posponía la primera lectura, y el SelectableText de la ruta provocaba
una excepción de accesibilidad en el motor Flutter de este entorno. La ruta
ahora usa texto normal con botón de copia; la compilación final completó el
recorrido sin esa excepción. No se modificó ni deshabilitó accesibilidad global.

## Alcance

Las descargas/catálogos se verificaron con transporte inyectado y hashes reales;
no se publicaron archivos ni se probó un hosting externo. La app completa con
Firebase no se recompiló en esta fase. Las pruebas del host usan factories
simuladas para los juegos: no afirman haber recorrido los 30 demos en hardware.
El ejemplo nativo sí renderizó la escena incluida.

No hay nuevos benchmarks, validación Android/iOS física ni compilación web del
host completo. El formato v2 referencia juegos compilados; no descarga nuevo
código Dart. Home y Apps siguen siendo repositorios locales sin publicación.
Los cuatro módulos VR anteriores conservan sus árboles de trabajo limpios.

El informe [del 3 de octubre](validation.md) corresponde al prototipo previo a
esta extracción; sus APIs de paquetes ahora pertenecen a `vrlizate_apps`.
