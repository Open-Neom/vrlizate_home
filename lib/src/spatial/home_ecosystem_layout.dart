import 'dart:math' as math;

import 'package:vrlizate_world/vrlizate_world.dart';

import '../ecosystem/vr_home_ecosystem_room.dart';
import 'home_lobby_layout.dart';
import 'home_room_identity.dart';
import 'home_world_objects.dart';

/// Cardinal wall placement of a storefront room relative to its plaza/wing.
///
/// - [west]: room sits on the West side (`x < wallCoord`), opens `+X`
/// - [east]: room sits on the East side (`x > wallCoord`), opens `-X`
/// - [north]: room sits on the North side (`z < wallCoord`), opens `+Z`
/// - [south]: room sits on the South side (`z > wallCoord`), opens `-Z`
enum HomePortalFacing { west, east, north, south }

/// Spatial organization of the walkable Mall / Plaza.
enum HomePlazaTopology {
  /// Original two-sided boulevard extending along `+Z`.
  boulevard,

  /// Cruciform multi-wing plaza (`Atrio Norte`, `Ala Oeste`, `Ala Este`,
  /// `Atrio Sur` y `Pabellón Sur`) radiating around a central crossroads so
  /// large room inventories stay compact and distributed instead of forming an
  /// endless linear corridor.
  distributedCruciform,
}

/// A real room and its inward-facing, selectable terminal. Dimensions are
/// meters and are shared by rendering, collision and reachability tests.
class HomeEcosystemPortal {
  const HomeEcosystemPortal({
    required this.room,
    required this.floor,
    required this.side,
    required this.z,
    HomePortalFacing? facing,
    double? centerX,
    double? customHalfFrontage,
    double? customDoorHalfWidth,
  }) : _facing = facing,
       _centerX = centerX,
       _customHalfFrontage = customHalfFrontage,
       _customDoorHalfWidth = customDoorHalfWidth;

  final VrHomeEcosystemRoom room;
  final HomeRoom floor;
  final double side, z;
  final HomePortalFacing? _facing;
  final double? _centerX;
  final double? _customHalfFrontage;
  final double? _customDoorHalfWidth;

  HomePortalFacing get facing =>
      _facing ?? (side < 0 ? HomePortalFacing.west : HomePortalFacing.east);
  bool get isNorthSouth =>
      facing == HomePortalFacing.north || facing == HomePortalFacing.south;
  double get zSide => switch (facing) {
    HomePortalFacing.north => -1.0,
    HomePortalFacing.south => 1.0,
    HomePortalFacing.west || HomePortalFacing.east => 0.0,
  };
  double get wallCenterX => _centerX ?? (floor.minX + floor.maxX) / 2;
  double get roomHalfFrontage =>
      _customHalfFrontage ?? HomeEcosystemLayout.roomHalfFrontage;

  double get doorX =>
      isNorthSouth ? wallCenterX : (side < 0 ? floor.maxX : floor.minX);
  double get doorZ =>
      isNorthSouth ? (zSide < 0 ? floor.maxZ : floor.minZ) : z;
  double get outerX =>
      isNorthSouth ? wallCenterX : (side < 0 ? floor.minX : floor.maxX);
  double get outerZ =>
      isNorthSouth ? (zSide < 0 ? floor.minZ : floor.maxZ) : z;
  double get terminalX => isNorthSouth ? wallCenterX : outerX - side * .22;
  double get terminalZ => isNorthSouth ? outerZ - zSide * .22 : z;
  double get standingX => isNorthSouth ? wallCenterX : outerX - side * 2.7;
  double get standingZ => isNorthSouth ? outerZ - zSide * 2.7 : z;
  double get signX => isNorthSouth ? wallCenterX : doorX - side * .45;
  double get signZ => isNorthSouth ? doorZ - zSide * .45 : z;
  double get roomCenterX => (floor.minX + floor.maxX) / 2;
  double get roomCenterZ => isNorthSouth ? (floor.minZ + floor.maxZ) / 2 : z;
  double get terminalWidth => isNorthSouth ? 2.3 : .14;
  double get terminalDepth => isNorthSouth ? .14 : 2.3;
  double get inwardForwardX => isNorthSouth ? 0.0 : side;
  double get inwardForwardZ => isNorthSouth ? zSide : 0.0;
  double get displayOffset => roomHalfFrontage * .8;
  double get doorHalfWidth =>
      _customDoorHalfWidth ?? HomeEcosystemLayout.doorHalfWidth;
  double get yaw => switch (facing) {
    HomePortalFacing.west || HomePortalFacing.east => -side * math.pi / 2,
    HomePortalFacing.north => 0.0,
    HomePortalFacing.south => math.pi,
  };
}

/// A broad public plaza behind the material gallery. Its arrival square, garden
/// islands and side arcades leave several independent walking routes between
/// full-size experience rooms. Rendering and collision share every solid.
/// An empty inventory preserves the original Home exactly.
class HomeEcosystemLayout {
  static const plazaHalfWidth = 15.0;
  static const roomDepth = 14.0;
  static const roomHalfFrontage = 5.5;
  static const rowPitch = 14.0;
  static const firstRowZ = 24.0;
  static const entryZ = 12.5;
  static const entryHalfWidth = 3.4;
  static const doorHalfWidth = 3.3;
  static const arcadeX = 11.5;
  static const cruciformCenterZ = 36.0;
  static const cruciformHalfWidth = 6.5;
  static const cruciformSouthEndZ = 65.5;

  factory HomeEcosystemLayout.custom({
    required Iterable<HomeRoom> rooms,
    required Iterable<HomeLobbyBox> boxes,
    required Iterable<HomeEcosystemPortal> portals,
    Iterable<VrWorldEntity> worldObjects = const [],
    required Iterable<HomeLobbyWaypoint> waypoints,
  }) => HomeEcosystemLayout._(rooms, boxes, portals, worldObjects, waypoints);

