import 'dart:math';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show VrStickEdgeTurn;
import 'package:vrlizate_scene/vrlizate_scene.dart'
    show StereoHeadRig, VrStickLook;

import 'virtual_home_models.dart';
import 'home_walk_space.dart';

/// Stick +Y means up; CameraRig's positive pitch looks down. Keep the same
/// signs as VrSceneInputController so Home and experiences do not invert aim.
({double yaw, double pitch}) homeLookRotation(double x, double y, double dt) {
  if (!x.isFinite || !y.isFinite || !dt.isFinite || dt <= 0) {
    return (yaw: 0, pitch: 0);
  }
  final step = min(dt, 0.1);
  // Stick drivers already shape input. Discard only one BLE quantum (1/127),
  // independently per axis so vertical input cannot admit lateral noise.
  final horizontal = x.abs() > 0.015 ? x.clamp(-1.0, 1.0) : 0.0;
  return (
    yaw: -horizontal * 2.2 * step,
    pitch: VrStickLook.pitchDelta(y, step),
  );
}

/// Applies manual look without overwriting the gravity-referenced head pitch.
/// The tracker replaces cameraRig.pitch on every sensor sample; bodyPitch
/// persists and is composed by StereoHeadRig for rendering and gaze rays.
void applyHomeLookRotation(StereoHeadRig rig, double x, double y, double dt) {
  final rotation = homeLookRotation(x, y, dt);
  rig.rotate(rotation.yaw, 0);
  rig.bodyPitch = (rig.bodyPitch + rotation.pitch).clamp(-1.45, 1.45);
}

/// Manages parabolic arc jump and smooth analog thumbstick locomotion in the 3D Virtual Home.
class VirtualHomeLocomotionController {
  ArcJumpAnim? _currentJump;
  bool _awaitingNeutral = false;
  double _travelSeconds = 0;
  double _currentWalkSpeed = 0;
  final vm.Vector3 _lastMoveDirection = vm.Vector3.zero();
  final VrStickEdgeTurn _edgeTurn = VrStickEdgeTurn();

  /// Current intended ground speed, including analog deflection, in m/s.
  /// Zero when neutral, suspended or blocked by a wall.
  double get currentWalkSpeed => _currentWalkSpeed;

  void _resetTravelSpeed() {
    _travelSeconds = 0;
    _currentWalkSpeed = 0;
    _lastMoveDirection.setZero();
  }

  /// A modal/route captured the stick. Require release before walking again.
  void suspendSmoothLocomotion() {
    _awaitingNeutral = true;
    _resetTravelSpeed();
    _edgeTurn.reset();
  }

  /// A route change or explicit Home action cancels any pending destination.
  void cancelJump() {
    _currentJump = null;
    suspendSmoothLocomotion();
  }

  ArcJumpAnim? get currentJump => _currentJump;
  bool get isJumping => _currentJump != null;

  /// Initiates an arc jump locomotion toward the destination.
  void startJump({
    required vm.Vector3 from,
    required vm.Vector3 to,
    required String targetName,
    double duration = 0.55,
  }) {
    suspendSmoothLocomotion();
    HapticFeedback.mediumImpact();
    _currentJump = ArcJumpAnim(
      from: from,
      to: to,
      targetName: targetName,
      duration: duration,
    );
  }

  /// Updates camera position along the parabolic trajectory.
  ///
  /// Returns a tuple containing:
  /// - [newPosition]: current camera eye center in 3D space.
  /// - [isFinished]: true if user just reached destination on this frame.
  /// - [arrivedZoneName]: name of the destination waypoint if finished.
  (vm.Vector3, bool, String?) tick(double dt, vm.Vector3 currentEyeCenter) {
    final jump = _currentJump;
    if (jump == null) {
      return (currentEyeCenter, false, null);
    }

    jump.t += dt / jump.duration;

    if (jump.t >= 1.0) {
      final arrivedName = jump.targetName;
      final finalPos = jump.to;
      _currentJump = null;
      HapticFeedback.lightImpact();
      return (finalPos, true, arrivedName);
    }

    // Horizontal linear mix
    final pos = jump.from + (jump.to - jump.from) * jump.t;
    // Parabolic vertical apex (+0.28m peak)
    pos.y = 1.60 + sin(jump.t * pi) * 0.28;

    return (pos, false, null);
  }

