import 'package:vrlizate_world/vrlizate_world.dart';

import '../ecosystem/vr_home_ecosystem_room.dart';
import 'home_ecosystem_layout.dart';
import 'home_lobby_layout.dart';
import 'home_world_objects.dart';

/// Architectural digital-twin archetypes of iconic world & Mexican plazas/malls.
enum FamousMallArchetype {
  /// Galleria Vittorio Emanuele II (Milán) — Cruciform vaulted arcade &
  /// central octagonal glass cupola (`Ottagono`).
  galleriaMilano,

  /// Plaza Artz & Antara (México) — Open-air central park, reflecting water
  /// mirrors, trees, and cantilevered basalt-and-oak terraces.
  plazaArtzMexico,

  /// The Dubai Mall Grand Atrium (Dubái) — Monumental central indoor cascading
  /// waterfall cylinder, alabaster colonnades, and gold coffered ceiling.
  dubaiGrandAtrium,

  /// The Shoppes at Marina Bay Sands (Singapur) — Curved steel-and-glass
  /// skylight pavilion over an indoor turquoise canal with pedestrian bridges.
  marinaCanalShoppes,
}

/// Builds a compact, 360°-distributed `36 m × 36 m` Grand Plaza (`max ~22.5 m`
/// walk from center to any corner booth) where up to 16 storefronts surround
/// the visitor on all 4 cardinal sides (`Norte, Este, Oeste, Sur`).
abstract final class HomeFamousMallLayout {
  static const double plazaHalfSize = 18.0;
  static const double boothDepth = 10.8;
  static const double boothHalfFrontage = 4.5;
  static const double spawnX = 0.0;
  static const double spawnZ = 9.2;