  factory HomeEcosystemLayout(
    Iterable<VrHomeEcosystemRoom> rooms, {
    Iterable<VrWorldEntity>? worldObjects,
    HomePlazaTopology topology = HomePlazaTopology.boulevard,
  }) {
    final supplied = List<VrHomeEcosystemRoom>.unmodifiable(rooms);
    final ids = <String>{};
    for (final room in supplied) {
      if (room.id.isEmpty || !ids.add(room.id)) {
        throw ArgumentError('Ecosystem rooms require unique, nonempty IDs.');
      }
    }
    if (supplied.isEmpty) {
      if (worldObjects?.isNotEmpty == true) {
        throw ArgumentError('Home objects require a plaza inventory.');
      }
      return HomeEcosystemLayout._(
        HomeLobbyLayout.rooms,
        HomeLobbyLayout.boxes,
        const [],
        const [],
        HomeLobbyLayout.waypoints,
      );
    }
    if (topology == HomePlazaTopology.distributedCruciform) {
      return _buildDistributedCruciform(supplied, worldObjects: worldObjects);
    }
    final objects = VrWorldRegistry(
      world: HomeWorldObjects.world,
      maxEntities: 128,
    );
    if (worldObjects != null) {
      for (final entity in worldObjects) {
        objects.add(entity);
      }
    }
    final rows = (supplied.length / 2).ceil();
    final endZ = firstRowZ + (rows - 1) * rowPitch + roomHalfFrontage + 3.0;
    final spaces = <HomeRoom>[
      ...HomeLobbyLayout.rooms,
      HomeRoom(
        'ecosystem_corridor',
        'Plaza de experiencias',
        -plazaHalfWidth,
        plazaHalfWidth,
        entryZ,
        endZ,
      ),
    ];
    final boxes = <HomeLobbyBox>[
      for (final box in HomeLobbyLayout.boxes)
        if (box.name != 'gallery_rear_wall') box,
    ];
    var zone = 'promenade';
    HomeRoomIdentity? identity;
    int? accent;
    void box(
      String name,
      double x,
      double y,
      double z,
      double width,
      double height,
      double depth, [
      HomeLobbyFinish finish = HomeLobbyFinish.plaster,
      int? color,
      HomeLobbyShape shape = HomeLobbyShape.cuboid,
    ]) {
      boxes.add(
        HomeLobbyBox(
          'ecosystem_$name',
          x: x,
          y: y,
          z: z,
          width: width,
          height: height,
          depth: depth,
          finish: finish,
          shape: shape,
          color:
              color ??
              (identity == null
                  ? null
                  : switch (finish) {
                      HomeLobbyFinish.stone => identity.floor,
                      HomeLobbyFinish.plaster => identity.wall,
                      HomeLobbyFinish.trim => accent,
                      HomeLobbyFinish.oak ||
                      HomeLobbyFinish.fabric ||
                      HomeLobbyFinish.rug => identity.furniture,
                    }),
          zone: zone,
        ),
      );
    }

    // Beyond the lintel the ceiling rises and the floor opens to a 30 m arrival
    // square. The gallery joins through a wide 6.8 m grand portal.
    const galleryOuterX = 4.9;
    const entryPierWidth = galleryOuterX - entryHalfWidth;
    const entryPierX = (galleryOuterX + entryHalfWidth) / 2;
    box('entry_left', -entryPierX, 2.3, entryZ, entryPierWidth, 4.6, .2);
    box('entry_right', entryPierX, 2.3, entryZ, entryPierWidth, 4.6, .2);
    box(
      'entry_lintel',
      0,
      3.95,
      entryZ,
      entryHalfWidth * 2,
      1.3,
      .2,
      HomeLobbyFinish.oak,
    );
    final plazaCenterZ = (entryZ + endZ) / 2;
    final plazaLength = endZ - entryZ;
    box(
      'corridor_floor',
      0,
      -.12,
      plazaCenterZ,
      plazaHalfWidth * 2,
      .24,
      plazaLength,
      HomeLobbyFinish.stone,
      0xFFD9D3C6,
    );
    // A single opaque sky canopy avoids expensive layered transparency. Its
    // generous headroom and upper clerestories expose the atrium's full volume.
    box(
      'atrium_sky',
      0,
      8.4,
      plazaCenterZ,
      plazaHalfWidth * 2,
      .1,
      plazaLength,
      HomeLobbyFinish.plaster,
      0xFFB8D9E5,
    );
    for (final side in const [-1.0, 1.0]) {
      box(
        'entry_wing_$side',
        side * (plazaHalfWidth + galleryOuterX) / 2,
        2.3,
        entryZ,
        plazaHalfWidth - galleryOuterX,
        4.6,
        .2,
        HomeLobbyFinish.plaster,
        0xFFE6DFD0,
      );
      box(
        'ceiling_gallery_$side',
        side * (plazaHalfWidth - 1.35),
        4.65,
        plazaCenterZ,
        2.7,
        .18,
        plazaLength,
        HomeLobbyFinish.plaster,
        0xFFE6DFD0,
      );
      box(
        'arcade_light_band_$side',
        side * (plazaHalfWidth - 2.65),
        4.53,
        plazaCenterZ,
        .15,
        .06,
        plazaLength,
        HomeLobbyFinish.trim,
        0xFFFFE7BC,
      );
      box(
        'clerestory_$side',
        side * (plazaHalfWidth - .05),
        6.55,
        plazaCenterZ,
        .2,
        3.6,
        plazaLength,
        HomeLobbyFinish.plaster,
        0xFF9EBDC3,
      );
      box(
        'clerestory_rail_$side',
        side * (plazaHalfWidth - .2),
        5.05,
        plazaCenterZ,
        .2,
        .18,
        plazaLength,
        HomeLobbyFinish.oak,
        0xFFAA9270,
      );
      for (final x in const [1.9, plazaHalfWidth - 4.7, plazaHalfWidth - 1.9]) {
        box(
          'paving_border_${side}_$x',
          side * x,
          .009,
          plazaCenterZ,
          .09,
          .018,
          plazaLength,
          HomeLobbyFinish.trim,
          0xFFAA977B,
        );
      }
    }
    box(
      'corridor_end',
      0,
      4.2,
      endZ,
      plazaHalfWidth * 2 + .2,
      8.4,
      .2,
      HomeLobbyFinish.plaster,
      0xFFE6DFD0,
    );
    box(
      'end_inset',
      0,
      3.0,
      endZ - .12,
      13,
      3.4,
      .08,
      HomeLobbyFinish.trim,
      0xFF7C9489,
    );
    for (var row = 0; row <= rows; row++) {
      final z = firstRowZ - rowPitch / 2 + row * rowPitch;
      if (z >= endZ) continue;
      box(
        'atrium_beam_$row',
        0,
        7.8,
        z,
        plazaHalfWidth * 2,
        .28,
        .24,
        HomeLobbyFinish.oak,
        0xFFAA9270,
      );
      for (final side in const [-1.0, 1.0]) {
        box(
          'clerestory_mullion_${row}_$side',
          side * (plazaHalfWidth - .25),
          6.5,
          z,
          .22,
          3.7,
          .22,
          HomeLobbyFinish.oak,
          0xFFAA9270,
        );
      }
    }
    // Broad crosswalks connect opposing shop entrances and both side arcades.
    for (var row = 0; row < rows; row++) {
      final z = firstRowZ + row * rowPitch;
      box(
        'crosswalk_$row',
        0,
        .006,
        z,
        plazaHalfWidth * 2,
        .012,
        doorHalfWidth * 2,
        HomeLobbyFinish.stone,
        0xFFECE4D5,
      );
      for (final direction in const [-1.0, 1.0]) {
        box(
          'crosswalk_edge_${row}_$direction',
          0,
          .015,
          z + direction * (doorHalfWidth + .04),
          plazaHalfWidth * 2,
          .018,
          .08,
          HomeLobbyFinish.trim,
          0xFFAA977B,
        );
      }
    }

    final portals = <HomeEcosystemPortal>[];
    for (var i = 0; i < supplied.length; i++) {
      final room = supplied[i];
      final side = i.isEven ? -1.0 : 1.0;
      final z = firstRowZ + (i ~/ 2) * rowPitch;
      portals.add(
        appendStorefrontRoom(
          room: room,
          facing: side < 0 ? HomePortalFacing.west : HomePortalFacing.east,
          wallCoord: side * plazaHalfWidth,
          alongCoord: z,
          spaces: spaces,
          boxes: boxes,
        ),
      );
    }
    zone = 'promenade';
    identity = null;
    accent = null;
    // Garden islands and benches make places to pause while three continuous
    // routes stay open: the central boulevard and the two 3 m side arcades.
    // Islands sit BETWEEN crosswalks so every storefront remains approachable.
    for (var row = -1; row < rows - 1; row++) {
      final z = firstRowZ + row * rowPitch + rowPitch / 2;
      for (final side in const [-1.0, 1.0]) {
        final x = side * (row < 0 ? 5.2 : 3.8);
        box(
          'planter_${row}_$side',
          x,
          .29,
          z,
          2.1,
          .58,
          2.6,
          HomeLobbyFinish.stone,
          0xFFB5AA96,
          HomeLobbyShape.beveledBox,
        );
        box(
          'planter_rim_${row}_$side',
          x,
          .6,
          z,
          2.22,
          .12,
          2.72,
          HomeLobbyFinish.trim,
          0xFFD6C8AF,
          HomeLobbyShape.beveledBox,
        );
        box(
          'garden_soil_${row}_$side',
          x,
          .661,
          z,
          1.86,
          .008,
          2.34,
          HomeLobbyFinish.plaster, // Fine matte grain; no wood fibers in soil.
          0xFF514438,
        );
        if (worldObjects == null) {
          objects.add(
            HomeWorldObjects.placeTree(
              id: 'tree_${row}_$side',
              x: x,
              z: z,
              mirrored: side < 0,
            ),
          );
        }
        final benchX = x + side * 2.0;
        box(
          'bench_seat_${row}_$side',
          benchX,
          .44,
          z,
          .7,
          .14,
          2.5,
          HomeLobbyFinish.oak,
          0xFFAF8A62,
          HomeLobbyShape.beveledBox,
        );
        box(
          'bench_back_${row}_$side',
          benchX - side * .32,
          .85,
          z,
          .12,
          .72,
          2.5,
          HomeLobbyFinish.oak,
          0xFFAF8A62,
          HomeLobbyShape.beveledBox,
        );
        for (final direction in const [-1.0, 1.0]) {
          box(
            'bench_foot_${row}_${side}_$direction',
            benchX,
            .2,
            z + direction * .92,
            .52,
            .4,
            .14,
            HomeLobbyFinish.trim,
            0xFF756D61,
          );
        }
      }
    }
    // Full-height piers only BETWEEN shops. Each shop owns its open doorway,
    // low display sills and high header; the odd final row stays closed opposite.
    for (final side in const [-1.0, 1.0]) {
      var from = entryZ;
      var segment = 0;
      for (final portal in portals.where((p) => p.side == side)) {
        final to = portal.z - roomHalfFrontage;
        box(
          'corridor_${side}_$segment',
          side * plazaHalfWidth,
          2.3,
          (from + to) / 2,
          .2,
          4.6,
          to - from,
        );
        from = portal.z + roomHalfFrontage;
        segment++;
      }
      box(
        'corridor_${side}_$segment',
        side * plazaHalfWidth,
        2.3,
        (from + endZ) / 2,
        .2,
        4.6,
        endZ - from,
      );
    }
    for (final entity in objects.entities) {
      boxes.addAll(HomeWorldObjects.boxesFor(entity));
    }
    final waypoints = <HomeLobbyWaypoint>[
      ...HomeLobbyLayout.waypoints,
      const HomeLobbyWaypoint(
        'mall_arrival',
        'Plaza de bienvenida del Mall',
        0,
        16.5,
        roomId: 'ecosystem_corridor',
      ),
      for (var row = 0; row < rows; row++)
        HomeLobbyWaypoint(
          'mall_crosswalk_$row',
          'Crucero ${row + 1} del Mall',
          0,
          firstRowZ + row * rowPitch,
          roomId: 'ecosystem_corridor',
        ),
      for (final portal in portals)
        HomeLobbyWaypoint(
          'portal_${portal.room.id}',
          portal.room.title,
          portal.standingX,
          portal.z,
          roomId: portal.floor.id,
        ),
      HomeLobbyWaypoint(
        'mall_rotunda',
        'Rotonda del Horizonte Sur',
        0,
        endZ - 2.2,
        roomId: 'ecosystem_corridor',
      ),
    ];
    return HomeEcosystemLayout._(
      spaces,
      boxes,
      portals,
      objects.entities,
      waypoints,
    );
  }