  /// Walks and gradually faces a direction held at the left stick's outer edge.
  ///
  /// The edge gesture rotates the virtual body, leaving tracked head motion and
  /// manual right-stick look independent. The shared policy preserves the
  /// chosen travel direction as the body turns, so a held rear direction takes
  /// backward steps first and becomes forward travel after completing the turn.
  /// Intermediate stick deflection keeps ordinary strafing and backing up.
  ///
  /// [intentX] and [intentY] optionally describe the unshaped physical stick;
  /// movement still uses the progressively shaped [stickX] and [stickY].
  /// [atEdge] can report only the physical rim contact without extra axes.
  /// Disable [edgeTurnEnabled] for digital navigation such as WASD.
  /// [manualLook] reports manual horizontal look; elevation alone should not
  /// interrupt the left stick's heading so both controls can work together.
  vm.Vector3 applySmoothRigLocomotion({
    required StereoHeadRig rig,
    required double stickX,
    required double stickY,
    required double dt,
    double? intentX,
    double? intentY,
    bool? atEdge,
    bool edgeTurnEnabled = true,
    bool manualLook = false,
    double speed = 2.4,
    double? maxSpeed,
    double accelerationSeconds = 2.4,
    double maxRadius = 15.0,
    HomeWalkSpace? walkSpace,
  }) {
    if (!_canWalk(
      stickX: stickX,
      stickY: stickY,
      dt: dt,
      speed: speed,
      topSpeed: maxSpeed ?? speed,
      accelerationSeconds: accelerationSeconds,
    )) {
      return rig.eyeCenter;
    }
    final input = _edgeTurn.update(
      stickX: stickX,
      stickY: stickY,
      intentX: intentX,
      intentY: intentY,
      atEdge: atEdge,
      enabled: edgeTurnEnabled,
      heading: rig.bodyYaw,
      dt: dt,
      manualLook: manualLook,
    );
    // rotate() can modify the tracked camera yaw when no spatial tracker is
    // active. This assist always belongs to the body and must observe its own
    // progress on the next frame, independently of physical head tracking.
    rig.bodyYaw += input.yawDelta;
    return applySmoothLocomotion(
      currentEyeCenter: rig.eyeCenter,
      headOrientation: rig.orientation,
      stickX: input.movementX,
      stickY: input.movementY,
      dt: dt,
      speed: speed,
      maxSpeed: maxSpeed,
      accelerationSeconds: accelerationSeconds,
      maxRadius: maxRadius,
      walkSpace: walkSpace,
    );
  }

  bool _canWalk({
    required double stickX,
    required double stickY,
    required double dt,
    required double speed,
    required double topSpeed,
    required double accelerationSeconds,
  }) {
    if (isJumping) return false;
    if (!dt.isFinite ||
        dt <= 0 ||
        !stickX.isFinite ||
        !stickY.isFinite ||
        !speed.isFinite ||
        speed < 0 ||
        !topSpeed.isFinite ||
        topSpeed < speed ||
        !accelerationSeconds.isFinite ||
        accelerationSeconds <= 0) {
      _resetTravelSpeed();
      _edgeTurn.reset();
      return false;
    }
    // Preserve gentle driver-shaped movement; ignore one BLE quantum (1/127).
    if (stickX.abs() <= 0.015 && stickY.abs() <= 0.015) {
      _awaitingNeutral = false;
      _resetTravelSpeed();
      _edgeTurn.reset();
      return false;
    }
    return !_awaitingNeutral;
  }

