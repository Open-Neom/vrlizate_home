import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart';
import 'package:vrlizate_home/src/spatial/vr_home_input_policy.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart' show StereoHeadRig;

void _closeVector(vm.Vector3 actual, vm.Vector3 expected) {
  expect(actual.x, closeTo(expected.x, 1e-5));
  expect(actual.y, closeTo(expected.y, 1e-5));
  expect(actual.z, closeTo(expected.z, 1e-5));
}

RemoteControllerState _aim({
  RemoteControllerMode mode = RemoteControllerMode.laser,
  bool pointerPoseReady = true,
  bool controllerVisible = true,
  bool isNeutralized = false,
}) => RemoteControllerState(
  // The transport quaternion is not a physical-posture attestation.
  orientation: vm.Quaternion.euler(.8, 1.2, .7),
  mode: mode,
  laserX: .35,
  laserY: -.15,
  pointerPoseReady: pointerPoseReady,
  controllerVisible: controllerVisible,
  isNeutralized: isNeutralized,
);

void main() {
  test(
    'legacy pose cannot retain Home ray ownership through mode or offsets',
    () {
      final rig = StereoHeadRig()..setOrientation(.5, -.2);
      final pointer = VrHomeRemotePointer();
      pointer.resolve(state: _aim(), rig: rig);
      final legacy = RemoteControllerState(
        orientation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
        mode: RemoteControllerMode.laser,
        laserSlideActive: true,
        laserX: .35,
        laserY: -.15,
      );
      expect(VrHomeRemotePointer.isPointing(legacy), isFalse);
      pointer.resolve(state: legacy, rig: rig);
      _closeVector(pointer.forward, rig.forward);
      expect(
        shouldLaserOwnHomeHover(
          isRemoteConnected: true,
          remoteLaserMode: VrHomeRemotePointer.isPointing(legacy),
          remoteLaserHitsTarget: true,
        ),
        isFalse,
      );
    },
  );

  test(
    'blocked pose or feedback yields to current gaze and preserves touch aim',
    () {
      final rig = StereoHeadRig()..setOrientation(.5, -.2);
      final pointer = VrHomeRemotePointer();
      pointer.resolve(state: _aim(), rig: rig);
      for (final mode in RemoteControllerMode.values) {
        for (final blocked in [
          _aim(mode: mode, pointerPoseReady: false),
          _aim(mode: mode, controllerVisible: false),
          _aim(mode: mode, isNeutralized: true),
        ]) {
          rig.setOrientation(-.7, .1);
          expect(VrHomeRemotePointer.isPointing(blocked), isFalse);
          pointer.resolve(state: blocked, rig: rig);
          _closeVector(pointer.forward, rig.forward);
          expect(
            shouldLaserOwnHomeHover(
              isRemoteConnected: true,
              remoteLaserMode: VrHomeRemotePointer.isPointing(blocked),
              remoteLaserHitsTarget: true,
            ),
            isFalse,
          );
          final expected = VrHomeRemotePointer()
            ..resolve(
              state: _aim(mode: mode),
              rig: rig,
            );
          pointer.resolve(
            state: _aim(mode: mode),
            rig: rig,
          );
          expect(VrHomeRemotePointer.isPointing(_aim(mode: mode)), isTrue);
          _closeVector(pointer.forward, expected.forward);
          final visual = vm.Matrix4.compose(
            vm.Vector3.zero(),
            pointer.orientation,
            vm.Vector3.all(1),
          );
          _closeVector(
            visual.transformed3(vm.Vector3(0, 0, -1)),
            pointer.forward,
          );
        }
      }
    },
  );

  test(
    'unready pointing yields hover while A remains a primary gamepad action',
    () {
      final inactive = _aim(pointerPoseReady: false);
      expect(
        shouldLaserOwnHomeHover(
          isRemoteConnected: true,
          remoteLaserMode: VrHomeRemotePointer.isPointing(inactive),
          remoteLaserHitsTarget: true,
        ),
        isFalse,
      );
      final arbiter = VrInputArbiter();
      addTearDown(arbiter.dispose);
      final driver = VrGamepadDriver();
      arbiter.attachDriver(driver);
      final policy = VrHomeGamepadPolicy();
      final actions = <VrHomeGamepadAction>[];
      arbiter.addListener((event) {
        final action = policy.handle(event);
        if (action != VrHomeGamepadAction.none) actions.add(action);
      });
      driver.updateButton(VrGamepadButton.a, true);
      driver.updateButton(VrGamepadButton.a, false);
      expect(actions, [VrHomeGamepadAction.primary]);
      expect(arbiter.pool.inUseCount, 0);
    },
  );
}
