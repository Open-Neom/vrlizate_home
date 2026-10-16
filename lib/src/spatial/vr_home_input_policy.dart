import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart' show StereoHeadRig;

import 'package:vrlizate_joystick/vrlizate_joystick.dart';
import 'vr_phone_pointer_policy.dart';

enum VrHomeGamepadAction { none, primary, back, previousCategory, nextCategory }

/// Empty-space taps may reveal preparation only when no world modal owns
/// input. This also includes a modal whose GPU labels are still loading:
/// hiding its gaze would leave no toolbar or touch path to recover it.
bool shouldRevealHomePreparationOnMiss({
  required bool controlsHidden,
  required bool hasWorldModal,
}) => controlsHidden && !hasWorldModal;

/// The reference driver encodes X/Y/L2 as `trigger` plus a button payload.
/// Reserve these events before the scene interprets a generic primary action.
class VrHomeGamepadPolicy {
  final List<bool> _held = List.filled(3, false);

  VrHomeGamepadAction handle(VrInputEvent event) {
    if (event.source != VrInputSource.gamepad || event.handled) {
      return VrHomeGamepadAction.none;
    }
    if (event.type == VrInputType.navigate) return VrHomeGamepadAction.none;
    if (event.type == VrInputType.select || event.type == VrInputType.back) {
      event.consume();
      if (!event.active) return VrHomeGamepadAction.none;
      // A/B are press-only events in VrGamepadDriver, not held-state triggers.
      return event.type == VrInputType.back
          ? VrHomeGamepadAction.back
          : VrHomeGamepadAction.primary;
    }
    final button = event.data?[VrGamepadDriver.buttonKey];
    final isX =
        event.type == VrInputType.buttonX ||
        (event.type == VrInputType.trigger &&
            (button == VrGamepadButton.x || button == 'x'));
    final isY =
        event.type == VrInputType.buttonY ||
        (event.type == VrInputType.trigger &&
            (button == VrGamepadButton.y || button == 'y'));
    final isPrimary =
        event.type == VrInputType.trigger &&
        (button == null || button == VrGamepadButton.r2 || button == 'r2');
    if (!isX && !isY && !isPrimary) {
      // L2/unknown secondary triggers must never open the focused demo.
      if (event.type == VrInputType.trigger) event.consume();
      return VrHomeGamepadAction.none;
    }
    event.consume();
    final index = isX ? 0 : (isY ? 1 : 2);
    final pressed = event.active && !_held[index];
    _held[index] = event.active;
    if (!pressed) return VrHomeGamepadAction.none;
    return isX
        ? VrHomeGamepadAction.previousCategory
        : (isY
              ? VrHomeGamepadAction.nextCategory
              : VrHomeGamepadAction.primary);
  }

  void reset() => _held.fillRange(0, _held.length, false);
}

/// Resolves the same touch-pad direction as demos without publishing a second
/// pointer owner to the Home arbiter. Outputs are borrowed, allocation-free
/// vectors/quaternions; the existing arm model still estimates the ray origin.
class VrHomeRemotePointer {
  VrHomeRemotePointer({VrInputEventPool? eventPool})
    : _pool = eventPool ?? VrInputEventPool(capacity: 1);

  final VrInputEventPool _pool;
  final VrSpatialInputState _spatial = VrSpatialInputState();
  final Map<String, dynamic> _payload = {
    'laserX': 0.0,
    'laserY': 0.0,
    'relativeToHead': true,
  };
  final vm.Ray _ray = vm.Ray();
  final vm.Quaternion orientation = vm.Quaternion.identity();
  vm.Vector3 get forward => _ray.direction;

  static bool isPointing(RemoteControllerState state) =>
      VrPhonePointerPolicy.isPointing(state);

  void resolve({
    required RemoteControllerState state,
    required StereoHeadRig rig,
  }) {
    VrPhonePointerPolicy.writePayload(_payload, state);
    final event = _pool.acquire(
      type: VrInputType.pointerMove,
      source: VrInputSource.remotePhone,
      timestampMicrosecondsSinceEpoch: 0,
      data: _payload,
      active: isPointing(state),
    );
    try {
      _spatial.handleEvent(event);
    } finally {
      _pool.release(event);
    }
    _spatial.writeRay(
      _ray,
      origin: rig.eyeCenter,
      forward: rig.forward,
      screenRight: rig.screenRight,
      up: rig.up,
    );
    // Shortest rotation from local -Z to the resolved touch ray. The visible
    // beam always matches selection, even after release or a controller shake.
    final w = 1 - forward.z;
    if (w < 1e-8) {
      orientation.setValues(1, 0, 0, 0);
    } else {
      orientation.setValues(forward.y, -forward.x, 0, w);
      orientation.normalize();
    }
  }

  void reset() {
    _spatial.reset();
    _ray.direction.setValues(0, 0, -1);
    orientation.setValues(0, 0, 0, 1);
  }
}
