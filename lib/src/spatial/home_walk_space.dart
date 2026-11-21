import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_physics/vrlizate_physics.dart';

import 'home_lobby_layout.dart';

class HomePanelPlacement {
  const HomePanelPlacement(this.forward, this.distance);
  final vm.Vector3 forward;
  final double distance;
}

/// Primary travel axis along which a [HomeWalkableElevation.ramp] interpolates
/// from `startElevationMeters` to `endElevationMeters`.
enum HomeElevationAxis { posX, negX, posZ, negZ }

enum _ElevationKind { terrace, ramp, radialBowl }

/// Walkable elevation zone enabling multi-level architectural worlds (terraces,
/// smooth ramps, arched Venetian/Japanese bridges, and sunken amphitheaters)
/// without breaking flat `y = 0` legacy rooms.
class HomeWalkableElevation {
  const HomeWalkableElevation.terrace({
    required this.minX,
    required this.maxX,
    required this.minZ,
    required this.maxZ,
    required double elevationMeters,
    this.id,
  }) : _kind = _ElevationKind.terrace,
       startElevationMeters = elevationMeters,
       endElevationMeters = elevationMeters,
       axis = HomeElevationAxis.posZ,
       archHeightMeters = 0.0,
       centerX = 0.0,
       centerZ = 0.0,
       innerRadius = 0.0,
       outerRadius = 0.0;

  /// Smooth `C¹` Hermite ramp or arched bridge (`archHeightMeters > 0`).
  const HomeWalkableElevation.ramp({
    required this.minX,
    required this.maxX,
    required this.minZ,
    required this.maxZ,
    required this.startElevationMeters,
    required this.endElevationMeters,
    required this.axis,
    this.archHeightMeters = 0.0,
    this.id,
  }) : _kind = _ElevationKind.ramp,
       centerX = 0.0,
       centerZ = 0.0,
       innerRadius = 0.0,
       outerRadius = 0.0;

  /// Circular sunken social amphitheater or raised pavilion mound.
  const HomeWalkableElevation.radialBowl({
    required this.centerX,
    required this.centerZ,
    required this.innerRadius,
    required this.outerRadius,
    required double centerElevationMeters,
    double rimElevationMeters = 0.0,
    this.id,
  }) : _kind = _ElevationKind.radialBowl,
       minX = centerX - outerRadius,
       maxX = centerX + outerRadius,
       minZ = centerZ - outerRadius,
       maxZ = centerZ + outerRadius,
       startElevationMeters = centerElevationMeters,
       endElevationMeters = rimElevationMeters,
       axis = HomeElevationAxis.posZ,
       archHeightMeters = 0.0;

  final String? id;
  final _ElevationKind _kind;
  final double minX, maxX, minZ, maxZ;
  final double startElevationMeters;
  final double endElevationMeters;
  final HomeElevationAxis axis;
  final double archHeightMeters;
  final double centerX, centerZ, innerRadius, outerRadius;

  /// Returns ground elevation in meters if `(x, z)` lies within this zone, or
  /// `null` otherwise.
  double? sampleAt(double x, double z) {
    if (x < minX || x > maxX || z < minZ || z > maxZ) return null;
    switch (_kind) {
      case _ElevationKind.terrace:
        return startElevationMeters;
      case _ElevationKind.ramp:
        final double rawT;
        switch (axis) {
          case HomeElevationAxis.posX:
            rawT = maxX > minX ? (x - minX) / (maxX - minX) : 0.0;
          case HomeElevationAxis.negX:
            rawT = maxX > minX ? (maxX - x) / (maxX - minX) : 0.0;
          case HomeElevationAxis.posZ:
            rawT = maxZ > minZ ? (z - minZ) / (maxZ - minZ) : 0.0;
          case HomeElevationAxis.negZ:
            rawT = maxZ > minZ ? (maxZ - z) / (maxZ - minZ) : 0.0;
        }
        final t = rawT.clamp(0.0, 1.0);
        // Smoothstep avoids sudden VR camera slope jolts at ramp entry/exit.
        final smooth = t * t * (3.0 - 2.0 * t);
        final slopeY =
            startElevationMeters +
            (endElevationMeters - startElevationMeters) * smooth;
        final archY = archHeightMeters != 0.0
            ? math.sin(t * math.pi) * archHeightMeters
            : 0.0;
        return slopeY + archY;
      case _ElevationKind.radialBowl:
        final dx = x - centerX;
        final dz = z - centerZ;
        final dist = math.sqrt(dx * dx + dz * dz);
        if (dist > outerRadius) return null;
        if (dist <= innerRadius || outerRadius <= innerRadius) {
          return startElevationMeters;
        }
        final t = ((dist - innerRadius) / (outerRadius - innerRadius)).clamp(
          0.0,
          1.0,
        );
        final smooth = t * t * (3.0 - 2.0 * t);
        return startElevationMeters +
            (endElevationMeters - startElevationMeters) * smooth;
    }
  }
}

