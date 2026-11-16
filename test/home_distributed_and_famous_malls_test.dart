import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_famous_mall_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';

void main() {
  test(
    'distributedCruciform eliminates endless linear corridor for 10 and 23 rooms',
    () {
      final rooms23 = <VrHomeEcosystemRoom>[
        ...VrHomeEcosystemRoom.defaults,
        VrHomeEcosystemRoom.openSourceGames,
        VrHomeEcosystemRoom.famousMalls,
        for (var i = 0; i < 13; i++)
          VrHomeEcosystemRoom.forLease(
            id: 'lease_$i',
            title: 'Local R-$i · EN RENTA',
            description: 'Espacio disponible en renta para experiencia .vrlz.',
            boothCode: 'R-$i',
          ),
      ];
      final linear = HomeEcosystemLayout(rooms23);
      final distributed = HomeEcosystemLayout(
        rooms23,
        topology: HomePlazaTopology.distributedCruciform,
      );

      final linearMaxZ = linear.portals.map((p) => p.z).reduce(math.max);
      final distCorridor = distributed.rooms.singleWhere(
        (r) => r.id == 'ecosystem_corridor',
      );
      expect(linearMaxZ, greaterThan(170));
      expect(distCorridor.maxZ, lessThanOrEqualTo(66.0));
      expect(
        distributed.portals.map((p) => p.facing).toSet(),
        containsAll(HomePortalFacing.values),
      );

      final space = HomeWalkSpace(
        rooms: distributed.rooms,
        boxes: distributed.boxes,
      );
      for (final wp in distributed.waypoints) {
        expect(space.canStand(wp.x, wp.z), isTrue, reason: wp.id);
      }

      // Straight, uninterrupted walk from Lobby (0,0) -> Gallery -> Grand Plaza (0,18)
      // with wide portals (4.8 m -> 6.8 m) and zero central chicane obstacles.
      var straightPos = vm.Vector3(0, 1.6, 0);
      for (var step = 0; step < 180; step++) {
        straightPos = space.move(straightPos, 0, 0.1);
        expect(space.canStand(straightPos.x, straightPos.z), isTrue);
      }
      expect(straightPos.z, closeTo(18.0, 1e-4));
      expect(
        space.roomAt(straightPos.x, straightPos.z)?.id,
        'ecosystem_corridor',
      );

      for (final portal in distributed.portals) {
        expect(portal.doorHalfWidth * 2, greaterThanOrEqualTo(6.6));
        expect(
          space.canStand(portal.doorX, portal.doorZ),
          isTrue,
          reason: '${portal.room.id} doorway',
        );
        expect(
          space.canStand(portal.standingX, portal.standingZ),
          isTrue,
          reason: '${portal.room.id} standing',
        );
        expect(
          space.canStand(portal.outerX, portal.outerZ),
          isFalse,
          reason: '${portal.room.id} outer wall solid',
        );
        expect(
          space.placePanel(
            eye: vm.Vector3(portal.standingX, 1.6, portal.standingZ),
            forward: vm.Vector3(
              portal.inwardForwardX,
              0,
              portal.inwardForwardZ,
            ),
            distance: 3,
          ),
          isNotNull,
          reason: '${portal.room.id} modal clearance',
        );
      }
    },
  );

  for (final archetype in FamousMallArchetype.values) {
    test(
      'FamousMallLayout ($archetype) distributes 16 booths 360° with EN RENTA showcases and full walkability',
      () {
        final booths = <VrHomeEcosystemRoom>[
          for (var i = 0; i < 16; i++)
            i % 4 == 0
                ? VrHomeEcosystemRoom(
                    id: '${archetype.name}_pilot_$i',
                    title: 'Puesto Piloto $i',
                    description: 'Experiencia activa de muestra en la plaza.',
                    accent: 0xFF00E5FF,
                    icon: VrHomeRoomIcon.gamepad,
                    purpose: VrHomeRoomPurpose.openSourceGames,
                    doorBadge: 'PUESTO EXPERIENCIA · ACTIVO',
                  )
                : VrHomeEcosystemRoom.forLease(
                    id: '${archetype.name}_lease_$i',
                    title: 'Local #${i + 1} · EN RENTA',
                    description:
                        'Espacio comercial EN RENTA para experiencia .vrlz.',
                    boothCode: 'L-${i + 1}',
                  ),
        ];

        final layout = HomeFamousMallLayout.build(
          archetype: archetype,
          mallTitle: 'Plaza ${archetype.name}',
          booths: booths,
        );
        final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);

        expect(layout.portals, hasLength(16));
        expect(
          space.canStand(
            HomeFamousMallLayout.spawnX,
            HomeFamousMallLayout.spawnZ,
          ),
          isTrue,
        );
        for (final wp in layout.waypoints) {
          expect(space.canStand(wp.x, wp.z), isTrue, reason: wp.id);
        }

        // Verify compact 360° radial distribution (< 25 m from plaza center to any doorway).
        for (final portal in layout.portals) {
          final doorwayDist = math.sqrt(
            portal.doorX * portal.doorX + portal.doorZ * portal.doorZ,
          );
          expect(doorwayDist, lessThan(23.0), reason: portal.room.id);
          expect(portal.doorHalfWidth * 2, greaterThanOrEqualTo(5.4 - 1e-9));
          expect(space.canStand(portal.doorX, portal.doorZ), isTrue);
          expect(space.canStand(portal.standingX, portal.standingZ), isTrue);
          expect(space.canStand(portal.outerX, portal.outerZ), isFalse);

          if (portal.room.isForLease) {
            expect(
              layout.boxes.any(
                (b) => b.name == 'ecosystem_${portal.room.id}_for_lease_stage',
              ),
              isTrue,
            );
            expect(
              layout.boxes.any(
                (b) =>
                    b.name ==
                    'ecosystem_${portal.room.id}_for_lease_window_placard',
              ),
              isTrue,
            );
          }

          expect(
            space.placePanel(
              eye: vm.Vector3(portal.standingX, 1.6, portal.standingZ),
              forward: vm.Vector3(
                portal.inwardForwardX,
                0,
                portal.inwardForwardZ,
              ),
              distance: 3,
            ),
            isNotNull,
          );
        }

        // Physically walk from spawn around the perimeter ring into every booth!
        var pos = vm.Vector3(
          HomeFamousMallLayout.spawnX,
          1.6,
          HomeFamousMallLayout.spawnZ,
        );
        void walkTo(double tx, double tz) {
          for (var step = 0; step < 500; step++) {
            final dx = (tx - pos.x).clamp(-.12, .12);
            final dz = (tz - pos.z).clamp(-.12, .12);
            if (dx.abs() + dz.abs() < 1e-5) break;
            pos = space.move(pos, dx, dz);
            expect(space.canStand(pos.x, pos.z), isTrue);
          }
          expect(pos.x, closeTo(tx, 1e-4));
          expect(pos.z, closeTo(tz, 1e-4));
        }

        // Perimeter ring at |x|, |z| = 13.5 m clears all central monuments/canals.
        const ring = 13.5;
        walkTo(0, ring);
        for (final portal in layout.portals) {
          switch (portal.facing) {
            case HomePortalFacing.north:
              walkTo(ring, pos.z);
              walkTo(ring, -ring);
              walkTo(portal.doorX, -ring);
              walkTo(portal.standingX, portal.standingZ);
              walkTo(portal.doorX, -ring);
            case HomePortalFacing.east:
              walkTo(ring, pos.z);
              walkTo(ring, portal.doorZ);
              walkTo(portal.standingX, portal.standingZ);
              walkTo(ring, portal.doorZ);
            case HomePortalFacing.west:
              walkTo(pos.x, ring);
              walkTo(-ring, ring);
              walkTo(-ring, portal.doorZ);
              walkTo(portal.standingX, portal.standingZ);
              walkTo(-ring, portal.doorZ);
            case HomePortalFacing.south:
              walkTo(pos.x, ring);
              walkTo(portal.doorX, ring);
              walkTo(portal.standingX, portal.standingZ);
              walkTo(portal.doorX, ring);
          }
        }
      },
    );
  }
}
