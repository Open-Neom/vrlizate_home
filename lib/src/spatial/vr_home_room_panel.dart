import 'package:flutter/material.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../ecosystem/vr_home_ecosystem_room.dart';
import '../ecosystem/vr_home_room_presentation.dart';
import '../ecosystem/vr_home_room_content.dart';

/// Bounded, world-space room UI. It never opens a Flutter route or owns content.
/// Text/mesh builders provide the same CPU test seam as the shared 3D widgets.
Future<VrWorldActionPanel3D> createVrHomeRoomPanel({
  required VrHomeEcosystemRoom room,
  required VrWorldPose pose,
  required VrHomeRoomPresentation? presentation,
  required bool busy,
  required String? error,
  required void Function(String) onAction,
  required VoidCallback onRetry,
  required VoidCallback onClose,
  required void Function(int) onPage,
  int pageIndex = 0,
  VrHomeRoomContent? content,
  VrControlMeshBuilder? meshBuilder,
  VrWorldTextNodeBuilder? textNodeBuilder,
}) {
  const pageSize = 4;
  final available = !busy && error == null
      ? presentation?.actions ?? const <VrHomeRoomAction>[]
      : const <VrHomeRoomAction>[];
  final pages = (available.length / pageSize).ceil().clamp(1, 1000000);
  final page = pageIndex.clamp(0, pages - 1);
  final actions = <VrWorldAction>[
    for (final action in available.skip(page * pageSize).take(pageSize))
      VrWorldAction(
        id: 'content:${action.id}',
        label: action.label,
        enabled: action.enabled,
        onPressed: () => onAction(action.id),
      ),
    if (pages > 1) ...[
      VrWorldAction(
        id: 'previous',
        label: 'Anterior',
        enabled: page > 0,
        onPressed: () => onPage(page - 1),
      ),
      VrWorldAction(
        id: 'next',
        label: 'Siguiente',
        enabled: page + 1 < pages,
        onPressed: () => onPage(page + 1),
      ),
    ],
    if (error != null)
      VrWorldAction(id: 'retry', label: 'Reintentar', onPressed: onRetry),
    VrWorldAction(id: 'close', label: 'Cerrar · B', onPressed: onClose),
  ];
  return VrWorldActionPanel3D.create(
    name: 'home_room_${room.id}',
    pose: pose,
    title: busy || error != null
        ? room.title
        : presentation?.title ?? room.title,
    subtitle: busy
        ? 'Cargando…'
        : error != null
        ? 'Contenido no disponible'
        : pages > 1
        ? '${presentation?.subtitle ?? ''} · ${page + 1}/$pages'
        : presentation?.subtitle ?? 'TU CASA EN VRLIZATE',
    description:
        error ??
        (busy
            ? 'Preparando el contenido de esta sala.'
            : presentation?.description ?? room.description),
    accentColor: Color(room.accent),
    width: 1.78,
    columns: actions.length > 1 ? 2 : 1,
    buttonHeight: .18,
    actionSpacing: .055,
    actions: actions,
    content: !busy && error == null && presentation != null && content != null
        ? VrWidgetSurface3D(
            name: 'home_room_${room.id}_content',
            child: content.child,
            logicalSize: content.logicalSize,
          )
        : null,
    meshBuilder: meshBuilder,
    textNodeBuilder: textNodeBuilder,
  );
}
