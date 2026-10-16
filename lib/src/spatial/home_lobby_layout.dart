import 'home_spatial_metrics.dart';

/// Meter-based production geometry shared by rendering and collision tests.
enum HomeLobbyFinish {
  stone,
  plaster,
  oak,
  trim,
  fabric,
  rug;

  /// One texture repeat covers this distance in authored world meters.
  double get textureTileMeters => switch (this) {
    stone || plaster => 2,
    oak || trim || fabric || rug => 1,
  };
}

/// Visual shape inside the same authored box used by walking collision.
/// Curves never change doorway clearance, placement, or material grouping.
enum HomeLobbyShape { cuboid, cylinder, ellipsoid, beveledBox }

class HomeLobbyBox {
  final String name;
  final double x, y, z, width, height, depth;
  final HomeLobbyFinish finish;
  final HomeLobbyShape shape;

  /// Optional authored sRGB finish, independent of the host's business data.
  final int? color;

  /// Static meshes are batched within this spatial zone, retaining room culling.
  final String zone;
  const HomeLobbyBox(
    this.name, {
    required this.x,
    required this.y,
    required this.z,
    required this.width,
    required this.height,
    required this.depth,
    required this.finish,
    this.shape = HomeLobbyShape.cuboid,
    this.color,
    this.zone = 'lobby',
  });
}

/// Connected floor rectangles. Walls, furniture and body clearance are applied
/// separately, so adjoining rectangles do not close a doorway at their seam.
class HomeRoom {
  final String id, title;
  final double minX, maxX, minZ, maxZ;
  const HomeRoom(
    this.id,
    this.title,
    this.minX,
    this.maxX,
    this.minZ,
    this.maxZ,
  );
  bool contains(double x, double z) =>
      x >= minX && x <= maxX && z >= minZ && z <= maxZ;
}

class HomeLobbyWaypoint {
  final String id, name, roomId;
  final double x, z;
  const HomeLobbyWaypoint(
    this.id,
    this.name,
    this.x,
    this.z, {
    this.roomId = 'lobby',
  });
}

/// A static, selectable landmark linking to a real existing experience.
class HomeExhibit {
  final String id, title, demoId, roomId;
  final double x, z, yaw;
  final int accent;
  const HomeExhibit(
    this.id,
    this.title,
    this.demoId,
    this.roomId,
    this.x,
    this.z,
    this.yaw,
    this.accent,
  );
}

abstract final class HomeLobbyLayout {
  static const rooms = <HomeRoom>[
    HomeRoom('lobby', 'Biblioteca', -5.5, 5.5, -8, 5.5),
    HomeRoom('science', 'Sala de ciencia', -12.5, -5.5, -3, 3),
    HomeRoom('workshop', 'Taller de ideas', 5.5, 12.5, -3, 3),
    HomeRoom('gallery', 'Galería de materiales', -3.8, 3.8, 5.5, 12.5),
  ];

  /// Reserved for the fixed library and its lower dock, not architecture.
  static const libraryClearance = HomeLobbyBox(
    'reserved_library_volume',
    x: 0,
    y: 1.5,
    z: -HomeSpatialMetrics.libraryDistance,
    width: 4.2,
    height: 3,
    depth: 0.6,
    finish: HomeLobbyFinish.plaster,
  );

  /// Existing IDs are retained; side/rear destinations now occupy real rooms.
  static const waypoints = <HomeLobbyWaypoint>[
    HomeLobbyWaypoint('center', 'Centro del lobby', 0, 0),
    HomeLobbyWaypoint('north_games', 'Vista de la biblioteca', 0, -0.8),
    HomeLobbyWaypoint(
      'east_prod',
      'Taller de ideas',
      8.5,
      0.3,
      roomId: 'workshop',
    ),
    HomeLobbyWaypoint(
      'west_media',
      'Sala de ciencia',
      -8.5,
      0.3,
      roomId: 'science',
    ),
    HomeLobbyWaypoint(
      'south_labs',
      'Galería de materiales',
      0,
      8,
      roomId: 'gallery',
    ),
  ];