  /// Appends a full 3D storefront room facing any of the 4 cardinal plaza
  /// directions (`west`, `east`, `north`, `south`).
  ///
  /// When [room.isForLease] is `true`, builds a commercial `"EN RENTA"` window
  /// showcase with amber/emerald beacons, architectural floorplan board, and
  /// holographic `.vrlz` podium while keeping the central modal approach clear.
  static HomeEcosystemPortal appendStorefrontRoom({
    required VrHomeEcosystemRoom room,
    required HomePortalFacing facing,
    required double wallCoord,
    required double alongCoord,
    required List<HomeRoom> spaces,
    required List<HomeLobbyBox> boxes,
    double actualRoomDepth = roomDepth,
    double actualHalfFrontage = roomHalfFrontage,
  }) {
    final roomZone = 'ecosystem_${room.id}';
    final identity = HomeRoomIdentity.forPurpose(room.purpose);
    final accent = room.accent;
    final isNS =
        facing == HomePortalFacing.north || facing == HomePortalFacing.south;
    final side = switch (facing) {
      HomePortalFacing.west || HomePortalFacing.north => -1.0,
      HomePortalFacing.east || HomePortalFacing.south => 1.0,
    };
    final actualDoorHalfWidth = actualHalfFrontage * (doorHalfWidth / roomHalfFrontage);

    void addBox(
      String name,
      double x,
      double y,
      double z,
      double width,
      double height,
      double depth, [
      HomeLobbyFinish finish = HomeLobbyFinish.plaster,
      int? color,
      HomeLobbyShape shape = HomeLobbyShape.cuboid,
    ]) {
      boxes.add(
        HomeLobbyBox(
          'ecosystem_$name',
          x: x,
          y: y,
          z: z,
          width: width,
          height: height,
          depth: depth,
          finish: finish,
          shape: shape,
          color:
              color ??
              switch (finish) {
                HomeLobbyFinish.stone => identity.floor,
                HomeLobbyFinish.plaster => identity.wall,
                HomeLobbyFinish.trim => accent,
                HomeLobbyFinish.oak ||
                HomeLobbyFinish.fabric ||
                HomeLobbyFinish.rug => identity.furniture,
              },
          zone: roomZone,
        ),
      );
    }

    final HomeRoom floor;
    final HomeEcosystemPortal portal;
    if (!isNS) {
      final minX = side < 0 ? wallCoord - actualRoomDepth : wallCoord;
      final maxX = side < 0 ? wallCoord : wallCoord + actualRoomDepth;
      floor = HomeRoom(
        'ecosystem_${room.id}',
        room.title,
        minX,
        maxX,
        alongCoord - actualHalfFrontage,
        alongCoord + actualHalfFrontage,
      );
      portal = HomeEcosystemPortal(
        room: room,
        floor: floor,
        side: side,
        z: alongCoord,
        facing: facing,
        customHalfFrontage: actualHalfFrontage == roomHalfFrontage
            ? null
            : actualHalfFrontage,
        customDoorHalfWidth: actualDoorHalfWidth == doorHalfWidth
            ? null
            : actualDoorHalfWidth,
      );
      final centerX = wallCoord + side * (actualRoomDepth / 2);
      addBox(
        '${room.id}_floor',
        centerX,
        -.12,
        alongCoord,
        actualRoomDepth,
        .24,
        actualHalfFrontage * 2,
        HomeLobbyFinish.stone,
      );
      addBox(
        '${room.id}_ceiling',
        centerX,
        4.65,
        alongCoord,
        actualRoomDepth,
        .15,
        actualHalfFrontage * 2,
      );
      addBox(
        '${room.id}_outer_wall',
        wallCoord + side * actualRoomDepth,
        2.3,
        alongCoord,
        .2,
        4.6,
        actualHalfFrontage * 2,
      );
      addBox(
        '${room.id}_front_wall',
        centerX,
        2.3,
        alongCoord - actualHalfFrontage,
        actualRoomDepth,
        4.6,
        .2,
      );
      addBox(
        '${room.id}_back_wall',
        centerX,
        2.3,
        alongCoord + actualHalfFrontage,
        actualRoomDepth,
        4.6,
        .2,
      );
      addBox(
        '${room.id}_door_lintel',
        wallCoord,
        3.95,
        alongCoord,
        .2,
        1.3,
        actualDoorHalfWidth * 2,
        HomeLobbyFinish.oak,
      );
    } else {
      final minZ = side < 0 ? wallCoord - actualRoomDepth : wallCoord;
      final maxZ = side < 0 ? wallCoord : wallCoord + actualRoomDepth;
      floor = HomeRoom(
        'ecosystem_${room.id}',
        room.title,
        alongCoord - actualHalfFrontage,
        alongCoord + actualHalfFrontage,
        minZ,
        maxZ,
      );
      portal = HomeEcosystemPortal(
        room: room,
        floor: floor,
        side: side,
        z: wallCoord,
        facing: facing,
        centerX: alongCoord,
        customHalfFrontage: actualHalfFrontage,
        customDoorHalfWidth: actualDoorHalfWidth,
      );
      final centerZ = wallCoord + side * (actualRoomDepth / 2);
      addBox(
        '${room.id}_floor',
        alongCoord,
        -.12,
        centerZ,
        actualHalfFrontage * 2,
        .24,
        actualRoomDepth,
        HomeLobbyFinish.stone,
      );
      addBox(
        '${room.id}_ceiling',
        alongCoord,
        4.65,
        centerZ,
        actualHalfFrontage * 2,
        .15,
        actualRoomDepth,
      );
      addBox(
        '${room.id}_outer_wall',
        alongCoord,
        2.3,
        wallCoord + side * actualRoomDepth,
        actualHalfFrontage * 2,
        4.6,
        .2,
      );
      addBox(
        '${room.id}_front_wall',
        alongCoord - actualHalfFrontage,
        2.3,
        centerZ,
        .2,
        4.6,
        actualRoomDepth,
      );
      addBox(
        '${room.id}_back_wall',
        alongCoord + actualHalfFrontage,
        2.3,
        centerZ,
        .2,
        4.6,
        actualRoomDepth,
      );
      addBox(
        '${room.id}_door_lintel',
        alongCoord,
        3.95,
        wallCoord,
        actualDoorHalfWidth * 2,
        1.3,
        .2,
        HomeLobbyFinish.oak,
      );
    }
    spaces.add(floor);

    final depthScale = actualRoomDepth / 7.8;
    final frontageScale = actualHalfFrontage / 3;
    const furnitureDepthScale = 9.8 / 7.8;
    const furnitureFrontageScale = 4.0 / 3;
    void part(
      String name,
      double x,
      double y,
      double offset,
      double width,
      double height,
      double depth, [
      HomeLobbyFinish finish = HomeLobbyFinish.oak,
      int? color,
      HomeLobbyShape shape = HomeLobbyShape.cuboid,
    ]) {
      final architecture =
          name.startsWith('display_sill_') ||
          name.startsWith('display_header_') ||
          name.startsWith('door_pillar_') ||
          name.startsWith('display_frame_') ||
          name.startsWith('window_ledge_') ||
          name.startsWith('marquee_light_') ||
          name.startsWith('for_lease_beacon_') ||
          name == 'fascia' ||
          name == 'canopy' ||
          name == 'threshold' ||
          name == 'interior_inlay';
      final localInto = architecture
          ? (x - 2.5) * depthScale
          : (x - 2.5) * furnitureDepthScale + (actualRoomDepth - 9.8);
      final localAlong = architecture
          ? offset * frontageScale
          : offset * furnitureFrontageScale +
                (offset.abs() >= 1
                    ? offset.sign * (actualHalfFrontage - 4.0) * .7
                    : 0);
      final scaledInto = width * (architecture ? depthScale : furnitureDepthScale);
      final scaledAlong =
          depth * (architecture ? frontageScale : furnitureFrontageScale);
      if (!isNS) {
        addBox(
          '${room.id}_$name',
          wallCoord + side * localInto,
          y,
          alongCoord + localAlong,
          scaledInto,
          height,
          scaledAlong,
          finish,
          color,
          shape,
        );
      } else {
        addBox(
          '${room.id}_$name',
          alongCoord + localAlong,
          y,
          wallCoord + side * localInto,
          scaledAlong,
          height,
          scaledInto,
          finish,
          color,
          shape,
        );
      }
    }

    for (final direction in const [-1.0, 1.0]) {
      part(
        'display_sill_$direction',
        2.5,
        .5,
        direction * 2.4,
        .2,
        1,
        1.2,
        HomeLobbyFinish.plaster,
      );
      part(
        'display_header_$direction',
        2.5,
        3.95,
        direction * 2.4,
        .2,
        1.3,
        1.2,
        HomeLobbyFinish.plaster,
      );
      part(
        'door_pillar_$direction',
        2.5,
        1.65,
        direction * 1.86,
        .22,
        3.3,
        .12,
        HomeLobbyFinish.trim,
        null,
        HomeLobbyShape.cylinder,
      );
      part(
        'display_frame_$direction',
        2.5,
        2,
        direction * 2.94,
        .25,
        2,
        .12,
        HomeLobbyFinish.oak,
      );
      part(
        'window_ledge_$direction',
        2.42,
        1.03,
        direction * 2.42,
        .42,
        .08,
        1.08,
        HomeLobbyFinish.oak,
      );
    }
    part(
      'fascia',
      2.35,
      3.72,
      0,
      .38,
      .76,
      3.8,
      HomeLobbyFinish.oak,
      room.isForLease ? 0xFF78350F : null,
    );
    part(
      'canopy',
      2.25,
      3.22,
      0,
      .8,
      .14,
      4.0,
      HomeLobbyFinish.trim,
      room.isForLease ? 0xFFF59E0B : null,
      HomeLobbyShape.beveledBox,
    );
    part('threshold', 3.05, .012, 0, 1.05, .024, 3.5, HomeLobbyFinish.trim);
    part('interior_inlay', 6.4, .009, 0, 5.6, .018, 3.0, HomeLobbyFinish.rug);

    if (room.isForLease) {
      for (var p = 0; p < 5; p++) {
        part(
          'for_lease_beacon_$p',
          2.12,
          4.08,
          -1.4 + p * .7,
          .14,
          .14,
          .28,
          HomeLobbyFinish.trim,
          p.isEven ? 0xFFFFB300 : 0xFF34D399,
        );
      }
      part(
        'for_lease_stage',
        6.8,
        .16,
        -1.95,
        2.4,
        .32,
        1.25,
        HomeLobbyFinish.stone,
        0xFF334155,
        HomeLobbyShape.beveledBox,
      );
      part(
        'for_lease_stage_rim',
        6.8,
        .34,
        -1.95,
        2.1,
        .06,
        1.05,
        HomeLobbyFinish.trim,
        0xFFF59E0B,
        HomeLobbyShape.beveledBox,
      );
      part(
        'for_lease_monolith',
        6.8,
        1.35,
        -1.95,
        1.15,
        1.95,
        .32,
        HomeLobbyFinish.trim,
        0xFF0F766E,
        HomeLobbyShape.beveledBox,
      );
      part(
        'for_lease_orb',
        6.8,
        1.42,
        -1.72,
        .62,
        .62,
        .62,
        HomeLobbyFinish.fabric,
        0xFFFBBF24,
        HomeLobbyShape.ellipsoid,
      );
      part(
        'for_lease_blueprint_frame',
        6.6,
        2.2,
        -2.76,
        3.4,
        1.65,
        .12,
        HomeLobbyFinish.oak,
        0xFF92400E,
      );
      part(
        'for_lease_blueprint_sheet',
        6.6,
        2.2,
        -2.68,
        3.1,
        1.38,
        .05,
        HomeLobbyFinish.plaster,
        0xFFFEF3C7,
      );
      part(
        'for_lease_desk',
        6.8,
        .42,
        1.95,
        2.2,
        .84,
        .95,
        HomeLobbyFinish.oak,
        0xFF78350F,
        HomeLobbyShape.beveledBox,
      );
      part(
        'for_lease_desk_top',
        6.8,
        .87,
        1.95,
        2.32,
        .07,
        1.04,
        HomeLobbyFinish.trim,
        0xFFFDE68A,
        HomeLobbyShape.beveledBox,
      );
      part(
        'for_lease_window_placard',
        3.7,
        1.35,
        2.05,
        .22,
        1.25,
        1.15,
        HomeLobbyFinish.trim,
        0xFFF59E0B,
        HomeLobbyShape.beveledBox,
      );
      return portal;
    }

    switch (room.purpose) {
      case VrHomeRoomPurpose.openSourceGames:
        part(
          'community_stage',
          7.4,
          .12,
          -2.0,
          3.4,
          .24,
          1.2,
          HomeLobbyFinish.stone,
          0xFF7D70AD,
          HomeLobbyShape.beveledBox,
        );
        part(
          'community_display_frame',
          7.1,
          2.65,
          -2.78,
          4.5,
          2.15,
          .18,
          HomeLobbyFinish.oak,
          0xFF413A5C,
          HomeLobbyShape.beveledBox,
        );
        part(
          'community_display',
          7.1,
          2.65,
          -2.66,
          4.1,
          1.77,
          .05,
          HomeLobbyFinish.plaster,
          0xFF99D8D3,
          HomeLobbyShape.beveledBox,
        );
        part(
          'gamepad_body',
          7.4,
          .82,
          -2.0,
          1.55,
          .56,
          .58,
          HomeLobbyFinish.fabric,
          0xFF60527D,
          HomeLobbyShape.ellipsoid,
        );
        for (final end in const [-1.0, 1.0]) {
          part(
            'gamepad_grip_$end',
            7.4 + end * .53,
            .67,
            -1.96,
            .49,
            .65,
            .58,
            HomeLobbyFinish.fabric,
            0xFF60527D,
            HomeLobbyShape.ellipsoid,
          );
          part(
            'gamepad_button_$end',
            7.4 + end * .42,
            1.09,
            -1.98,
            .16,
            .08,
            .16,
            HomeLobbyFinish.trim,
            end < 0 ? 0xFFCAF3EB : 0xFFB6A0FF,
            HomeLobbyShape.cylinder,
          );
        }
        for (var bay = 0; bay < 3; bay++) {
          final x = 4.8 + bay * 1.85;
          part(
            'arcade_cabinet_$bay',
            x,
            .92,
            2.15,
            1.12,
            1.84,
            .88,
            HomeLobbyFinish.oak,
            0xFF413A5C,
            HomeLobbyShape.beveledBox,
          );
          part(
            'arcade_screen_$bay',
            x,
            1.37,
            1.685,
            .87,
            .71,
            .055,
            HomeLobbyFinish.plaster,
            bay.isEven ? 0xFFB7E6DD : 0xFFC2AEED,
            HomeLobbyShape.beveledBox,
          );
          part(
            'arcade_control_deck_$bay',
            x,
            .86,
            1.6,
            1.05,
            .12,
            .38,
            HomeLobbyFinish.trim,
            0xFF92CEC6,
            HomeLobbyShape.beveledBox,
          );
          part(
            'creator_marquee_$bay',
            x,
            2.03,
            2.02,
            1.22,
            .24,
            .48,
            HomeLobbyFinish.trim,
            null,
            HomeLobbyShape.beveledBox,
          );
        }
        for (final direction in const [-1.0, 1.0]) {
          part(
            'gallery_light_ribbon_$direction',
            6.8,
            4.35,
            direction * 2.5,
            5.8,
            .07,
            .16,
            HomeLobbyFinish.trim,
            direction < 0 ? 0xFFC6B4FA : 0xFFA3E2D6,
            HomeLobbyShape.beveledBox,
          );
        }
      case VrHomeRoomPurpose.profile:
        part(
          'gallery_console',
          7.4,
          .38,
          1.8,
          2.5,
          .76,
          1.2,
          HomeLobbyFinish.oak,
          null,
          HomeLobbyShape.beveledBox,
        );
        for (var p = 0; p < 3; p++) {
          part(
            'portrait_frame_$p',
            4.8 + p * 1.7,
            2.1,
            -2.82,
            1.25,
            1.65,
            .16,
            HomeLobbyFinish.trim,
          );
          part(
            'portrait_inset_$p',
            4.8 + p * 1.7,
            2.1,
            -2.71,
            1.04,
            1.42,
            .05,
            HomeLobbyFinish.plaster,
          );
          part(
            'portrait_silhouette_$p',
            4.8 + p * 1.7,
            1.96,
            -2.67,
            .43,
            .65,
            .04,
            HomeLobbyFinish.fabric,
          );
        }
      case VrHomeRoomPurpose.avatar:
        part(
          'avatar_platform',
          6.7,
          .16,
          -2.0,
          2.5,
          .32,
          2.4,
          HomeLobbyFinish.stone,
          null,
          HomeLobbyShape.cylinder,
        );
        part(
          'avatar_backdrop',
          6.7,
          1.8,
          -3.15,
          3.4,
          3.3,
          .12,
          HomeLobbyFinish.trim,
        );
        part(
          'avatar_mannequin_body',
          6.7,
          1.15,
          -2.0,
          .55,
          1.1,
          .36,
          HomeLobbyFinish.fabric,
        );
        part(
          'avatar_mannequin_head',
          6.7,
          1.95,
          -2.0,
          .42,
          .42,
          .42,
          HomeLobbyFinish.plaster,
          null,
          HomeLobbyShape.ellipsoid,
        );
        for (final armSide in const [-1.0, 1.0]) {
          part(
            'avatar_mannequin_arm_$armSide',
            6.7 + armSide * .4,
            1.15,
            -2.0,
            .18,
            .82,
            .25,
            HomeLobbyFinish.fabric,
          );
        }
        part(
          'showcase_lounge_clearance',
          6.7,
          1.2,
          1.85,
          2.5,
          2.4,
          1.8,
          HomeLobbyFinish.fabric,
        );
      case VrHomeRoomPurpose.social:
        for (final direction in const [-1.0, 1.0]) {
          part(
            'sofa_seat_$direction',
            7.4,
            .3,
            direction * 1.8,
            2.7,
            .6,
            1.1,
            HomeLobbyFinish.fabric,
            null,
            HomeLobbyShape.beveledBox,
          );
          part(
            'sofa_back_$direction',
            7.4,
            .9,
            direction * 2.25,
            2.7,
            .7,
            .23,
            HomeLobbyFinish.fabric,
            null,
            HomeLobbyShape.beveledBox,
          );
          for (final end in const [-1.0, 1.0]) {
            part(
              'sofa_arm_${direction}_$end',
              7.4 + end * 1.25,
              .7,
              direction * 1.8,
              .2,
              .25,
              1.1,
              HomeLobbyFinish.oak,
              null,
              HomeLobbyShape.beveledBox,
            );
          }
        }
        part(
          'community_board',
          4.8,
          2.05,
          -2.82,
          1.7,
          1.35,
          .1,
          HomeLobbyFinish.trim,
        );
      case VrHomeRoomPurpose.creation:
        part(
          'workbench',
          7.4,
          .4,
          1.8,
          2.5,
          .8,
          1.2,
          HomeLobbyFinish.oak,
          null,
          HomeLobbyShape.beveledBox,
        );
        part(
          'design_wall',
          6.7,
          2.15,
          -2.81,
          4,
          1.8,
          .12,
          HomeLobbyFinish.trim,
        );
        for (var p = 0; p < 3; p++) {
          part(
            'prototype_$p',
            6.7 + p * .65,
            1.0 + p * .15,
            1.8,
            .4,
            .4 + p * .3,
            .4,
            HomeLobbyFinish.trim,
          );
          part(
            'project_tile_$p',
            5.45 + p * 1.25,
            2.15,
            -2.7,
            .85,
            1.2,
            .08,
            HomeLobbyFinish.plaster,
          );
        }
      case VrHomeRoomPurpose.reading:
        part(
          'reading_table',
          7.4,
          .38,
          1.8,
          2.5,
          .76,
          1.2,
          HomeLobbyFinish.oak,
          null,
          HomeLobbyShape.beveledBox,
        );
        for (var bay = 0; bay < 3; bay++) {
          final x = 4.8 + bay * 1.7;
          part('bookcase_back_$bay', x, 1.4, -2.75, 1.5, 2.8, .18);
          for (var shelf = 0; shelf < 3; shelf++) {
            final y = .4 + shelf * .85;
            part('shelf_${bay}_$shelf', x, y, -2.5, 1.5, .09, .65);
            for (var book = 0; book < 3; book++) {
              part(
                'books_${bay}_${shelf}_$book',
                x - .47 + book * .46,
                y + .33,
                -2.52,
                .32,
                .55,
                .37,
                book.isEven ? HomeLobbyFinish.trim : HomeLobbyFinish.fabric,
              );
            }
          }
        }
      case VrHomeRoomPurpose.music:
        part('listening_stage', 7.4, .13, 1.8, 3.5, .26, 1.5);
        for (final direction in const [-1.0, 1.0]) {
          part(
            'speaker_$direction',
            7.4 + direction * 1.25,
            1.05,
            2.02,
            .7,
            1.6,
            .64,
            HomeLobbyFinish.fabric,
          );
          for (var cone = 0; cone < 2; cone++) {
            part(
              'speaker_cone_${direction}_$cone',
              7.4 + direction * 1.25,
              .75 + cone * .64,
              1.68,
              .46,
              .46,
              .05,
              HomeLobbyFinish.trim,
            );
          }
        }
        for (var p = 0; p < 6; p++) {
          part(
            'acoustic_panel_$p',
            4.25 + p * .9,
            2.15,
            -2.78,
            .55,
            1.9 - (p % 3) * .25,
            .18,
            HomeLobbyFinish.fabric,
          );
        }
      case VrHomeRoomPurpose.meditation:
        part(
          'tatami_platform',
          7.4,
          .14,
          1.8,
          2.5,
          .28,
          1.2,
          HomeLobbyFinish.fabric,
        );
        for (var p = 0; p < 9; p++) {
          part(
            'bamboo_screen_$p',
            4.6 + p * .57,
            1.7,
            -2.8,
            .13,
            3.4,
            .15,
            HomeLobbyFinish.oak,
            0xFFAD986D,
            HomeLobbyShape.cylinder,
          );
        }
        for (final x in const [4.7, 9.1]) {
          part(
            'stone_planter_$x',
            x,
            .35,
            2.12,
            .7,
            .7,
            .7,
            HomeLobbyFinish.stone,
            null,
            HomeLobbyShape.cylinder,
          );
          part(
            'plant_crown_$x',
            x,
            1.0,
            2.12,
            .65,
            .8,
            .65,
            HomeLobbyFinish.fabric,
            0xFF64806C,
            HomeLobbyShape.ellipsoid,
          );
        }
      case VrHomeRoomPurpose.cinema:
        part(
          'screen_frame',
          10.03,
          3.5,
          0,
          .12,
          1.5,
          4.1,
          HomeLobbyFinish.oak,
          0xFF322E38,
        );
        part(
          'screen',
          9.94,
          3.5,
          0,
          .06,
          1.25,
          3.8,
          HomeLobbyFinish.plaster,
          0xFFDDDCD9,
        );
        for (var row = 0; row < 2; row++) {
          final x = 5.7 + row * 1.7;
          for (final direction in const [-1.0, 1.0]) {
            part(
              'seat_${row}_$direction',
              x,
              .35,
              direction * 1.8,
              .9,
              .7,
              1.05,
              HomeLobbyFinish.fabric,
              null,
              HomeLobbyShape.beveledBox,
            );
            part(
              'seat_back_${row}_$direction',
              x - .37,
              .94,
              direction * 1.8,
              .18,
              .8,
              1.05,
              HomeLobbyFinish.fabric,
              null,
              HomeLobbyShape.beveledBox,
            );
          }
        }
        for (var p = 0; p < 7; p++) {
          part(
            'marquee_light_$p',
            2.12,
            4.08,
            -1.5 + p * .5,
            .13,
            .12,
            .22,
            HomeLobbyFinish.trim,
            0xFFFFDF9C,
          );
        }
      case VrHomeRoomPurpose.portableWorld:
        part(
          'world_compass_stage',
          7.2,
          .12,
          -2.0,
          2.8,
          .24,
          1.4,
          HomeLobbyFinish.stone,
          0xFF3E7C78,
          HomeLobbyShape.beveledBox,
        );
        for (final pillarSide in const [-1.0, 1.0]) {
          part(
            'world_portal_pillar_$pillarSide',
            7.2 + pillarSide * .95,
            1.45,
            -2.0,
            .26,
            2.4,
            .26,
            HomeLobbyFinish.oak,
            0xFF285956,
            HomeLobbyShape.cylinder,
          );
        }
        part(
          'world_portal_lintel',
          7.2,
          2.75,
          -2.0,
          2.35,
          .24,
          .34,
          HomeLobbyFinish.trim,
          0xFF63E6BE,
          HomeLobbyShape.beveledBox,
        );
        part(
          'world_portal_orb',
          7.2,
          1.45,
          -2.0,
          .75,
          .75,
          .75,
          HomeLobbyFinish.fabric,
          0xFF63E6BE,
          HomeLobbyShape.ellipsoid,
        );
        part(
          'world_horizon_display',
          7.1,
          2.45,
          2.62,
          3.8,
          1.65,
          .12,
          HomeLobbyFinish.plaster,
          0xFF8EE8D8,
          HomeLobbyShape.beveledBox,
        );
    }
    return portal;
  }

