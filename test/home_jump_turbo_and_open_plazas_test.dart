import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_famous_mall_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';
import 'package:vrlizate_home/src/spatial/virtual_home_locomotion_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Vertical jump (SALTAR) & TURBO sprint cadence', () {
    test('triggerHop launches a parabolic jump arc and lands cleanly', () {
      final controller = VirtualHomeLocomotionController();
      expect(controller.isHopping, isFalse);
      expect(controller.triggerHop(), isTrue);
      expect(controller.isHopping, isTrue);
      // Double jump in mid-air is ignored until touchdown.
      expect(controller.triggerHop(), isFalse);

      var peakY = VirtualHomeLocomotionController.baseEyeHeight;
      var landedCount = 0;
      for (var i = 0; i < 90; i++) {
        final step = controller.stepVerticalAndGait(1 / 60);
        if (step.eyeY > peakY) peakY = step.eyeY;
        if (step.landed) landedCount++;
      }

      expect(peakY, greaterThan(2.25));
      expect(peakY, lessThan(2.55));
      expect(landedCount, 1);
      expect(controller.isHopping, isFalse);
      expect(
        controller.stepVerticalAndGait(1 / 60).eyeY,
        closeTo(VirtualHomeLocomotionController.baseEyeHeight, 1e-4),
      );
    });

    test(
      'holding TURBO accelerates faster, reaches higher sprint speed, and engages running cadence after sustained movement',
      () {
        final walker = VirtualHomeLocomotionController();
        final sprinter = VirtualHomeLocomotionController();
        var walkPos = vm.Vector3(0, 1.6, 0);
        var sprintPos = vm.Vector3(0, 1.6, 0);

        var footstepPulses = 0;
        var maxBobDelta = 0.0;
        var sawRunningAfterRamp = false;

        for (var frame = 0; frame < 90; frame++) {
          const dt = 1 / 60;
          walkPos = walker.applySmoothLocomotion(
            currentEyeCenter: walkPos,
            headOrientation: vm.Quaternion.identity(),
            stickX: 0,
            stickY: 1.0,
            dt: dt,
            speed: 1.6,
            maxSpeed: 4.8,
            accelerationSeconds: 2.4,
            maxRadius: 200,
          );
          sprintPos = sprinter.applySmoothLocomotion(
            currentEyeCenter: sprintPos,
            headOrientation: vm.Quaternion.identity(),
            stickX: 0,
            stickY: 1.0,
            dt: dt,
            turbo: true,
            speed: 1.6,
            maxSpeed: 4.8,
            accelerationSeconds: 2.4,
            maxRadius: 200,
          );
          final gait = sprinter.stepVerticalAndGait(dt);
          final bob = (gait.eyeY - VirtualHomeLocomotionController.baseEyeHeight)
              .abs();
          if (bob > maxBobDelta) maxBobDelta = bob;
          if (gait.footstepPulse) footstepPulses++;
          if (frame > 50 && sprinter.isRunning) {
            sawRunningAfterRamp = true;
          }
        }

        // Sprinter covers substantially more distance & hits ~6.8 m/s.
        expect(sprintPos.z.abs(), greaterThan(walkPos.z.abs() * 1.45));
        expect(sprinter.currentWalkSpeed, greaterThanOrEqualTo(6.7));
        expect(sprinter.isTurboActive, isTrue);
        expect(sawRunningAfterRamp, isTrue);
        expect(maxBobDelta, greaterThan(0.015));
        expect(maxBobDelta, lessThanOrEqualTo(0.04));
        expect(footstepPulses, greaterThan(0));

        // Player can jump smoothly mid-sprint without cancelling horizontal travel.
        expect(sprinter.triggerHop(), isTrue);
        final airStep = sprinter.stepVerticalAndGait(0.08);
        expect(airStep.eyeY, greaterThan(1.85));
      },
    );
  });

  group('Obstacle-free central walking corridors across plazas', () {
    test(
      'distributedCruciform has completely unobstructed central N-S and E-W grand avenues',
      () {
        final rooms = <VrHomeEcosystemRoom>[
          ...VrHomeEcosystemRoom.defaults,
          VrHomeEcosystemRoom.famousMalls,
          VrHomeEcosystemRoom.openSourceGames,
          VrHomeEcosystemRoom.freeStreamingTv,
        ];
        final layout = HomeEcosystemLayout(
          rooms,
          topology: HomePlazaTopology.distributedCruciform,
        );
        final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);

        // Full straight N-S sprint down the entire Grand Plaza (x in [-8, 8]).
        for (final x in const [-7.5, -3.5, 0.0, 3.5, 7.5]) {
          var pos = vm.Vector3(x, 1.6, 14.0);
          while (pos.z < 61.0) {
            final next = space.move(pos, 0, 0.2);
            expect(next.z, greaterThan(pos.z), reason: 'N-S blocked at x=$x, z=${pos.z}');
            pos = next;
          }
        }

        // Full straight E-W sprint across the entire cruciform wing axis (z in [31.5, 40.5]).
        final eastWing = layout.rooms.singleWhere(
          (r) => r.id == 'ecosystem_east_wing',
        );
        final westWing = layout.rooms.singleWhere(
          (r) => r.id == 'ecosystem_west_wing',
        );
        for (final z in const [32.0, 36.0, 40.0]) {
          var pos = vm.Vector3(westWing.minX + 1.0, 1.6, z);
          final targetX = eastWing.maxX - 1.0;
          while (pos.x < targetX) {
            final next = space.move(pos, 0.2, 0);
            expect(next.x, greaterThan(pos.x), reason: 'E-W blocked at x=${pos.x}, z=$z');
            pos = next;
          }
        }
      },
    );

    test(
      'Plaza Artz MX, Galleria Milano, and Marina Bay allow unobstructed straight center crossings',
      () {
        final booths = <VrHomeEcosystemRoom>[
          for (var i = 0; i < 16; i++)
            VrHomeEcosystemRoom.forLease(
              id: 'b_$i',
              title: 'Local $i',
              description: 'Local de prueba',
              boothCode: 'L-${i + 1}',
            ),
        ];

        for (final archetype in const [
          FamousMallArchetype.galleriaMilano,
          FamousMallArchetype.plazaArtzMexico,
          FamousMallArchetype.marinaCanalShoppes,
        ]) {
          final layout = HomeFamousMallLayout.build(
            archetype: archetype,
            mallTitle: archetype.name,
            booths: booths,
          );
          final space = HomeWalkSpace(rooms: layout.rooms, boxes: layout.boxes);

          // Straight North-South crossing right through (0, 0)
          var nsPos = vm.Vector3(0, 1.6, -14.0);
          while (nsPos.z < 14.0) {
            final next = space.move(nsPos, 0, 0.2);
            expect(next.z, greaterThan(nsPos.z), reason: '$archetype N-S at z=${nsPos.z}');
            nsPos = next;
          }

          // Straight West-East crossing right through (0, 0)
          var ewPos = vm.Vector3(-14.0, 1.6, 0);
          while (ewPos.x < 14.0) {
            final next = space.move(ewPos, 0.2, 0);
            expect(next.x, greaterThan(ewPos.x), reason: '$archetype E-W at x=${ewPos.x}');
            ewPos = next;
          }
        }
      },
    );
  });
}
