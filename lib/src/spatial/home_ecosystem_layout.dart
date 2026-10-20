import 'dart:math' as math;

import 'package:vrlizate_world/vrlizate_world.dart';

import '../ecosystem/vr_home_ecosystem_room.dart';
import 'home_lobby_layout.dart';
import 'home_room_identity.dart';
import 'home_world_objects.dart';

/// A real room and its inward-facing, selectable terminal. Dimensions are
/// meters and are shared by rendering, collision and reachability tests.
class HomeEcosystemPortal {
  const HomeEcosystemPortal({
    required this.room,
    required this.floor,
    required this.side,
    required this.z,
  });

  final VrHomeEcosystemRoom room;
  final HomeRoom floor;
  final double side, z;
  double get doorX => side < 0 ? floor.maxX : floor.minX;
  double get outerX => side < 0 ? floor.minX : floor.maxX;
  double get terminalX => outerX - side * .22;
  double get standingX => outerX - side * 2.7;
  double get signX => doorX - side * .45;
  double get roomCenterX => (floor.minX + floor.maxX) / 2;
  double get displayOffset => HomeEcosystemLayout.roomHalfFrontage * .7;
  double get doorHalfWidth => 1.6;
  double get yaw => -side * math.pi / 2;
}

/// A broad public plaza behind the material gallery. Its arrival square, garden
/// islands and side arcades leave several independent walking routes between
/// full-size experience rooms. Rendering and collision share every solid.
/// An empty inventory preserves the original Home exactly.
class HomeEcosystemLayout {
  static const plazaHalfWidth = 12.0;
  static const roomDepth = 9.8;
  static const roomHalfFrontage = 4.0;
  static const rowPitch = 11.0;
  static const firstRowZ = 22.0;
  static const entryZ = 12.5;
  static const arcadeX = 8.5;