  /// Applies smooth horizontal locomotion driven by analog thumbstick inputs.
  ///
  /// - [currentEyeCenter]: current camera position in world space.
  /// - [headOrientation]: orientation of the player's head (to move relative to gaze direction).
  /// - [stickX]: horizontal deflection (-1.0 to 1.0, strafe left/right).
  /// - [stickY]: vertical deflection (-1.0 to 1.0, walk backward/forward).
  /// - [dt]: delta time since last frame in seconds.
  /// - [speed]: walking speed in meters/second (default 2.4 m/s).
  /// - [maxSpeed]: optional progressive travel ceiling; omit for fixed speed.
  /// - [accelerationSeconds]: time from [speed] to [maxSpeed] with a firm stick.
  ///   Small deflections (<0.7) keep precise base-speed movement. Neutral,
  ///   suspension, a direction reversal and a blocking wall reset acceleration.
  /// - [maxRadius]: perimeter clamp radius from world origin in meters (default 15.0 m).
  vm.Vector3 applySmoothLocomotion({
    required vm.Vector3 currentEyeCenter,
    required vm.Quaternion headOrientation,
    required double stickX,
    required double stickY,
    required double dt,
    double speed = 2.4,
    double? maxSpeed,
    double accelerationSeconds = 2.4,
    double maxRadius = 15.0,
    HomeWalkSpace? walkSpace,
  }) {
    final topSpeed = maxSpeed ?? speed;
    if (!_canWalk(
      stickX: stickX,
      stickY: stickY,
      dt: dt,
      speed: speed,
      topSpeed: topSpeed,
      accelerationSeconds: accelerationSeconds,
    )) {
      return currentEyeCenter;
    }

    // Extract horizontal forward vector from head orientation
    final lookDir = headOrientation.rotate(vm.Vector3(0, 0, -1));
    final forward = vm.Vector3(lookDir.x, 0, lookDir.z);
    if (forward.length2 > 1e-4) {
      forward.normalize();
    } else {
      forward.setValues(0, 0, -1);
    }

    // flutter_scene's left-handed view uses screenRight = up × forward.
    // With an identity pose screen-right is world -X, not local +X.
    final right = vm.Vector3(forward.z, 0, -forward.x);

    // Combine stick deflection
    final moveDir = forward * stickY + right * stickX;
    if (moveDir.length2 > 1.0) {
      moveDir.normalize();
    }

    final magnitude = moveDir.length;
    final direction = moveDir / magnitude;
    // A held forward boost must never turn into an instant fast reverse/strafe.
    if (_lastMoveDirection.length2 > 0 &&
        _lastMoveDirection.dot(direction) < 0.5) {
      _resetTravelSpeed();
    }
    _lastMoveDirection.setFrom(direction);

    // Preserve the fixed-speed API; progressive/collision travel bounds stalled
    // frames to 100 ms, so a resumed frame cannot advance the whole ramp.
    final step = maxSpeed != null || walkSpace != null ? min(dt, 0.1) : dt;
    double distance;
    if (topSpeed > speed && magnitude >= 0.7) {
      final previous = _travelSeconds;
      _travelSeconds = min(previous + step, accelerationSeconds);
      // Integrate the linear ramp, including any part past the speed ceiling.
      // This gives equal distance at 30, 60 and 120 Hz.
      final rampStep = _travelSeconds - previous;
      final rampArea =
          (previous + _travelSeconds) * rampStep / (2 * accelerationSeconds) +
          (step - rampStep);
      distance = speed * step + (topSpeed - speed) * rampArea;
      _currentWalkSpeed =
          (speed + (topSpeed - speed) * _travelSeconds / accelerationSeconds) *
          magnitude;
    } else {
      _travelSeconds = 0;
      distance = speed * step;
      _currentWalkSpeed = speed * magnitude;
    }

    if (walkSpace != null) {
      final result = walkSpace.move(
        currentEyeCenter,
        moveDir.x * distance,
        moveDir.z * distance,
      );
      final movedX = result.x - currentEyeCenter.x;
      final movedZ = result.z - currentEyeCenter.z;
      // Do not accumulate a running start while pushing into a wall/furniture.
      if (movedX * movedX + movedZ * movedZ <
          distance * distance * magnitude * magnitude * 0.25) {
        _resetTravelSpeed();
      }
      return result;
    }
    final newPos = currentEyeCenter + moveDir * distance;

    // Maintain eye height at 1.60m
    newPos.y = 1.60;

    // Perimeter boundary clamp
    final horizontalDist = sqrt(newPos.x * newPos.x + newPos.z * newPos.z);
    if (horizontalDist > maxRadius) {
      final ratio = maxRadius / horizontalDist;
      newPos.x *= ratio;
      newPos.z *= ratio;
      _resetTravelSpeed();
    }

    return newPos;
  }
}
