import 'dart:math' as math;

import 'package:vrlizate_world/vrlizate_world.dart';

import 'home_lobby_layout.dart';

/// Static prefab placement for Home. Objects keep stable IDs and coordinates;
/// their meshes still join Home's existing material/zone batches. Authored
/// bounds remain the conservative walking colliders, independent of silhouette.
/// Dynamic remote avatars must use retained nodes, not rebuild this layout.
abstract final class HomeWorldObjects {
  static final world = VrWorldAddress(
    worldId: 'vrlizate.home',
    instanceId: 'local',
  );
  static const tree = 'plaza.tree';
  static const mirroredTree = 'plaza.tree.mirrored';

  static VrWorldEntity placeTree({
    required String id,
    required double x,
    required double z,
    double y = .65,
    bool mirrored = false,
    double scale = 1,
    double yawRadians = 0,
  }) => VrWorldEntity(
    id: id,
    prototypeId: mirrored ? mirroredTree : tree,
    world: world,
    transform: VrWorldTransform(
      position: VrWorldPosition(x, y, z),
      yawRadians: yawRadians,
      scale: scale,
    ),
  );

  /// Placement supports quarter turns, preserving the authored collider bounds.
  /// Visual cylinders/ellipsoids fit inside those same transformed bounds.
  static List<HomeLobbyBox> boxesFor(VrWorldEntity entity) {
    if (entity.world != world ||
        (entity.prototypeId != tree && entity.prototypeId != mirroredTree)) {
      throw ArgumentError('Unregistered Home object prototype or world.');
    }
    final transform = entity.transform;
    final turns = transform.yawRadians / (math.pi / 2);
    if ((turns - turns.round()).abs() > 1e-8) {
      throw ArgumentError('Home cuboid prefabs require quarter-turn yaw.');
    }
    final swap = turns.round().isOdd;
    final side = entity.prototypeId == mirroredTree ? -1.0 : 1.0;
    HomeLobbyBox part(
      String suffix,
      double x,
      double y,
      double z,
      double width,
      double height,
      double depth,
      HomeLobbyFinish finish,
      int color,
      HomeLobbyShape shape,
    ) {
      final center = transform.transformPoint(VrWorldPosition(x, y, z));
      return HomeLobbyBox(
        'entity_${entity.id}_$suffix',
        x: center.x,
        y: center.y,
        z: center.z,
        width: (swap ? depth : width) * transform.scale,
        height: height * transform.scale,
        depth: (swap ? width : depth) * transform.scale,
        finish: finish,
        color: color,
        shape: shape,
        zone: 'promenade',
      );
    }

    return [
      part(
        'trunk',
        0,
        1.25,
        0,
        .24,
        2.5,
        .24,
        HomeLobbyFinish.oak,
        0xFF897154,
        HomeLobbyShape.cylinder,
      ),
      part(
        'crown',
        0,
        2.75,
        0,
        2.5,
        1.6,
        2.7,
        HomeLobbyFinish.fabric,
        0xFF6F8C73,
        HomeLobbyShape.ellipsoid,
      ),
      part(
        'top',
        side * .2,
        3.67,
        .16,
        1.8,
        .65,
        1.9,
        HomeLobbyFinish.fabric,
        0xFF88A381,
        HomeLobbyShape.ellipsoid,
      ),
    ];
  }
}
