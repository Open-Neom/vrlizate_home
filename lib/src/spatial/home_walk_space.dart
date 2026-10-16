import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_physics/vrlizate_physics.dart';

import 'home_lobby_layout.dart';

class HomePanelPlacement {
  const HomePanelPlacement(this.forward, this.distance);
  final vm.Vector3 forward;
  final double distance;
}

/// Lightweight XZ body collision against the same boxes the GPU draws.
/// This is bounded, seated-controller locomotion, not physical room tracking.
class HomeWalkSpace {
  HomeWalkSpace({
    this.bodyRadius = 0.25,
    Iterable<HomeRoom> rooms = HomeLobbyLayout.rooms,
    Iterable<HomeLobbyBox> boxes = HomeLobbyLayout.boxes,
  }) : rooms = List.unmodifiable(rooms),
       _physics = PhysicsCharacterSpace(
         bodyRadius: bodyRadius,
         regions: rooms.map(
           (room) =>
               PhysicsWalkRegion(room.minX, room.maxX, room.minZ, room.maxZ),
         ),
         obstacles: boxes.map(
           (box) => PhysicsObstacleBox(
             x: box.x,
             y: box.y,
             z: box.z,
             width: box.width,
             height: box.height,
             depth: box.depth,
           ),
         ),
       );

  final double bodyRadius;
  final List<HomeRoom> rooms;
  final PhysicsCharacterSpace _physics;

  HomeRoom? roomAt(double x, double z) {
    for (final room in rooms) {
      if (room.contains(x, z)) return room;
    }
    return null;
  }

  bool canStand(double x, double z) => _physics.canStand(x, z);

  /// Settle an interrupted arc without trapping the viewer inside a wall.
  /// Prefer the current XZ, then the last legal point seen along the route,
  /// then the jump's own start. Never substitute the plaza's global origin.
  vm.Vector3? settleCancelledJump({
    required vm.Vector3 current,
    required vm.Vector3 jumpStart,
    vm.Vector3? lastSafe,
  }) {
    for (final candidate in [current, lastSafe, jumpStart]) {
      if (candidate != null && canStand(candidate.x, candidate.z)) {
        return vm.Vector3(candidate.x, 1.6, candidate.z);
      }
    }
    return null;
  }

  /// Choose once when opening: keep a real panel inside the room, never track
  /// the head. Near a wall it may open to the side, requiring a natural turn.
  /// A minimum 1.8 m fallback is preferable to clipping UI through architecture.
  HomePanelPlacement? placePanel({
    required vm.Vector3 eye,
    required vm.Vector3 forward,
    required double distance,
    double width = 1.78,
  }) {
    if (!canStand(eye.x, eye.z) || !distance.isFinite || distance < 1.8) {
      return null;
    }
    final flat = vm.Vector3(forward.x, 0, forward.z);
    if (!flat.length2.isFinite || flat.length2 < 1e-6) flat.setValues(0, 0, -1);
    flat.normalize();
    for (final requested in [distance, 2.6, 2.2, 1.8]) {
      if (requested > distance) continue;
      for (var step = 0; step <= 12; step++) {
        for (final sign in const [1, -1]) {
          if (step == 0 && sign < 0) continue;
          final angle = step * sign * math.pi / 12;
          final dir = vm.Vector3(
            flat.x * math.cos(angle) - flat.z * math.sin(angle),
            0,
            flat.x * math.sin(angle) + flat.z * math.cos(angle),
          );
          final center = eye + dir * requested;
          var clear = true;
          // Sample the full panel width and rays leading to each point, not
          // just the center (which could be visible through a narrow doorway).
          for (var i = -4; i <= 4 && clear; i++) {
            final offset = width / 2 * i / 4;
            final px = center.x + dir.z * offset;
            final pz = center.z - dir.x * offset;
            final segments = (requested / 0.12).ceil();
            for (var j = 1; j <= segments; j++) {
              final t = j / segments;
              if (!canStand(
                eye.x + (px - eye.x) * t,
                eye.z + (pz - eye.z) * t,
              )) {
                clear = false;
                break;
              }
            }
          }
          if (clear) return HomePanelPlacement(dir, requested);
        }
      }
    }
    return null;
  }

  /// Small substeps prevent crossing a thin wall, even at diagonal approaches.
  /// Axis sliding keeps walking parallel to a wall comfortable and predictable.
  vm.Vector3 move(vm.Vector3 from, double dx, double dz) {
    final moved = _physics.move(from, dx, dz);
    // Home owns its fixed seated eye height; collision is renderer-neutral.
    return identical(moved, from) ? from : (moved..y = 1.6);
  }
}
