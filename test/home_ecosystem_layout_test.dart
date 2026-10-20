import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';
import 'package:vrlizate/vrlizate.dart';
import 'package:vrlizate_home/src/spatial/home_room_identity.dart';
import 'package:vrlizate_home/src/spatial/vr_demo_library_model.dart';
import 'package:vrlizate_home/src/spatial/vr_home_input_policy.dart';

void main() {
  test('default rooms have distinct stable host routes and purposes', () {
    expect(VrHomeEcosystemRoom.defaults.map((r) => r.id), [
      'profile',
      'social',
      'creator',
      'emxi',
      'gigmeout',
      'cyberneom',
      'cinema',
      'avatar',
    ]);
    expect(
      VrHomeEcosystemRoom.defaults.map((r) => r.purpose).toSet(),
      VrHomeRoomPurpose.values
          .where(
            (purpose) =>
                purpose != VrHomeRoomPurpose.openSourceGames &&
                purpose != VrHomeRoomPurpose.portableWorld,
          )
          .toSet(),
    );
    expect(() => VrHomeEcosystemRoom.defaults.clear(), throwsUnsupportedError);
  });

  test('opting out preserves every original room and wall', () {
    final layout = HomeEcosystemLayout(const []);
    expect(layout.rooms, HomeLobbyLayout.rooms);
    expect(layout.boxes, HomeLobbyLayout.boxes);
    expect(layout.portals, isEmpty);
    final original = HomeWalkSpace();
    final extension = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
    for (var x = -13.0; x <= 13; x += .5) {
      for (var z = -8.0; z <= 13; z += .5) {
        expect(extension.canStand(x, z), original.canStand(x, z));
      }
    }
  });

  test(
    'walks from original Home through every door to its terminal and back',
    () {
      final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
      final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
      var position = vm.Vector3(0, 1.6, 0);
      void walkTo(double x, double z) {
        for (var step = 0; step < 600; step++) {
          final dx = (x - position.x).clamp(-.1, .1);
          final dz = (z - position.z).clamp(-.1, .1);
          if (dx.abs() + dz.abs() < 1e-6) break;
          position = space.move(position, dx, dz);
          expect(space.canStand(position.x, position.z), isTrue);
        }
        expect(position.x, closeTo(x, 1e-5));
        expect(position.z, closeTo(z, 1e-5));
      }

      walkTo(0, 8);
      // The existing gallery exhibit remains in place: walk around it.
      walkTo(2, 8);
      walkTo(2, 11.7);
      walkTo(0, 11.7);
      for (final portal in layout.portals) {
        walkTo(0, portal.z);
        walkTo(portal.standingX, portal.z);
        expect(space.roomAt(position.x, position.z)?.id, portal.floor.id);
        expect((portal.terminalX - position.x).abs(), lessThan(3));
        walkTo(0, portal.z);
      }
      walkTo(0, 11.7);
      walkTo(2, 11.7);
      walkTo(2, 8);
      walkTo(0, 8);
      walkTo(0, 0);
      expect(space.roomAt(position.x, position.z)?.id, 'lobby');
    },
  );

  test('rooms share visible solid walls and body-clear door openings', () {
    final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
    final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
    expect(space.canStand(0, 12.5), isTrue);
    expect(space.canStand(1.15, 12.5), isFalse);
    for (final portal in layout.portals) {
      expect(space.canStand(portal.doorX, portal.z), isTrue);
      expect(
        space.canStand(portal.doorX, portal.z + portal.doorHalfWidth - .08),
        isFalse,
      );
      expect(space.canStand(portal.outerX, portal.z), isFalse);
      var blocked = vm.Vector3(0, 1.6, portal.z + portal.displayOffset);
      for (var i = 0; i < 30; i++) {
        blocked = space.move(blocked, portal.side * 30, 0);
      }
      expect(blocked.x.abs(), lessThanOrEqualTo(portal.doorX.abs() - .34));
      final lintel = layout.boxes.singleWhere(
        (box) => box.name == 'ecosystem_${portal.room.id}_door_lintel',
      );
      expect(lintel.y - lintel.height / 2, greaterThan(2.5));
    }
  });

  test('custom inventory is copied and an odd row has no phantom doorway', () {
    final supplied = [VrHomeEcosystemRoom.defaults.first];
    final layout = HomeEcosystemLayout(supplied);
    supplied.clear();
    expect(layout.portals.single.room.id, 'profile');
    final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
    final portal = layout.portals.single;
    expect(space.canStand(portal.doorX, portal.z), isTrue);
    expect(space.canStand(-portal.doorX, portal.z), isFalse);
    expect(() => layout.boxes.clear(), throwsUnsupportedError);
    expect(
      () => HomeEcosystemLayout([
        VrHomeEcosystemRoom.defaults.first,
        VrHomeEcosystemRoom.defaults.first,
      ]),
      throwsArgumentError,
    );
  });

  test('each purpose has a visible architectural identity and approach', () {
    final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
    final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
    const landmarks = {
      'profile': 'gallery_console',
      'social': 'sofa_seat_-1.0',
      'creator': 'workbench',
      'emxi': 'bookcase_back_0',
      'gigmeout': 'listening_stage',
      'cyberneom': 'tatami_platform',
      'cinema': 'screen',
      'avatar': 'avatar_platform',
    };
    expect(
      VrHomeRoomPurpose.values
          .map(HomeRoomIdentity.forPurpose)
          .map((identity) => identity.category)
          .toSet(),
      hasLength(VrHomeRoomPurpose.values.length),
    );
    for (final portal in layout.portals) {
      final roomBoxes = layout.boxes
          .where((box) => box.zone == portal.floor.id)
          .toList();
      expect(
        roomBoxes.any(
          (box) =>
              box.name ==
              'ecosystem_${portal.room.id}_${landmarks[portal.room.id]}',
        ),
        isTrue,
      );
      expect(roomBoxes.map((box) => box.color).toSet().length, greaterThan(2));
      expect(
        space.placePanel(
          eye: vm.Vector3(portal.standingX, 1.6, portal.z),
          forward: vm.Vector3(portal.side, 0, 0),
          distance: 3,
        ),
        isNotNull,
        reason: 'Furniture must leave a body-clear modal approach.',
      );
    }
  });

  test('shop windows are visible openings with solid low sills', () {
    final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
    final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
    for (final portal in layout.portals) {
      for (final direction in const [-1.0, 1.0]) {
        final x = portal.doorX;
        final z = portal.z + direction * portal.displayOffset;
        expect(space.canStand(x, z), isFalse);
        final crossesEye = layout.boxes.any(
          (box) =>
              (x - box.x).abs() < box.width / 2 &&
              (z - box.z).abs() < box.depth / 2 &&
              1.6 > box.y - box.height / 2 &&
              1.6 < box.y + box.height / 2,
        );
        expect(crossesEye, isFalse);
      }
    }
    expect(
      layout.boxes.any((box) => box.name == 'ecosystem_atrium_sky'),
      isTrue,
    );
    // Cinema and the avatar studio share the fourth plaza row.
    final cinema = layout.portals.singleWhere(
      (portal) => portal.room.id == 'cinema',
    );
    expect(cinema.room.id, 'cinema');
    expect(cinema.z, 55);
    expect(space.canStand(cinema.doorX, cinema.z), isTrue);
    expect(space.canStand(-cinema.doorX, cinema.z), isTrue);
    for (var z = 14.0; z < 61; z += .2) {
      expect(space.canStand(-1.3, z), isTrue);
      expect(space.canStand(1.3, z), isTrue);
    }
  });

  test(
    'plaza has a large arrival square and three independent walking routes',
    () {
      final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
      final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
      final plaza = layout.rooms.singleWhere(
        (room) => room.id == 'ecosystem_corridor',
      );
      expect(plaza.maxX - plaza.minX, greaterThanOrEqualTo(20));
      expect(
        (plaza.maxX - plaza.minX) * (plaza.maxZ - plaza.minZ),
        greaterThan(1000),
      );
      for (final portal in layout.portals) {
        expect(
          (portal.floor.maxX - portal.floor.minX) *
              (portal.floor.maxZ - portal.floor.minZ),
          greaterThan(70),
        );
      }
      // Side arcades remain traversable around the planted seating islands, not
      // merely individual reachable points sampled beyond an invisible wall.
      for (final x in [
        -HomeEcosystemLayout.arcadeX,
        0.0,
        HomeEcosystemLayout.arcadeX,
      ]) {
        var position = vm.Vector3(x, 1.6, plaza.minZ + 1);
        final targetZ = plaza.maxZ - 1;
        while (position.z < targetZ - 1e-6) {
          final previousZ = position.z;
          position = space.move(
            position,
            0,
            (targetZ - position.z).clamp(0, .1),
          );
          expect(position.z, greaterThan(previousZ));
        }
        expect(position.z, closeTo(targetZ, 1e-5));
      }
      // Every paired storefront has a direct body-clear crosswalk across the
      // entire plaza. Furniture cannot force users back into a single corridor.
      for (final z in layout.portals.map((portal) => portal.z).toSet()) {
        var position = vm.Vector3(-HomeEcosystemLayout.arcadeX, 1.6, z);
        for (var step = 0; step < 170; step++) {
          position = space.move(position, .1, 0);
        }
        expect(position.x, closeTo(HomeEcosystemLayout.arcadeX, 1e-5));
      }
    },
  );

  test(
    'landscaping is solid and no geometry crosses the central boulevard',
    () {
      final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
      final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
      final planters = layout.boxes.where(
        (box) =>
            box.name.startsWith('ecosystem_planter_') &&
            !box.name.startsWith('ecosystem_planter_rim_'),
      );
      expect(planters.length, greaterThanOrEqualTo(6));
      for (final planter in planters) {
        expect(space.canStand(planter.x, planter.z), isFalse);
        expect(space.canStand(0, planter.z), isTrue);
      }
      final sky = layout.boxes.singleWhere(
        (box) => box.name == 'ecosystem_atrium_sky',
      );
      expect(sky.y - sky.height / 2, greaterThan(8));
      for (final box in layout.boxes) {
        expect(box.width, greaterThan(0), reason: box.name);
        expect(box.height, greaterThan(0), reason: box.name);
        expect(box.depth, greaterThan(0), reason: box.name);
      }
      for (final waypoint in layout.waypoints) {
        expect(
          space.canStand(waypoint.x, waypoint.z),
          isTrue,
          reason: waypoint.id,
        );
        expect(
          space.roomAt(waypoint.x, waypoint.z)?.id,
          waypoint.roomId,
          reason: waypoint.id,
        );
      }
    },
  );

  test(
    'expandWithWorldCatalog appends .vrlw storefronts to the Mall boulevard',
    () {
      const worldEntries = [
        VrDemoLibraryEntry(
          id: 'world_oasis',
          title: 'Oasis Solar .vrlw',
          subtitle: 'Santuario desértico interactivo',
          category: VrDemoLibraryCategory.featured,
          accent: 0xFF38BDF8,
          icon: 'world',
          tags: ['worlds'],
        ),
        VrDemoLibraryEntry(
          id: 'world_citadel',
          title: 'Ciudadela Neón .vrlw',
          subtitle: 'Distrito cyberpunk vertical',
          category: VrDemoLibraryCategory.featured,
          accent: 0xFFA78BFA,
          icon: 'world',
          tags: ['worlds'],
        ),
        VrDemoLibraryEntry(
          id: 'game_ignored',
          title: 'Arcade Retro',
          subtitle: 'No es un mundo .vrlw',
          category: VrDemoLibraryCategory.games,
          accent: 0xFF22C55E,
          icon: 'gamepad',
          tags: ['games'],
        ),
      ];
      final expanded = VrHomeEcosystemRoom.expandWithWorldCatalog(
        VrHomeEcosystemRoom.defaults,
        worldEntries,
      );
      expect(expanded.length, VrHomeEcosystemRoom.defaults.length + 2);
      final worldRooms = expanded
          .where((r) => r.purpose == VrHomeRoomPurpose.portableWorld)
          .toList();
      expect(worldRooms.map((r) => r.targetRouteId), [
        'world_oasis',
        'world_citadel',
      ]);

      final layout = HomeEcosystemLayout(expanded);
      final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
      for (final worldRoom in worldRooms) {
        final portal = layout.portals.singleWhere(
          (p) => p.room.id == worldRoom.id,
        );
        expect(space.canStand(portal.doorX, portal.z), isTrue);
        expect(space.canStand(portal.standingX, portal.z), isTrue);
        expect(
          layout.boxes.any(
            (b) => b.name == 'ecosystem_${worldRoom.id}_world_compass_stage',
          ),
          isTrue,
        );
        expect(
          layout.boxes.any(
            (b) => b.name == 'ecosystem_${worldRoom.id}_world_portal_orb',
          ),
          isTrue,
        );
        expect(
          space.placePanel(
            eye: vm.Vector3(portal.standingX, 1.6, portal.z),
            forward: vm.Vector3(portal.side, 0, 0),
            distance: 3,
          ),
          isNotNull,
        );
      }
    },
  );

  test(
    'VrHomeGamepadPolicy maps L1, R1, Start and Select to toggleMainMenu',
    () {
      final policy = VrHomeGamepadPolicy();
      for (final btn in const ['l1', 'r1', 'start', 'select', 'menu']) {
        final down = VrInputEvent(
          type: VrInputType.trigger,
          source: VrInputSource.gamepad,
          active: true,
          data: {VrGamepadDriver.buttonKey: btn},
        );
        expect(policy.handle(down), VrHomeGamepadAction.toggleMainMenu);
        final held = VrInputEvent(
          type: VrInputType.trigger,
          source: VrInputSource.gamepad,
          active: true,
          data: {VrGamepadDriver.buttonKey: btn},
        );
        expect(policy.handle(held), VrHomeGamepadAction.none);
        final up = VrInputEvent(
          type: VrInputType.trigger,
          source: VrInputSource.gamepad,
          active: false,
          data: {VrGamepadDriver.buttonKey: btn},
        );
        expect(policy.handle(up), VrHomeGamepadAction.none);
      }
    },
  );
}
