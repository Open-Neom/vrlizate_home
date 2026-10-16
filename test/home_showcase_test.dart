import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_showcase.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

// Inspect the bundled assets, not a synthetic stand-in or a GPU importer.
({Map<String, dynamic> json, ByteData binary}) _readGlb(String asset) {
  final path = asset.replaceFirst('packages/vrlizate_home/', '');
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(data.getUint32(0, Endian.little), 0x46546c67);
  expect(data.getUint32(4, Endian.little), 2);
  expect(data.getUint32(8, Endian.little), bytes.length);
  expect(bytes.length, lessThan(2 * 1024 * 1024));
  final jsonLength = data.getUint32(12, Endian.little);
  expect(data.getUint32(16, Endian.little), 0x4e4f534a);
  final json =
      jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)))
          as Map<String, dynamic>;
  final binHeader = 20 + jsonLength;
  expect(data.getUint32(binHeader + 4, Endian.little), 0x004e4942);
  expect(
    binHeader + 8 + data.getUint32(binHeader, Endian.little),
    bytes.length,
  );
  return (json: json, binary: ByteData.sublistView(bytes, binHeader + 8));
}

int _triangles(Map<String, dynamic> json) {
  final accessors = json['accessors'] as List;
  var count = 0;
  for (final mesh in json['meshes'] as List) {
    for (final primitive in mesh['primitives'] as List) {
      expect(primitive['mode'] ?? 4, 4);
      count += (accessors[primitive['indices']]['count'] as int) ~/ 3;
    }
  }
  return count;
}

({vm.Vector3 min, vm.Vector3 max}) _loungeBounds(
  ({Map<String, dynamic> json, ByteData binary}) model,
) {
  // The authored lounge bakes positions into each mesh; catch a future change
  // to node transforms instead of silently testing the wrong coordinate space.
  for (final node in model.json['nodes'] as List) {
    expect(
      node.keys,
      isNot(
        anyOf(
          contains('matrix'),
          contains('translation'),
          contains('rotation'),
          contains('scale'),
        ),
      ),
    );
  }
  final minimum = vm.Vector3.all(double.infinity);
  final maximum = vm.Vector3.all(-double.infinity);
  for (final mesh in model.json['meshes'] as List) {
    for (final primitive in mesh['primitives'] as List) {
      final accessor =
          model.json['accessors'][primitive['attributes']['POSITION']];
      expect(accessor['type'], 'VEC3');
      expect(accessor['componentType'], 5126);
      final view = model.json['bufferViews'][accessor['bufferView']];
      final offset =
          (view['byteOffset'] as int? ?? 0) +
          (accessor['byteOffset'] as int? ?? 0);
      final stride = view['byteStride'] as int? ?? 12;
      for (var vertex = 0; vertex < accessor['count']; vertex++) {
        for (var axis = 0; axis < 3; axis++) {
          final value = model.binary.getFloat32(
            offset + vertex * stride + axis * 4,
            Endian.little,
          );
          expect(value.isFinite, isTrue);
          minimum[axis] = math.min(minimum[axis], value);
          maximum[axis] = math.max(maximum[axis], value);
        }
      }
    }
  }
  return (min: minimum, max: maximum);
}

HomeLobbyBox _part(HomeEcosystemLayout layout, String room, String suffix) =>
    layout.boxes.singleWhere((box) => box.name == 'ecosystem_${room}_$suffix');