/// Lightweight XZ body collision + optional smooth multi-elevation surface
/// queries against the same geometry the GPU draws.
/// This is bounded, seated-controller locomotion, not physical room tracking.
class HomeWalkSpace {
  HomeWalkSpace({
    this.bodyRadius = 0.25,
    Iterable<HomeRoom> rooms = HomeLobbyLayout.rooms,
    Iterable<HomeLobbyBox> boxes = HomeLobbyLayout.boxes,
    Iterable<HomeWalkableElevation> elevations = const [],
  }) : rooms = List.unmodifiable(rooms),
       elevations = List.unmodifiable(elevations),
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

  static const double defaultStandingEyeHeight = 1.60;

  final double bodyRadius;
  final List<HomeRoom> rooms;
  final List<HomeWalkableElevation> elevations;
  final PhysicsCharacterSpace _physics;

  /// Continuous ground floor elevation (in meters) at world `(x, z)`.
  /// Returns `0.0` everywhere when no [elevations] are authored.
  double groundHeightAt(double x, double z) {
    if (elevations.isEmpty || !x.isFinite || !z.isFinite) return 0.0;
    double? best;
    for (final zone in elevations) {
      final sampled = zone.sampleAt(x, z);
      if (sampled == null) continue;
      if (best == null || sampled > best) {
        best = sampled;
      }
    }
    return best ?? 0.0;
  }

  /// Target VR camera eye height at world `(x, z)`.
  double eyeHeightAt(
    double x,
    double z, {
    double standingEyeHeight = defaultStandingEyeHeight,
  }) => groundHeightAt(x, z) + standingEyeHeight;

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
        return vm.Vector3(
          candidate.x,
          eyeHeightAt(candidate.x, candidate.z),
          candidate.z,
        );
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
  /// Axis sliding keeps walking parallel to a wall comfortable and predictable,
  /// and threshold bevel-funneling gently guides shoulders past doorway jambs
  /// (within 0.45 m of an open portal) so passages never snag the viewer.
  vm.Vector3 move(vm.Vector3 from, double dx, double dz) {
    if (!dx.isFinite || !dz.isFinite) return from;
    var clampedDx = dx;
    var clampedDz = dz;
    final largest = math.max(clampedDx.abs(), clampedDz.abs());
    if (largest > 0) {
      final nx = clampedDx / largest;
      final nz = clampedDz / largest;
      final normLen = math.sqrt(nx * nx + nz * nz);
      if (largest > _physics.maxMoveMeters / normLen) {
        clampedDx = nx * _physics.maxMoveMeters / normLen;
        clampedDz = nz * _physics.maxMoveMeters / normLen;
      }
    }
    final requestedLen = math.sqrt(
      clampedDx * clampedDx + clampedDz * clampedDz,
    );
    var moved = _physics.move(from, clampedDx, clampedDz);
    if (identical(moved, from)) return from;

    final actualDx = moved.x - from.x;
    final actualDz = moved.z - from.z;
    final actualLen = math.sqrt(actualDx * actualDx + actualDz * actualDz);
    if (requestedLen > 1e-4 && actualLen < requestedLen * 0.35) {
      if (clampedDz.abs() >= clampedDx.abs() && clampedDz.abs() > 1e-4) {
        final side = _findOpenPassageLateral(
          moved.x,
          moved.z,
          alongZ: true,
          forwardSign: clampedDz.sign,
        );
        if (side != 0) {
          final nudge = side * math.min(requestedLen, 0.14);
          moved = _physics.move(from, clampedDx + nudge, clampedDz);
        }
      } else if (clampedDx.abs() > 1e-4) {
        final side = _findOpenPassageLateral(
          moved.x,
          moved.z,
          alongZ: false,
          forwardSign: clampedDx.sign,
        );
        if (side != 0) {
          final nudge = side * math.min(requestedLen, 0.14);
          moved = _physics.move(from, clampedDx, clampedDz + nudge);
        }
      }
    }

    // Follow multi-level terraces/ramps/bridges smoothly (1.60 m on flat y=0).
    return moved..y = eyeHeightAt(moved.x, moved.z);
  }

  double _findOpenPassageLateral(
    double x,
    double z, {
    required bool alongZ,
    required double forwardSign,
  }) {
    const forwardProbe = 0.36;
    for (final offset in const [0.15, 0.30, 0.45]) {
      final negOpen = alongZ
          ? canStand(x - offset, z) &&
                canStand(x - offset, z + forwardSign * forwardProbe)
          : canStand(x, z - offset) &&
                canStand(x + forwardSign * forwardProbe, z - offset);
      final posOpen = alongZ
          ? canStand(x + offset, z) &&
                canStand(x + offset, z + forwardSign * forwardProbe)
          : canStand(x, z + offset) &&
                canStand(x + forwardSign * forwardProbe, z + offset);
      if (negOpen && !posOpen) return -1.0;
      if (posOpen && !negOpen) return 1.0;
    }
    return 0.0;
  }
}
