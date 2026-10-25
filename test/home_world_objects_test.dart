import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_architecture_batch.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';
import 'package:vrlizate_home/src/spatial/home_world_objects.dart';

void main() {
  test(
    'organic trees preserve stable placements and original collision bounds',
    () {
      final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
      expect(layout.worldObjects, hasLength(8));
      expect(layout.worldObjects.map((e) => e.id).toSet(), hasLength(8));
      final first = layout.worldObjects.first;
      expect(
        first.transform.position,
        VrWorldPosition(
          -5.2,
          .65,
          HomeEcosystemLayout.firstRowZ - HomeEcosystemLayout.rowPitch / 2,
        ),
      );
      final boxes = HomeWorldObjects.boxesFor(first);
      expect(boxes, hasLength(3));
      expect(boxes.map((box) => box.shape), [
        HomeLobbyShape.cylinder,
        HomeLobbyShape.ellipsoid,
        HomeLobbyShape.ellipsoid,
      ]);
      expect(boxes[0].y, closeTo(1.9, 1e-8));
      expect(boxes[1].y, closeTo(3.4, 1e-8));
      expect(boxes[2].x, closeTo(-5.4, 1e-8));
      expect(boxes[2].y, closeTo(4.32, 1e-8));
      expect(boxes[1].width, 2.5);
      expect(boxes[1].depth, 2.7);
      final meshes = HomeArchitectureBatch.group(
        boxes,
      ).map((batch) => batch.build(defaultColor: 0xFFFFFFFF));
      expect(
        meshes.fold<int>(0, (sum, mesh) => sum + mesh.indices.length ~/ 3),
        384,
      );
      expect(() => layout.worldObjects.clear(), throwsUnsupportedError);
    },
  );

  test('injected coordinates change rendering and collision together', () {
    final clear = HomeEcosystemLayout(
      VrHomeEcosystemRoom.defaults,
      worldObjects: [],
    );
    final tree = HomeWorldObjects.placeTree(id: 'test.tree', x: 0, z: 22, y: 0);
    final planted = HomeEcosystemLayout(
      VrHomeEcosystemRoom.defaults,
      worldObjects: [tree],
    );
    final clearSpace = HomeWalkSpace(rooms: clear.rooms, boxes: clear.boxes);
    final plantedSpace = HomeWalkSpace(
      rooms: planted.rooms,
      boxes: planted.boxes,
    );
    expect(clearSpace.canStand(0, 22), isTrue);
    expect(plantedSpace.canStand(0, 22), isFalse);
    expect(plantedSpace.canStand(2, 22), isTrue);
    expect(planted.boxes.length, clear.boxes.length + 3);
    // The first crown adds a foliage batch; subsequent trees share it.
    final twoTrees = HomeEcosystemLayout(
      VrHomeEcosystemRoom.defaults,
      worldObjects: [
        tree,
        HomeWorldObjects.placeTree(id: 'second', x: 3, z: 22),
      ],
    );
    expect(
      HomeArchitectureBatch.group(planted.boxes).length,
      HomeArchitectureBatch.group(clear.boxes).length + 1,
    );
    expect(
      HomeArchitectureBatch.group(twoTrees.boxes).length,
      HomeArchitectureBatch.group(planted.boxes).length,
    );
  });

  test(
    'quarter-turn and scale preserve a single geometry for all consumers',
    () {
      final tree = HomeWorldObjects.placeTree(
        id: 'turned',
        x: 4,
        z: 9,
        y: 1,
        scale: 2,
        yawRadians: math.pi / 2,
      );
      final boxes = HomeWorldObjects.boxesFor(tree);
      expect(boxes[1].width, 5.4);
      expect(boxes[1].depth, 5);
      expect(boxes[0].height, 5);
      expect(boxes[2].x, closeTo(4.32, 1e-8));
      expect(boxes[2].z, closeTo(8.6, 1e-8));
    },
  );

  test(
    'unknown prototypes, foreign instances and duplicates cannot enter Home',
    () {
      final tree = HomeWorldObjects.placeTree(id: 'tree', x: 4, z: 9);
      for (final entity in [
        VrWorldEntity(
          id: 'bad',
          prototypeId: 'downloaded-code',
          world: tree.world,
          transform: tree.transform,
        ),
        VrWorldEntity(
          id: 'bad',
          prototypeId: tree.prototypeId,
          world: VrWorldAddress(worldId: 'other', instanceId: 'local'),
          transform: tree.transform,
        ),
        tree.copyWith(transform: tree.transform.copyWith(yawRadians: .1)),
      ]) {
        expect(
          () => HomeEcosystemLayout(
            VrHomeEcosystemRoom.defaults,
            worldObjects: [entity],
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => HomeEcosystemLayout(
          VrHomeEcosystemRoom.defaults,
          worldObjects: [tree, tree],
        ),
        throwsStateError,
      );
      expect(
        () => HomeEcosystemLayout([], worldObjects: [tree]),
        throwsArgumentError,
      );
    },
  );

  test(
    'explicit empty placements remove trees and retain plaza architecture',
    () {
      final authored = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
      final bare = HomeEcosystemLayout(
        VrHomeEcosystemRoom.defaults,
        worldObjects: [],
      );
      expect(bare.worldObjects, isEmpty);
      expect(authored.boxes.length - bare.boxes.length, 24);
      expect(
        bare.portals.map((p) => p.room.id),
        authored.portals.map((p) => p.room.id),
      );
    },
  );
}
