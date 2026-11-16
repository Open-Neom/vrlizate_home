import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../theme/vr_home_theme.dart';
import 'home_ecosystem_layout.dart';

/// Pure-CPU kinematic state for an ambient plaza visitor so crowd motion,
/// storefront browsing pauses, social clusters, and player-proximity greetings
/// can be verified deterministically in headless tests without a GPU context.
final class HomePlazaVisitorState {
  HomePlazaVisitorState({
    required this.id,
    required this.appearance,
    required this.routePoints,
    required this.storefrontLookYaw,
    required this.walkSpeed,
    required this.phaseOffset,
    required this.conversationalist,
    this.partnerYaw,
  }) : assert(routePoints.isNotEmpty),
       x = routePoints.first.x,
       z = routePoints.first.z,
       yaw = partnerYaw ?? 0.0;

  final String id;
  final VrAvatarAppearance appearance;
  final List<vm.Vector3> routePoints;
  final List<double?> storefrontLookYaw;
  final double walkSpeed;
  final double phaseOffset;
  final bool conversationalist;
  final double? partnerYaw;

  double x;
  double z;
  double yaw;
  int targetIndex = 1;
  double pauseRemaining = 0.0;
  bool greetingPlayer = false;
  VrAvatarPose pose = VrAvatarPose.neutral;

  void step(double time, double dt, vm.Vector3? playerEye) {
    final stepDt = dt.isFinite ? dt.clamp(0.0, 0.1) : 0.0;
    final blinkWave = math.sin(time * 0.9 + phaseOffset * 3.1);
    final blink = blinkWave > 0.985 ? ((blinkWave - 0.985) / 0.015) : 0.0;

    // Friendly proximity reaction: when the player walks within 3.4 m, pause
    // and turn smoothly toward the player with a welcoming wave!
    if (playerEye != null) {
      final dx = playerEye.x - x;
      final dz = playerEye.z - z;
      final distSq = dx * dx + dz * dz;
      if (distSq <= 3.4 * 3.4 && distSq > 0.04) {
        greetingPlayer = true;
        final desiredYaw = math.atan2(dx, dz);
        yaw = _lerpAngle(yaw, desiredYaw, (stepDt * 5.5).clamp(0.0, 1.0));
        pose = VrAvatarPose.wave(
          time + phaseOffset,
          leftHand: phaseOffset.toInt().isOdd,
          waveAmount: 0.92,
          blink: blink,
        );
        return;
      }
    }
    greetingPlayer = false;

    if (conversationalist || routePoints.length < 2) {
      final baseYaw = partnerYaw ?? yaw;
      yaw = _lerpAngle(yaw, baseYaw, (stepDt * 3.0).clamp(0.0, 1.0));
      final gesturePhase = time * 1.65 + phaseOffset;
      final speaking = math.sin(gesturePhase * 0.55) > -0.15;
      pose = VrAvatarPose(
        nod: math.sin(gesturePhase * 1.4) * 0.065,
        look: math.sin(gesturePhase * 0.7) * 0.14,
        tilt: math.cos(gesturePhase * 0.5) * 0.035,
        leftArmFlexion: speaking
            ? (0.28 + math.sin(gesturePhase * 1.8) * 0.18)
            : 0.08,
        rightArmFlexion: speaking
            ? (0.22 + math.cos(gesturePhase * 1.5) * 0.16)
            : 0.08,
        leftArmAbduction: 0.09,
        rightArmAbduction: 0.09,
        blink: blink,
      );
      return;
    }

    if (pauseRemaining > 0) {
      pauseRemaining = math.max(0.0, pauseRemaining - stepDt);
      final idx =
          (targetIndex - 1 + routePoints.length) % routePoints.length;
      final lookTarget = storefrontLookYaw[idx];
      if (lookTarget != null) {
        yaw = _lerpAngle(yaw, lookTarget, (stepDt * 4.2).clamp(0.0, 1.0));
      }
      final inspectPhase = time * 1.8 + phaseOffset;
      pose = VrAvatarPose(
        nod: -0.05 + math.sin(inspectPhase) * 0.05,
        look: math.sin(inspectPhase * 0.8) * 0.22,
        leftArmFlexion: 0.16,
        rightArmFlexion: 0.12,
        blink: blink,
      );
      return;
    }

    final target = routePoints[targetIndex % routePoints.length];
    final dx = target.x - x;
    final dz = target.z - z;
    final dist = math.sqrt(dx * dx + dz * dz);
    if (dist <= 0.22) {
      x = target.x;
      z = target.z;
      final reachedIdx = targetIndex % routePoints.length;
      targetIndex = (targetIndex + 1) % routePoints.length;
      if (storefrontLookYaw[reachedIdx] != null) {
        pauseRemaining = 2.6 + (phaseOffset % 2.1);
      }
      return;
    }

    final step = math.min(dist, walkSpeed * stepDt);
    final nx = dx / dist;
    final nz = dz / dist;
    x += nx * step;
    z += nz * step;
    final travelYaw = math.atan2(nx, nz);
    yaw = _lerpAngle(yaw, travelYaw, (stepDt * 6.0).clamp(0.0, 1.0));
    pose = VrAvatarPose.walk(
      time * (walkSpeed * 3.6) + phaseOffset,
      amplitude: 0.50,
      lean: 0.05,
      look: math.sin(time * 0.65 + phaseOffset) * 0.10,
      blink: blink,
    );
  }

