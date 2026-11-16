import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_famous_mall_layout.dart';
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';
import 'package:vrlizate_home/src/spatial/virtual_home_locomotion_controller.dart';
import 'package:vrlizate_home/src/spatial/vr_home_spatial_bindings.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart' show StereoHeadRig;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void runVoiceFrames(
    VirtualHomeLocomotionController controller,
    StereoHeadRig rig, {
    required int frames,
    double dt = 1 / 60,
    HomeWalkSpace? walkSpace,
  }) {
    for (var i = 0; i < frames; i++) {
      if (!controller.isVoiceMoving) break;
      final step = controller.consumeVoiceStep(dt);
      if (step.stepDt <= 0) break;
      if (step.turnRate.abs() > 0.015) {
        applyHomeLookRotation(rig, step.turnRate, 0, step.stepDt);
      }
      if (step.stickX.abs() > 0.015 || step.stickY.abs() > 0.015) {
        rig.eyeCenter = controller.applySmoothRigLocomotion(
          rig: rig,
          stickX: step.stickX,
          stickY: step.stickY,
          edgeTurnEnabled: false,
          manualLook: step.turnRate.abs() > 0.015,
          dt: step.stepDt,
          speed: 1.8,
          maxSpeed: 2.6,
          accelerationSeconds: 2.0,
          walkSpace: walkSpace,
        );
      }
    }
  }

  group('3D Voice Locomotion — forward, backward, sideways & turn', () {
    test(
      'walks forward on frame 1 even right after suspendSmoothLocomotion()',
      () {
        final controller = VirtualHomeLocomotionController();
        final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));

        // Simulate Subtle Menu closing or fresh connection latching _awaitingNeutral
        controller.suspendSmoothLocomotion();

        // "caminar un poco adelante" -> stickY = 0.80, duration = 1.05s
        controller.startVoiceMotion(stickY: 0.80, durationSeconds: 1.05);
        // Even a late suspendSmoothLocomotion while voice is active must not block it
        controller.suspendSmoothLocomotion();

        runVoiceFrames(controller, rig, frames: 80);

        expect(controller.isVoiceMoving, isFalse);
        expect(rig.eyeCenter.z, closeTo(-1.69, 0.15));
        expect(rig.eyeCenter.x, closeTo(0.0, 1e-4));
        expect(rig.eyeCenter.y, closeTo(1.6, 1e-5));
      },
    );

    test('walks backward ("hacia tras") cleanly along +Z', () {
      final controller = VirtualHomeLocomotionController();
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));

      controller.startVoiceMotion(stickY: -0.75, durationSeconds: 1.05);
      runVoiceFrames(controller, rig, frames: 80);

      expect(controller.isVoiceMoving, isFalse);
      expect(rig.eyeCenter.z, closeTo(1.58, 0.15));
      expect(rig.eyeCenter.x, closeTo(0.0, 1e-4));
    });

    test('moves sideways ("a un lado") left and right without rotating view', () {
      final controller = VirtualHomeLocomotionController();
      final rigRight = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      controller.startVoiceMotion(stickX: 0.78, durationSeconds: 1.05);
      runVoiceFrames(controller, rigRight, frames: 80);
      // In flutter_scene left-handed projection, screen-right at identity pose is -X.
      expect(rigRight.eyeCenter.x, closeTo(-1.65, 0.15));
      expect(rigRight.eyeCenter.z, closeTo(0.0, 1e-4));
      expect(rigRight.yaw, closeTo(0.0, 1e-6));

      final rigLeft = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      controller.startVoiceMotion(stickX: -0.78, durationSeconds: 1.05);
      runVoiceFrames(controller, rigLeft, frames: 80);
      expect(rigLeft.eyeCenter.x, closeTo(1.65, 0.15));
      expect(rigLeft.eyeCenter.z, closeTo(0.0, 1e-4));
      expect(rigLeft.yaw, closeTo(0.0, 1e-6));
    });

    test('turns ("girar" 90° and "media vuelta" 180°) with exact angular travel', () {
      final controller = VirtualHomeLocomotionController();
      final rig90 = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      // 90° = pi/2 rad at angular speed 0.68 * 2.2 = 1.496 rad/s -> ~1.05s
      controller.startVoiceMotion(turnRate: 0.68, durationSeconds: 1.05);
      runVoiceFrames(controller, rig90, frames: 90);
      expect(rig90.yaw.abs(), closeTo(math.pi / 2, 0.04));

      final rig180 = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      controller.startVoiceMotion(turnRate: 1.0, durationSeconds: 1.43);
      runVoiceFrames(controller, rig180, frames: 120);
      expect(rig180.yaw.abs(), closeTo(math.pi, 0.04));
    });
  });

  group('3D Specific-Point Navigation ("ir a un punto específico")', () {
    test('resolves gaze-projected floor point safely within walkable space', () {
      final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
      final walkSpace = HomeWalkSpace(
        rooms: [...HomeLobbyLayout.rooms, ...layout.rooms],
        boxes: [...HomeLobbyLayout.boxes, ...layout.boxes],
      );
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 1.2));
      // Face down corridor (+Z) by rotating 180°
      rig.rotate(math.pi, 0);

      final resolved = VirtualHomeLocomotionController.resolveSpecificPoint(
        guidance: const VrHomeGuidance(
          actionType: VrHomeActionType.goToPoint,
          speechResponse: 'Saltando al punto frente a tu mirada.',
          useGazeTarget: true,
          distanceMeters: 4.0,
        ),
        rig: rig,
        walkSpace: walkSpace,
        portals: layout.portals,
      );

      expect(resolved.destination, isNotNull);
      expect(
        walkSpace.canStand(resolved.destination!.x, resolved.destination!.z),
        isTrue,
      );
      expect(resolved.destination!.z, greaterThan(4.5));
    });

    test('resolves booth code ("L-02") & room name ("Cyberneom") and faces portal', () {
      final mallLayout = HomeFamousMallLayout.build(
        archetype: FamousMallArchetype.plazaArtzMexico,
        mallTitle: 'Plaza Artz',
        booths: VrHomeEcosystemRoom.defaults,
      );
      final walkSpace = HomeWalkSpace(
        rooms: mallLayout.rooms,
        boxes: mallLayout.boxes,
      );
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(
          HomeFamousMallLayout.spawnX,
          1.6,
          HomeFamousMallLayout.spawnZ,
        ),
      );

      final boothResolved =
          VirtualHomeLocomotionController.resolveSpecificPoint(
            guidance: const VrHomeGuidance(
              actionType: VrHomeActionType.goToPoint,
              speechResponse: 'Dirigiéndote hacia l-02.',
              targetPointQuery: 'l-02',
            ),
            rig: rig,
            walkSpace: walkSpace,
            portals: mallLayout.portals,
          );

      expect(boothResolved.destination, isNotNull);
      expect(
        boothResolved.targetName,
        mallLayout.portals[1].room.title,
      );
      expect(
        walkSpace.canStand(
          boothResolved.destination!.x,
          boothResolved.destination!.z,
        ),
        isTrue,
      );

      VirtualHomeLocomotionController.faceHorizontalPoint(
        rig,
        boothResolved.destination!,
        boothResolved.faceLookX!,
        boothResolved.faceLookZ!,
      );
      final toDoor = vm.Vector3(
        boothResolved.faceLookX! - boothResolved.destination!.x,
        0,
        boothResolved.faceLookZ! - boothResolved.destination!.z,
      )..normalize();
      final rigFlatFwd = vm.Vector3(rig.forward.x, 0, rig.forward.z)
        ..normalize();
      expect(rigFlatFwd.dot(toDoor), greaterThan(0.99));

      // Named room lookup ("cyberneom")
      final namedResolved =
          VirtualHomeLocomotionController.resolveSpecificPoint(
            guidance: const VrHomeGuidance(
              actionType: VrHomeActionType.goToPoint,
              speechResponse: 'Dirigiéndote hacia cyberneom.',
              targetPointQuery: 'cyberneom',
            ),
            rig: rig,
            walkSpace: walkSpace,
            portals: mallLayout.portals,
          );
      expect(namedResolved.destination, isNotNull);
      expect(
        namedResolved.targetName!.toLowerCase(),
        contains('cyberneom'),
      );
    });

    test('resolves explicit metric XZ coordinates inside walkable floor', () {
      final mallLayout = HomeFamousMallLayout.build(
        archetype: FamousMallArchetype.galleriaMilano,
        mallTitle: 'Galleria Milano',
        booths: VrHomeEcosystemRoom.defaults,
      );
      final walkSpace = HomeWalkSpace(
        rooms: mallLayout.rooms,
        boxes: mallLayout.boxes,
      );
      final rig = StereoHeadRig(
        eyeCenter: vm.Vector3(
          HomeFamousMallLayout.spawnX,
          1.6,
          HomeFamousMallLayout.spawnZ,
        ),
      );

      final coordResolved =
          VirtualHomeLocomotionController.resolveSpecificPoint(
            guidance: const VrHomeGuidance(
              actionType: VrHomeActionType.goToPoint,
              speechResponse: 'Yendo al punto (5.5, -4.0).',
              targetX: 5.5,
              targetZ: -4.0,
            ),
            rig: rig,
            walkSpace: walkSpace,
          );
      expect(coordResolved.destination, isNotNull);
      expect(coordResolved.destination!.x, closeTo(5.5, 1.2));
      expect(coordResolved.destination!.z, closeTo(-4.0, 1.2));
      expect(
        walkSpace.canStand(
          coordResolved.destination!.x,
          coordResolved.destination!.z,
        ),
        isTrue,
      );
    });
  });
}
