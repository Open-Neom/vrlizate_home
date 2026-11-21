import 'package:vrlizate_world/vrlizate_world.dart';

import '../ecosystem/vr_home_ecosystem_room.dart';
import 'home_ecosystem_layout.dart';
import 'home_lobby_layout.dart';
import 'home_walk_space.dart';
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
      bool walkable = false,
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
          walkable: walkable,
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

    // Build archetype-specific iconic central landmark, multi-elevation Croquis 2
    // bridges/terraces/daises, interactive benches, & roof architecture.
    final elevations = <HomeWalkableElevation>[];
    final seats = <HomeInteractiveSeat>[];
    _buildArchetypeLandmark(archetype, pBox, objects, elevations, seats);

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
      elevations: elevations,
      seats: seats,
    );
  }

  static void _addScenicBench({
    required void Function(
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
      bool,
    ])
    pBox,
    required List<HomeInteractiveSeat> seats,
    required String id,
    required String label,
    required double x,
    required double z,
    required double lookAtX,
    required double lookAtZ,
    required double standUpX,
    required double standUpZ,
    required double backOffsetX,
    required double backOffsetZ,
    required bool alongX,
  }) {
    final seatW = alongX ? 2.4 : 0.70;
    final seatD = alongX ? 0.70 : 2.4;
    pBox(
      '${id}_seat',
      x,
      0.44,
      z,
      seatW,
      0.14,
      seatD,
      HomeLobbyFinish.oak,
      0xFFB28B5E,
      HomeLobbyShape.beveledBox,
    );
    pBox(
      '${id}_back',
      x + backOffsetX,
      0.82,
      z + backOffsetZ,
      alongX ? 2.4 : 0.12,
      0.66,
      alongX ? 0.12 : 2.4,
      HomeLobbyFinish.oak,
      0xFFB28B5E,
      HomeLobbyShape.beveledBox,
    );
    for (final dir in const [-1.0, 1.0]) {
      pBox(
        '${id}_foot_$dir',
        alongX ? x + dir * 0.88 : x,
        0.20,
        alongX ? z : z + dir * 0.88,
        alongX ? 0.14 : 0.50,
        0.40,
        alongX ? 0.50 : 0.14,
        HomeLobbyFinish.trim,
        0xFF756D61,
      );
    }
    seats.add(
      HomeInteractiveSeat(
        id: id,
        label: label,
        x: x,
        z: z,
        lookAtX: lookAtX,
        lookAtZ: lookAtZ,
        standUpX: standUpX,
        standUpZ: standUpZ,
      ),
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
      bool,
    ])
    pBox,
    VrWorldRegistry objects,
    List<HomeWalkableElevation> elevations,
    List<HomeInteractiveSeat> seats,
  ) {
    switch (archetype) {
      case FamousMallArchetype.galleriaMilano:
        // Galleria Vittorio Emanuele II: raised +0.38 m sculpted circular
        // marble Ottagono dais + inlaid mosaic medallion + 8 Neo-Renaissance
        // triumphal arch piers + gilded octagonal dome + café terrace benches.
        const ottagonoY = 0.38;
        elevations.add(
          const HomeWalkableElevation.radialBowl(
            id: 'milano_ottagono_dais',
            centerX: 0,
            centerZ: 0,
            innerRadius: 5.4,
            outerRadius: 8.8,
            centerElevationMeters: ottagonoY,
          ),
        );
        pBox(
          'milano_mosaic_outer',
          0,
          ottagonoY + .007,
          0,
          10.6,
          .014,
          10.6,
          HomeLobbyFinish.trim,
          0xFFC69C53,
          HomeLobbyShape.cylinder,
          true,
        );
        pBox(
          'milano_mosaic_inner',
          0,
          ottagonoY + .013,
          0,
          7.6,
          .014,
          7.6,
          HomeLobbyFinish.stone,
          0xFFF7F1E3,
          HomeLobbyShape.cylinder,
          true,
        );
        pBox(
          'milano_mosaic_crest',
          0,
          ottagonoY + .019,
          0,
          3.2,
          .014,
          3.2,
          HomeLobbyFinish.trim,
          0xFF991B1B,
          HomeLobbyShape.cylinder,
          true,
        );
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'milano_cafe_bench_sw',
          label: 'Terraza Café Ottagono (SO)',
          x: -8.6,
          z: 8.6,
          lookAtX: 0.0,
          lookAtZ: 0.0,
          standUpX: -7.5,
          standUpZ: 7.5,
          backOffsetX: 0.0,
          backOffsetZ: 0.31,
          alongX: true,
        );
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'milano_cafe_bench_ne',
          label: 'Terraza Café Ottagono (NE)',
          x: 8.6,
          z: -8.6,
          lookAtX: 0.0,
          lookAtZ: 0.0,
          standUpX: 7.5,
          standUpZ: -7.5,
          backOffsetX: 0.0,
          backOffsetZ: -0.31,
          alongX: true,
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
        // Plaza Artz / Antara (CDMX / Guadalajara): raised +0.68 m basalt & oak
        // central park deck reached via North/South smooth ramps and East/West
        // open-arch footbridges spanning right over the twin reflecting water
        // mirrors, plus 4 corner garden trees & interactive park benches.
        const artzDeckY = 0.68;
        elevations.addAll(const [
          HomeWalkableElevation.terrace(
            id: 'artz_central_park_deck',
            minX: -2.4,
            maxX: 2.4,
            minZ: -4.2,
            maxZ: 4.2,
            elevationMeters: artzDeckY,
          ),
          HomeWalkableElevation.ramp(
            id: 'artz_ramp_north',
            minX: -2.4,
            maxX: 2.4,
            minZ: -8.2,
            maxZ: -4.2,
            startElevationMeters: 0.0,
            endElevationMeters: artzDeckY,
            axis: HomeElevationAxis.posZ,
          ),
          HomeWalkableElevation.ramp(
            id: 'artz_ramp_south',
            minX: -2.4,
            maxX: 2.4,
            minZ: 4.2,
            maxZ: 8.2,
            startElevationMeters: artzDeckY,
            endElevationMeters: 0.0,
            axis: HomeElevationAxis.posZ,
          ),
          HomeWalkableElevation.ramp(
            id: 'artz_water_bridge_west',
            minX: -8.6,
            maxX: -2.4,
            minZ: -2.0,
            maxZ: 2.0,
            startElevationMeters: 0.0,
            endElevationMeters: artzDeckY,
            axis: HomeElevationAxis.posX,
            archHeightMeters: 0.35,
          ),
          HomeWalkableElevation.ramp(
            id: 'artz_water_bridge_east',
            minX: 2.4,
            maxX: 8.6,
            minZ: -2.0,
            maxZ: 2.0,
            startElevationMeters: artzDeckY,
            endElevationMeters: 0.0,
            axis: HomeElevationAxis.posX,
            archHeightMeters: 0.35,
          ),
        ]);
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
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'artz_park_bench_nw',
          label: 'Banca Jardín Artz (NO)',
          x: -8.6,
          z: -8.2,
          lookAtX: 0.0,
          lookAtZ: 0.0,
          standUpX: -7.6,
          standUpZ: -7.2,
          backOffsetX: 0.0,
          backOffsetZ: -0.31,
          alongX: true,
        );
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'artz_park_bench_se',
          label: 'Banca Jardín Artz (SE)',
          x: 8.6,
          z: 8.2,
          lookAtX: 0.0,
          lookAtZ: 0.0,
          standUpX: 7.6,
          standUpZ: 7.2,
          backOffsetX: 0.0,
          backOffsetZ: 0.31,
          alongX: true,
        );
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
        // The Dubai Mall Grand Atrium: sculpted +0.42 m circular alabaster
        // promenade encircling the cascading central waterfall column +
        // interactive atrium lounge benches.
        const dubaiPromenadeY = 0.42;
        elevations.add(
          const HomeWalkableElevation.radialBowl(
            id: 'dubai_waterfall_promenade',
            centerX: 0,
            centerZ: 0,
            innerRadius: 3.2,
            outerRadius: 7.4,
            centerElevationMeters: dubaiPromenadeY,
          ),
        );
        pBox(
          'dubai_fountain_basin',
          0,
          dubaiPromenadeY + .24,
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
          dubaiPromenadeY + .50,
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
          dubaiPromenadeY + 4.4,
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
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'dubai_atrium_bench_sw',
          label: 'Banca Cascada Atrium (SO)',
          x: -8.6,
          z: 8.2,
          lookAtX: 0.0,
          lookAtZ: 0.0,
          standUpX: -7.6,
          standUpZ: 7.2,
          backOffsetX: 0.0,
          backOffsetZ: 0.31,
          alongX: true,
        );
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'dubai_atrium_bench_ne',
          label: 'Banca Cascada Atrium (NE)',
          x: 8.6,
          z: -8.2,
          lookAtX: 0.0,
          lookAtZ: 0.0,
          standUpX: 7.6,
          standUpZ: -7.2,
          backOffsetX: 0.0,
          backOffsetZ: -0.31,
          alongX: true,
        );

      case FamousMallArchetype.marinaCanalShoppes:
        // Croquis 2 — Marina Bay Sands / Venetian Canal Arcades:
        // +0.55 m sculpted central Rain Oculus skywalk dais + TWO open-arch
        // +1.25 m Venetian pedestrian bridges arching right over the glowing
        // turquoise indoor canals so water reflects clearly beneath them, plus
        // canal-side café benches.
        const oculusY = 0.55;
        elevations.addAll(const [
          HomeWalkableElevation.radialBowl(
            id: 'marina_rain_oculus_skywalk',
            centerX: 0,
            centerZ: 0,
            innerRadius: 2.3,
            outerRadius: 5.4,
            centerElevationMeters: oculusY,
          ),
          HomeWalkableElevation.ramp(
            id: 'marina_arched_bridge_west',
            minX: -9.8,
            maxX: -6.8,
            minZ: -5.2,
            maxZ: 5.2,
            startElevationMeters: 0.0,
            endElevationMeters: 0.0,
            axis: HomeElevationAxis.posZ,
            archHeightMeters: 1.25,
          ),
          HomeWalkableElevation.ramp(
            id: 'marina_arched_bridge_east',
            minX: 6.8,
            maxX: 9.8,
            minZ: -5.2,
            maxZ: 5.2,
            startElevationMeters: 0.0,
            endElevationMeters: 0.0,
            axis: HomeElevationAxis.posZ,
            archHeightMeters: 1.25,
          ),
        ]);
        pBox(
          'marina_oculus_basin',
          0,
          oculusY + .008,
          0,
          4.4,
          .016,
          4.4,
          HomeLobbyFinish.stone,
          0xFFE2E8F0,
          HomeLobbyShape.cylinder,
          true,
        );
        pBox(
          'marina_oculus_water',
          0,
          oculusY + .016,
          0,
          3.7,
          .012,
          3.7,
          HomeLobbyFinish.trim,
          0xFF06B6D4,
          HomeLobbyShape.cylinder,
          true,
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
          // Warm oak abutment lanterns framing both ends of each arched bridge.
          for (final endSign in const [-1.0, 1.0]) {
            pBox(
              'marina_bridge_lamp_post_${side}_$endSign',
              side * 10.1,
              1.10,
              endSign * 5.05,
              .18,
              2.20,
              .18,
              HomeLobbyFinish.oak,
              0xFFB28B5E,
              HomeLobbyShape.cylinder,
            );
            pBox(
              'marina_bridge_lamp_globe_${side}_$endSign',
              side * 10.1,
              2.32,
              endSign * 5.05,
              .30,
              .30,
              .30,
              HomeLobbyFinish.trim,
              0xFFFFE7A8,
              HomeLobbyShape.ellipsoid,
            );
          }
        }
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'marina_canal_bench_nw',
          label: 'Banca Paseo del Canal (NO)',
          x: -8.3,
          z: -8.2,
          lookAtX: -8.3,
          lookAtZ: 0.0,
          standUpX: -8.3,
          standUpZ: -7.0,
          backOffsetX: 0.0,
          backOffsetZ: -0.31,
          alongX: true,
        );
        _addScenicBench(
          pBox: pBox,
          seats: seats,
          id: 'marina_canal_bench_se',
          label: 'Banca Paseo del Canal (SE)',
          x: 8.3,
          z: 8.2,
          lookAtX: 8.3,
          lookAtZ: 0.0,
          standUpX: 8.3,
          standUpZ: 7.0,
          backOffsetX: 0.0,
          backOffsetZ: 0.31,
          alongX: true,
        );
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
