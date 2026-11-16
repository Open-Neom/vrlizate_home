import 'dart:math';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show VrStickEdgeTurn;
import 'package:vrlizate_scene/vrlizate_scene.dart'
    show StereoHeadRig, VrStickLook;

import 'virtual_home_models.dart';
import 'home_ecosystem_layout.dart';
import 'home_lobby_layout.dart';
import 'home_walk_space.dart';
import 'vr_home_spatial_bindings.dart';

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
  double _voiceRemainingSec = 0;
  double _voiceStickX = 0;
  double _voiceStickY = 0;
  double _voiceTurnRate = 0;
  final vm.Vector3 _lastMoveDirection = vm.Vector3.zero();
  final VrStickEdgeTurn _edgeTurn = VrStickEdgeTurn();

  /// Current intended ground speed, including analog deflection, in m/s.
  /// Zero when neutral, suspended or blocked by a wall.
  double get currentWalkSpeed => _currentWalkSpeed;

  /// True while a timed spoken locomotion command is driving the rig.
  bool get isVoiceMoving => _voiceRemainingSec > 0;

  void _resetTravelSpeed() {
    _travelSeconds = 0;
    _currentWalkSpeed = 0;
    _lastMoveDirection.setZero();
  }

  /// Starts explicit voice-driven walking, strafing, or turning without waiting
  /// for a physical thumbstick neutral edge.
  void startVoiceMotion({
    double stickX = 0.0,
    double stickY = 0.0,
    double turnRate = 0.0,
    required double durationSeconds,
  }) {
    final sx = stickX.isFinite ? stickX.clamp(-1.0, 1.0) : 0.0;
    final sy = stickY.isFinite ? stickY.clamp(-1.0, 1.0) : 0.0;
    final tr = turnRate.isFinite ? turnRate.clamp(-1.0, 1.0) : 0.0;
    if (!durationSeconds.isFinite ||
        durationSeconds <= 0 ||
        (sx.abs() <= 0.015 && sy.abs() <= 0.015 && tr.abs() <= 0.015)) {
      stopVoiceMotion();
      return;
    }
    _currentJump = null;
    _awaitingNeutral = false;
    _edgeTurn.reset();
    _voiceStickX = sx;
    _voiceStickY = sy;
    _voiceTurnRate = tr;
    _voiceRemainingSec = durationSeconds.clamp(0.05, 12.0);
  }

  /// Stops any active voice-driven walking, strafing, or turning.
  void stopVoiceMotion() {
    _voiceRemainingSec = 0;
    _voiceStickX = 0;
    _voiceStickY = 0;
    _voiceTurnRate = 0;
    _resetTravelSpeed();
    _edgeTurn.reset();
  }

  /// Consumes up to [dt] seconds of active voice motion and returns the
  /// effective `(stickX, stickY, turnRate, effectiveDt)` step for this frame.
  ({double stickX, double stickY, double turnRate, double stepDt})
  consumeVoiceStep(double dt) {
    if (_voiceRemainingSec <= 0 || !dt.isFinite || dt <= 0) {
      return (stickX: 0, stickY: 0, turnRate: 0, stepDt: 0);
    }
    _awaitingNeutral = false;
    final clampedDt = min(dt, 0.1);
    final stepDt = min(clampedDt, _voiceRemainingSec);
    final sx = _voiceStickX;
    final sy = _voiceStickY;
    final tr = _voiceTurnRate;
    _voiceRemainingSec -= stepDt;
    if (_voiceRemainingSec <= 1e-6) {
      _voiceRemainingSec = 0;
      _voiceStickX = 0;
      _voiceStickY = 0;
      _voiceTurnRate = 0;
    }
    return (stickX: sx, stickY: sy, turnRate: tr, stepDt: stepDt);
  }

  /// A modal/route captured the stick. Require release before walking again.
  void suspendSmoothLocomotion() {
    if (_voiceRemainingSec <= 0) {
      _awaitingNeutral = true;
    }
    _resetTravelSpeed();
    _edgeTurn.reset();
  }

  /// A route change or explicit Home action cancels any pending destination.
  void cancelJump() {
    _currentJump = null;
    stopVoiceMotion();
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
    stopVoiceMotion();
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

  /// Rotates [rig] horizontally so that from [standPos] its horizontal forward
  /// vector points directly at `(lookX, lookZ)`.
  static void faceHorizontalPoint(
    StereoHeadRig rig,
    vm.Vector3 standPos,
    double lookX,
    double lookZ,
  ) {
    final dx = lookX - standPos.x;
    final dz = lookZ - standPos.z;
    final len = sqrt(dx * dx + dz * dz);
    if (len < 0.08) return;
    final dirX = dx / len;
    final dirZ = dz / len;
    final fLen = sqrt(
      rig.forward.x * rig.forward.x + rig.forward.z * rig.forward.z,
    );
    if (fLen < 1e-4) return;
    final fx = rig.forward.x / fLen;
    final fz = rig.forward.z / fLen;
    // CameraRig forward = (sin(yaw), 0, -cos(yaw)), so +dYaw rotates (fx, fz)
    // by sin(dYaw) = fx * dirZ - fz * dirX.
    final yawDelta = atan2(fx * dirZ - fz * dirX, fx * dirX + fz * dirZ);
    if (yawDelta.isFinite && yawDelta.abs() > 0.02) {
      rig.rotate(yawDelta, 0);
    }
  }

  /// Resolves a `VrHomeActionType.goToPoint` instruction into a collision-safe
  /// walkable destination (coordinates, named room/booth/waypoint/exhibit, or
  /// gaze-projected floor point).
  static ({
    vm.Vector3? destination,
    String? targetName,
    String statusMessage,
    double? faceLookX,
    double? faceLookZ,
  })
  resolveSpecificPoint({
    required VrHomeGuidance guidance,
    required StereoHeadRig rig,
    required HomeWalkSpace walkSpace,
    List<FloorWaypoint> waypoints = const [],
    List<HomeEcosystemPortal> portals = const [],
    List<HomeExhibit> exhibits = const [],
    FloorWaypoint? hoveredWaypoint,
  }) {
    vm.Vector3? nearestStandable(double tx, double tz) {
      if (walkSpace.canStand(tx, tz)) {
        return vm.Vector3(tx, 1.60, tz);
      }
      for (final radius in const [
        0.35,
        0.70,
        1.15,
        1.65,
        2.25,
        3.00,
        3.80,
        4.50,
      ]) {
        for (var step = 0; step < 16; step++) {
          final angle = step * (pi / 8.0);
          final cx = tx + cos(angle) * radius;
          final cz = tz + sin(angle) * radius;
          if (walkSpace.canStand(cx, cz)) {
            return vm.Vector3(cx, 1.60, cz);
          }
        }
      }
      return null;
    }

    // 1. Explicit metric XZ coordinates
    if (guidance.targetX != null && guidance.targetZ != null) {
      final landing = nearestStandable(guidance.targetX!, guidance.targetZ!);
      if (landing != null) {
        final label =
            '(${landing.x.toStringAsFixed(1)}, ${landing.z.toStringAsFixed(1)})';
        return (
          destination: landing,
          targetName: 'punto $label',
          statusMessage: 'Saltando al punto $label...',
          faceLookX: null,
          faceLookZ: null,
        );
      }
      return (
        destination: null,
        targetName: null,
        statusMessage: 'Ese punto está fuera del área caminable',
        faceLookX: null,
        faceLookZ: null,
      );
    }

    // 2. Named spatial destination (waypoint, booth code L-02, room, or exhibit)
    final rawQuery = guidance.targetPointQuery?.trim() ?? '';
    if (rawQuery.isNotEmpty) {
      final q = _normalizeSpatialToken(rawQuery);

      for (final wp in waypoints) {
        final normName = _normalizeSpatialToken(wp.name);
        final normId = _normalizeSpatialToken(wp.id);
        if (normId == q ||
            normName == q ||
            (q.length >= 4 &&
                (normName.contains(q) || q.contains(normName)))) {
          final dest =
              nearestStandable(wp.position.x, wp.position.z) ??
              vm.Vector3(wp.position.x, 1.60, wp.position.z);
          return (
            destination: dest,
            targetName: wp.name,
            statusMessage: 'Yendo a ${wp.name}...',
            faceLookX: null,
            faceLookZ: null,
          );
        }
      }

      final boothNumMatch = RegExp(
        r'^(?:l-?|local\s*)?0*(\d+)$',
      ).firstMatch(q);
      if (boothNumMatch != null && portals.isNotEmpty) {
        final oneBased = int.tryParse(boothNumMatch.group(1) ?? '');
        if (oneBased != null && oneBased >= 1 && oneBased <= portals.length) {
          final portal = portals[oneBased - 1];
          final dest =
              nearestStandable(portal.standingX, portal.standingZ) ??
              nearestStandable(
                portal.doorX - portal.side * 1.35,
                portal.doorZ - portal.zSide * 1.35,
              );
          if (dest != null) {
            return (
              destination: dest,
              targetName: portal.room.title,
              statusMessage: 'Yendo a ${portal.room.title}...',
              faceLookX: portal.doorX,
              faceLookZ: portal.doorZ,
            );
          }
        }
      }

      for (final portal in portals) {
        final normTitle = _normalizeSpatialToken(portal.room.title);
        final normId = _normalizeSpatialToken(portal.room.id);
        if (normId == q ||
            normTitle == q ||
            (q.length >= 3 &&
                (normTitle.contains(q) || q.contains(normTitle)))) {
          final dest =
              nearestStandable(portal.standingX, portal.standingZ) ??
              nearestStandable(
                portal.doorX - portal.side * 1.35,
                portal.doorZ - portal.zSide * 1.35,
              );
          if (dest != null) {
            return (
              destination: dest,
              targetName: portal.room.title,
              statusMessage: 'Yendo a ${portal.room.title}...',
              faceLookX: portal.doorX,
              faceLookZ: portal.doorZ,
            );
          }
        }
      }

      for (final exhibit in exhibits) {
        final normTitle = _normalizeSpatialToken(exhibit.title);
        final normId = _normalizeSpatialToken(exhibit.id);
        final normDemo = _normalizeSpatialToken(exhibit.demoId);
        if (normId == q ||
            normDemo == q ||
            normTitle == q ||
            (q.length >= 3 &&
                (normTitle.contains(q) || q.contains(normTitle)))) {
          final dest =
              nearestStandable(exhibit.x, exhibit.z + 1.8) ??
              nearestStandable(exhibit.x, exhibit.z);
          if (dest != null) {
            return (
              destination: dest,
              targetName: exhibit.title,
              statusMessage: 'Yendo frente a ${exhibit.title}...',
              faceLookX: exhibit.x,
              faceLookZ: exhibit.z,
            );
          }
        }
      }

      if (!guidance.useGazeTarget) {
        return (
          destination: null,
          targetName: null,
          statusMessage: 'No encontré el punto «$rawQuery» en este espacio',
          faceLookX: null,
          faceLookZ: null,
        );
      }
    }

    // 3. Gaze-projected floor point
    if (hoveredWaypoint != null) {
      return (
        destination: vm.Vector3(
          hoveredWaypoint.position.x,
          1.60,
          hoveredWaypoint.position.z,
        ),
        targetName: hoveredWaypoint.name,
        statusMessage: 'Saltando a ${hoveredWaypoint.name}...',
        faceLookX: null,
        faceLookZ: null,
      );
    }

    final flatForward = vm.Vector3(rig.forward.x, 0, rig.forward.z);
    if (!flatForward.length2.isFinite || flatForward.length2 < 1e-6) {
      flatForward.setValues(0, 0, -1);
    } else {
      flatForward.normalize();
    }

    double desiredDist = (guidance.distanceMeters ?? 4.2).clamp(1.0, 14.0);
    if (rig.forward.y < -0.06 && guidance.distanceMeters == null) {
      final horizComponent = sqrt(
        max(1e-4, 1.0 - rig.forward.y * rig.forward.y),
      );
      final rayFloorDist = (rig.eyeCenter.y / -rig.forward.y) * horizComponent;
      desiredDist = rayFloorDist.clamp(1.2, 14.0);
    }

    var marchPos = rig.eyeCenter.clone();
    const stepSize = 0.40;
    final steps = (desiredDist / stepSize).ceil().clamp(1, 40);
    final perStepDist = desiredDist / steps;
    for (var i = 0; i < steps; i++) {
      final next = walkSpace.move(
        marchPos,
        flatForward.x * perStepDist,
        flatForward.z * perStepDist,
      );
      final delta = (next - marchPos).length;
      marchPos = next;
      if (delta < 0.02) break;
    }

    final movedMeters = (marchPos - rig.eyeCenter).length;
    if (movedMeters < 0.20) {
      return (
        destination: null,
        targetName: null,
        statusMessage: 'Hay un muro u obstáculo justo frente a ti',
        faceLookX: null,
        faceLookZ: null,
      );
    }

    return (
      destination: vm.Vector3(marchPos.x, 1.60, marchPos.z),
      targetName: 'punto mirado (${movedMeters.toStringAsFixed(1)} m)',
      statusMessage:
          'Yendo al punto frente a tu mirada (${movedMeters.toStringAsFixed(1)} m)...',
      faceLookX: null,
      faceLookZ: null,
    );
  }

  static String _normalizeSpatialToken(String raw) {
    var out = raw.toLowerCase().trim();
    const accented = 'áéíóúüñ';
    const plain = 'aeiouun';
    for (var i = 0; i < accented.length; i++) {
      out = out.replaceAll(accented[i], plain[i]);
    }
    return out
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