void main() {
  test(
    'bundled robot supplies the controller clips, skins and bounded geometry',
    () {
      final robot = _readGlb(HomeShowcase.robotAsset);
      final clips = {
        for (final clip in robot.json['animations'] as List) clip['name']: clip,
      };
      expect(clips.keys, containsAll(VrActorAnimation.defaultClipNames.values));
      for (final name in VrActorAnimation.defaultClipNames.values) {
        final clip = clips[name]!;
        expect(clip['channels'] as List, isNotEmpty);
        var duration = 0.0;
        for (final sampler in clip['samplers'] as List) {
          final input = robot.json['accessors'][sampler['input']];
          duration = math.max(duration, (input['max'][0] as num).toDouble());
          expect(
            sampler['interpolation'] ?? 'LINEAR',
            'LINEAR',
            reason: 'The current runtime does not preserve cubic/step curves.',
          );
        }
        expect(duration, inExclusiveRange(0, 10));
      }
      final skins = robot.json['skins'] as List;
      expect(skins, isNotEmpty);
      for (final skin in skins) {
        expect((skin['joints'] as List).length, inInclusiveRange(1, 64));
      }
      expect(_triangles(robot.json), lessThan(10000));
      for (final mesh in robot.json['meshes'] as List) {
        for (final primitive in mesh['primitives'] as List) {
          expect(
            (primitive['targets'] as List? ?? []).length,
            lessThanOrEqualTo(8),
          );
        }
      }
      expect(
        (robot.json['buffers'] as List).every((b) => b['uri'] == null),
        isTrue,
      );
    },
  );

  test(
    'lounge collision envelope contains the real GLB in either room order',
    () {
      final lounge = _readGlb(HomeShowcase.loungeAsset);
      final bounds = _loungeBounds(lounge);
      expect(_triangles(lounge.json), lessThan(22000));
      expect(lounge.json['animations'] as List? ?? [], isEmpty);
      expect(lounge.json['skins'] as List? ?? [], isEmpty);
      final avatar = VrHomeEcosystemRoom.defaults.singleWhere(
        (room) => room.purpose == VrHomeRoomPurpose.avatar,
      );
      final sides = <double>{};
      for (final rooms in [
        VrHomeEcosystemRoom.defaults,
        [
          avatar,
          ...VrHomeEcosystemRoom.defaults.where((room) => room != avatar),
        ],
      ]) {
        final layout = HomeEcosystemLayout(rooms);
        final portal = layout.portals.singleWhere((p) => p.room == avatar);
        sides.add(portal.side);
        final collision = _part(layout, avatar.id, 'showcase_lounge_clearance');
        final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);
        final center = vm.Vector3(collision.x, 0, collision.z);
        final boxMin = vm.Vector3(
          collision.x - collision.width / 2,
          collision.y - collision.height / 2,
          collision.z - collision.depth / 2,
        );
        final boxMax = vm.Vector3(
          collision.x + collision.width / 2,
          collision.y + collision.height / 2,
          collision.z + collision.depth / 2,
        );
        // Flutter Scene's import root mirrors Z. Check every actual bounding
        // corner against the collision envelope and room's solid walls.
        for (final x in [bounds.min.x, bounds.max.x]) {
          for (final y in [bounds.min.y, bounds.max.y]) {
            for (final z in [bounds.min.z, bounds.max.z]) {
              final point = center + vm.Vector3(x, y, -z);
              for (var axis = 0; axis < 3; axis++) {
                expect(
                  point[axis],
                  inInclusiveRange(boxMin[axis] - 1e-5, boxMax[axis] + 1e-5),
                );
              }
              expect(portal.floor.contains(point.x, point.z), isTrue);
            }
          }
        }
        expect(space.canStand(collision.x, collision.z), isFalse);
        var position = vm.Vector3(0, 1.6, portal.z);
        // The new lounge must leave a complete approach to the host terminal.
        for (var step = 0; step < 400; step++) {
          position = space.move(
            position,
            (portal.standingX - position.x).clamp(-.1, .1),
            0,
          );
        }
        expect(position.x, closeTo(portal.standingX, 1e-5));
        expect(space.canStand(position.x, position.z), isTrue);
      }
      expect(sides, {-1, 1});
    },
  );

  test('documented robot poses fit the stage and room on either side', () {
    final metadata =
        jsonDecode(
              File(
                'assets/showcase/robot_expressive.metadata.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final avatar = VrHomeEcosystemRoom.defaults.last;
    final poses = [
      metadata['boundsRestPoseWorld'],
      ...(metadata['boundsAtAnimationStart'] as Map).values,
    ];
    for (final rooms in [
      VrHomeEcosystemRoom.defaults,
      [avatar, ...VrHomeEcosystemRoom.defaults.where((room) => room != avatar)],
    ]) {
      final layout = HomeEcosystemLayout(rooms);
      final portal = layout.portals.singleWhere((p) => p.room == avatar);
      final stage = _part(layout, avatar.id, 'avatar_platform');
      final placement =
          vm.Matrix4.translationValues(
              stage.x,
              stage.y + stage.height / 2 + HomeShowcase.robotFloorOffset,
              stage.z,
            )
            ..rotateY(portal.side * math.pi / 2)
            ..scaleByDouble(
              HomeShowcase.robotScale,
              HomeShowcase.robotScale,
              -HomeShowcase.robotScale,
              1,
            );
      for (final pose in poses) {
        for (final x in [pose['min'][0], pose['max'][0]]) {
          for (final z in [pose['min'][2], pose['max'][2]]) {
            final point = placement.transformed3(
              vm.Vector3((x as num).toDouble(), 0, (z as num).toDouble()),
            );
            expect((point.x - stage.x).abs(), lessThan(stage.width / 2));
            expect((point.z - stage.z).abs(), lessThan(stage.depth / 2));
            expect(portal.floor.contains(point.x, point.z), isTrue);
          }
        }
        final top =
            (pose['max'][1] as num).toDouble() * HomeShowcase.robotScale +
            stage.y +
            stage.height / 2 +
            HomeShowcase.robotFloorOffset;
        expect(top, lessThan(3), reason: 'Below the doorway/room ceiling.');
      }
    }
    // These are measured rest/start poses, not a claim about all animated bounds.
  });
}