  // 41 static cuboids: four rooms, three 2.4 m doorways and furniture.
  // Floor tops remain y=0; door headers leave 3 m of headroom.
  static const boxes = <HomeLobbyBox>[
    HomeLobbyBox(
      'floor',
      x: 0,
      y: -0.12,
      z: -1.25,
      width: 11.2,
      height: 0.24,
      depth: 13.7,
      finish: HomeLobbyFinish.stone,
    ),
    HomeLobbyBox(
      'rug',
      x: 0,
      y: 0.005,
      z: 0.4,
      width: 5.6,
      height: 0.01,
      depth: 4.3,
      finish: HomeLobbyFinish.rug,
    ),
    HomeLobbyBox(
      'ceiling',
      x: 0,
      y: 4.65,
      z: -1.25,
      width: 11.2,
      height: 0.15,
      depth: 13.7,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'wall_west_front',
      x: -5.5,
      y: 2.3,
      z: -4.6,
      width: 0.2,
      height: 4.6,
      depth: 6.8,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'wall_west_rear',
      x: -5.5,
      y: 2.3,
      z: 3.35,
      width: 0.2,
      height: 4.6,
      depth: 4.3,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'door_science_header',
      x: -5.5,
      y: 3.8,
      z: 0,
      width: 0.2,
      height: 1.6,
      depth: 2.4,
      finish: HomeLobbyFinish.oak,
    ),
    HomeLobbyBox(
      'wall_east_front',
      x: 5.5,
      y: 2.3,
      z: -4.6,
      width: 0.2,
      height: 4.6,
      depth: 6.8,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'wall_east_rear',
      x: 5.5,
      y: 2.3,
      z: 3.35,
      width: 0.2,
      height: 4.6,
      depth: 4.3,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'door_workshop_header',
      x: 5.5,
      y: 3.8,
      z: 0,
      width: 0.2,
      height: 1.6,
      depth: 2.4,
      finish: HomeLobbyFinish.oak,
    ),
    HomeLobbyBox(
      'wall_rear_left',
      x: -3.35,
      y: 2.3,
      z: 5.5,
      width: 4.3,
      height: 4.6,
      depth: 0.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'wall_rear_right',
      x: 3.35,
      y: 2.3,
      z: 5.5,
      width: 4.3,
      height: 4.6,
      depth: 0.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'door_gallery_header',
      x: 0,
      y: 3.8,
      z: 5.5,
      width: 2.4,
      height: 1.6,
      depth: 0.2,
      finish: HomeLobbyFinish.oak,
    ),
    HomeLobbyBox(
      'window_sill',
      x: 0,
      y: 0.3,
      z: -8,
      width: 11.1,
      height: 0.6,
      depth: 0.22,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'window_header',
      x: 0,
      y: 4.35,
      z: -8,
      width: 11.1,
      height: 0.5,
      depth: 0.22,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'window_left_frame',
      x: -5.1,
      y: 2.35,
      z: -7.9,
      width: 0.12,
      height: 3.5,
      depth: 0.16,
      finish: HomeLobbyFinish.trim,
    ),
    HomeLobbyBox(
      'window_right_frame',
      x: 5.1,
      y: 2.35,
      z: -7.9,
      width: 0.12,
      height: 3.5,
      depth: 0.16,
      finish: HomeLobbyFinish.trim,
    ),
    HomeLobbyBox(
      'window_top_frame',
      x: 0,
      y: 4.08,
      z: -7.9,
      width: 10.3,
      height: 0.08,
      depth: 0.16,
      finish: HomeLobbyFinish.trim,
    ),
    HomeLobbyBox(
      'window_bottom_frame',
      x: 0,
      y: 0.62,
      z: -7.9,
      width: 10.3,
      height: 0.08,
      depth: 0.16,
      finish: HomeLobbyFinish.trim,
    ),
    HomeLobbyBox(
      'console_base',
      x: 0,
      y: 0.36,
      z: -7.2,
      width: 4.6,
      height: 0.6,
      depth: 0.62,
      finish: HomeLobbyFinish.oak,
    ),
    HomeLobbyBox(
      'console_top',
      x: 0,
      y: 0.69,
      z: -7.2,
      width: 4.72,
      height: 0.06,
      depth: 0.72,
      finish: HomeLobbyFinish.stone,
    ),
    HomeLobbyBox(
      'bench_base',
      x: 4.45,
      y: 0.23,
      z: 3.6,
      width: 1.18,
      height: 0.4,
      depth: 2.6,
      finish: HomeLobbyFinish.oak,
    ),
    HomeLobbyBox(
      'bench_back',
      x: 4.99,
      y: 0.82,
      z: 3.6,
      width: 0.18,
      height: 0.95,
      depth: 2.6,
      finish: HomeLobbyFinish.fabric,
    ),
    HomeLobbyBox(
      'bench_seat',
      x: 4.37,
      y: 0.49,
      z: 3.6,
      width: 1.08,
      height: 0.18,
      depth: 2.6,
      finish: HomeLobbyFinish.fabric,
    ),
    HomeLobbyBox(
      'science_floor',
      x: -9,
      y: -0.12,
      z: 0,
      width: 7,
      height: 0.24,
      depth: 6,
      finish: HomeLobbyFinish.stone,
    ),
    HomeLobbyBox(
      'science_ceiling',
      x: -9,
      y: 4.65,
      z: 0,
      width: 7,
      height: 0.15,
      depth: 6,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'science_outer_wall',
      x: -12.5,
      y: 2.3,
      z: 0,
      width: 0.2,
      height: 4.6,
      depth: 6.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'science_front_wall',
      x: -9,
      y: 2.3,
      z: -3,
      width: 7,
      height: 4.6,
      depth: 0.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'science_rear_wall',
      x: -9,
      y: 2.3,
      z: 3,
      width: 7,
      height: 4.6,
      depth: 0.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'science_exhibit_base',
      x: -9.5,
      y: 0.38,
      z: -1.8,
      width: 1.8,
      height: 0.76,
      depth: 1.3,
      finish: HomeLobbyFinish.oak,
    ),
    HomeLobbyBox(
      'workshop_floor',
      x: 9,
      y: -0.12,
      z: 0,
      width: 7,
      height: 0.24,
      depth: 6,
      finish: HomeLobbyFinish.stone,
    ),
    HomeLobbyBox(
      'workshop_ceiling',
      x: 9,
      y: 4.65,
      z: 0,
      width: 7,
      height: 0.15,
      depth: 6,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'workshop_outer_wall',
      x: 12.5,
      y: 2.3,
      z: 0,
      width: 0.2,
      height: 4.6,
      depth: 6.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'workshop_front_wall',
      x: 9,
      y: 2.3,
      z: -3,
      width: 7,
      height: 4.6,
      depth: 0.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'workshop_rear_wall',
      x: 9,
      y: 2.3,
      z: 3,
      width: 7,
      height: 4.6,
      depth: 0.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'workshop_exhibit_base',
      x: 9.5,
      y: 0.38,
      z: -1.8,
      width: 1.8,
      height: 0.76,
      depth: 1.3,
      finish: HomeLobbyFinish.oak,
    ),
    HomeLobbyBox(
      'gallery_floor',
      x: 0,
      y: -0.12,
      z: 9,
      width: 7.6,
      height: 0.24,
      depth: 7,
      finish: HomeLobbyFinish.stone,
    ),
    HomeLobbyBox(
      'gallery_ceiling',
      x: 0,
      y: 4.65,
      z: 9,
      width: 7.6,
      height: 0.15,
      depth: 7,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'gallery_west_wall',
      x: -3.8,
      y: 2.3,
      z: 9,
      width: 0.2,
      height: 4.6,
      depth: 7,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'gallery_east_wall',
      x: 3.8,
      y: 2.3,
      z: 9,
      width: 0.2,
      height: 4.6,
      depth: 7,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'gallery_rear_wall',
      x: 0,
      y: 2.3,
      z: 12.5,
      width: 7.8,
      height: 4.6,
      depth: 0.2,
      finish: HomeLobbyFinish.plaster,
    ),
    HomeLobbyBox(
      'gallery_exhibit_base',
      x: 0,
      y: 0.38,
      z: 10.5,
      width: 1.8,
      height: 0.76,
      depth: 1.3,
      finish: HomeLobbyFinish.oak,
    ),
  ];
}
