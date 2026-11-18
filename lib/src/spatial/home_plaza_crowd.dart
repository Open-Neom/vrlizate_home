import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
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
    this.displayName = 'Visitante',
    this.role = 'Explorador VR',
    this.nearestRoomTitle,
    this.ambientComment = '¡Qué buena vibra se siente en esta plaza!',
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
  final String displayName;
  final String role;
  final String? nearestRoomTitle;
  final double? partnerYaw;

  String ambientComment;
  bool talkingToPlayer = false;
  double socialReactionRemaining = 0.0;
  double? socialReactionTargetYaw;

  double x;
  double z;
  double yaw;
  double vx = 0.0;
  double vz = 0.0;
  int targetIndex = 1;
  double pauseRemaining = 0.0;
  bool greetingPlayer = false;
  VrAvatarPose pose = VrAvatarPose.neutral;

  /// Triggers a lively brief social reaction (turning toward an active portal
  /// launch or newly arrived remote user with a welcoming wave and optional
  /// updated ambient remark) without any GPU allocation.
  void triggerSocialReaction(
    double targetYaw, {
    double durationSeconds = 3.2,
    String? comment,
  }) {
    if (!targetYaw.isFinite) return;
    socialReactionTargetYaw = targetYaw;
    socialReactionRemaining = durationSeconds.clamp(0.5, 8.0);
    if (comment != null && comment.trim().isNotEmpty) {
      ambientComment = comment.trim();
    }
  }

  void step(double time, double dt, vm.Vector3? playerEye) {
    final stepDt = dt.isFinite ? dt.clamp(0.0, 0.25) : 0.0;
    final blinkWave = math.sin(time * 0.9 + phaseOffset * 3.1);
    final blink = blinkWave > 0.985 ? ((blinkWave - 0.985) / 0.015) : 0.0;

    if (socialReactionRemaining > 0.0 && !talkingToPlayer) {
      socialReactionRemaining = math.max(0.0, socialReactionRemaining - stepDt);
      vx = 0.0;
      vz = 0.0;
      final desiredYaw = socialReactionTargetYaw ?? yaw;
      yaw = _lerpAngle(yaw, desiredYaw, (stepDt * 5.8).clamp(0.0, 1.0));
      pose = VrAvatarPose.wave(
        time + phaseOffset,
        leftHand: phaseOffset.toInt().isEven,
        waveAmount: 0.78,
        blink: blink,
      );
      return;
    }

    // Active conversation lock: hold position, face the player smoothly, and
    // animate warm conversational gestures until the dialogue panel closes.
    if (talkingToPlayer && playerEye != null) {
      greetingPlayer = true;
      vx = 0.0;
      vz = 0.0;
      final dx = playerEye.x - x;
      final dz = playerEye.z - z;
      if (dx * dx + dz * dz > 0.01) {
        final desiredYaw = math.atan2(dx, dz);
        yaw = _lerpAngle(yaw, desiredYaw, (stepDt * 6.5).clamp(0.0, 1.0));
      }
      final talkPhase = time * 2.1 + phaseOffset;
      pose = VrAvatarPose(
        nod: math.sin(talkPhase * 1.3) * 0.075,
        look: math.sin(talkPhase * 0.65) * 0.11,
        tilt: math.cos(talkPhase * 0.5) * 0.04,
        leftArmFlexion: 0.34 + math.sin(talkPhase * 1.7) * 0.18,
        rightArmFlexion: 0.28 + math.cos(talkPhase * 1.45) * 0.16,
        leftArmAbduction: 0.11,
        rightArmAbduction: 0.11,
        blink: blink,
      );
      return;
    }

    // Friendly proximity reaction: when the player walks within 3.4 m, pause
    // and turn smoothly toward the player with a welcoming wave!
    if (playerEye != null) {
      final dx = playerEye.x - x;
      final dz = playerEye.z - z;
      final distSq = dx * dx + dz * dz;
      if (distSq <= 3.4 * 3.4 && distSq > 0.04) {
        greetingPlayer = true;
        vx = 0.0;
        vz = 0.0;
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
      vx = 0.0;
      vz = 0.0;
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
      vx = 0.0;
      vz = 0.0;
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
      vx = 0.0;
      vz = 0.0;
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
    vx = nx * walkSpeed;
    vz = nz * walkSpeed;
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
  }) {
    for (final v in visitors) {
      peerStage.upsertPeer(
        VrPeerAvatarSnapshot(
          peerId: v.id,
          appearance: v.appearance,
          x: v.x,
          z: v.z,
          yaw: v.yaw,
          pose: v.pose,
        ),
      );
    }
  }

  static const _npcPersonas = <(String name, String role)>[
    ('Valeria', 'Exploradora VR'),
    ('Mateo', 'Curador de Mundos'),
    ('Nexo-7', 'Guía Sintético'),
    ('Kitsune Sol', 'Viajero Curioso'),
    ('Sofía', 'Arquitecta Espacial'),
    ('Axo-Luma', 'Embajador Bio-Digital'),
    ('Diego', 'Coleccionista Arcade'),
    ('Brote Jade', 'Botánico Virtual'),
    ('Órbita-3', 'Cronista Espacial'),
    ('Camila', 'Crítica de Cine 3D'),
    ('Prisma', 'Espíritu Lumínico'),
    ('Emilio', 'Visitante de la Plaza'),
  ];

  static String _seedCommentFor({
    required int index,
    String? roomTitle,
    String? plazaBannerText,
  }) {
    final cleanPlaza = plazaBannerText
        ?.split('\n')
        .first
        .trim();
    if (roomTitle != null && roomTitle.trim().isNotEmpty) {
      return switch (index % 6) {
        0 => '¡Hola! El acceso a «$roomTitle» luce espectacular hoy.',
        1 => 'Estaba admirando «$roomTitle»… vale mucho la pena entrar.',
        2 => '¿Ya probaste «$roomTitle»? Es de mis rincones favoritos aquí.',
        3 => 'Me encanta caminar por esta ala rumbo a «$roomTitle».',
        4 => 'Qué fluidez tiene este espacio cerca de «$roomTitle».',
        _ => 'Si buscas algo distinto, asómate por «$roomTitle».',
      };
    }
    final where = (cleanPlaza != null && cleanPlaza.isNotEmpty)
        ? cleanPlaza
        : 'esta plaza VR';
    return switch (index % 4) {
      0 => '¡Qué gusto saludarte en $where! Pregúntame lo que quieras.',
      1 => 'La atmósfera sonora y la luz de $where relajan muchísimo.',
      2 => 'Siempre descubro portales nuevos paseando por $where.',
      _ => '¡Bienvenido! Si quieres recomendaciones, conversemos un momento.',
    };
  }

  factory HomePlazaCrowd.plan({
    required HomeEcosystemLayout layout,
    VrHomeThemeData theme = VrHomeThemeData.aurora,
    String? plazaBannerText,
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
        final persona = _npcPersonas[i % _npcPersonas.length];
        final roomTitle = pA.room.title;
        final visitor = HomePlazaVisitorState(
          id: 'plaza_stroller_$i',
          appearance: palettes[i % palettes.length],
          routePoints: pts,
          storefrontLookYaw: looks,
          walkSpeed: 1.04 + (i % 4) * 0.09,
          phaseOffset: i * 1.37,
          conversationalist: false,
          displayName: persona.$1,
          role: persona.$2,
          nearestRoomTitle: roomTitle,
          ambientComment: _seedCommentFor(
            index: i,
            roomTitle: roomTitle,
            plazaBannerText: plazaBannerText,
          ),
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
        final persona = _npcPersonas[i % _npcPersonas.length];
        visitors.add(
          HomePlazaVisitorState(
            id: 'plaza_stroller_$i',
            appearance: palettes[i % palettes.length],
            routePoints: pts,
            storefrontLookYaw: List<double?>.filled(pts.length, null),
            walkSpeed: 1.12,
            phaseOffset: i * 1.6,
            conversationalist: false,
            displayName: persona.$1,
            role: persona.$2,
            ambientComment: _seedCommentFor(
              index: i,
              plazaBannerText: plazaBannerText,
            ),
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
      final personaA = _npcPersonas[baseIdx % _npcPersonas.length];
      final personaB = _npcPersonas[(baseIdx + 1) % _npcPersonas.length];
      final roomA = portals.isNotEmpty
          ? portals[(p * 3) % portals.length].room.title
          : null;
      final roomB = portals.length > 1
          ? portals[(p * 3 + 1) % portals.length].room.title
          : roomA;
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
          displayName: personaA.$1,
          role: personaA.$2,
          nearestRoomTitle: roomA,
          ambientComment: _seedCommentFor(
            index: baseIdx,
            roomTitle: roomA,
            plazaBannerText: plazaBannerText,
          ),
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
          displayName: personaB.$1,
          role: personaB.$2,
          nearestRoomTitle: roomB,
          ambientComment: _seedCommentFor(
            index: baseIdx + 1,
            roomTitle: roomB,
            plazaBannerText: plazaBannerText,
          ),
        ),
      );
    }

    return HomePlazaCrowd._(visitors: visitors, theme: theme);
  }

  final List<HomePlazaVisitorState> visitors;
  final VrHomeThemeData theme;
  final Node root = Node(name: 'home_plaza_crowd_root')
    ..raycastable = false
    ..shadowCastingMode = ShadowCastingMode.off;

  /// Shared instanced stage that batches all NPCs and any live multiplayer
  /// peer avatars (`upsertPeer` / `removePeer`) into `<= 3` GPU draw calls.
  final VrPeerAvatarStage peerStage = VrPeerAvatarStage(maxPeers: 48);

  static Geometry? _sharedOrbGeometry;
  InstancedMesh? _aerialOrbMesh;
  Node? _aerialOrbNode;
  final Map<String, VrTextLabel> _barkCache = <String, VrTextLabel>{};
  final Set<String> _barkPendingKeys = <String>{};
  VrTextLabel? _activeBarkLabel;
  double _lastTime = -1;
  double _aiAccum = 1.0;
  double _orbAccum = 1.0;
  double _lastGreetingAudioTime = -10.0;
  int _mountEpoch = 0;
  bool _gpuMounted = false;
  bool _disposed = false;

  bool get isGpuMounted => _gpuMounted;

  HomePlazaVisitorState? visitorById(String id) {
    for (final v in visitors) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Locks [visitorId] in an attentive conversational pose facing the player,
  /// or clears all conversation locks when [visitorId] is `null`.
  void setVisitorTalking(String? visitorId) {
    for (final v in visitors) {
      v.talkingToPlayer = visitorId != null && v.id == visitorId;
    }
    _aiAccum = 1.0;
  }

  /// Updates an NPC's floating ambient comment (e.g. after Itzli generates a
  /// fresh in-character remark) without allocating any GPU resources until
  /// that visitor is focused by the player.
  void setVisitorComment(String visitorId, String comment) {
    final v = visitorById(visitorId);
    if (v == null) return;
    final compact = comment.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return;
    final runes = compact.runes.take(151).toList(growable: false);
    v.ambientComment = runes.length <= 150
        ? String.fromCharCodes(runes)
        : '${String.fromCharCodes(runes.take(149))}…';
  }

  /// Number of biome-aware atmospheric floating particles packed into the
  /// single shared ambient `InstancedMesh` draw call (`0` extra draw calls).
  static const int ambientParticleCount = 18;

  /// Alerts nearby plaza visitors (`<= radiusMeters`) to turn and wave toward
  /// a live plaza event (such as opening a room portal or a multiplayer peer
  /// arriving), returning how many visitors reacted.
  int reactToEvent(
    vm.Vector3 focusPoint, {
    String? reactionComment,
    double radiusMeters = 7.5,
  }) {
    if (_disposed || !radiusMeters.isFinite || radiusMeters <= 0) return 0;
    final maxDistSq = radiusMeters * radiusMeters;
    var reacted = 0;
    for (final v in visitors) {
      if (v.talkingToPlayer) continue;
      final dx = focusPoint.x - v.x;
      final dz = focusPoint.z - v.z;
      final distSq = dx * dx + dz * dz;
      if (distSq > maxDistSq || distSq < 0.04) continue;
      final yaw = math.atan2(dx, dz);
      v.triggerSocialReaction(
        yaw,
        comment: reacted == 0 ? reactionComment : null,
      );
      reacted++;
      if (reacted >= 4) break;
    }
    if (reacted > 0) _aiAccum = 1.0;
    return reacted;
  }

  /// Pure-CPU cone & distance query (`< 0.002 ms`, `0` allocations) returning
  /// the single nearby visitor best aligned with the player's view or ray.
  HomePlazaVisitorState? findFocusedVisitor(
    vm.Vector3 eyePosition,
    vm.Vector3 viewerForward, {
    double maxDistance = 3.8,
    double minForwardDot = 0.68,
  }) {
    final fxRaw = viewerForward.x;
    final fzRaw = viewerForward.z;
    final fLen = math.sqrt(fxRaw * fxRaw + fzRaw * fzRaw);
    final fx = fLen > 1e-5 ? fxRaw / fLen : 0.0;
    final fz = fLen > 1e-5 ? fzRaw / fLen : -1.0;
    final maxDistSq = maxDistance * maxDistance;

    HomePlazaVisitorState? best;
    var bestScore = -1.0;
    for (var i = 0; i < visitors.length; i++) {
      final v = visitors[i];
      final dx = v.x - eyePosition.x;
      final dz = v.z - eyePosition.z;
      final distSq = dx * dx + dz * dz;
      if (distSq > maxDistSq || distSq < 0.09) continue;
      final dist = math.sqrt(distSq);
      final dot = (dx * fx + dz * fz) / dist;
      if (dot < minForwardDot) continue;
      final score = dot / (0.65 + dist * 0.25);
      if (score > bestScore) {
        bestScore = score;
        best = v;
      }
    }
    return best;
  }

  /// Pure-CPU rasterizer for the single floating NPC speech card. Testable in
  /// headless environments without an Impeller GPU context.
  @visibleForTesting
  static Future<VrTextBitmap> rasterizeBarkBubble(
    String header,
    String comment, {
    String? actionHint,
    Color accent = const Color(0xFF38BDF8),
  }) async {
    final fullText = actionHint == null || actionHint.isEmpty
        ? '$header\n«$comment»'
        : '$header\n«$comment»\n$actionHint';
    final bitmap = await VrTextRaster.rasterize(
      fullText,
      color: const Color(0xFFF8FAFC),
      fontWeight: FontWeight.w700,
      fontSize: 52,
      paddingPx: 22,
      maxLines: actionHint == null ? 3 : 4,
      maxWidthPx: 1120,
    );
    final pixels = Uint8List.fromList(bitmap.pixels);
    final w = bitmap.width;
    final h = bitmap.height;
    const bgR = 0x0B, bgG = 0x13, bgB = 0x22;
    final accentArgb = accent.toARGB32();
    final acR = (accentArgb >> 16) & 255;
    final acG = (accentArgb >> 8) & 255;
    final acB = accentArgb & 255;
    const borderBarPx = 4;

    for (var y = 0; y < h; y++) {
      final isAccentBar = y < borderBarPx || y >= h - borderBarPx;
      final rowOffset = y * w * 4;
      for (var x = 0; x < w; x++) {
        final idx = rowOffset + x * 4;
        final alpha = pixels[idx + 3];
        final baseR = isAccentBar ? acR : bgR;
        final baseG = isAccentBar ? acG : bgG;
        final baseB = isAccentBar ? acB : bgB;
        pixels[idx] =
            (pixels[idx] * alpha + baseR * (255 - alpha) + 127) ~/ 255;
        pixels[idx + 1] =
            (pixels[idx + 1] * alpha + baseG * (255 - alpha) + 127) ~/ 255;
        pixels[idx + 2] =
            (pixels[idx + 2] * alpha + baseB * (255 - alpha) + 127) ~/ 255;
        pixels[idx + 3] = 246;
      }
    }
    return VrTextBitmap(pixels, w, h);
  }

  /// Attaches the shared [VrPeerAvatarStage] (`3` `InstancedMesh`es total for
  /// all visitors + remote users) and `1` `InstancedMesh` for `18` biome-aware
  /// atmospheric particles (fireflies / neon motes / stardust — zero extra draw calls).
  void mountGpu(Node parent) {
    if (_disposed || _gpuMounted || !Scene.isReadyToRender) return;
    _gpuMounted = true;
    ++_mountEpoch;
    peerStage.mountGpu(root);

    final orbGeometry = _sharedOrbGeometry ??= SphereGeometry(
      radius: 0.045,
      segments: 8,
      rings: 6,
    );
    final mat = UnlitMaterial()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 0.84)
      ..vertexColorWeight = 0.0;
    final orbMesh = InstancedMesh(
      geometry: orbGeometry,
      material: mat,
      cullInstances: false,
    );
    final accent = theme.accent;
    final secondary = theme.secondary;
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < ambientParticleCount; i++) {
      final isOrb = i < 6;
      final c = i % 3 == 0 ? accent : (i % 3 == 1 ? secondary : const Color(0xFFF8FAFC));
      orbMesh.addInstance(
        identity,
        color: vm.Vector4(c.r, c.g, c.b, isOrb ? 0.88 : 0.62),
      );
    }
    final orbNode = Node(name: 'plaza_ambient_orbs_instanced')
      ..raycastable = false
      ..shadowCastingMode = ShadowCastingMode.off
      ..addComponent(InstancedMeshComponent(orbMesh));
    root.add(orbNode);
    _aerialOrbMesh = orbMesh;
    _aerialOrbNode = orbNode;

    parent.add(root);
  }

  void _updateOverheadBark({
    required vm.Vector3? eyePosition,
    required vm.Vector3? viewerForward,
    required bool hideBarkBubble,
    required bool canTalkToVisitors,
  }) {
    if (!_gpuMounted ||
        hideBarkBubble ||
        eyePosition == null ||
        viewerForward == null) {
      _activeBarkLabel?.node.visible = false;
      _activeBarkLabel = null;
      return;
    }
    final focused = findFocusedVisitor(
      eyePosition,
      viewerForward,
      maxDistance: 3.55,
      minForwardDot: 0.65,
    );
    if (focused == null) {
      _activeBarkLabel?.node.visible = false;
      _activeBarkLabel = null;
      return;
    }
    final key = '${focused.id}|${focused.ambientComment}|$canTalkToVisitors';
    final cached = _barkCache[key];
    if (cached != null) {
      if (!identical(_activeBarkLabel, cached)) {
        _activeBarkLabel?.node.visible = false;
        _activeBarkLabel = cached;
      }
      final labelY = focused.appearance.heightMeters + 0.36;
      cached.node.localTransform = vm.Matrix4.translationValues(
        focused.x,
        labelY,
        focused.z,
      );
      cached.faceCamera(eyePosition);
      cached.node.visible = true;
      return;
    }

    _activeBarkLabel?.node.visible = false;
    _activeBarkLabel = null;
    if (!Scene.isReadyToRender || _barkPendingKeys.contains(key)) return;
    _barkPendingKeys.add(key);
    final epoch = _mountEpoch;
    final header = '${focused.displayName} · ${focused.role}';
    final comment = focused.ambientComment;
    final hint = canTalkToVisitors ? '[ A · Hablar (IA Local) ]' : null;
    rasterizeBarkBubble(
      header,
      comment,
      actionHint: hint,
      accent: theme.accent,
    ).then((bitmap) {
      _barkPendingKeys.remove(key);
      if (_disposed || !_gpuMounted || epoch != _mountEpoch) return;
      if (!Scene.isReadyToRender) return;
      if (_barkCache.length >= 16) {
        final oldestKey = _barkCache.keys.first;
        final evicted = _barkCache.remove(oldestKey);
        if (identical(_activeBarkLabel, evicted)) _activeBarkLabel = null;
        evicted?.node.parent?.remove(evicted.node);
      }
      final label = VrTextLabel.fromBitmap(
        bitmap,
        '$header\n$comment',
        center: vm.Vector3(focused.x, focused.appearance.heightMeters + 0.36, focused.z),
        height: math.min(0.30, 1.45 / bitmap.aspect),
        name: 'npc_bark_${focused.id}',
      );
      label.node
        ..raycastable = false
        ..shadowCastingMode = ShadowCastingMode.off
        ..visible = false;
      root.add(label.node);
      _barkCache[key] = label;
    }).catchError((Object _) {
      _barkPendingKeys.remove(key);
    });
  }

  void tick(
    double time, {
    vm.Vector3? eyePosition,
    vm.Vector3? viewerForward,
    void Function(vm.Vector3 visitorPosition)? onVisitorGreeted,
    bool hideBarkBubble = false,
    bool canTalkToVisitors = false,
  }) {
    if (_disposed || !time.isFinite) return;
    final dt = _lastTime < 0 ? (1 / 60) : (time - _lastTime).clamp(0.0, 0.1);
    _lastTime = time;

    // Decouple AI pathing to 12 Hz (matching multiplayer 10–15 Hz peer ticks)
    // when GPU is mounted; VrPeerAvatarStage dead-reckons smoothly at 60–120 Hz!
    _aiAccum += dt;
    final runAiStep = !_gpuMounted || _aiAccum >= (1.0 / 12.0);
    if (runAiStep) {
      final aiDt = _gpuMounted ? _aiAccum.clamp(0.0, 0.25) : dt;
      _aiAccum = 0.0;
      for (var i = 0; i < visitors.length; i++) {
        final v = visitors[i];
        final wasGreeting = v.greetingPlayer;
        v.step(time, aiDt, eyePosition);
        if (!wasGreeting &&
            v.greetingPlayer &&
            onVisitorGreeted != null &&
            time - _lastGreetingAudioTime >= 4.0) {
          _lastGreetingAudioTime = time;
          onVisitorGreeted(vm.Vector3(v.x, 1.5, v.z));
        }
        peerStage.updatePeerMotion(
          v.id,
          x: v.x,
          z: v.z,
          yaw: v.yaw,
          vx: v.vx,
          vz: v.vz,
          pose: v.pose,
        );
      }
    }

    peerStage.tick(
      dt,
      eyePosition: eyePosition,
      viewerForward: viewerForward,
    );

    _updateOverheadBark(
      eyePosition: eyePosition,
      viewerForward: viewerForward,
      hideBarkBubble: hideBarkBubble,
      canTalkToVisitors: canTalkToVisitors,
    );

    if (_gpuMounted && _aerialOrbMesh != null) {
      _orbAccum += dt;
      if (_orbAccum >= (1.0 / 24.0)) {
        _orbAccum = 0.0;
        final warmBiome = theme.accent.r > theme.accent.b;
        _aerialOrbMesh!.updateInstanceTransforms((transforms) {
          for (var i = 0; i < transforms.length; i++) {
            transforms[i].setIdentity();
            if (i < 6) {
              // 6 primary sculptural atrium orbs
              final phase = time * 0.42 + i * (math.pi / 3);
              final radius = 4.2 + (i % 3) * 1.6;
              final ox = math.cos(phase) * radius;
              final oz = 1.5 + math.sin(phase * 0.85) * (radius * 1.15);
              final oy = 3.15 + math.sin(time * 1.1 + i * 1.3) * 0.32;
              transforms[i].scaleByDouble(1.4, 1.4, 1.4, 1.0);
              transforms[i].setTranslationRaw(ox, oy, oz);
            } else {
              // 12 biome-aware floating atmospheric motes (fireflies / neon / stardust)
              final m = i - 6;
              final orbit = time * (warmBiome ? 0.22 : 0.34) + m * 0.54;
              final radius = 2.6 + (m % 4) * 2.15;
              final ox = math.cos(orbit) * radius + math.sin(time * 0.7 + m) * 0.35;
              final oz = -1.0 + math.sin(orbit * 0.82) * (radius * 1.1);
              final rise = ((time * (warmBiome ? 0.28 : 0.42) + m * 0.37) % 1.0);
              final oy = 1.05 + rise * 3.45 + math.sin(time * 1.9 + m) * 0.14;
              final s = 0.42 + 0.35 * math.sin(rise * math.pi);
              transforms[i].scaleByDouble(s, s, s, 1.0);
              transforms[i].setTranslationRaw(ox, oy, oz);
            }
          }
        }, recomputeWinding: false);
        _aerialOrbNode?.markTransformDirty();
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_mountEpoch;
    peerStage.dispose();
    for (final label in _barkCache.values) {
      label.node.parent?.remove(label.node);
    }
    _barkCache.clear();
    _barkPendingKeys.clear();
    _activeBarkLabel = null;
    _aerialOrbMesh?.clearInstances();
    _aerialOrbNode?.detach();
    _aerialOrbMesh = null;
    _aerialOrbNode = null;
    root.parent?.remove(root);
  }
}