  /// Seals solid wall piers along a boundary `[start, end]`, leaving open
  /// `[min, max]` intervals for storefronts and lateral wing archways.
  static void fillWallSegments({
    required List<HomeLobbyBox> boxes,
    required String prefix,
    required bool alongX,
    required double fixedCoord,
    required double start,
    required double end,
    required List<(double, double)> openings,
    double height = 4.6,
    int? color,
    String zone = 'promenade',
  }) {
    final sorted = [...openings]..sort((a, b) => a.$1.compareTo(b.$1));
    var cursor = start;
    var index = 0;
    void emit(double from, double to) {
      final length = to - from;
      if (length <= 0.02) return;
      final mid = (from + to) / 2;
      boxes.add(
        HomeLobbyBox(
          'ecosystem_${prefix}_$index',
          x: alongX ? mid : fixedCoord,
          y: height / 2,
          z: alongX ? fixedCoord : mid,
          width: alongX ? length : .2,
          height: height,
          depth: alongX ? .2 : length,
          finish: HomeLobbyFinish.plaster,
          color: color,
          zone: zone,
        ),
      );
      index++;
    }

    for (final (openStart, openEnd) in sorted) {
      if (openStart > cursor) emit(cursor, openStart);
      if (openEnd > cursor) cursor = openEnd;
    }
    if (end > cursor) emit(cursor, end);
  }

