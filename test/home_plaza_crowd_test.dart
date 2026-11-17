import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_home/vrlizate_home_spatial.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
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
  });
}
