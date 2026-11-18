import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_home/vrlizate_home_spatial.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomePlazaCrowd (living plazas & famous malls)', () {
    test('populates Home distributed plaza with strolling & social visitors', () {
      final layout = HomeEcosystemLayout(
        VrHomeEcosystemRoom.defaults,
        topology: HomePlazaTopology.distributedCruciform,
      );
      final crowd = HomePlazaCrowd.plan(layout: layout);
      expect(crowd.visitors.length, greaterThanOrEqualTo(10));

      final strollers = crowd.visitors.where((v) => !v.conversationalist).toList();
      final social = crowd.visitors.where((v) => v.conversationalist).toList();
      expect(strollers, isNotEmpty);
      expect(social.length, 4);

      final startX = strollers.first.x;
      final startZ = strollers.first.z;
      for (var step = 1; step <= 60; step++) {
        crowd.tick(step / 30.0);
      }
      final movedDist = (strollers.first.x - startX).abs() +
          (strollers.first.z - startZ).abs();
      expect(movedDist, greaterThan(0.4));
    });

    test('visitors pause to wave when the player walks within 3.4 m', () {
      final layout = HomeFamousMallLayout.build(
        archetype: FamousMallArchetype.galleriaMilano,
        mallTitle: 'Galleria Milano',
        booths: VrHomeEcosystemRoom.defaults,
      );
      final crowd = HomePlazaCrowd.plan(layout: layout);
      final target = crowd.visitors.first;
      final nearPlayer = vm.Vector3(target.x + 1.2, 1.6, target.z + 1.2);

      crowd.tick(1.0, eyePosition: nearPlayer);
      crowd.tick(1.05, eyePosition: nearPlayer);
      expect(target.greetingPlayer, isTrue);
      expect(target.pose.rightArmAbduction + target.pose.leftArmAbduction, greaterThan(0.5));

      final farPlayer = vm.Vector3(target.x + 20.0, 1.6, target.z + 20.0);
      crowd.tick(1.10, eyePosition: farPlayer);
      expect(target.greetingPlayer, isFalse);

      // Remote multiplayer user avatars share the exact same VrPeerAvatarStage!
      final baseCount = crowd.peerStage.peerCount;
      expect(
        crowd.peerStage.upsertPeer(
          VrPeerAvatarSnapshot(
            peerId: 'remote_user_42',
            appearance: VrAvatarAppearance(species: VrAvatarSpecies.fox),
            x: 1.5,
            z: 2.0,
            yaw: 0.4,
            vx: 1.1,
            sequence: 1,
          ),
        ),
        isTrue,
      );
      expect(crowd.peerStage.peerCount, baseCount + 1);
      crowd.tick(1.15, eyePosition: vm.Vector3(0, 1.6, 6), viewerForward: vm.Vector3(0, 0, -1));
      expect(crowd.peerStage.interpolatedPosition('remote_user_42')!.x, greaterThan(1.5));
      expect(crowd.peerStage.removePeer('remote_user_42'), isTrue);
      crowd.dispose();
    });

    test('assigns personas/comments, finds focused NPC, locks talking pose & rasterizes bark bubble', () async {
      final layout = HomeEcosystemLayout(
        VrHomeEcosystemRoom.defaults,
        topology: HomePlazaTopology.distributedCruciform,
      );
      final crowd = HomePlazaCrowd.plan(
        layout: layout,
        plazaBannerText: 'PLAZA CENTRAL VRLIZATE',
      );
      final npc = crowd.visitors.first;
      expect(npc.displayName, isNotEmpty);
      expect(npc.role, isNotEmpty);
      expect(npc.ambientComment, isNotEmpty);

      // Stand 2.4 m away looking directly at npc
      final eye = vm.Vector3(npc.x, 1.6, npc.z + 2.4);
      final forward = vm.Vector3(0, 0, -1);
      final focused = crowd.findFocusedVisitor(eye, forward);
      expect(focused?.id, npc.id);

      // Looking opposite direction does not select npc behind player
      expect(crowd.findFocusedVisitor(eye, vm.Vector3(0, 0, 1)), isNull);

      // Lock NPC in active conversation even at 3.9 m (outside passive wave radius)
      final talkEye = vm.Vector3(npc.x, 1.6, npc.z + 3.9);
      crowd.setVisitorTalking(npc.id);
      crowd.tick(2.0, eyePosition: talkEye, viewerForward: forward);
      expect(npc.talkingToPlayer, isTrue);
      expect(npc.vx, 0.0);
      expect(npc.vz, 0.0);

      // Update ambient comment from Itzli
      crowd.setVisitorComment(npc.id, '¡Te recomiendo explorar el Cine Gratis 24/7!');
      expect(npc.ambientComment, '¡Te recomiendo explorar el Cine Gratis 24/7!');

      crowd.setVisitorTalking(null);
      expect(npc.talkingToPlayer, isFalse);

      final bitmap = await HomePlazaCrowd.rasterizeBarkBubble(
        '${npc.displayName} · ${npc.role}',
        npc.ambientComment,
        actionHint: '[ A · Hablar (IA Local) ]',
      );
      expect(bitmap.width, greaterThan(80));
      expect(bitmap.height, greaterThan(40));
      expect(bitmap.pixels.length, bitmap.width * bitmap.height * 4);
      crowd.dispose();
    });

    test('createVrHomeNpcDialoguePanel exposes embedded SAIA text + explicit TTS toggle', () async {
      final actionsTriggered = <String>[];
      var closed = 0;
      final npc = VrHomeNpcDescriptor(
        id: 'plaza_stroller_0',
        displayName: 'Valeria',
        role: 'Exploradora VR',
        speciesName: 'human',
        ambientComment: '¡Hola! Bienvenido a la plaza.',
        position: vm.Vector3(0, 0, -2.5),
        nearestRoomTitle: 'Cine VR',
      );
      final pose = VrWorldPose.facingEye(
        center: vm.Vector3(0, 1.55, -1.8),
        eye: vm.Vector3(0, 1.6, 0),
      );

      final idlePanel = await createVrHomeNpcDialoguePanel(
        npc: npc,
        pose: pose,
        text: 'SAIA recomienda visitar la sala de Cine Gratis 24/7.',
        busy: false,
        listening: false,
        speakingTts: false,
        subtitleOverride: '3D · IA EN ESTACIÓN FARO · TTS OPCIONAL',
        onAction: actionsTriggered.add,
        onClose: () => closed++,
        meshBuilder: () => Mesh.primitives(primitives: const []),
        textNodeBuilder: (spec) async => Node(name: spec.nodeName),
      );

      expect(
        idlePanel.actions.map((a) => a.id).toList(),
        equals([
          'npc:recommend',
          'npc:about_place',
          'npc:surprise',
          'npc:listen',
          'npc:tts',
          'close',
        ]),
      );
      final ttsIdle = idlePanel.actions.firstWhere((a) => a.id == 'npc:tts');
      expect(ttsIdle.label, 'Leer en voz (TTS)');
      expect(ttsIdle.enabled, isTrue);
      ttsIdle.onPressed();
      expect(actionsTriggered, ['tts']);

      final speakingPanel = await createVrHomeNpcDialoguePanel(
        npc: npc,
        pose: pose,
        text: 'Itzli recomienda visitar la sala de Cine Gratis 24/7.',
        busy: false,
        listening: false,
        speakingTts: true,
        onAction: actionsTriggered.add,
        onClose: () => closed++,
        meshBuilder: () => Mesh.primitives(primitives: const []),
        textNodeBuilder: (spec) async => Node(name: spec.nodeName),
      );
      final ttsSpeaking = speakingPanel.actions.firstWhere((a) => a.id == 'npc:tts');
      expect(ttsSpeaking.label, 'Callar voz (TTS)');
      expect(ttsSpeaking.enabled, isTrue);

      speakingPanel.actions.last.onPressed();
      expect(closed, 1);

      final writePanel = await createVrHomeNpcDialoguePanel(
        npc: npc,
        pose: pose,
        text: 'Pregunta lo que quieras con WordSphere.',
        busy: false,
        listening: false,
        speakingTts: false,
        enableWriteAction: true,
        onAction: actionsTriggered.add,
        onClose: () => closed++,
        meshBuilder: () => Mesh.primitives(primitives: const []),
        textNodeBuilder: (spec) async => Node(name: spec.nodeName),
      );
      final writeAction = writePanel.actions.firstWhere((a) => a.id == 'npc:write');
      expect(writeAction.label, 'Escribir (WordSphere)');
      writeAction.onPressed();
      expect(actionsTriggered, contains('write'));
    });

    test('reactToEvent turns nearby visitors with social reaction & 18 ambient particles', () {
      expect(HomePlazaCrowd.ambientParticleCount, 18);
      final layout = HomeEcosystemLayout(
        VrHomeEcosystemRoom.defaults,
        topology: HomePlazaTopology.distributedCruciform,
      );
      final crowd = HomePlazaCrowd.plan(layout: layout);
      final first = crowd.visitors.first;
      final reacted = crowd.reactToEvent(
        vm.Vector3(first.x + 2.0, 1.5, first.z + 2.0),
        reactionComment: '¡Qué gran sala acabas de abrir!',
        radiusMeters: 6.0,
      );
      expect(reacted, greaterThanOrEqualTo(1));
      expect(first.socialReactionRemaining, greaterThan(0.0));
      crowd.tick(0.2, eyePosition: vm.Vector3(100, 1.6, 100));
      expect(first.pose.leftArmFlexion + first.pose.rightArmFlexion, greaterThan(0.1));
      crowd.dispose();
    });
  });
}