  static HomeEcosystemLayout build({
    required FamousMallArchetype archetype,
    required String mallTitle,
    required List<VrHomeEcosystemRoom> booths,
  }) {
    if (booths.isEmpty || booths.length > 16) {
      throw ArgumentError(
        'FamousMallLayout expects between 1 and 16 booths (got ${booths.length}).',
      );
    }
    final ids = <String>{};
    for (final booth in booths) {
      if (booth.id.isEmpty || !ids.add(booth.id)) {
        throw ArgumentError('Famous mall booths require unique, nonempty IDs.');
      }
    }

    final objects = VrWorldRegistry(
      world: HomeWorldObjects.world,
      maxEntities: 128,
    );
    final spaces = <HomeRoom>[
      HomeRoom(
        'ecosystem_corridor',
        mallTitle,
        -plazaHalfSize,
        plazaHalfSize,
        -plazaHalfSize,
        plazaHalfSize,
      ),
    ];
    final boxes = <HomeLobbyBox>[];

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

    final palette = _paletteFor(archetype);

    // Base plaza stone floor & sunlit overhead sky canopy.
    pBox(
      'corridor_floor',
      0,
      -.12,
      0,
      plazaHalfSize * 2,
      .24,
      plazaHalfSize * 2,
      HomeLobbyFinish.stone,
      palette.floorColor,
    );
    pBox(
      'directory_kiosk_base',
      -3.4,
      .36,
      9.4,
      1.0,
      .72,
      1.0,
      HomeLobbyFinish.oak,
      palette.trimColor,
    );
    pBox(
      'atrium_sky',
      0,
      palette.skyHeight,
      0,
      (plazaHalfSize + boothDepth) * 2,
      .12,
      (plazaHalfSize + boothDepth) * 2,
      HomeLobbyFinish.plaster,
      palette.skyColor,
    );

    // Upper clerestory drum & corner architectural piers framing the 36x36 plaza.
    const upperWallY = 7.4;
    const upperWallH = 5.5;
    for (final sign in const [-1.0, 1.0]) {
      pBox(
        'upper_north_south_$sign',
        0,
        upperWallY,
        sign * plazaHalfSize,
        plazaHalfSize * 2 + .4,
        upperWallH,
        .26,
        HomeLobbyFinish.plaster,
        palette.upperWallColor,
      );
      pBox(
        'upper_east_west_$sign',
        sign * plazaHalfSize,
        upperWallY,
        0,
        .26,
        upperWallH,
        plazaHalfSize * 2 + .4,
        HomeLobbyFinish.plaster,
        palette.upperWallColor,
      );
      pBox(
        'cornice_ns_$sign',
        0,
        4.72,
        sign * (plazaHalfSize - .35),
        plazaHalfSize * 2,
        .22,
        .7,
        HomeLobbyFinish.oak,
        palette.trimColor,
      );
      pBox(
        'cornice_ew_$sign',
        sign * (plazaHalfSize - .35),
        4.72,
        0,
        .7,
        .22,
        plazaHalfSize * 2,
        HomeLobbyFinish.oak,
        palette.trimColor,
      );
    }
    for (final sx in const [-1.0, 1.0]) {
      for (final sz in const [-1.0, 1.0]) {
        pBox(
          'corner_pier_${sx}_$sz',
          sx * (plazaHalfSize - .25),
          5.0,
          sz * (plazaHalfSize - .25),
          .65,
          10.0,
          .65,
          HomeLobbyFinish.oak,
          palette.trimColor,
        );
      }
    }

    // Build archetype-specific iconic central landmark & roof architecture.
    _buildArchetypeLandmark(archetype, pBox, objects);

    // 16 symmetric slots around the 4 cardinal plaza facades (4 per wing).
    const wingCenters = [-13.5, -4.5, 4.5, 13.5];
    final slotDefs = <(HomePortalFacing, double, double)>[
      for (final x in wingCenters) (HomePortalFacing.north, -plazaHalfSize, x),
      for (final z in wingCenters) (HomePortalFacing.east, plazaHalfSize, z),
      for (final z in wingCenters) (HomePortalFacing.west, -plazaHalfSize, z),
      for (final x in wingCenters) (HomePortalFacing.south, plazaHalfSize, x),
    ];

    final portals = <HomeEcosystemPortal>[];
    for (var i = 0; i < booths.length; i++) {
      final (facing, wallCoord, alongCoord) = slotDefs[i];
      portals.add(
        HomeEcosystemLayout.appendStorefrontRoom(
          room: booths[i],
          facing: facing,
          wallCoord: wallCoord,
          alongCoord: alongCoord,
          spaces: spaces,
          boxes: boxes,
          actualRoomDepth: boothDepth,
          actualHalfFrontage: boothHalfFrontage,
        ),
      );
    }

    // Seal any unoccupied facade slots if fewer than 16 booths were supplied.
    List<(double, double)> spansFor(HomePortalFacing facing) => [
      for (final p in portals.where((p) => p.facing == facing))
        p.isNorthSouth
            ? (
                p.wallCenterX - p.roomHalfFrontage,
                p.wallCenterX + p.roomHalfFrontage,
              )
            : (p.z - p.roomHalfFrontage, p.z + p.roomHalfFrontage),
    ];
    HomeEcosystemLayout.fillWallSegments(
      boxes: boxes,
      prefix: 'famous_north_seal',
      alongX: true,
      fixedCoord: -plazaHalfSize,
      start: -plazaHalfSize,
      end: plazaHalfSize,
      openings: spansFor(HomePortalFacing.north),
      color: palette.upperWallColor,
    );
    HomeEcosystemLayout.fillWallSegments(
      boxes: boxes,
      prefix: 'famous_south_seal',
      alongX: true,
      fixedCoord: plazaHalfSize,
      start: -plazaHalfSize,
      end: plazaHalfSize,
      openings: spansFor(HomePortalFacing.south),
      color: palette.upperWallColor,
    );
    HomeEcosystemLayout.fillWallSegments(
      boxes: boxes,
      prefix: 'famous_west_seal',
      alongX: false,
      fixedCoord: -plazaHalfSize,
      start: -plazaHalfSize,
      end: plazaHalfSize,
      openings: spansFor(HomePortalFacing.west),
      color: palette.upperWallColor,
    );
    HomeEcosystemLayout.fillWallSegments(
      boxes: boxes,
      prefix: 'famous_east_seal',
      alongX: false,
      fixedCoord: plazaHalfSize,
      start: -plazaHalfSize,
      end: plazaHalfSize,
      openings: spansFor(HomePortalFacing.east),
      color: palette.upperWallColor,
    );

    for (final entity in objects.entities) {
      boxes.addAll(HomeWorldObjects.boxesFor(entity));
    }

    final waypoints = <HomeLobbyWaypoint>[
      const HomeLobbyWaypoint(
        'center',
        'Paseo Central de la Plaza',
        spawnX,
        spawnZ,
        roomId: 'ecosystem_corridor',
      ),
      const HomeLobbyWaypoint(
        'wing_north',
        'Ala Norte',
        0,
        -12.5,
        roomId: 'ecosystem_corridor',
      ),
      const HomeLobbyWaypoint(
        'wing_east',
        'Ala Este',
        12.5,
        0,
        roomId: 'ecosystem_corridor',
      ),
      const HomeLobbyWaypoint(
        'wing_west',
        'Ala Oeste',
        -12.5,
        0,
        roomId: 'ecosystem_corridor',
      ),
      const HomeLobbyWaypoint(
        'wing_south',
        'Ala Sur',
        0,
        12.5,
        roomId: 'ecosystem_corridor',
      ),
      for (final portal in portals)
        HomeLobbyWaypoint(
          'portal_${portal.room.id}',
          portal.room.title,
          portal.standingX,
          portal.standingZ,
          roomId: portal.floor.id,
        ),
    ];

    return HomeEcosystemLayout.custom(
      rooms: spaces,
      boxes: boxes,
      portals: portals,
      worldObjects: objects.entities,
      waypoints: waypoints,
    );
  }

