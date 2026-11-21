import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/spatial/home_architecture_batch.dart';
import 'package:vrlizate_home/vrlizate_home_spatial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-elevation walkability (terraces, arched bridges, sunken bowls)', () {
    test('flat default HomeWalkSpace preserves y=0 and 1.60m eye height', () {
      final flat = HomeWalkSpace();
      expect(flat.groundHeightAt(0, 0), 0.0);
      expect(flat.eyeHeightAt(0, 0), closeTo(1.60, 1e-6));
    });

    test('terrace, smooth ramp, arched bridge, and radial sunken amphitheater interpolate smoothly', () {
      const rooms = <HomeRoom>[
        HomeRoom('pavilion', 'Pabellón', -20, 20, -20, 20),
      ];
      const elevations = <HomeWalkableElevation>[
        // North overlook terrace (+1.2 m)
        HomeWalkableElevation.terrace(
          id: 'north_overlook',
          minX: -6,
          maxX: 6,
          minZ: 10,
          maxZ: 16,
          elevationMeters: 1.2,
        ),
        // Smooth ramp climbing from 0.0 m -> +1.2 m along +Z
        HomeWalkableElevation.ramp(
          id: 'north_ramp',
          minX: -2,
          maxX: 2,
          minZ: 4,
          maxZ: 10,
          startElevationMeters: 0.0,
          endElevationMeters: 1.2,
          axis: HomeElevationAxis.posZ,
        ),
        // Arched Venetian/Kyoto bridge along +X (0 -> 0 with +1.5 m arch apex)
        HomeWalkableElevation.ramp(
          id: 'canal_bridge',
          minX: 6,
          maxX: 14,
          minZ: -2,
          maxZ: 2,
          startElevationMeters: 0.0,
          endElevationMeters: 0.0,
          axis: HomeElevationAxis.posX,
          archHeightMeters: 1.5,
        ),
        // Sunken social amphitheater bowl (-0.7 m center, smooth rim to 0.0 m)
        HomeWalkableElevation.radialBowl(
          id: 'sunken_court',
          centerX: -10,
          centerZ: 0,
          innerRadius: 2.0,
          outerRadius: 5.0,
          centerElevationMeters: -0.7,
        ),
      ];

      final space = HomeWalkSpace(
        rooms: rooms,
        boxes: const [],
        elevations: elevations,
      );

      // Terrace
      expect(space.groundHeightAt(0, 12), closeTo(1.2, 1e-6));
      expect(space.eyeHeightAt(0, 12), closeTo(2.8, 1e-6));

      // Smooth ramp endpoints and midpoint
      expect(space.groundHeightAt(0, 4.0), closeTo(0.0, 1e-6));
      expect(space.groundHeightAt(0, 7.0), closeTo(0.6, 1e-6));
      expect(space.groundHeightAt(0, 10.0), closeTo(1.2, 1e-6));

      // Arched bridge entry, exact mid-arch apex (+1.5 m), and exit
      expect(space.groundHeightAt(6.0, 0), closeTo(0.0, 1e-6));
      expect(space.groundHeightAt(10.0, 0), closeTo(1.5, 1e-6));
      expect(space.groundHeightAt(14.0, 0), closeTo(0.0, 1e-6));

      // Sunken circular amphitheater bowl
      expect(space.groundHeightAt(-10.0, 0), closeTo(-0.7, 1e-6));
      expect(space.groundHeightAt(-13.5, 0), closeTo(-0.35, 1e-6));
      expect(space.groundHeightAt(-15.0, 0), closeTo(0.0, 1e-6));

      // Walking onto the ramp elevates moved eye smoothly
      final moved = space.move(vm.Vector3(0, 1.60, 6.5), 0.0, 0.5);
      expect(moved.z, closeTo(7.0, 1e-5));
      expect(moved.y, closeTo(2.20, 1e-5));
    });

    test('parabolic jump and smoothVerticalEyeFollow bridge distinct elevations smoothly', () {
      final controller = VirtualHomeLocomotionController();
      controller.startJump(
        from: vm.Vector3(0, 0.90, 0), // sunken court (-0.7 + 1.6)
        to: vm.Vector3(0, 2.80, 12), // raised terrace (+1.2 + 1.6)
        targetName: 'Mirador Norte',
        duration: 1.0,
      );

      final (midPos, finishedMid, _) = controller.tick(
        0.5,
        vm.Vector3(0, 0.90, 0),
      );
      expect(finishedMid, isFalse);
      // Midpoint baseY = (0.90 + 2.80) / 2 = 1.85, plus +0.28 m parabolic apex
      expect(midPos.y, closeTo(1.85 + 0.28, 1e-5));

      final (endPos, finishedEnd, name) = controller.tick(0.5, midPos);
      expect(finishedEnd, isTrue);
      expect(name, 'Mirador Norte');
      expect(endPos.y, closeTo(2.80, 1e-5));

      // Smooth exponential damper avoids sudden single-frame vertical step jumps
      final damped = VirtualHomeLocomotionController.smoothVerticalEyeFollow(
        currentY: 1.60,
        targetGroundY: 1.20,
        dt: 1 / 60,
      );
      expect(damped, greaterThan(1.60));
      expect(damped, lessThan(2.00));
    });

    test(
      'Croquis 1 distributedCruciform Pavilion: walkable Rotonda (+0.36m), sweeping Belvedere (+0.95m) via 4 ramps, batched mesh, NPCs, and 4 interactive seats',
      () {
        final layout = HomeEcosystemLayout(
          VrHomeEcosystemRoom.defaults,
          topology: HomePlazaTopology.distributedCruciform,
        );
        expect(layout.elevations, hasLength(6));
        expect(layout.seats, hasLength(4));

        final space = HomeWalkSpace(
          rooms: layout.rooms,
          boxes: layout.boxes,
          elevations: layout.elevations,
        );

        // 1. Walk continuously from Lobby (0, 0) -> Water Court (0, 17.5) ->
        //    Rotonda Circular Central (0, 36.0) -> North Ramp -> Belvedere (0, 56.5).
        var pos = vm.Vector3(0, 1.60, 0);
        for (var i = 0; i < 565; i++) {
          pos = space.move(pos, 0, 0.1);
          expect(space.canStand(pos.x, pos.z), isTrue, reason: 'step $i at z=${pos.z}');
        }
        expect(pos.z, closeTo(56.5, 1e-3));
        expect(space.groundHeightAt(0, 17.5), closeTo(0.0, 1e-6));
        expect(space.groundHeightAt(0, 36.0), closeTo(0.36, 1e-6));
        expect(space.groundHeightAt(0, 50.2), closeTo(0.475, 1e-4));
        expect(space.groundHeightAt(0, 56.5), closeTo(0.95, 1e-6));
        expect(pos.y, closeTo(2.55, 1e-4));

        // 2. Climb via West and East architectural ramps onto Belvedere (+0.95 m)
        //    and descend smoothly via the South ramp back to ground level (0.0 m).
        var westPos = vm.Vector3(-12.0, 1.60, 56.8);
        for (var i = 0; i < 45; i++) {
          westPos = space.move(westPos, 0.1, 0);
          expect(space.canStand(westPos.x, westPos.z), isTrue);
        }
        expect(westPos.x, closeTo(-7.5, 1e-3));
        expect(westPos.y, closeTo(2.55, 1e-4));

        var eastPos = vm.Vector3(12.0, 1.60, 56.8);
        for (var i = 0; i < 45; i++) {
          eastPos = space.move(eastPos, -0.1, 0);
          expect(space.canStand(eastPos.x, eastPos.z), isTrue);
        }
        expect(eastPos.x, closeTo(7.5, 1e-3));
        expect(eastPos.y, closeTo(2.55, 1e-4));
        expect(space.groundHeightAt(0, 61.9), closeTo(0.475, 1e-4));
        expect(space.groundHeightAt(0, 63.6), closeTo(0.0, 1e-6));

        // 3. Structural Belvedere corner columns remain solid obstacles.
        expect(space.canStand(8.85, 53.60), isFalse);

        // 4. Every interactive bench has a valid stand-up point & focus check.
        for (final seat in layout.seats) {
          expect(
            space.canStand(seat.standUpX, seat.standUpZ),
            isTrue,
            reason: 'seat ${seat.id} standUp must be walkable',
          );
          final viewerEye = vm.Vector3(
            seat.standUpX,
            space.eyeHeightAt(seat.standUpX, seat.standUpZ),
            seat.standUpZ,
          );
          final toSeat = vm.Vector3(
            seat.x - viewerEye.x,
            0,
            seat.z - viewerEye.z,
          )..normalize();
          expect(seat.isFocusedBy(viewerEye, toSeat), isTrue);
          expect(seat.isFocusedBy(viewerEye, -toSeat), isFalse);
        }

        // 5. Batched elevation surface mesh compiles cleanly in 1 mesh with unit normals.
        final mesh = HomeArchitectureBatch.buildElevationSurfaces(
          elevations: layout.elevations,
          architecturalContactAo: true,
        );
        expect(mesh, isNotNull);
        expect(mesh!.indices.length, greaterThan(200));
        expect(mesh.indices.length % 3, 0);
        for (var i = 0; i < mesh.normals.length; i += 3) {
          final len = math.sqrt(
            mesh.normals[i] * mesh.normals[i] +
                mesh.normals[i + 1] * mesh.normals[i + 1] +
                mesh.normals[i + 2] * mesh.normals[i + 2],
          );
          expect(len, closeTo(1.0, 1e-3));
        }

        // 6. Locomotion gait tracks elevated terrace and seated eye offsets smoothly.
        final ctrl = VirtualHomeLocomotionController();
        var gaitY = 1.60;
        for (var f = 0; f < 45; f++) {
          gaitY = ctrl.stepVerticalAndGait(1 / 60, groundHeight: 0.95).eyeY;
        }
        expect(gaitY, closeTo(2.55, 0.02));
        for (var f = 0; f < 45; f++) {
          gaitY = ctrl
              .stepVerticalAndGait(
                1 / 60,
                groundHeight: 0.95,
                standingEyeHeight: 1.14,
              )
              .eyeY;
        }
        expect(gaitY, closeTo(2.09, 0.02));

        // 7. Ambient NPC crowd samples exact elevation across Rotonda & Belvedere.
        final crowd = HomePlazaCrowd.plan(layout: layout);
        expect(crowd.groundYAt(0, 36.0), closeTo(0.36, 1e-6));
        expect(crowd.groundYAt(0, 56.5), closeTo(0.95, 1e-6));
        crowd.dispose();
      },
    );
  });
}
