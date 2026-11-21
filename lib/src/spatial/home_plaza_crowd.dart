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
import 'home_walk_space.dart';

/// Pure-CPU kinematic and social state for an ambient plaza visitor so crowd
/// motion, multi-wing exploration, NPC-to-NPC micro-conversations, storefront
/// browsing pauses, and player-proximity greetings can be verified
/// deterministically in headless tests without a GPU context.
final class HomePlazaVisitorState {
  HomePlazaVisitorState({
    required this.id,
    required this.appearance,
    required this.routePoints,
    required this.storefrontLookYaw,
    required this.walkSpeed,
    required this.phaseOffset,
    required this.conversationalist,
    this.routeRoomTitles = const [],
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
  final List<String?> routeRoomTitles;
  final double walkSpeed;
  final double phaseOffset;
  final bool conversationalist;
  final String displayName;
  final String role;
  final double? partnerYaw;

  String? nearestRoomTitle;
  String ambientComment;
  bool talkingToPlayer = false;
  double socialReactionRemaining = 0.0;
  double? socialReactionTargetYaw;

  // Dynamic NPC-to-NPC conversation state (pure CPU, 0 allocations per frame).
  String? chatPartnerId;
  String? chatPartnerName;
  double chatPartnerX = 0.0;
  double chatPartnerZ = 0.0;
  double chatRemainingSeconds = 0.0;
  double chatCooldownSeconds = 0.0;
  int chatTurnIndex = 0;
  bool isChatSpeaker = false;
  bool chatFarewell = false;
  String? activeChatLine;

  double x;
  double z;
  double yaw;
  double vx = 0.0;
  double vz = 0.0;
  int targetIndex = 1;
  double pauseRemaining = 0.0;
  bool greetingPlayer = false;
  VrAvatarPose pose = VrAvatarPose.neutral;

  bool get isChattingWithNpc =>
      chatPartnerId != null && chatRemainingSeconds > 0.0;

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

  void _clearNpcChat({double cooldown = 14.0}) {
    chatPartnerId = null;
    chatPartnerName = null;
    chatRemainingSeconds = 0.0;
    isChatSpeaker = false;
    chatFarewell = false;
    activeChatLine = null;
    chatCooldownSeconds = math.max(chatCooldownSeconds, cooldown);
  }

  void step(double time, double dt, vm.Vector3? playerEye) {
    final stepDt = dt.isFinite ? dt.clamp(0.0, 0.25) : 0.0;
    final blinkWave = math.sin(time * 0.92 + phaseOffset * 3.1);
    final blink = blinkWave > 0.982 ? ((blinkWave - 0.982) / 0.018) : 0.0;

    if (chatCooldownSeconds > 0.0) {
      chatCooldownSeconds = math.max(0.0, chatCooldownSeconds - stepDt);
    }

    if (socialReactionRemaining > 0.0 && !talkingToPlayer) {
      socialReactionRemaining = math.max(0.0, socialReactionRemaining - stepDt);
      vx = 0.0;
      vz = 0.0;
      final desiredYaw = socialReactionTargetYaw ?? yaw;
      yaw = _lerpAngle(yaw, desiredYaw, (stepDt * 5.8).clamp(0.0, 1.0));
      pose = VrAvatarPose.wave(
        time + phaseOffset,
        leftHand: phaseOffset.toInt().isEven,
        waveAmount: 0.82,
        blink: blink,
      );
      return;
    }

    // Active conversation lock with the player: hold position, face the player
    // smoothly, and animate expressive conversational gestures.
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
      final talkPhase = time * 2.25 + phaseOffset;
      pose = VrAvatarPose(
        lean: 0.035 + math.sin(talkPhase * 0.65) * 0.025,
        turn: math.sin(talkPhase * 0.55) * 0.06,
        nod: math.sin(talkPhase * 1.45) * 0.085,
        look: math.sin(talkPhase * 0.72) * 0.13,
        tilt: math.cos(talkPhase * 0.58) * 0.055,
        leftArmFlexion: 0.36 + math.sin(talkPhase * 1.75) * 0.22,
        rightArmFlexion: 0.30 + math.cos(talkPhase * 1.50) * 0.20,
        leftArmAbduction: 0.14 + math.sin(talkPhase * 1.1).abs() * 0.08,
        rightArmAbduction: 0.14 + math.cos(talkPhase * 0.95).abs() * 0.08,
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
        yaw = _lerpAngle(yaw, desiredYaw, (stepDt * 5.6).clamp(0.0, 1.0));
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

    // Active NPC-to-NPC conversation: face partner, maintain personal spacing,
    // alternate speaker/listener gestures, and wave goodbye on farewell beat!
    if (isChattingWithNpc) {
      vx = 0.0;
      vz = 0.0;
      final dx = chatPartnerX - x;
      final dz = chatPartnerZ - z;
      final dist = math.sqrt(dx * dx + dz * dz);
      if (dist > 0.05) {
        final desiredYaw = math.atan2(dx, dz);
        yaw = _lerpAngle(yaw, desiredYaw, (stepDt * 6.0).clamp(0.0, 1.0));
        // Ease gently into comfortable ~1.35 m social spacing without popping.
        if (dist < 1.18) {
          final push = math.min(0.35 * stepDt, (1.25 - dist) * 0.5);
          x -= (dx / dist) * push;
          z -= (dz / dist) * push;
        }
      }
      if (chatFarewell) {
        pose = VrAvatarPose.wave(
          time * 1.15 + phaseOffset,
          leftHand: phaseOffset.toInt().isEven,
          waveAmount: 0.85,
          blink: blink,
        );
        return;
      }
      final g = time * 2.15 + phaseOffset;
      if (isChatSpeaker) {
        // Expressive speaking pose: animated gesturing hands, forward lean & nods.
        pose = VrAvatarPose(
          lean: 0.045 + math.sin(g * 0.8) * 0.028,
          turn: math.sin(g * 0.65) * 0.085,
          bob: math.sin(g * 1.6).abs() * 0.012,
          nod: math.sin(g * 1.65) * 0.095,
          look: math.sin(g * 0.7) * 0.10,
          tilt: math.cos(g * 0.62) * 0.065,
          leftArmFlexion: 0.42 + math.sin(g * 1.95) * 0.26,
          rightArmFlexion: 0.34 + math.cos(g * 1.65) * 0.24,
          leftArmAbduction: 0.16 + math.sin(g * 1.3).abs() * 0.12,
          rightArmAbduction: 0.14 + math.cos(g * 1.1).abs() * 0.11,
          blink: blink,
        );
      } else {
        // Attentive listening pose: approving head nods, slight head tilt, relaxed arms.
        pose = VrAvatarPose(
          lean: 0.015,
          turn: math.sin(g * 0.42) * 0.04,
          nod: 0.03 + math.sin(g * 1.35) * 0.085,
          look: math.sin(g * 0.55) * 0.07,
          tilt: 0.065 * math.sin(g * 0.45 + 0.8),
          leftArmFlexion: 0.14 + math.sin(g * 0.85) * 0.06,
          rightArmFlexion: 0.18 + math.cos(g * 0.75) * 0.07,
          leftArmAbduction: 0.08,
          rightArmAbduction: 0.09,
          blink: blink,
        );
      }
      return;
    }

    if (routePoints.length < 2 || walkSpeed <= 0.01) {
      vx = 0.0;
      vz = 0.0;
      final baseYaw = partnerYaw ?? yaw;
      yaw = _lerpAngle(yaw, baseYaw, (stepDt * 3.0).clamp(0.0, 1.0));
      final gesturePhase = time * 1.85 + phaseOffset;
      final speaking = math.sin(gesturePhase * 0.55) > -0.15;
      pose = VrAvatarPose(
        lean: speaking ? 0.03 : 0.0,
        turn: math.sin(gesturePhase * 0.48) * 0.06,
        nod: math.sin(gesturePhase * 1.45) * 0.075,
        look: math.sin(gesturePhase * 0.75) * 0.16,
        tilt: math.cos(gesturePhase * 0.55) * 0.05,
        leftArmFlexion: speaking
            ? (0.32 + math.sin(gesturePhase * 1.85) * 0.20)
            : 0.10,
        rightArmFlexion: speaking
            ? (0.26 + math.cos(gesturePhase * 1.55) * 0.18)
            : 0.10,
        leftArmAbduction: 0.11,
        rightArmAbduction: 0.11,
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
        yaw = _lerpAngle(yaw, lookTarget, (stepDt * 4.4).clamp(0.0, 1.0));
      }
      final inspectPhase = time * 1.9 + phaseOffset;
      final admirePoint = math.sin(inspectPhase * 0.45) > 0.35;
      pose = VrAvatarPose(
        lean: 0.025,
        turn: math.sin(inspectPhase * 0.52) * 0.07,
        nod: -0.04 + math.sin(inspectPhase * 1.15) * 0.065,
        look: math.sin(inspectPhase * 0.85) * 0.28,
        tilt: math.cos(inspectPhase * 0.6) * 0.055,
        leftArmFlexion: 0.14 + math.sin(inspectPhase * 0.9) * 0.05,
        rightArmFlexion: admirePoint
            ? (0.48 + math.sin(inspectPhase * 1.5) * 0.10)
            : (0.16 + math.cos(inspectPhase * 0.8) * 0.05),
        leftArmAbduction: 0.08,
        rightArmAbduction: admirePoint ? 0.18 : 0.08,
        blink: blink,
      );
      return;
    }

    final target = routePoints[targetIndex % routePoints.length];
    final dx = target.x - x;
    final dz = target.z - z;
    final dist = math.sqrt(dx * dx + dz * dz);
    if (dist <= 0.26) {
      x = target.x;
      z = target.z;
      vx = 0.0;
      vz = 0.0;
      final reachedIdx = targetIndex % routePoints.length;
      if (reachedIdx < routeRoomTitles.length &&
          routeRoomTitles[reachedIdx] != null) {
        nearestRoomTitle = routeRoomTitles[reachedIdx];
      }
      targetIndex = (targetIndex + 1) % routePoints.length;
      if (storefrontLookYaw[reachedIdx] != null) {
        pauseRemaining = 2.4 + (phaseOffset % 2.4);
      } else if (conversationalist && reachedIdx.isEven) {
        // Social ambassadors take brief panoramic pauses at plaza hubs to mingle.
        pauseRemaining = 1.6 + (phaseOffset % 1.4);
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
    yaw = _lerpAngle(yaw, travelYaw, (stepDt * 6.2).clamp(0.0, 1.0));
    final stridePhi = time * (walkSpeed * 4.1) + phaseOffset;
    final walkBase = VrAvatarPose.walk(
      stridePhi,
      amplitude: 0.62,
      lean: 0.055,
      look: math.sin(time * 0.85 + phaseOffset) * 0.16,
      blink: blink,
    );
    // Layer subtle organic hip/torso counter-twist & head tilt on top of walk.
    pose = walkBase.copyWith(
      turn: math.sin(stridePhi) * 0.068,
      tilt: math.cos(stridePhi * 0.5) * 0.03,
    );
  }

  static double _lerpAngle(double from, double to, double t) {
    var diff = (to - from) % (math.pi * 2);
    if (diff > math.pi) diff -= math.pi * 2;
    if (diff < -math.pi) diff += math.pi * 2;
    return from + diff * t;
  }
}

/// Active pure-CPU micro-conversation between two plaza visitors.
final class _NpcSocialExchange {
  _NpcSocialExchange({
    required this.a,
    required this.b,
    required this.lines,
    required this.turnDurationSeconds,
  }) : totalSeconds = lines.length * turnDurationSeconds + 1.4;

  final HomePlazaVisitorState a;
  final HomePlazaVisitorState b;
  final List<String> lines;
  final double turnDurationSeconds;
  final double totalSeconds;
  double elapsed = 0.0;

  int get currentTurn =>
      (elapsed ~/ turnDurationSeconds).clamp(0, lines.length - 1);
  bool get isFarewell => elapsed >= lines.length * turnDurationSeconds;
  bool get isFinished => elapsed >= totalSeconds;
  HomePlazaVisitorState get currentSpeaker => currentTurn.isEven ? a : b;
  HomePlazaVisitorState get currentListener => currentTurn.isEven ? b : a;
  String get currentLine => lines[currentTurn];
}

/// Populates Virtual Home Plazas and 360° Famous Malls with living, colorful,
/// strolling, window-shopping, and socially conversing 3D visitors
/// (`VrPeerAvatarStage`) plus biome-tinted aerial light-drones while staying
/// strictly within mobile VR GPU budgets (`<= 3` instanced avatar draw calls
/// and `<= 1` active overhead speech/thought bubble quad at any moment).
final class HomePlazaCrowd {
  HomePlazaCrowd._({
    required this.visitors,
    required this.theme,
    List<HomeWalkableElevation> elevations = const [],
    List<_NpcSocialExchange> initialExchanges = const [],
  }) : elevations = List.unmodifiable(elevations) {
    _activeExchanges.addAll(initialExchanges);
    for (final ex in _activeExchanges) {
      _syncExchangeToVisitors(ex);
    }
    for (final v in visitors) {
      peerStage.upsertPeer(
        VrPeerAvatarSnapshot(
          peerId: v.id,
          appearance: v.appearance,
          x: v.x,
          y: groundYAt(v.x, v.z),
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

  static List<String> _buildDialogueLines(
    HomePlazaVisitorState a,
    HomePlazaVisitorState b,
    int seed,
  ) {
    final topicA = a.nearestRoomTitle ?? 'la Gran Plaza';
    final topicB =
        (b.nearestRoomTitle != null && b.nearestRoomTitle != topicA)
        ? b.nearestRoomTitle!
        : 'el Crucero Central';
    final nameA = a.displayName;
    final nameB = b.displayName;
    return switch (seed % 6) {
      0 => [
        '¡Hey $nameB! ¿Ya pasaste por «$topicA»?',
        '¡Sí, $nameA! Me encantó la luz de ahí. Ahora voy hacia «$topicB».',
        'Buenísima ruta, yo doy una vuelta por esta ala y te alcanzo.',
        '¡Perfecto! Nos vemos cerca de los portales.',
      ],
      1 => [
        'Qué buen ambiente hay hoy por aquí, ¿verdad $nameB?',
        'Totalmente, $nameA. Justo vengo saliendo de «$topicB».',
        '¿Lo recomiendas? Quiero probar algo nuevo en VR.',
        '¡Al cien! Te va a sorprender cuando entres.',
      ],
      2 => [
        '¡Hola $nameB! ¿Viste cuánta gente está explorando hoy?',
        '¡Sí! Estuve echando un vistazo a «$topicA» hace un momento.',
        'Yo voy rumbo a «$topicB» para ver qué hay de novedad.',
        '¡Suerte en el recorrido, nos cruzamos luego!',
      ],
      3 => [
        'Oye $nameB, ¿por qué ala me recomiendas caminar ahora?',
        'Pasa por «$topicB», $nameA, la vista en estéreo se ve increíble.',
        '¡Anotado! Y tú no te pierdas «$topicA» si pasas por allá.',
        'Gracias por el tip, ¡disfruta la plaza!',
      ],
      4 => [
        '¡Qué gusto coincidir contigo en el paseo, $nameB!',
        'Igual $nameA, me encanta recorrer las cuatro alas con calma.',
        'Dicen que hoy en «$topicA» hay experiencias geniales gratis.',
        '¡Vamos a curiosear! Hasta ahorita.',
      ],
      _ => [
        '¡Hola $nameB! ¿Cuál ha sido tu espacio favorito hoy?',
        'Sin duda «$topicA», aunque también quiero pasar a «$topicB».',
        'Qué coincidencia, justo iba en esa dirección.',
        '¡Excelente, nos vemos por la plaza!',
      ],
    };
  }

  /// Safe walkable plaza point right outside a portal's doorway (1.45 m on the
  /// plaza side of the door, facing directly into the storefront).
  static (vm.Vector3 point, double lookYaw) _storefrontPromenadePoint(
    HomeEcosystemPortal portal, {
    double lateralShift = 0.0,
  }) {
    final frontX = portal.doorX - portal.inwardForwardX * 1.48;
    final frontZ = portal.doorZ - portal.inwardForwardZ * 1.48;
    // Lateral tangent perpendicular to inward normal so parallel strollers spread cleanly.
    final tangentX = -portal.inwardForwardZ;
    final tangentZ = portal.inwardForwardX;
    final lookYaw = math.atan2(portal.inwardForwardX, portal.inwardForwardZ);
    return (
      vm.Vector3(
        frontX + tangentX * lateralShift,
        0,
        frontZ + tangentZ * lateralShift,
      ),
      lookYaw,
    );
  }

  /// Picks the corridor spine hub closest to [target] so multi-wing routes
  /// travel along walkable avenues instead of cutting diagonally across walls.
  static vm.Vector3 _nearestHub(
    vm.Vector3 target,
    List<vm.Vector3> hubs,
  ) {
    var best = hubs.first;
    var bestDistSq = double.infinity;
    for (final h in hubs) {
      final dx = h.x - target.x;
      final dz = h.z - target.z;
      final dSq = dx * dx + dz * dz;
      if (dSq < bestDistSq) {
        bestDistSq = dSq;
        best = h;
      }
    }
    return best;
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
        cosmeticId: VrAvatarCosmeticCatalog.wayfinder,
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
        bodyColorArgb: 0xFF34495E,
        accentColorArgb: 0xFF00E5FF,
        heightMeters: 1.82,
        featureScale: 1.12,
        pattern: VrAvatarPattern.stripes,
        cosmeticId: VrAvatarCosmeticCatalog.neon,
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
        cosmeticId: VrAvatarCosmeticCatalog.canopy,
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
        cosmeticId: VrAvatarCosmeticCatalog.aurora,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.sprout,
        bodyColorArgb: 0xFF20BF6B,
        accentColorArgb: 0xFFFED330,
        heightMeters: 1.46,
        featureScale: 1.18,
        pattern: VrAvatarPattern.spots,
        cosmeticId: VrAvatarCosmeticCatalog.canopy,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.robot,
        bodyColorArgb: 0xFF3B3B98,
        accentColorArgb: 0xFFF8EFBA,
        heightMeters: 1.78,
        pattern: VrAvatarPattern.solid,
        cosmeticId: VrAvatarCosmeticCatalog.neon,
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
        heightMeters: 1.54,
        pattern: VrAvatarPattern.spots,
        cosmeticId: VrAvatarCosmeticCatalog.aurora,
      ),
      VrAvatarAppearance(
        species: VrAvatarSpecies.human,
        bodyColorArgb: 0xFF1E824C,
        accentColorArgb: 0xFF55E6C1,
        heightMeters: 1.76,
        pattern: VrAvatarPattern.solid,
        cosmeticId: VrAvatarCosmeticCatalog.wayfinder,
      ),
    ];

    final visitors = <HomePlazaVisitorState>[];
    final portals = layout.portals;
    final waypoints = layout.waypoints;

    // Extract walkable open-plaza hubs (corridors, crossroads, wings, rotunda),
    // skipping portal-interior waypoints so paths stay cleanly in open avenues.
    final corridorHubs = <vm.Vector3>[
      for (final wp in waypoints)
        if (!wp.id.startsWith('portal_')) vm.Vector3(wp.x, 0, wp.z),
    ];
    if (corridorHubs.isEmpty) {
      corridorHubs.addAll([
        vm.Vector3(-3.4, 0, -2.2),
        vm.Vector3(-3.4, 0, 5.2),
        vm.Vector3(3.4, 0, 5.2),
        vm.Vector3(3.4, 0, -2.2),
      ]);
    }
    // Prefer central crossroads / plaza center as the main interchange node.
    vm.Vector3 centralHub = corridorHubs.first;
    for (final wp in waypoints) {
      if (wp.id == 'mall_crucero_central' ||
          wp.id == 'center' ||
          wp.id == 'mall_arrival') {
        centralHub = vm.Vector3(wp.x, 0, wp.z);
        if (wp.id == 'mall_crucero_central' || wp.id == 'center') break;
      }
    }

    // 1. Promenade strollers touring DIFFERENT wings & storefront doors (up to 8)
    if (portals.length >= 2) {
      final strollerCount = math.min(8, portals.length);
      for (var i = 0; i < strollerCount; i++) {
        final stride = math.max(1, portals.length ~/ 3);
        final pA = portals[i % portals.length];
        final pB = portals[(i + stride) % portals.length];
        final pC = portals[(i + stride * 2) % portals.length];
        final lane = (i.isEven ? -0.65 : 0.65) + ((i % 3) - 1) * 0.25;

        final (ptA, lookA) = _storefrontPromenadePoint(pA, lateralShift: lane * 0.5);
        final (ptB, lookB) = _storefrontPromenadePoint(pB, lateralShift: -lane * 0.5);
        final (ptC, lookC) = _storefrontPromenadePoint(pC, lateralShift: lane * 0.35);

        final hubA = _nearestHub(ptA, corridorHubs);
        final hubB = _nearestHub(ptB, corridorHubs);
        final hubC = _nearestHub(ptC, corridorHubs);

        final pts = <vm.Vector3>[
          ptA,
          vm.Vector3(hubA.x + lane * 0.5, 0, hubA.z + lane * 0.35),
          vm.Vector3(centralHub.x + lane * 0.9, 0, centralHub.z - lane * 0.55),
          vm.Vector3(hubB.x - lane * 0.45, 0, hubB.z + lane * 0.4),
          ptB,
          vm.Vector3(hubB.x + lane * 0.4, 0, hubB.z - lane * 0.45),
          vm.Vector3(centralHub.x - lane * 0.8, 0, centralHub.z + lane * 0.6),
          vm.Vector3(hubC.x - lane * 0.35, 0, hubC.z - lane * 0.4),
          ptC,
        ];
        final looks = <double?>[
          lookA,
          null,
          null,
          null,
          lookB,
          null,
          null,
          null,
          lookC,
        ];
        final roomNames = <String?>[
          pA.room.title,
          null,
          null,
          null,
          pB.room.title,
          null,
          null,
          null,
          pC.room.title,
        ];

        final persona = _npcPersonas[i % _npcPersonas.length];
        final visitor = HomePlazaVisitorState(
          id: 'plaza_stroller_$i',
          appearance: palettes[i % palettes.length],
          routePoints: pts,
          storefrontLookYaw: looks,
          routeRoomTitles: roomNames,
          walkSpeed: 0.98 + (i % 4) * 0.10,
          phaseOffset: i * 1.41,
          conversationalist: false,
          displayName: persona.$1,
          role: persona.$2,
          nearestRoomTitle: pA.room.title,
          ambientComment: _seedCommentFor(
            index: i,
            roomTitle: pA.room.title,
            plazaBannerText: plazaBannerText,
          ),
        );
        // Spread strollers across ALL zones on initial spawn so every wing
        // feels alive immediately!
        final startIdx = (i * 2) % pts.length;
        final nextIdx = (startIdx + 1) % pts.length;
        final a = pts[startIdx];
        final b = pts[nextIdx];
        final frac = ((i * 0.31) % 0.72) + 0.14;
        visitor
          ..x = a.x + (b.x - a.x) * frac
          ..z = a.z + (b.z - a.z) * frac
          ..targetIndex = nextIdx
          ..yaw = math.atan2(b.x - a.x, b.z - a.z)
          ..chatCooldownSeconds = 2.0 + (i % 4) * 2.2;
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
            walkSpeed: 1.08,
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

    // 2. Four social ambassadors (`conversationalist: true`) who start in 2
    // lively NPC-to-NPC conversations at distinct plaza hubs, then wave goodbye
    // and roam across OTHER wings & plazas to mingle with passing visitors!
    final arrivalHub = corridorHubs.length > 1
        ? corridorHubs[1]
        : corridorHubs.first;
    final socialAnchor0 = vm.Vector3(
      arrivalHub.x - 2.3,
      0,
      arrivalHub.z + 1.2,
    );
    final socialAnchor1 = vm.Vector3(
      centralHub.x + 2.4,
      0,
      centralHub.z - 1.1,
    );
    final socialPairs = <(double x1, double z1, double x2, double z2)>[
      (
        socialAnchor0.x,
        socialAnchor0.z,
        socialAnchor0.x + 1.38,
        socialAnchor0.z + 0.42,
      ),
      (
        socialAnchor1.x,
        socialAnchor1.z,
        socialAnchor1.x - 1.38,
        socialAnchor1.z - 0.42,
      ),
    ];

    final initialExchanges = <_NpcSocialExchange>[];
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

      // Each social ambassador has a real multi-zone roaming route across the
      // plaza hubs so they walk to new spots once their conversation ends!
      final tourA = <vm.Vector3>[
        vm.Vector3(x1, 0, z1),
        for (var h = 0; h < math.min(4, corridorHubs.length); h++)
          vm.Vector3(
            corridorHubs[(p + h) % corridorHubs.length].x - 1.2,
            0,
            corridorHubs[(p + h) % corridorHubs.length].z + 0.9,
          ),
      ];
      final tourB = <vm.Vector3>[
        vm.Vector3(x2, 0, z2),
        for (var h = 0; h < math.min(4, corridorHubs.length); h++)
          vm.Vector3(
            corridorHubs[(corridorHubs.length - 1 - ((p + h) % corridorHubs.length))]
                    .x +
                1.2,
            0,
            corridorHubs[(corridorHubs.length - 1 - ((p + h) % corridorHubs.length))]
                    .z -
                0.9,
          ),
      ];

      final npcA = HomePlazaVisitorState(
        id: 'plaza_social_${p}_a',
        appearance: palettes[baseIdx % palettes.length],
        routePoints: tourA,
        storefrontLookYaw: List<double?>.filled(tourA.length, null),
        walkSpeed: 0.92,
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
      );
      final npcB = HomePlazaVisitorState(
        id: 'plaza_social_${p}_b',
        appearance: palettes[(baseIdx + 1) % palettes.length],
        routePoints: tourB,
        storefrontLookYaw: List<double?>.filled(tourB.length, null),
        walkSpeed: 0.96,
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
      );
      visitors
        ..add(npcA)
        ..add(npcB);

      initialExchanges.add(
        _NpcSocialExchange(
          a: npcA,
          b: npcB,
          lines: _buildDialogueLines(npcA, npcB, p),
          turnDurationSeconds: 2.8,
        )..elapsed = p * 1.4,
      );
    }

    return HomePlazaCrowd._(
      visitors: visitors,
      theme: theme,
      elevations: layout.elevations,
      initialExchanges: initialExchanges,
    );
  }

  final List<HomePlazaVisitorState> visitors;
  final VrHomeThemeData theme;
  final List<HomeWalkableElevation> elevations;

  /// Continuous ground elevation (in meters) at world `(x, z)` so roaming NPCs,
  /// floating speech bubbles, and 3D spatial greetings ride terraces and ramps
  /// cleanly without clipping into sloped surfaces.
  double groundYAt(double x, double z) =>
      elevations.isEmpty ? 0.0 : HomeWalkSpace.sampleElevations(elevations, x, z);
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
  final List<_NpcSocialExchange> _activeExchanges = <_NpcSocialExchange>[];
  VrTextLabel? _activeBarkLabel;
  double _lastTime = -1;
  double _aiAccum = 1.0;
  double _orbAccum = 1.0;
  double _lastGreetingAudioTime = -10.0;
  int _dialogueSeed = 2;
  int _mountEpoch = 0;
  bool _gpuMounted = false;
  bool _disposed = false;

  bool get isGpuMounted => _gpuMounted;

  /// Number of live NPC-to-NPC conversations currently taking place across the plaza.
  int get activeNpcConversationCount => _activeExchanges.length;

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
    if (visitorId != null) {
      _endExchangesInvolving(visitorId);
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

  /// Pure-CPU query returning the nearest actively speaking NPC in a live
  /// NPC-to-NPC conversation within [maxDistance] in front of the player so we
  /// can float a single ambient overheard speech bubble with zero extra GPU quads.
  HomePlazaVisitorState? findNearbyConversingSpeaker(
    vm.Vector3 eyePosition,
    vm.Vector3 viewerForward, {
    double maxDistance = 10.5,
    double minForwardDot = 0.35,
  }) {
    if (_activeExchanges.isEmpty) return null;
    final fxRaw = viewerForward.x;
    final fzRaw = viewerForward.z;
    final fLen = math.sqrt(fxRaw * fxRaw + fzRaw * fzRaw);
    final fx = fLen > 1e-5 ? fxRaw / fLen : 0.0;
    final fz = fLen > 1e-5 ? fzRaw / fLen : -1.0;
    final maxDistSq = maxDistance * maxDistance;

    HomePlazaVisitorState? best;
    var bestDistSq = double.infinity;
    for (var i = 0; i < _activeExchanges.length; i++) {
      final ex = _activeExchanges[i];
      if (ex.isFarewell) continue;
      final speaker = ex.currentSpeaker;
      if (speaker.activeChatLine == null || speaker.talkingToPlayer) continue;
      final dx = speaker.x - eyePosition.x;
      final dz = speaker.z - eyePosition.z;
      final distSq = dx * dx + dz * dz;
      if (distSq > maxDistSq || distSq < 0.16) continue;
      final invDist = 1.0 / math.sqrt(distSq);
      final dot = (dx * fx + dz * fz) * invDist;
      if (dot < minForwardDot) continue;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        best = speaker;
      }
    }
    return best;
  }

  void _endExchangesInvolving(String visitorId) {
    for (var i = _activeExchanges.length - 1; i >= 0; i--) {
      final ex = _activeExchanges[i];
      if (ex.a.id == visitorId || ex.b.id == visitorId) {
        ex.a._clearNpcChat(cooldown: 10.0);
        ex.b._clearNpcChat(cooldown: 10.0);
        _activeExchanges.removeAt(i);
      }
    }
  }

  void _syncExchangeToVisitors(_NpcSocialExchange ex) {
    final remaining = math.max(0.0, ex.totalSeconds - ex.elapsed);
    final speaker = ex.currentSpeaker;
    final listener = ex.currentListener;
    final line = ex.currentLine;

    ex.a
      ..chatPartnerId = ex.b.id
      ..chatPartnerName = ex.b.displayName
      ..chatPartnerX = ex.b.x
      ..chatPartnerZ = ex.b.z
      ..chatRemainingSeconds = remaining
      ..chatTurnIndex = ex.currentTurn
      ..chatFarewell = ex.isFarewell
      ..isChatSpeaker = identical(speaker, ex.a)
      ..activeChatLine = identical(speaker, ex.a) ? line : null;

    ex.b
      ..chatPartnerId = ex.a.id
      ..chatPartnerName = ex.a.displayName
      ..chatPartnerX = ex.a.x
      ..chatPartnerZ = ex.a.z
      ..chatRemainingSeconds = remaining
      ..chatTurnIndex = ex.currentTurn
      ..chatFarewell = ex.isFarewell
      ..isChatSpeaker = identical(speaker, ex.b)
      ..activeChatLine = identical(speaker, ex.b) ? line : null;

    if (!ex.isFarewell) {
      speaker.ambientComment = line;
      listener.ambientComment =
          'Estaba platicando con ${speaker.displayName}: «$line»';
    }
  }

  /// Advances active NPC-to-NPC exchanges, starts new organic encounters when
  /// two available visitors cross paths (`<= 2.55 m`), and applies gentle
  /// personal-space steering (`< 1.05 m`) so walking visitors don't overlap.
  void _stepSocialEncounters(double dt) {
    // 1. Advance active exchanges and retire completed or interrupted ones.
    for (var i = _activeExchanges.length - 1; i >= 0; i--) {
      final ex = _activeExchanges[i];
      ex.elapsed += dt;
      final interrupted =
          ex.a.talkingToPlayer ||
          ex.b.talkingToPlayer ||
          ex.a.greetingPlayer ||
          ex.b.greetingPlayer;
      if (interrupted || ex.isFinished) {
        final cooldown = interrupted ? 10.0 : (14.0 + (_dialogueSeed % 7) * 1.3);
        ex.a._clearNpcChat(cooldown: cooldown);
        ex.b._clearNpcChat(cooldown: cooldown + 1.8);
        // Send partners toward distinct next route points so they spread out!
        if (ex.a.routePoints.length >= 2) {
          ex.a.targetIndex = (ex.a.targetIndex + 1) % ex.a.routePoints.length;
        }
        if (ex.b.routePoints.length >= 2) {
          ex.b.targetIndex = (ex.b.targetIndex + 2) % ex.b.routePoints.length;
        }
        _activeExchanges.removeAt(i);
        continue;
      }
      _syncExchangeToVisitors(ex);
    }

    // 2. Discover new spontaneous NPC-to-NPC conversations (cap at 3 active
    // pairs across the plaza so most visitors keep strolling across wings).
    const maxConcurrentExchanges = 3;
    const encounterRadiusSq = 2.55 * 2.55;
    const separationRadiusSq = 1.05 * 1.05;

    for (var i = 0; i < visitors.length; i++) {
      final a = visitors[i];
      for (var j = i + 1; j < visitors.length; j++) {
        final b = visitors[j];
        final dx = b.x - a.x;
        final dz = b.z - a.z;
        final distSq = dx * dx + dz * dz;
        if (distSq > encounterRadiusSq) continue;

        final canStartChat =
            _activeExchanges.length < maxConcurrentExchanges &&
            !a.isChattingWithNpc &&
            !b.isChattingWithNpc &&
            !a.talkingToPlayer &&
            !b.talkingToPlayer &&
            !a.greetingPlayer &&
            !b.greetingPlayer &&
            a.socialReactionRemaining <= 0.0 &&
            b.socialReactionRemaining <= 0.0 &&
            a.chatCooldownSeconds <= 0.0 &&
            b.chatCooldownSeconds <= 0.0;

        if (canStartChat) {
          final exchange = _NpcSocialExchange(
            a: a,
            b: b,
            lines: _buildDialogueLines(a, b, _dialogueSeed++),
            turnDurationSeconds: 2.75,
          );
          _activeExchanges.add(exchange);
          _syncExchangeToVisitors(exchange);
          continue;
        }

        // Gentle lateral personal-space separation for passing strollers.
        if (distSq < separationRadiusSq &&
            distSq > 1e-4 &&
            !a.talkingToPlayer &&
            !b.talkingToPlayer &&
            !(a.isChattingWithNpc && a.chatPartnerId == b.id)) {
          final dist = math.sqrt(distSq);
          final overlap = (1.05 - dist) * 0.5;
          final push = math.min(overlap, 0.42 * dt);
          final nx = dx / dist;
          final nz = dz / dist;
          if (!a.isChattingWithNpc && !a.greetingPlayer) {
            a.x -= nx * push;
            a.z -= nz * push;
          }
          if (!b.isChattingWithNpc && !b.greetingPlayer) {
            b.x += nx * push;
            b.z += nz * push;
          }
        }
      }
    }
  }

  /// Pure-CPU rasterizer for the floating semi-transparent NPC speech/thought
  /// bubble (`💬` spoken / `💭` thought). Testable in headless environments
  /// without an Impeller GPU context.
  @visibleForTesting
  static Future<VrTextBitmap> rasterizeBarkBubble(
    String header,
    String comment, {
    String? actionHint,
    Color accent = const Color(0xFF38BDF8),
    bool isThought = false,
    bool isSpeakingTts = false,
    bool isBusy = false,
  }) async {
    final badge = isSpeakingTts
        ? '🔊'
        : (isBusy || isThought ? '💭' : '💬');
    final fullText = actionHint == null || actionHint.isEmpty
        ? '$badge $header\n«$comment»'
        : '$badge $header\n«$comment»\n$actionHint';
    final bitmap = await VrTextRaster.rasterize(
      fullText,
      color: const Color(0xFFF8FAFC),
      fontWeight: FontWeight.w700,
      fontSize: 48,
      paddingPx: 26,
      maxLines: actionHint == null ? 4 : 5,
      maxWidthPx: 1120,
    );
    const tailHeight = 26;
    final w = bitmap.width;
    final bodyH = bitmap.height;
    final h = bodyH + tailHeight;
    final pixels = Uint8List(w * h * 4);
    final src = bitmap.pixels;

    final effectiveAccent = isSpeakingTts
        ? const Color(0xFF34D399)
        : (isThought ? const Color(0xFFC084FC) : accent);
    final accentArgb = effectiveAccent.toARGB32();
    final acR = (accentArgb >> 16) & 255;
    final acG = (accentArgb >> 8) & 255;
    final acB = accentArgb & 255;

    // Translucent dark cosmic glass background (semi-transparent so the 3D
    // world stays natively visible behind the speech/thought cloud!).
    final bgR = isThought ? 0x18 : 0x09;
    final bgG = isThought ? 0x10 : 0x14;
    final bgB = isThought ? 0x2E : 0x26;
    const bgAlpha = 182; // ~71% opacity — crisp readability + native translucency
    const borderPx = 4.0;
    final radius = math.min(
      isThought ? 48.0 : 30.0,
      math.min(w, bodyH) * 0.34,
    );

    // Draw rounded semi-transparent bubble body + luminous border + text.
    for (var y = 0; y < bodyH; y++) {
      final dyTop = radius - y;
      final dyBot = y - (bodyH - 1 - radius);
      final dy = dyTop > 0 ? dyTop : (dyBot > 0 ? dyBot : 0.0);
      final srcRow = y * w * 4;
      final dstRow = y * w * 4;
      for (var x = 0; x < w; x++) {
        final dxLeft = radius - x;
        final dxRight = x - (w - 1 - radius);
        final dx = dxLeft > 0 ? dxLeft : (dxRight > 0 ? dxRight : 0.0);
        final cornerDist = (dx > 0 && dy > 0)
            ? math.sqrt(dx * dx + dy * dy)
            : 0.0;
        if (cornerDist > radius) continue;

        final edgeDist = (dx > 0 && dy > 0)
            ? (radius - cornerDist)
            : math.min(
                math.min(x.toDouble(), (w - 1 - x).toDouble()),
                math.min(y.toDouble(), (bodyH - 1 - y).toDouble()),
              );
        final isBorder = edgeDist < borderPx;

        final srcIdx = srcRow + x * 4;
        final dstIdx = dstRow + x * 4;
        final textAlpha = src[srcIdx + 3];
        final baseR = isBorder ? acR : bgR;
        final baseG = isBorder ? acG : bgG;
        final baseB = isBorder ? acB : bgB;
        final baseA = isBorder ? 228 : bgAlpha;

        if (textAlpha == 0) {
          pixels[dstIdx] = baseR;
          pixels[dstIdx + 1] = baseG;
          pixels[dstIdx + 2] = baseB;
          pixels[dstIdx + 3] = baseA;
        } else {
          // Composite crisp white/bright glyph cleanly over translucent glass.
          final inv = 255 - textAlpha;
          final outA = textAlpha + ((baseA * inv + 127) ~/ 255);
          pixels[dstIdx] =
              (src[srcIdx] * textAlpha + baseR * inv + 127) ~/ 255;
          pixels[dstIdx + 1] =
              (src[srcIdx + 1] * textAlpha + baseG * inv + 127) ~/ 255;
          pixels[dstIdx + 2] =
              (src[srcIdx + 2] * textAlpha + baseB * inv + 127) ~/ 255;
          pixels[dstIdx + 3] = outA.clamp(0, 255);
        }
      }
    }

    // Draw speech pointer triangle or floating thought dots below the bubble.
    final cx = w * 0.5;
    if (isThought) {
      void drawDot(double dotX, double dotY, double r, int alpha) {
        final rSq = r * r;
        final minX = math.max(0, (dotX - r - 1).floor());
        final maxX = math.min(w - 1, (dotX + r + 1).ceil());
        final minY = math.max(bodyH, (dotY - r - 1).floor());
        final maxY = math.min(h - 1, (dotY + r + 1).ceil());
        for (var y = minY; y <= maxY; y++) {
          final dy = y - dotY;
          for (var x = minX; x <= maxX; x++) {
            final dx = x - dotX;
            final dSq = dx * dx + dy * dy;
            if (dSq <= rSq) {
              final idx = (y * w + x) * 4;
              final rim = dSq > (r - 2.2) * (r - 2.2);
              pixels[idx] = rim ? acR : bgR;
              pixels[idx + 1] = rim ? acG : bgG;
              pixels[idx + 2] = rim ? acB : bgB;
              pixels[idx + 3] = rim ? 220 : alpha;
            }
          }
        }
      }

      drawDot(cx - 8, bodyH + 8, 7.5, 190);
      drawDot(cx + 8, bodyH + 19, 5.0, 170);
    } else {
      for (var dy = 0; dy < tailHeight - 4; dy++) {
        final y = bodyH + dy;
        final halfW = ((tailHeight - 4 - dy) * 0.85).round();
        final leftX = math.max(0, (cx - halfW).round());
        final rightX = math.min(w - 1, (cx + halfW).round());
        for (var x = leftX; x <= rightX; x++) {
          final isRim = (x - leftX) < 3 || (rightX - x) < 3 || dy >= tailHeight - 7;
          final idx = (y * w + x) * 4;
          pixels[idx] = isRim ? acR : bgR;
          pixels[idx + 1] = isRim ? acG : bgG;
          pixels[idx + 2] = isRim ? acB : bgB;
          pixels[idx + 3] = isRim ? 222 : bgAlpha;
        }
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
      ..vertexColorWeight = 1.0;
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
    String? activeTalkingNpcId,
    String? activeTalkingNpcText,
    bool activeNpcSpeakingTts = false,
    bool activeNpcBusy = false,
  }) {
    if (!_gpuMounted ||
        hideBarkBubble ||
        eyePosition == null ||
        viewerForward == null) {
      _activeBarkLabel?.node.visible = false;
      _activeBarkLabel = null;
      return;
    }

    // Priority 1: Directly focused NPC within interactive range (<= 4.35 m).
    final focused = findFocusedVisitor(
      eyePosition,
      viewerForward,
      maxDistance: 4.35,
      minForwardDot: 0.60,
    );

    // Priority 2: Overheard ambient NPC-to-NPC conversation in front of viewer
    // (reuses the exact single _activeBarkLabel slot — 0 extra GPU quads!).
    final ambientSpeaker = focused == null
        ? findNearbyConversingSpeaker(eyePosition, viewerForward)
        : null;

    final target = focused ?? ambientSpeaker;
    if (target == null) {
      _activeBarkLabel?.node.visible = false;
      _activeBarkLabel = null;
      return;
    }

    final isOverheardChat = focused == null && ambientSpeaker != null;
    final isActiveConversant = !isOverheardChat && activeTalkingNpcId == target.id;
    final liveComment = isOverheardChat
        ? (target.activeChatLine ?? target.ambientComment)
        : (isActiveConversant &&
                  activeTalkingNpcText != null &&
                  activeTalkingNpcText.trim().isNotEmpty
              ? activeTalkingNpcText.trim()
              : target.ambientComment);
    final speakingTts = isActiveConversant && activeNpcSpeakingTts;
    final busy = isActiveConversant && activeNpcBusy;
    // Ambient NPC-to-NPC dialogue uses a spoken glass bubble (`💬`); idle solo
    // focused visitors show a thought cloud (`💭`) until engaged.
    final isThought =
        !isOverheardChat && !isActiveConversant && !target.talkingToPlayer;
    final header = isOverheardChat && target.chatPartnerName != null
        ? '${target.displayName} → ${target.chatPartnerName}'
        : '${target.displayName} · ${target.role}';
    final key =
        '${target.id}|$header|$liveComment|$canTalkToVisitors|$isOverheardChat|$isThought|$speakingTts|$busy';

    final cached = _barkCache[key];
    if (cached != null) {
      if (!identical(_activeBarkLabel, cached)) {
        _activeBarkLabel?.node.visible = false;
        _activeBarkLabel = cached;
      }
      final labelY = groundYAt(target.x, target.z) + target.appearance.heightMeters + 0.44;
      cached.node.localTransform = vm.Matrix4.translationValues(
        target.x,
        labelY,
        target.z,
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
    final comment = liveComment.length > 168
        ? '${liveComment.substring(0, 167)}…'
        : liveComment;
    final String? hint;
    if (isOverheardChat) {
      hint = canTalkToVisitors ? 'Acércate para unirte · X voz · Y charlar' : null;
    } else if (!canTalkToVisitors) {
      hint = null;
    } else if (busy) {
      hint = 'Pensando respuesta…';
    } else if (speakingTts) {
      hint = 'X · 🔇 Callar voz   ·   Y · 💬 Otra idea   ·   L · WordSphere';
    } else {
      hint = 'X · 🔊 Escuchar   ·   Y · 💬 Charlar   ·   L · WordSphere';
    }
    rasterizeBarkBubble(
      header,
      comment,
      actionHint: hint,
      accent: isOverheardChat ? const Color(0xFF34D399) : theme.accent,
      isThought: isThought,
      isSpeakingTts: speakingTts,
      isBusy: busy,
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
        center: vm.Vector3(
          target.x,
          groundYAt(target.x, target.z) + target.appearance.heightMeters + 0.44,
          target.z,
        ),
        height: math.min(0.40, 1.68 / bitmap.aspect),
        name: 'npc_bark_${target.id}',
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
    String? activeTalkingNpcId,
    String? activeTalkingNpcText,
    bool activeNpcSpeakingTts = false,
    bool activeNpcBusy = false,
  }) {
    if (_disposed || !time.isFinite) return;
    final dt = _lastTime < 0 ? (1 / 60) : (time - _lastTime).clamp(0.0, 0.1);
    _lastTime = time;

    // Decouple AI pathing & social encounters to 12 Hz (matching multiplayer
    // 10–15 Hz peer ticks) when GPU is mounted; VrPeerAvatarStage dead-reckons
    // position, yaw, and pose damping smoothly at 60–120 Hz!
    _aiAccum += dt;
    final runAiStep = !_gpuMounted || _aiAccum >= (1.0 / 12.0);
    if (runAiStep) {
      final aiDt = _gpuMounted ? _aiAccum.clamp(0.0, 0.25) : dt;
      _aiAccum = 0.0;
      _stepSocialEncounters(aiDt);
      for (var i = 0; i < visitors.length; i++) {
        final v = visitors[i];
        final wasGreeting = v.greetingPlayer;
        v.step(time, aiDt, eyePosition);
        final groundY = groundYAt(v.x, v.z);
        if (!wasGreeting &&
            v.greetingPlayer &&
            onVisitorGreeted != null &&
            time - _lastGreetingAudioTime >= 4.0) {
          _lastGreetingAudioTime = time;
          onVisitorGreeted(vm.Vector3(v.x, groundY + 1.5, v.z));
        }
        peerStage.updatePeerMotion(
          v.id,
          x: v.x,
          y: groundY,
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
      activeTalkingNpcId: activeTalkingNpcId,
      activeTalkingNpcText: activeTalkingNpcText,
      activeNpcSpeakingTts: activeNpcSpeakingTts,
      activeNpcBusy: activeNpcBusy,
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
    _activeExchanges.clear();
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