  factory HomeEcosystemLayout(
    Iterable<VrHomeEcosystemRoom> rooms, {
    Iterable<VrWorldEntity>? worldObjects,
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
    final endZ = 18.0 + rows * rowPitch;
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

    // The original gallery keeps its doorway. Beyond the lintel the ceiling
    // rises and the floor opens to a 24 m arrival square, not a scaled hallway.
    box('entry_left', -2.55, 2.3, entryZ, 2.7, 4.6, .2);
    box('entry_right', 2.55, 2.3, entryZ, 2.7, 4.6, .2);
    box('entry_lintel', 0, 3.8, entryZ, 2.4, 1.6, .2, HomeLobbyFinish.oak);
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
        side * 7.95,
        2.3,
        entryZ,
        8.1,
        4.6,
        .2,
        HomeLobbyFinish.plaster,
        0xFFE6DFD0,
      );
      box(
        'ceiling_gallery_$side',
        side * 10.65,
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
        side * 9.35,
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
        side * 11.95,
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
        side * 11.8,
        5.05,
        plazaCenterZ,
        .2,
        .18,
        plazaLength,
        HomeLobbyFinish.oak,
        0xFFAA9270,
      );
      for (final x in const [1.9, 7.3, 10.1]) {
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
          side * 11.75,
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
        3.2,
        HomeLobbyFinish.stone,
        0xFFECE4D5,
      );
      for (final direction in const [-1.0, 1.0]) {
        box(
          'crosswalk_edge_${row}_$direction',
          0,
          .015,
          z + direction * 1.64,
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
      zone = 'ecosystem_${room.id}';
      identity = HomeRoomIdentity.forPurpose(room.purpose);
      accent = room.accent;
      final side = i.isEven ? -1.0 : 1.0;
      final z = firstRowZ + (i ~/ 2) * rowPitch;
      final floor = HomeRoom(
        'ecosystem_${room.id}',
        room.title,
        side < 0 ? -(plazaHalfWidth + roomDepth) : plazaHalfWidth,
        side < 0 ? -plazaHalfWidth : plazaHalfWidth + roomDepth,
        z - roomHalfFrontage,
        z + roomHalfFrontage,
      );
      spaces.add(floor);
      portals.add(
        HomeEcosystemPortal(room: room, floor: floor, side: side, z: z),
      );
      final centerX = side * (plazaHalfWidth + roomDepth / 2);
      box(
        '${room.id}_floor',
        centerX,
        -.12,
        z,
        roomDepth,
        .24,
        roomHalfFrontage * 2,
        HomeLobbyFinish.stone,
      );
      box(
        '${room.id}_ceiling',
        centerX,
        4.65,
        z,
        roomDepth,
        .15,
        roomHalfFrontage * 2,
      );
      box(
        '${room.id}_outer_wall',
        side * (plazaHalfWidth + roomDepth),
        2.3,
        z,
        .2,
        4.6,
        roomHalfFrontage * 2,
      );
      box(
        '${room.id}_front_wall',
        centerX,
        2.3,
        z - roomHalfFrontage,
        roomDepth,
        4.6,
        .2,
      );
      box(
        '${room.id}_back_wall',
        centerX,
        2.3,
        z + roomHalfFrontage,
        roomDepth,
        4.6,
        .2,
      );
      box(
        '${room.id}_door_lintel',
        side * plazaHalfWidth,
        3.8,
        z,
        .2,
        1.6,
        3.2,
        HomeLobbyFinish.oak,
      );
      // Preserve each authored room's silhouette, with generous floor area and
      // a 3.2 m entrance. The local furniture coordinates predate the plaza.
      const depthScale = roomDepth / 7.8;
      const frontageScale = roomHalfFrontage / 3;
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
        box(
          '${room.id}_$name',
          side * (plazaHalfWidth + (x - 2.5) * depthScale),
          y,
          z + offset * frontageScale,
          width * depthScale,
          height,
          depth * frontageScale,
          finish,
          color,
          shape,
        );
      }

      // Open display windows above solid sills reveal the room from the walk.
      // They are actual openings; there is no invisible glass collision plane.
      for (final direction in const [-1.0, 1.0]) {
        part(
          'display_sill_$direction',
          2.5,
          .5,
          direction * 2.1,
          .2,
          1,
          1.8,
          HomeLobbyFinish.plaster,
        );
        part(
          'display_header_$direction',
          2.5,
          3.8,
          direction * 2.1,
          .2,
          1.6,
          1.8,
          HomeLobbyFinish.plaster,
        );
        part(
          'door_pillar_$direction',
          2.5,
          1.5,
          direction * 1.28,
          .28,
          3,
          .16,
          HomeLobbyFinish.trim,
          null,
          HomeLobbyShape.cylinder,
        );
        part(
          'display_frame_$direction',
          2.5,
          2,
          direction * 2.91,
          .25,
          2,
          .12,
          HomeLobbyFinish.oak,
        );
        part(
          'window_ledge_$direction',
          2.42,
          1.03,
          direction * 2.13,
          .42,
          .08,
          1.65,
          HomeLobbyFinish.oak,
        );
      }
      part('fascia', 2.35, 3.6, 0, .38, .82, 3.5, HomeLobbyFinish.oak);
      part(
        'canopy',
        2.25,
        3.05, // Separate the underside from the window headers at y=3.0.
        0,
        .8,
        .14,
        3.8,
        HomeLobbyFinish.trim,
        null,
        HomeLobbyShape.beveledBox,
      );
      part('threshold', 3.05, .012, 0, 1.05, .024, 2.3, HomeLobbyFinish.trim);
      part('interior_inlay', 6.4, .009, 0, 5.6, .018, 2.1, HomeLobbyFinish.rug);

      // Distinct silhouettes, kept beside the central approach to the terminal.
      // Static silhouettes share finish textures; no mirrors, transparent
      // glazing or per-frame animation are needed for room identity.
      switch (room.purpose) {
        case VrHomeRoomPurpose.openSourceGames:
          // An arcade/gallery, usable both as one catalog entrance and as a
          // dedicated creator/game room. The host owns the real game content;
          // these static forms never pretend that a runtime has been loaded.
          // Both side displays leave the complete central terminal approach
          // clear, including the authored 3.2 m doorway and panel width.
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
          // A controller sculpture provides a recognizable curved silhouette,
          // even before the host's catalog panel becomes readable.
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
          // A fitting platform beside the route to the room's control panel.
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
          for (final side in const [-1.0, 1.0]) {
            part(
              'avatar_mannequin_arm_$side',
              6.7 + side * .4,
              1.15,
              -2.0,
              .18,
              .82,
              .25,
              HomeLobbyFinish.fabric,
            );
          }
          // Conservative collision envelope for the authored GLB lounge.
          // The world builder replaces this visual with the detailed model.
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
              // Three grouped book spines per shelf, rather than many assets.
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
          // Broad bars give the marquee a film-frame silhouette at low cost.
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
