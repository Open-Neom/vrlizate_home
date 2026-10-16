import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';
import 'package:vrlizate_home/src/spatial/virtual_home_locomotion_controller.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart' show StereoHeadRig;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void step(
    VirtualHomeLocomotionController controller,
    StereoHeadRig rig, {
    double x = 0,
    double y = -1,
    double? intentX,
    double? intentY,
    bool? atEdge,
    bool edgeTurnEnabled = true,
    bool manualLook = false,
    double dt = 1 / 60,
    HomeWalkSpace? walkSpace,
  }) {
    rig.eyeCenter = controller.applySmoothRigLocomotion(
      rig: rig,
      stickX: x,
      stickY: y,
      intentX: intentX,
      intentY: intentY,
      atEdge: atEdge,
      edgeTurnEnabled: edgeTurnEnabled,
      manualLook: manualLook,
      dt: dt,
      speed: 1.6,
      maxSpeed: 4.8,
      accelerationSeconds: 2.4,
      maxRadius: 1000,
      walkSpace: walkSpace,
    );
  }

  test(
    'rear edge takes backward steps then faces and travels the same way',
    () {
      final controller = VirtualHomeLocomotionController();
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      for (var frame = 0; frame < 36; frame++) {
        step(controller, rig);
      }
      expect(rig.bodyYaw, 0);
      expect(rig.eyeCenter.z, greaterThan(.9));
      for (var frame = 0; frame < 264; frame++) {
        step(controller, rig);
      }
      expect(rig.bodyYaw.abs(), closeTo(math.pi, 1e-5));
      expect(rig.eyeCenter.x, closeTo(0, 1e-4));
      expect(rig.eyeCenter.z, greaterThan(15));
      expect(rig.cameraRig.yaw, 0);
      final settledYaw = rig.bodyYaw;
      final z = rig.eyeCenter.z;
      for (var frame = 0; frame < 240; frame++) {
        step(controller, rig);
      }
      expect(rig.bodyYaw, closeTo(settledYaw, 1e-9));
      expect(rig.eyeCenter.z, greaterThan(z));
      expect(rig.eyeCenter.x, closeTo(0, 1e-4));
    },
  );

  test('right edge stays screen-right through the quarter turn', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    for (var frame = 0; frame < 240; frame++) {
      step(controller, rig, x: 1, y: 0);
    }
    expect(rig.bodyYaw, closeTo(-math.pi / 2, 1e-5));
    expect(rig.eyeCenter.x, lessThan(-10));
    expect(rig.eyeCenter.z, closeTo(0, 1e-4));
  });

  test('partial stick keeps precise backward motion without changing view', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    for (var frame = 0; frame < 300; frame++) {
      step(controller, rig, y: -.5);
    }
    expect(rig.bodyYaw, 0);
    expect(rig.eyeCenter.z, closeTo(4, 1e-4));
  });

  test('raw edge intent turns even while movement sensitivity is ramping', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    for (var frame = 0; frame < 90; frame++) {
      step(controller, rig, y: -.4, intentX: 0, intentY: -1);
    }
    expect(rig.bodyYaw.abs(), greaterThan(.4));
    expect(controller.currentWalkSpeed, closeTo(.64, 1e-5));
    expect(rig.eyeCenter.x, closeTo(0, 1e-4));
  });

  test(
    'rim metadata starts a turn before the movement gain reaches maximum',
    () {
      final controller = VirtualHomeLocomotionController();
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      for (var frame = 0; frame < 90; frame++) {
        step(controller, rig, y: -.4, atEdge: true);
      }
      expect(rig.bodyYaw.abs(), greaterThan(.4));
      expect(rig.eyeCenter.x, closeTo(0, 1e-4));
      final yaw = rig.bodyYaw;
      for (var frame = 0; frame < 120; frame++) {
        step(controller, rig, atEdge: false);
      }
      expect(rig.bodyYaw, yaw);
    },
  );

  test('digital movement can keep ordinary strafing at full input', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    for (var frame = 0; frame < 240; frame++) {
      step(controller, rig, x: 1, y: 0, edgeTurnEnabled: false);
    }
    expect(rig.bodyYaw, 0);
    expect(rig.eyeCenter.x, lessThan(-10));
    expect(rig.eyeCenter.z, closeTo(0, 1e-4));
  });

  test('manual look cancels assistance until the left stick is released', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    for (var frame = 0; frame < 90; frame++) {
      step(controller, rig);
    }
    expect(rig.bodyYaw.abs(), greaterThan(.4));
    step(controller, rig, manualLook: true);
    final yaw = rig.bodyYaw;
    for (var frame = 0; frame < 240; frame++) {
      step(controller, rig);
    }
    expect(rig.bodyYaw, yaw);
    step(controller, rig, y: 0);
    for (var frame = 0; frame < 90; frame++) {
      step(controller, rig);
    }
    expect((rig.bodyYaw - yaw).abs(), greaterThan(.4));
  });

  test(
    'suspension cancels target and requires neutral before another turn',
    () {
      final controller = VirtualHomeLocomotionController();
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      for (var frame = 0; frame < 90; frame++) {
        step(controller, rig);
      }
      controller.suspendSmoothLocomotion();
      final yaw = rig.bodyYaw;
      final position = rig.eyeCenter.clone();
      for (var frame = 0; frame < 180; frame++) {
        step(controller, rig);
      }
      expect(rig.bodyYaw, yaw);
      expect(rig.eyeCenter, position);
      expect(controller.currentWalkSpeed, 0);
      step(controller, rig, y: 0);
      for (var frame = 0; frame < 36; frame++) {
        step(controller, rig);
      }
      expect(rig.bodyYaw, yaw);
      expect((rig.eyeCenter - position).length, greaterThan(.9));
    },
  );

  test(
    'a wall blocks walking but never resets the in-place heading target',
    () {
      final space = HomeWalkSpace(
        rooms: const [HomeRoom('test', 'Test', -100, 100, -100, 100)],
        boxes: const [
          HomeLobbyBox(
            'wall',
            x: 0,
            y: 1.5,
            z: 2,
            width: 10,
            height: 3,
            depth: .1,
            finish: HomeLobbyFinish.plaster,
          ),
        ],
      );
      final controller = VirtualHomeLocomotionController();
      final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
      for (var frame = 0; frame < 360; frame++) {
        step(controller, rig, walkSpace: space);
        expect(space.canStand(rig.eyeCenter.x, rig.eyeCenter.z), isTrue);
        expect(rig.eyeCenter.z, lessThanOrEqualTo(1.7 + 1e-6));
      }
      expect(rig.bodyYaw.abs(), closeTo(math.pi, 1e-5));
      expect(controller.currentWalkSpeed, 0);
    },
  );

  test('tracked head motion stays independent of the virtual turn', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    for (var frame = 0; frame < 300; frame++) {
      rig.cameraRig.setOrientation(frame < 90 ? .3 : .7, 0);
      step(controller, rig);
    }
    expect(rig.bodyYaw.abs(), closeTo(math.pi, 1e-5));
    expect(rig.cameraRig.yaw, closeTo(.7, 1e-9));
  });

  test('right-stick elevation and the left rear turn operate together', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));
    for (var frame = 0; frame < 300; frame++) {
      applyHomeLookRotation(rig, 0, .15, 1 / 60);
      step(controller, rig);
    }
    expect(rig.bodyYaw.abs(), closeTo(math.pi, 1e-5));
    expect(rig.bodyPitch, lessThan(-.3));
    expect(rig.cameraRig.yaw, 0);
    expect(rig.eyeCenter.x, closeTo(0, 1e-4));
    expect(rig.eyeCenter.z, greaterThan(15));
  });
}
