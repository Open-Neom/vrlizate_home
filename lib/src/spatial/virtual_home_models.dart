import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Floor teleportation waypoint in the Virtual Home.
class FloorWaypoint {
  final String id;
  final String name;
  final vm.Vector3 position;
  final Color color;
  final Node node;
  final PhysicallyBasedMaterial material;

  FloorWaypoint({
    required this.id,
    required this.name,
    required this.position,
    required this.color,
    required this.node,
    required this.material,
  });
}

/// Parabolic arc-jump locomotion animation.
class ArcJumpAnim {
  final vm.Vector3 from;
  final vm.Vector3 to;
  final String targetName;
  final double duration;
  double t = 0.0;

  ArcJumpAnim({
    required this.from,
    required this.to,
    required this.targetName,
    required this.duration,
  });

  /// Evaluates the camera position along the parabolic arc trajectory.
  vm.Vector3 evaluate() {
    final horizontal = from + (to - from) * t;
    // Parabolic arc jump curve: reaches +0.28m peak at midpoint (t = 0.5)
    final arcHeight = (3.14159265 * t.clamp(0.0, 1.0));
    final yOffset = (arcHeight >= 0 && arcHeight <= 3.14159265)
        ? (0.28 * (t > 0 && t < 1 ? (4.0 * t * (1.0 - t)) : 0.0))
        : 0.0;
    return vm.Vector3(horizontal.x, horizontal.y + yOffset, horizontal.z);
  }
}

/// Thematic shape for the procedural 3D diorama floating above each pedestal.
enum DioramaShape {
  chessPiece,
  planet,
  tower,
  portalRing,
  crystal,
  chartBars,
  kanbanBoard,
  noteCard,
  wordsphereOrb,
  cinemaReel,
  gem,
  terrainMountain,
  cuboidPbr,
  holographicHand,
  radarWaves,
  handSkeleton,
}

/// Interactive pedestal in the Virtual Home representing a VR experience.
class PortalPedestal {
  final String demoId;
  final String title;
  final String subtitle;
  final Color color;
  final vm.Vector3 position;
  final Node dioramaNode;
  final PhysicallyBasedMaterial material;

  PortalPedestal({
    required this.demoId,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.position,
    required this.dioramaNode,
    required this.material,
  });
}