  static double _lerpAngle(double from, double to, double t) {
    var diff = (to - from) % (math.pi * 2);
    if (diff > math.pi) diff -= math.pi * 2;
    if (diff < -math.pi) diff += math.pi * 2;
    return from + diff * t;
  }
}

/// Populates Virtual Home Plazas and 360° Famous Malls with living, strolling,
/// window-shopping, and social 3D visitors (`VrAvatarNode`) plus gentle aerial
/// atrium light-drones so large plazas feel vibrant and inhabited while
/// staying strictly within mobile VR GPU budgets.
final class HomePlazaCrowd {
  HomePlazaCrowd._({
    required this.visitors,
    required this.theme,
  });

  factory HomePlazaCrowd.plan({
    required HomeEcosystemLayout layout,
    VrHomeThemeData theme = VrHomeThemeData.aurora,
  }) {
    final palettes = <VrAvatarAppearance>[
      VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFF2E86DE,
        accentColorArgb: 0xFF7EF0DD,
        heightMeters: 1.72,
        pattern: VrAvatarPattern.solid,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFFE17055,
        accentColorArgb: 0xFFFFEAA7,
        heightMeters: 1.66,
        pattern: VrAvatarPattern.stripes,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.robot,
        bodyColorArgb: 0xFF576574,
        accentColorArgb: 0xFF00E5FF,
        heightMeters: 1.82,
        featureScale: 1.12,
        pattern: VrAvatarPattern.stripes,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.fox,
        bodyColorArgb: 0xFFD35400,
        accentColorArgb: 0xFFFAD390,
        heightMeters: 1.58,
        featureScale: 1.22,
        pattern: VrAvatarPattern.stripes,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFF10AC84,
        accentColorArgb: 0xFFC8D6E5,
        heightMeters: 1.75,
        pattern: VrAvatarPattern.solid,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.axolotl,
        bodyColorArgb: 0xFF8854D0,
        accentColorArgb: 0xFF7EF0DD,
        heightMeters: 1.48,
        featureScale: 1.25,
        pattern: VrAvatarPattern.spots,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFF6C5CE7,
        accentColorArgb: 0xFF81ECEC,
        heightMeters: 1.69,
        pattern: VrAvatarPattern.solid,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.sprout,
        bodyColorArgb: 0xFF20BF6B,
        accentColorArgb: 0xFFFED330,
        heightMeters: 1.44,
        featureScale: 1.18,
        pattern: VrAvatarPattern.spots,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.robot,
        bodyColorArgb: 0xFF3B3B98,
        accentColorArgb: 0xFFF8EFBA,
        heightMeters: 1.78,
        pattern: VrAvatarPattern.solid,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFFB33771,
        accentColorArgb: 0xFFFFCCCC,
        heightMeters: 1.64,
        pattern: VrAvatarPattern.stripes,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.orb,
        bodyColorArgb: 0xFF0FB9B1,
        accentColorArgb: 0xFFF7B731,
        heightMeters: 1.52,
        pattern: VrAvatarPattern.spots,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFF2C3A47,
        accentColorArgb: 0xFF55E6C1,
        heightMeters: 1.76,
        pattern: VrAvatarPattern.solid,
      ),
    ];

    final visitors = <HomePlazaVisitorState>[];
    final portals = layout.portals;
    final waypoints = layout.waypoints;