  static HomeEcosystemLayout _buildDistributedCruciform(
    List<VrHomeEcosystemRoom> supplied, {
    Iterable<VrWorldEntity>? worldObjects,
  }) {
    final objects = VrWorldRegistry(
      world: HomeWorldObjects.world,
      maxEntities: 128,
    );
    if (worldObjects != null) {
      for (final entity in worldObjects) {
        objects.add(entity);
      }
    }

    final numBays = math.max(1, ((supplied.length - 8) / 4).ceil());
    final wingEnd = 36.0 + (numBays - 1) * 12.5 + 6.5;
    const wingMinZ = cruciformCenterZ - cruciformHalfWidth; // 29.5
    const wingMaxZ = cruciformCenterZ + cruciformHalfWidth; // 42.5
    const endZ = cruciformSouthEndZ; // 65.5

    final spaces = <HomeRoom>[
      ...HomeLobbyLayout.rooms,
      const HomeRoom(
        'ecosystem_corridor',
        'Gran Crucero Central VRlizate',
        -plazaHalfWidth,
        plazaHalfWidth,
        entryZ,
        endZ,
      ),
      HomeRoom(
        'ecosystem_west_wing',
        'Ala Oeste del Crucero',
        -wingEnd,
        -plazaHalfWidth,
        wingMinZ,
        wingMaxZ,
      ),
      HomeRoom(
        'ecosystem_east_wing',
        'Ala Este del Crucero',
        plazaHalfWidth,
        wingEnd,
        wingMinZ,
        wingMaxZ,
      ),
    ];

    final boxes = <HomeLobbyBox>[
      for (final b in HomeLobbyLayout.boxes)
        if (b.name != 'gallery_rear_wall') b,
    ];
    void pBox(
      String name,
      double x,
      double y,
      double z,
      double width,
      double height,
      double depth, [
      HomeLobbyFinish finish = HomeLobbyFinish.plaster,
      int? color,
      HomeLobbyShape shape = HomeLobbyShape.cuboid,
    ]) {
      boxes.add(
        HomeLobbyBox(
          'ecosystem_$name',
          x: x,
          y: y,
          z: z,
          width: width,
          height: height,
          depth: depth,
          finish: finish,
          shape: shape,
          color: color,
          zone: 'promenade',
        ),
      );
    }

    // Entry archway from the Gallery into the Arrival Square (6.8 m portal).
    const galleryOuterX = 4.9;
    const entryPierWidth = galleryOuterX - entryHalfWidth;
    const entryPierX = (galleryOuterX + entryHalfWidth) / 2;
    pBox('entry_left', -entryPierX, 2.3, entryZ, entryPierWidth, 4.6, .2);
    pBox('entry_right', entryPierX, 2.3, entryZ, entryPierWidth, 4.6, .2);
    pBox(
      'entry_lintel',
      0,
      3.95,
      entryZ,
      entryHalfWidth * 2,
      1.3,
      .2,
      HomeLobbyFinish.oak,
    );
    for (final side in const [-1.0, 1.0]) {
      pBox(
        'entry_wing_$side',
        side * (plazaHalfWidth + galleryOuterX) / 2,
        2.3,
        entryZ,
        plazaHalfWidth - galleryOuterX,
        4.6,
        .2,
        HomeLobbyFinish.plaster,
        0xFFE6DFD0,
      );
    }

    // Central N-S Plaza floor & sky canopy + East/West lateral wing floors & sky.
    const plazaCenterZ = (entryZ + endZ) / 2;
    const plazaLength = endZ - entryZ;
    pBox(
      'corridor_floor',
      0,
      -.12,
      plazaCenterZ,
      plazaHalfWidth * 2,
      .24,
      plazaLength,
      HomeLobbyFinish.stone,
      0xFFD9D3C6,
    );
    pBox(
      'atrium_sky',
      0,
      8.8,
      plazaCenterZ,
      wingEnd * 2,
      .1,
      plazaLength + 4,
      HomeLobbyFinish.plaster,
      0xFFB8D9E5,
    );
    final wingLength = wingEnd - plazaHalfWidth;
    for (final side in const [-1.0, 1.0]) {
      final wingCenterX = side * (plazaHalfWidth + wingLength / 2);
      pBox(
        'wing_floor_$side',
        wingCenterX,
        -.12,
        cruciformCenterZ,
        wingLength,
        .24,
        cruciformHalfWidth * 2,
        HomeLobbyFinish.stone,
        0xFFE2DDD0,
      );
      // Monumental triumphal arch header framing each lateral wing at x = ±15 m.
      pBox(
        'wing_arch_header_$side',
        side * plazaHalfWidth,
        6.2,
        cruciformCenterZ,
        .36,
        3.2,
        cruciformHalfWidth * 2,
        HomeLobbyFinish.oak,
        0xFFAA9270,
      );
      for (var rib = 0; rib <= numBays; rib++) {
        final rx = side * (plazaHalfWidth + 6.0 + rib * 12.5);
        if (rx.abs() < wingEnd) {
          pBox(
            'wing_skylight_beam_${side}_$rib',
            rx,
            7.4,
            cruciformCenterZ,
            .26,
            .28,
            cruciformHalfWidth * 2,
            HomeLobbyFinish.oak,
            0xFFAA9270,
          );
        }
      }
    }

    // Central Octagonal Compass Medallion at (0, 36.0) — walkable zero-height inlay.
    pBox(
      'cruciform_compass_outer',
      0,
      .007,
      cruciformCenterZ,
      9.4,
      .014,
      9.4,
      HomeLobbyFinish.trim,
      0xFFB59A72,
      HomeLobbyShape.cylinder,
    );
    pBox(
      'cruciform_compass_inner',
      0,
      .013,
      cruciformCenterZ,
      6.2,
      .014,
      6.2,
      HomeLobbyFinish.stone,
      0xFFF2ECE1,
      HomeLobbyShape.cylinder,
    );
    pBox(
      'cruciform_compass_star',
      0,
      .019,
      cruciformCenterZ,
      2.4,
      .014,
      2.4,
      HomeLobbyFinish.trim,
      0xFF0D9488,
      HomeLobbyShape.cylinder,
    );
    // Overhead Cupola Crown Ring above the Central Crossroads (0, 36.0).
    pBox(
      'cruciform_dome_ring',
      0,
      8.1,
      cruciformCenterZ,
      16.0,
      .38,
      16.0,
      HomeLobbyFinish.oak,
      0xFFC9A66B,
      HomeLobbyShape.cylinder,
    );
    for (final z in const [18.0, 27.5, 45.0, 56.5]) {
      pBox(
        'atrium_beam_$z',
        0,
        7.8,
        z,
        plazaHalfWidth * 2,
        .28,
        .24,
        HomeLobbyFinish.oak,
        0xFFAA9270,
      );
    }

    // Build distributed slot table around all 4 wings (Norte, Oeste, Este, Sur).
    final slots = <(HomePortalFacing, double, double)>[
      (HomePortalFacing.west, -plazaHalfWidth, 22.0),
      (HomePortalFacing.east, plazaHalfWidth, 22.0),
      for (var b = 0; b < numBays; b++) ...[
        (HomePortalFacing.north, wingMinZ, -(36.0 + b * 12.5)),
        (HomePortalFacing.north, wingMinZ, 36.0 + b * 12.5),
        (HomePortalFacing.south, wingMaxZ, -(36.0 + b * 12.5)),
        (HomePortalFacing.south, wingMaxZ, 36.0 + b * 12.5),
      ],
      (HomePortalFacing.west, -plazaHalfWidth, 51.0),
      (HomePortalFacing.east, plazaHalfWidth, 51.0),
      (HomePortalFacing.west, -wingEnd, cruciformCenterZ),
      (HomePortalFacing.east, wingEnd, cruciformCenterZ),
      (HomePortalFacing.south, endZ, -9.2),
      (HomePortalFacing.south, endZ, 9.2),
    ];

    // Ensure any avatar showcase room lands on an East/West slot so HomeShowcase
    // keeps its exact orientation invariants.
    final orderedRooms = [...supplied];
    final assignedSlots = <(HomePortalFacing, double, double)>[];
    final availableSlots = [...slots];
    for (final room in orderedRooms) {
      if (room.purpose == VrHomeRoomPurpose.avatar) {
        final ewIndex = availableSlots.indexWhere(
          (s) => s.$1 == HomePortalFacing.east || s.$1 == HomePortalFacing.west,
        );
        assignedSlots.add(
          availableSlots.removeAt(ewIndex >= 0 ? ewIndex : 0),
        );
      } else {
        assignedSlots.add(availableSlots.removeAt(0));
      }
    }

    final portals = <HomeEcosystemPortal>[];
    for (var i = 0; i < orderedRooms.length; i++) {
      final (facing, wallCoord, alongCoord) = assignedSlots[i];
      portals.add(
        appendStorefrontRoom(
          room: orderedRooms[i],
          facing: facing,
          wallCoord: wallCoord,
          alongCoord: alongCoord,
          spaces: spaces,
          boxes: boxes,
        ),
      );
    }

    // Seal all 10 perimeter segments around the Cruciform Plaza & Lateral Wings.
    List<(double, double)> portalSpansWhere(
      bool Function(HomeEcosystemPortal) predicate,
    ) => [
      for (final p in portals.where(predicate))
        p.isNorthSouth
            ? (p.wallCenterX - p.roomHalfFrontage, p.wallCenterX + p.roomHalfFrontage)
            : (p.z - p.roomHalfFrontage, p.z + p.roomHalfFrontage),
    ];

    fillWallSegments(
      boxes: boxes,
      prefix: 'corridor_west',
      alongX: false,
      fixedCoord: -plazaHalfWidth,
      start: entryZ,
      end: endZ,
      openings: [
        (wingMinZ, wingMaxZ),
        ...portalSpansWhere(
          (p) =>
              p.facing == HomePortalFacing.west &&
              (p.doorX + plazaHalfWidth).abs() < 0.05,
        ),
      ],
      color: 0xFFE6DFD0,
    );
    fillWallSegments(
      boxes: boxes,
      prefix: 'corridor_east',
      alongX: false,
      fixedCoord: plazaHalfWidth,
      start: entryZ,
      end: endZ,
      openings: [
        (wingMinZ, wingMaxZ),
        ...portalSpansWhere(
          (p) =>
              p.facing == HomePortalFacing.east &&
              (p.doorX - plazaHalfWidth).abs() < 0.05,
        ),
      ],
      color: 0xFFE6DFD0,
    );
    fillWallSegments(
      boxes: boxes,
      prefix: 'corridor_south',
      alongX: true,
      fixedCoord: endZ,
      start: -plazaHalfWidth,
      end: plazaHalfWidth,
      openings: portalSpansWhere(
        (p) =>
            p.facing == HomePortalFacing.south && (p.doorZ - endZ).abs() < 0.05,
      ),
      height: 8.4,
      color: 0xFFE6DFD0,
    );
    pBox(
      'end_inset',
      0,
      3.4,
      endZ - .12,
      6.4,
      3.2,
      .08,
      HomeLobbyFinish.trim,
      0xFF7C9489,
    );

    fillWallSegments(
      boxes: boxes,
      prefix: 'west_wing_north',
      alongX: true,
      fixedCoord: wingMinZ,
      start: -wingEnd,
      end: -plazaHalfWidth,
      openings: portalSpansWhere(
        (p) => p.facing == HomePortalFacing.north && p.wallCenterX < 0,
      ),
      color: 0xFFE6DFD0,
    );
    fillWallSegments(
      boxes: boxes,
      prefix: 'west_wing_south',
      alongX: true,
      fixedCoord: wingMaxZ,
      start: -wingEnd,
      end: -plazaHalfWidth,
      openings: portalSpansWhere(
        (p) => p.facing == HomePortalFacing.south && (p.doorZ - wingMaxZ).abs() < 0.05 && p.wallCenterX < 0,
      ),
      color: 0xFFE6DFD0,
    );
    fillWallSegments(
      boxes: boxes,
      prefix: 'west_wing_end',
      alongX: false,
      fixedCoord: -wingEnd,
      start: wingMinZ,
      end: wingMaxZ,
      openings: portalSpansWhere(
        (p) =>
            p.facing == HomePortalFacing.west &&
            (p.doorX + wingEnd).abs() < 0.05,
      ),
      color: 0xFFE6DFD0,
    );

    fillWallSegments(
      boxes: boxes,
      prefix: 'east_wing_north',
      alongX: true,
      fixedCoord: wingMinZ,
      start: plazaHalfWidth,
      end: wingEnd,
      openings: portalSpansWhere(
        (p) => p.facing == HomePortalFacing.north && p.wallCenterX > 0,
      ),
      color: 0xFFE6DFD0,
    );
    fillWallSegments(
      boxes: boxes,
      prefix: 'east_wing_south',
      alongX: true,
      fixedCoord: wingMaxZ,
      start: plazaHalfWidth,
      end: wingEnd,
      openings: portalSpansWhere(
        (p) => p.facing == HomePortalFacing.south && (p.doorZ - wingMaxZ).abs() < 0.05 && p.wallCenterX > 0,
      ),
      color: 0xFFE6DFD0,
    );
    fillWallSegments(
      boxes: boxes,
      prefix: 'east_wing_end',
      alongX: false,
      fixedCoord: wingEnd,
      start: wingMinZ,
      end: wingMaxZ,
      openings: portalSpansWhere(
        (p) =>
            p.facing == HomePortalFacing.east &&
            (p.doorX - wingEnd).abs() < 0.05,
      ),
      color: 0xFFE6DFD0,
    );

    // Sculpted garden planters in the 4 colonnade courts (keeping all exhibit
    // kiosks and crosswalks 100% clear).
    final gardenCoords = <(String, double, double)>[
      ('north_w', -7.6, 16.5),
      ('north_e', 7.6, 16.5),
      ('south_w', -7.6, 57.5),
      ('south_e', 7.6, 57.5),
      ('west_court', -22.5, cruciformCenterZ),
      ('east_court', 22.5, cruciformCenterZ),
    ];
    for (final (id, gx, gz) in gardenCoords) {
      pBox(
        'planter_$id',
        gx,
        .29,
        gz,
        2.0,
        .58,
        2.2,
        HomeLobbyFinish.stone,
        0xFFB5AA96,
        HomeLobbyShape.beveledBox,
      );
      pBox(
        'planter_rim_$id',
        gx,
        .6,
        gz,
        2.12,
        .12,
        2.32,
        HomeLobbyFinish.trim,
        0xFFD6C8AF,
        HomeLobbyShape.beveledBox,
      );
      if (worldObjects == null) {
        objects.add(
          HomeWorldObjects.placeTree(
            id: 'tree_$id',
            x: gx,
            z: gz,
            mirrored: gx < 0,
          ),
        );
      }
    }
    for (final entity in objects.entities) {
      boxes.addAll(HomeWorldObjects.boxesFor(entity));
    }

    final waypoints = <HomeLobbyWaypoint>[
      ...HomeLobbyLayout.waypoints,
      const HomeLobbyWaypoint(
        'mall_arrival',
        'Plaza Norte de Bienvenida',
        0,
        18.0,
        roomId: 'ecosystem_corridor',
      ),
      const HomeLobbyWaypoint(
        'mall_crucero_central',
        'Gran Crucero Central (4 Alas)',
        0,
        cruciformCenterZ,
        roomId: 'ecosystem_corridor',
      ),
      const HomeLobbyWaypoint(
        'mall_west_wing',
        'Ala Oeste',
        -28.5,
        cruciformCenterZ,
        roomId: 'ecosystem_west_wing',
      ),
      const HomeLobbyWaypoint(
        'mall_east_wing',
        'Ala Este',
        28.5,
        cruciformCenterZ,
        roomId: 'ecosystem_east_wing',
      ),
      for (final portal in portals)
        HomeLobbyWaypoint(
          'portal_${portal.room.id}',
          portal.room.title,
          portal.standingX,
          portal.standingZ,
          roomId: portal.floor.id,
        ),
      const HomeLobbyWaypoint(
        'mall_rotunda',
        'Atrio Sur · Portal OpenWorld',
        0,
        56.5,
        roomId: 'ecosystem_corridor',
      ),
    ];

    return HomeEcosystemLayout._(
      spaces,
      boxes,
      portals,
      objects.entities,
      waypoints,
    );
  }

  HomeEcosystemLayout._(
    Iterable<HomeRoom> rooms,
    Iterable<HomeLobbyBox> boxes,
    Iterable<HomeEcosystemPortal> portals,
    Iterable<VrWorldEntity> worldObjects,
    Iterable<HomeLobbyWaypoint> waypoints,
  ) : rooms = List.unmodifiable(rooms),
      boxes = List.unmodifiable(boxes),
      portals = List.unmodifiable(portals),
      worldObjects = List.unmodifiable(worldObjects),
      waypoints = List.unmodifiable(waypoints);

  final List<HomeRoom> rooms;
  final List<HomeLobbyBox> boxes;
  final List<HomeEcosystemPortal> portals;
  final List<VrWorldEntity> worldObjects;
  final List<HomeLobbyWaypoint> waypoints;
}