  static void _buildArchetypeLandmark(
    FamousMallArchetype archetype,
    void Function(
      String,
      double,
      double,
      double,
      double,
      double,
      double, [
      HomeLobbyFinish,
      int?,
      HomeLobbyShape,
    ])
    pBox,
    VrWorldRegistry objects,
  ) {
    switch (archetype) {
      case FamousMallArchetype.galleriaMilano:
        // Galleria Vittorio Emanuele II: walkable central mosaic Ottagono +
        // 8 Neo-Renaissance triumphal arch piers + gilded octagonal dome.
        pBox(
          'milano_mosaic_outer',
          0,
          .007,
          0,
          12.4,
          .014,
          12.4,
          HomeLobbyFinish.trim,
          0xFFC69C53,
          HomeLobbyShape.cylinder,
        );
        pBox(
          'milano_mosaic_inner',
          0,
          .013,
          0,
          8.6,
          .014,
          8.6,
          HomeLobbyFinish.stone,
          0xFFF7F1E3,
          HomeLobbyShape.cylinder,
        );
        pBox(
          'milano_mosaic_crest',
          0,
          .019,
          0,
          3.4,
          .014,
          3.4,
          HomeLobbyFinish.trim,
          0xFF991B1B,
          HomeLobbyShape.cylinder,
        );
        for (final sx in const [-1.0, 1.0]) {
          for (final sz in const [-1.0, 1.0]) {
            pBox(
              'milano_arch_pier_a_${sx}_$sz',
              sx * 6.4,
              4.4,
              sz * 11.2,
              .78,
              8.8,
              .78,
              HomeLobbyFinish.plaster,
              0xFFEFE6D5,
              HomeLobbyShape.beveledBox,
            );
            pBox(
              'milano_arch_pier_b_${sx}_$sz',
              sx * 11.2,
              4.4,
              sz * 6.4,
              .78,
              8.8,
              .78,
              HomeLobbyFinish.plaster,
              0xFFEFE6D5,
              HomeLobbyShape.beveledBox,
            );
          }
        }
        pBox(
          'milano_dome_drum',
          0,
          9.4,
          0,
          18.5,
          .45,
          18.5,
          HomeLobbyFinish.oak,
          0xFFD4AF37,
          HomeLobbyShape.cylinder,
        );
        pBox(
          'milano_dome_lantern',
          0,
          10.7,
          0,
          9.5,
          .45,
          9.5,
          HomeLobbyFinish.trim,
          0xFFFDE68A,
          HomeLobbyShape.cylinder,
        );
        for (var i = 0; i < 4; i++) {
          final alongX = i.isEven;
          final offset = (i < 2 ? -1.0 : 1.0) * 4.8;
          pBox(
            'milano_vault_rib_$i',
            alongX ? 0 : offset,
            9.9,
            alongX ? offset : 0,
            alongX ? 34.0 : .28,
            .32,
            alongX ? .28 : 34.0,
            HomeLobbyFinish.oak,
            0xFFB8860B,
          );
        }

      case FamousMallArchetype.plazaArtzMexico:
        // Plaza Artz / Antara (CDMX / Guadalajara): walkable flush reflecting
        // glass-deck water mirrors + 4 corner garden trees leaving a massive,
        // obstacle-free central park court under cantilevered oak pergolas.
        for (final side in const [-1.0, 1.0]) {
          pBox(
            'artz_water_curb_$side',
            side * 5.2,
            .008,
            0,
            3.6,
            .016,
            6.8,
            HomeLobbyFinish.stone,
            0xFF334155,
          );
          pBox(
            'artz_water_mirror_$side',
            side * 5.2,
            .016,
            0,
            3.1,
            .012,
            6.3,
            HomeLobbyFinish.trim,
            0xFF0EA5E9,
          );
          for (final zSide in const [-1.0, 1.0]) {
            final gx = side * 11.4;
            final gz = zSide * 11.4;
            pBox(
              'artz_planter_${side}_$zSide',
              gx,
              .32,
              gz,
              2.0,
              .64,
              2.0,
              HomeLobbyFinish.stone,
              0xFF475569,
              HomeLobbyShape.beveledBox,
            );
            objects.add(
              HomeWorldObjects.placeTree(
                id: 'artz_tree_${side}_$zSide',
                x: gx,
                z: gz,
                mirrored: side < 0,
              ),
            );
          }
        }
        // Cantilevered Sordo Madaleno oak & basalt perimeter pergolas.
        for (final sign in const [-1.0, 1.0]) {
          pBox(
            'artz_pergola_ns_$sign',
            0,
            4.95,
            sign * (plazaHalfSize - 2.2),
            plazaHalfSize * 2,
            .24,
            4.2,
            HomeLobbyFinish.oak,
            0xFF8B5A2B,
          );
          pBox(
            'artz_pergola_ew_$sign',
            sign * (plazaHalfSize - 2.2),
            4.95,
            0,
            4.2,
            .24,
            plazaHalfSize * 2 - 8.4,
            HomeLobbyFinish.oak,
            0xFF8B5A2B,
          );
        }

      case FamousMallArchetype.dubaiGrandAtrium:
        // The Dubai Mall Grand Atrium: sleek sculpted central cascading
        // waterfall column with wide open promenades all around it.
        pBox(
          'dubai_fountain_basin',
          0,
          .24,
          0,
          3.4,
          .48,
          3.4,
          HomeLobbyFinish.stone,
          0xFFF8FAFC,
          HomeLobbyShape.cylinder,
        );
        pBox(
          'dubai_fountain_water',
          0,
          .50,
          0,
          2.9,
          .06,
          2.9,
          HomeLobbyFinish.trim,
          0xFF38BDF8,
          HomeLobbyShape.cylinder,
        );
        pBox(
          'dubai_waterfall_cylinder',
          0,
          4.6,
          0,
          1.9,
          8.4,
          1.9,
          HomeLobbyFinish.trim,
          0xFF0284C7,
          HomeLobbyShape.cylinder,
        );
        pBox(
          'dubai_waterfall_crown',
          0,
          8.9,
          0,
          3.8,
          .42,
          3.8,
          HomeLobbyFinish.oak,
          0xFFD4AF37,
          HomeLobbyShape.cylinder,
        );
        for (final sx in const [-1.0, 1.0]) {
          for (final sz in const [-1.0, 1.0]) {
            pBox(
              'dubai_diver_sculpture_${sx}_$sz',
              sx * 1.25,
              4.2,
              sz * 1.25,
              .22,
              1.45,
              .22,
              HomeLobbyFinish.plaster,
              0xFFF1F5F9,
              HomeLobbyShape.ellipsoid,
            );
            pBox(
              'dubai_gold_column_${sx}_$sz',
              sx * 11.2,
              5.1,
              sz * 11.2,
              .74,
              10.2,
              .74,
              HomeLobbyFinish.oak,
              0xFFE5C158,
              HomeLobbyShape.cylinder,
            );
          }
        }
        pBox(
          'dubai_chandelier_ring',
          0,
          9.6,
          0,
          14.5,
          .3,
          14.5,
          HomeLobbyFinish.trim,
          0xFFFDE047,
          HomeLobbyShape.cylinder,
        );

      case FamousMallArchetype.marinaCanalShoppes:
        // Marina Bay Sands Canal Shoppes: walkable glass-skywalk Rain Oculus
        // & glowing turquoise indoor canals — zero blocking curbs across center.
        pBox(
          'marina_oculus_basin',
          0,
          .008,
          0,
          4.4,
          .016,
          4.4,
          HomeLobbyFinish.stone,
          0xFFE2E8F0,
          HomeLobbyShape.cylinder,
        );
        pBox(
          'marina_oculus_water',
          0,
          .016,
          0,
          3.7,
          .012,
          3.7,
          HomeLobbyFinish.trim,
          0xFF06B6D4,
          HomeLobbyShape.cylinder,
        );
        for (final side in const [-1.0, 1.0]) {
          pBox(
            'marina_canal_curb_$side',
            side * 8.4,
            .007,
            0,
            6.2,
            .014,
            3.4,
            HomeLobbyFinish.stone,
            0xFFCBD5E1,
          );
          pBox(
            'marina_canal_water_$side',
            side * 8.4,
            .014,
            0,
            5.7,
            .012,
            2.9,
            HomeLobbyFinish.trim,
            0xFF22D3EE,
          );
          for (final railSide in const [-1.0, 1.0]) {
            pBox(
              'marina_bridge_deck_${side}_$railSide',
              side * 3.65,
              .018,
              0,
              2.2,
              .014,
              4.0,
              HomeLobbyFinish.oak,
              0xFFC29B61,
            );
          }
        }
        for (var rib = -3; rib <= 3; rib++) {
          pBox(
            'marina_skylight_rib_$rib',
            rib * 4.8,
            9.7,
            0,
            .24,
            .32,
            34.5,
            HomeLobbyFinish.plaster,
            0xFFE0F2FE,
          );
        }
    }
  }