    // 1. Promenade strollers visiting storefronts & plaza waypoints (up to 8)
    if (portals.length >= 2) {
      final strollerCount = math.min(8, portals.length);
      for (var i = 0; i < strollerCount; i++) {
        final pA = portals[(i * 2) % portals.length];
        final pB = portals[(i * 2 + 1) % portals.length];
        final pC = portals[(i * 2 + 3) % portals.length];
        final laneShift = (i.isEven ? -0.42 : 0.42);
        final pts = <vm.Vector3>[
          vm.Vector3(pA.standingX + laneShift * 0.5, 0, pA.standingZ),
          if (waypoints.isNotEmpty)
            vm.Vector3(
              waypoints[i % waypoints.length].x + laneShift,
              0,
              waypoints[i % waypoints.length].z,
            ),
          vm.Vector3(pB.standingX - laneShift * 0.5, 0, pB.standingZ),
          vm.Vector3(pC.standingX + laneShift * 0.3, 0, pC.standingZ),
        ];
        final looks = <double?>[
          math.atan2(pA.inwardForwardX, pA.inwardForwardZ),
          if (waypoints.isNotEmpty) null,
          math.atan2(pB.inwardForwardX, pB.inwardForwardZ),
          math.atan2(pC.inwardForwardX, pC.inwardForwardZ),
        ];
        final visitor = HomePlazaVisitorState(
          id: 'plaza_stroller_$i',
          appearance: palettes[i % palettes.length],
          routePoints: pts,
          storefrontLookYaw: looks,
          walkSpeed: 1.04 + (i % 4) * 0.09,
          phaseOffset: i * 1.37,
          conversationalist: false,
        );
        // Distribute initial positions along their route so they don't bunch up
        if (pts.length >= 2) {
          final startIdx = i % pts.length;
          final nextIdx = (startIdx + 1) % pts.length;
          final a = pts[startIdx];
          final b = pts[nextIdx];
          final frac = ((i * 0.37) % 0.8) + 0.1;
          visitor
            ..x = a.x + (b.x - a.x) * frac
            ..z = a.z + (b.z - a.z) * frac
            ..targetIndex = nextIdx
            ..yaw = math.atan2(b.x - a.x, b.z - a.z);
        }
        visitors.add(visitor);
      }
    } else {
      // Fallback plaza loop around the central atrium when no portals exist
      const loop = <(double, double)>[
        (-3.6, -2.5),
        (-3.6, 5.5),
        (3.6, 5.5),
        (3.6, -2.5),
      ];
      for (var i = 0; i < 4; i++) {
        final pts = [
          for (var k = 0; k < loop.length; k++)
            vm.Vector3(
              loop[(i + k) % loop.length].$1,
              0,
              loop[(i + k) % loop.length].$2,
            ),
        ];
        visitors.add(
          HomePlazaVisitorState(
            id: 'plaza_stroller_$i',
            appearance: palettes[i % palettes.length],
            routePoints: pts,
            storefrontLookYaw: List<double?>.filled(pts.length, null),
            walkSpeed: 1.12,
            phaseOffset: i * 1.6,
            conversationalist: false,
          ),
        );
      }
    }

    // 2. Two friendly social pairs chatting off to the sides of the atrium
    // (clear of the spawn sightline `(0, 0)` -> `(0, -4.8)` Library window).
    final hubZ = waypoints.isNotEmpty ? waypoints.first.z + 2.4 : 2.4;
    final socialPairs = <(double x1, double z1, double x2, double z2)>[
      (-3.1, hubZ - 1.2, -2.35, hubZ - 0.65),
      (3.1, hubZ + 1.4, 2.35, hubZ + 0.85),
    ];
    for (var p = 0; p < socialPairs.length; p++) {
      final (x1, z1, x2, z2) = socialPairs[p];
      final yaw1To2 = math.atan2(x2 - x1, z2 - z1);
      final yaw2To1 = math.atan2(x1 - x2, z1 - z2);
      final baseIdx = 8 + p * 2;
      visitors.add(
        HomePlazaVisitorState(
          id: 'plaza_social_${p}_a',
          appearance: palettes[baseIdx % palettes.length],
          routePoints: [vm.Vector3(x1, 0, z1)],
          storefrontLookYaw: const [null],
          walkSpeed: 0,
          phaseOffset: p * 2.1 + 0.4,
          conversationalist: true,
          partnerYaw: yaw1To2,
        ),
      );
      visitors.add(
        HomePlazaVisitorState(
          id: 'plaza_social_${p}_b',
          appearance: palettes[(baseIdx + 1) % palettes.length],
          routePoints: [vm.Vector3(x2, 0, z2)],
          storefrontLookYaw: const [null],
          walkSpeed: 0,
          phaseOffset: p * 2.1 + 1.5,
          conversationalist: true,
          partnerYaw: yaw2To1,
        ),
      );
    }

