# Assets del piloto de Home

Procedencia verificada el 15 de octubre de 2026. Este directorio contiene dos
archivos glTF 2.0 binarios, sin enlaces a texturas o buffers externos.

## RobotExpressive

`robot_expressive.glb` es una copia **sin modificaciones** del modelo de
Tomás Laulhé (Quaternius), con las modificaciones de Don McCurdy que distribuye
el proyecto Three.js. Su licencia es **CC0 1.0 Universal**. Conservamos estos
créditos por trazabilidad; no implican respaldo de sus autores a VRlizate.

- Fuente primaria de autoría y licencia:
  <https://github.com/mrdoob/three.js/blob/r186/examples/models/gltf/RobotExpressive/README.md>
- Archivo oficial de referencia:
  <https://github.com/mrdoob/three.js/blob/r186/examples/models/gltf/RobotExpressive/RobotExpressive.glb>
- Licencia: <https://creativecommons.org/publicdomain/zero/1.0/>
- Autor: <https://www.patreon.com/quaternius>
- Modificaciones upstream: <https://donmccurdy.com/>
- Copia local de origen:
  `codebase_vr/three_js/examples/assets/models/gltf/RobotExpressive/RobotExpressive.glb`.
- Tamaño: **463.988 bytes**. La comparación con el archivo oficial r186 dio
  igualdad byte por byte, sin modificar clips, huesos, materiales ni morphs.
- SHA-256:
  `047f5e5fb3bb6d378bd1df16ca6137f2a596c99b3a1b5690b4020c05aaf6f319`.

Contiene 14 clips: `Dance`, `Death`, `Idle`, `Jump`, `No`, `Punch`, `Running`,
`Sitting`, `Standing`, `ThumbsUp`, `Walking`, `WalkJump`, `Wave`, `Yes`.
Hay 43 joints distintos, referenciados por dos skins; el mesh `Head` contiene
los morph targets `Angry`, `Surprised`, `Sad` en sus tres primitivas.

`robot_expressive.metadata.json` contiene duraciones, conteos y bounds calculados
con las transformaciones de nodos y el skinning del archivo. La pose inicial
del clip `Idle` mide aproximadamente 4,496814 unidades de altura: una escala
uniforme de **0,411402412** produce 1,85 m. Para apoyar esa pose sobre una
plataforma situada en Y=0,32 m, la traslación Y es **0,328353288**. Mantener esa
escala durante las animaciones; no normalizar el tamaño cada frame. Los bounds
de inicio de clip no cubren todos los movimientos posteriores.

## Lounge original de VRlizate

`lounge.glb` y su generador son trabajo original para este paquete y se
distribuyen bajo su licencia **Apache-2.0**, disponible en `../../LICENSE`.
No contienen geometría, texturas o diseños descargados de terceros.

Generación reproducible con Python 3 y su biblioteca estándar, desde la raíz
del paquete:

```sh
python3 tool/generate_showcase_lounge.py
```

El generador también escribe `lounge.metadata.json` con hash, tamaños, conteos
y bounds por objeto. No necesita Blender, NumPy, imágenes, red ni un renderer.

- Unidades: metros; +Y arriba; el sillón mira hacia +Z.
- Origen: centro horizontal de los bounds del conjunto, a nivel del suelo.
- Bounds del conjunto: min **(-1,488857; 0; -0,652960)**,
  max **(1,488857; 1,784475; 0,652960)**.
- Ocupa **2,977714 × 1,305920 m** en planta; altura **1,784475 m**.
- Centro del sillón proyectado al suelo: **(-0,228857; 0; 0,182960)**.
- Tres nodos y meshes identificables: `LoungeChair`, `SideTable`,
  `PlanterAndPlant`. Sus coordenadas están horneadas respecto al mismo origen.
- Sillón tapizado verde petróleo, ribete suave, patas delgadas de latón
  envejecido y apoyos grafito; mesa de caliza cálida y latón; maceta de cerámica
  marfil con tierra, tres tallos, pecíolos y quince hojas volumétricas.
- Materiales metallic-roughness PBR estándar: 12 materiales en 13 primitivas,
  sin extensiones glTF, texturas, transparencias, skins o animaciones.
- **586.688 bytes**, 11.159 vértices y 18.060 triángulos. Las hojas tienen
  espesor geométrico; no dependen de `doubleSided` ni de recortes de alfa.
- SHA-256:
  `6e96f2ee5973bc3d57a14d1284847d30d36cdba820a0f8f50af555e7f2c48674`.

Se comprobaron índices, posiciones finitas, normales unitarias y reproducibilidad
binaria. La inspección visual inicial usa una proyección de diagnóstico del GLB;
la iluminación, importación y coste real en Scene/Thermion se verifican durante
la integración. El asset no incorpora colisiones ni navegación.