  static ({
    int floorColor,
    int upperWallColor,
    int trimColor,
    int skyColor,
    double skyHeight,
  })
  _paletteFor(FamousMallArchetype archetype) => switch (archetype) {
    FamousMallArchetype.galleriaMilano => (
      floorColor: 0xFFEAE2D3,
      upperWallColor: 0xFFF2E8D5,
      trimColor: 0xFFC59B27,
      skyColor: 0xFFD9ECF5,
      skyHeight: 11.2,
    ),
    FamousMallArchetype.plazaArtzMexico => (
      floorColor: 0xFFD6D3CD,
      upperWallColor: 0xFF57534E,
      trimColor: 0xFF9A6B3B,
      skyColor: 0xFF7DD3FC,
      skyHeight: 12.2,
    ),
    FamousMallArchetype.dubaiGrandAtrium => (
      floorColor: 0xFFF4EFE6,
      upperWallColor: 0xFFFAF5EB,
      trimColor: 0xFFD4AF37,
      skyColor: 0xFFFEF3C7,
      skyHeight: 10.8,
    ),
    FamousMallArchetype.marinaCanalShoppes => (
      floorColor: 0xFFE2E8F0,
      upperWallColor: 0xFFF1F5F9,
      trimColor: 0xFF0EA5E9,
      skyColor: 0xFFBAE6FD,
      skyHeight: 10.4,
    ),
  };
}
