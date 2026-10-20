import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_architecture_batch.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_room_identity.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';

void main() {
  test('open source gallery is an explicit host opt-in', () {
    const room = VrHomeEcosystemRoom.openSourceGames;
    expect(room.id, 'open_source_games');
    expect(room.purpose, VrHomeRoomPurpose.openSourceGames);
    expect(room.icon, VrHomeRoomIcon.gamepad);
    expect(VrHomeEcosystemRoom.defaults, hasLength(8));
    expect(VrHomeEcosystemRoom.defaults, isNot(contains(room)));
    final defaults = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
    final enabled = HomeEcosystemLayout([
      ...VrHomeEcosystemRoom.defaults,
      room,
    ]);
    expect(defaults.portals.any((p) => p.room.id == room.id), isFalse);
    expect(enabled.portals.where((p) => p.room.id == room.id), hasLength(1));
    for (var i = 0; i < defaults.portals.length; i++) {
      final before = defaults.portals[i], after = enabled.portals[i];
      expect(after.room.id, before.room.id);
      expect(after.doorX, before.doorX);
      expect(after.z, before.z);
    }
  });

  test(
    'a catalog of 23 dedicated game rooms remains walkable and reachable',
    () {
      // IDs and titles belong to the host. Architecture must follow purpose,
      // including both sides and the unpaired final room of a full catalog.
      final layout = HomeEcosystemLayout([
        for (var i = 0; i < 23; i++) _gameRoom(i),
      ]);
      final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
      expect(layout.portals, hasLength(23));
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
      walkTo(2, 8);
      walkTo(2, 11.7);
      walkTo(0, 11.7);
      for (final portal in layout.portals) {
        walkTo(0, portal.z);
        walkTo(portal.standingX, portal.z);
        expect(space.roomAt(position.x, position.z)?.id, portal.floor.id);
        expect(
          (portal.floor.maxX - portal.floor.minX) *
              (portal.floor.maxZ - portal.floor.minZ),
          greaterThan(70),
        );
        expect(space.canStand(portal.outerX, portal.z), isFalse);
        expect(
          space.placePanel(
            eye: position,
            forward: vm.Vector3(portal.side, 0, 0),
            distance: 3,
          ),
          isNotNull,
          reason:
              'The host catalog must open without crossing an arcade cabinet.',
        );
        walkTo(0, portal.z);
      }
      final last = layout.portals.last;
      expect(space.canStand(-last.doorX, last.z), isFalse);
      for (final waypoint in layout.waypoints) {
        expect(space.canStand(waypoint.x, waypoint.z), isTrue);
      }
      for (final x in [
        -HomeEcosystemLayout.arcadeX,
        0.0,
        HomeEcosystemLayout.arcadeX,
      ]) {
        final plaza = layout.rooms.singleWhere(
          (r) => r.id == 'ecosystem_corridor',
        );
        position = vm.Vector3(x, 1.6, plaza.minZ + 1);
        while (position.z < plaza.maxZ - 1 - 1e-6) {
          final previousZ = position.z;
          position = space.move(position, 0, .1);
          expect(position.z, greaterThan(previousZ));
        }
      }
    },
  );

  test(
    'game rooms have curved arcade identity within a static mesh budget',
    () {
      final layout = HomeEcosystemLayout([_gameRoom(0), _gameRoom(1)]);
      final identity = HomeRoomIdentity.forPurpose(
        VrHomeRoomPurpose.openSourceGames,
      );
      expect(identity.category, 'JUEGOS Y CREADORES');
      expect(
        VrHomeRoomPurpose.values
            .map(HomeRoomIdentity.forPurpose)
            .map((value) => value.category)
            .toSet(),
        hasLength(VrHomeRoomPurpose.values.length),
      );
      for (final portal in layout.portals) {
        final boxes = layout.boxes
            .where((b) => b.zone == portal.floor.id)
            .toList();
        final prefix = 'ecosystem_${portal.room.id}_';
        final stage = boxes.singleWhere(
          (b) => b.name == '${prefix}community_stage',
        );
        final display = boxes.singleWhere(
          (b) => b.name == '${prefix}community_display',
        );
        final cabinets = boxes.where(
          (b) => b.name.startsWith('${prefix}arcade_cabinet_'),
        );
        expect(cabinets, hasLength(3));
        expect(stage.shape, isNot(HomeLobbyShape.cuboid));
        expect(display.shape, isNot(HomeLobbyShape.cuboid));
        expect(cabinets.every((b) => b.shape != HomeLobbyShape.cuboid), isTrue);
        expect(boxes.map((b) => b.color).toSet().length, greaterThan(5));
        final batches = HomeArchitectureBatch.group(boxes);
        expect(
          batches.length,
          lessThanOrEqualTo(HomeLobbyFinish.values.length),
        );
        final triangles = batches.fold<int>(
          0,
          (sum, batch) =>
              sum + batch.build(defaultColor: 0xFFFFFFFF).indices.length ~/ 3,
        );
        expect(triangles, lessThan(3000));
        // Reusing the authored collider bounds cannot leak furniture into the
        // plaza, adjacent rooms or the solid outer wall when mirrored.
        for (final box in boxes.where(
          (b) =>
              b.name.contains('arcade_') ||
              b.name.contains('community_') ||
              b.name.contains('gamepad_'),
        )) {
          expect(box.x - box.width / 2, greaterThan(portal.floor.minX));
          expect(box.x + box.width / 2, lessThan(portal.floor.maxX));
          expect(box.z - box.depth / 2, greaterThan(portal.floor.minZ));
          expect(box.z + box.depth / 2, lessThan(portal.floor.maxZ));
        }
      }
    },
  );
}

VrHomeEcosystemRoom _gameRoom(int index) => VrHomeEcosystemRoom(
  id: 'oss_game_$index',
  title: 'Juego $index',
  description: 'Proyecto de su creador.',
  accent: VrHomeEcosystemRoom.openSourceGames.accent,
  icon: VrHomeRoomIcon.gamepad,
  purpose: VrHomeRoomPurpose.openSourceGames,
);