    return HomePlazaCrowd._(visitors: visitors, theme: theme);
  }

  final List<HomePlazaVisitorState> visitors;
  final VrHomeThemeData theme;
  final Node root = Node(name: 'home_plaza_crowd_root')..raycastable = false;

  final List<_MountedVisitor> _mounted = [];
  final List<Node> _aerialOrbs = [];
  double _lastTime = -1;
  bool _gpuMounted = false;
  bool _disposed = false;

  bool get isGpuMounted => _gpuMounted;

  /// Attaches 3D [VrAvatarNode] visitors and ambient atrium orbs to [parent]
  /// when Flutter GPU (`Scene.isReadyToRender`) is active.
  void mountGpu(Node parent) {
    if (_disposed || _gpuMounted || !Scene.isReadyToRender) return;
    _gpuMounted = true;
    for (final state in visitors) {
      final avatar = VrAvatarNode(
        appearance: state.appearance,
        animateIdle: true,
        detail: VrAvatarDetail.far,
      );
      _disableShadowsAndPicking(avatar.root);
      final holder = Node(name: state.id)
        ..raycastable = false
        ..localTransform = _placementMatrix(state.x, state.z, state.yaw)
        ..add(avatar.root);
      root.add(holder);
      _mounted.add(_MountedVisitor(state: state, holder: holder, avatar: avatar));
    }

    // Add 6 gentle luminous micro-orbs gliding through the upper plaza atrium
    final orbGeometry = SphereGeometry(radius: 0.065, segments: 10, rings: 8);
    final accent = theme.accent;
    final secondary = theme.secondary;
    for (var i = 0; i < 6; i++) {
      final c = i.isEven ? accent : secondary;
      final mat = UnlitMaterial()
        ..baseColorFactor = vm.Vector4(c.r, c.g, c.b, 0.88)
        ..vertexColorWeight = 0.0;
      final orb = Node(
        name: 'plaza_ambient_orb_$i',
        mesh: Mesh(orbGeometry, mat),
      )
        ..raycastable = false
        ..shadowCastingMode = ShadowCastingMode.off;
      root.add(orb);
      _aerialOrbs.add(orb);
    }

    parent.add(root);
  }

  void tick(double time, {vm.Vector3? eyePosition}) {
    if (_disposed || !time.isFinite) return;
    final dt = _lastTime < 0 ? (1 / 60) : (time - _lastTime).clamp(0.0, 0.1);
    _lastTime = time;

    for (var i = 0; i < visitors.length; i++) {
      final v = visitors[i];
      v.step(time, dt, eyePosition);
      if (!_gpuMounted || i >= _mounted.length) continue;
      final m = _mounted[i];
      m.holder.localTransform = _placementMatrix(v.x, v.z, v.yaw);

      if (eyePosition != null) {
        final dx = eyePosition.x - v.x;
        final dz = eyePosition.z - v.z;
        final distSq = dx * dx + dz * dz;
        final shouldBeNear = m.avatar.detail == VrAvatarDetail.near
            ? distSq <= 12.5 * 12.5
            : distSq <= 9.5 * 9.5;
        final desiredDetail = shouldBeNear
            ? VrAvatarDetail.near
            : VrAvatarDetail.far;
        if (m.avatar.detail != desiredDetail) {
          m.avatar.setDetail(desiredDetail);
          _disableShadowsAndPicking(m.avatar.root);
        }
        // Cull visitors beyond 34 m so huge malls never waste draw calls
        final visible = distSq <= 34.0 * 34.0;
        if (m.holder.visible != visible) {
          m.holder.visible = visible;
        }
      }

      if (m.holder.visible && m.avatar.detail == VrAvatarDetail.near) {
        m.avatar.setPose(v.pose);
        m.avatar.tick(dt);
      }
    }

    if (_gpuMounted) {
      for (var i = 0; i < _aerialOrbs.length; i++) {
        final phase = time * 0.42 + i * (math.pi / 3);
        final radius = 4.2 + (i % 3) * 1.6;
        final ox = math.cos(phase) * radius;
        final oz = 1.5 + math.sin(phase * 0.85) * (radius * 1.15);
        final oy = 3.15 + math.sin(time * 1.1 + i * 1.3) * 0.32;
        _aerialOrbs[i].localTransform = vm.Matrix4.translationValues(ox, oy, oz);
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final m in _mounted) {
      m.avatar.dispose();
    }
    _mounted.clear();
    _aerialOrbs.clear();
    root.parent?.remove(root);
  }

  static vm.Matrix4 _placementMatrix(double x, double z, double yaw) =>
      vm.Matrix4.translationValues(x, 0, z)..rotateY(yaw);

  static void _disableShadowsAndPicking(Node node) {
    node.raycastable = false;
    node.shadowCastingMode = ShadowCastingMode.off;
    for (final child in node.children) {
      _disableShadowsAndPicking(child);
    }
  }
}

final class _MountedVisitor {
  _MountedVisitor({
    required this.state,
    required this.holder,
    required this.avatar,
  });

  final HomePlazaVisitorState state;
  final Node holder;
  final VrAvatarNode avatar;
}
