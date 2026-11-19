import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/vrlizate_home_spatial.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plaza contact detail follows quality recovery and downscaling', () {
    final settings = EnvironmentSettings();
    const look = VirtualHomeWorldBuilder.naturalLook;

    // Exercise the same settings object used when the viewer adapts quality;
    // a downgrade must remove expensive passes rather than leave them active.
    for (final preset in [
      VrQualityPreset.medium,
      VrQualityPreset.high,
      VrQualityPreset.ultra,
      VrQualityPreset.low,
      VrQualityPreset.medium,
    ]) {
      look.applyTo(settings, preset);
      final detailed = preset.tier.index >= VrQualityTier.high.index;
      expect(settings.ambientOcclusionEnabled, detailed);
      expect(settings.bloomEnabled, preset == VrQualityPreset.ultra);
      expect(settings.exposure, 1);
      expect(settings.colorGradingEnabled, isFalse);
      expect(settings.fogEnabled, isFalse);
      if (detailed) {
        expect(settings.ambientOcclusionHalfResolution, isTrue);
        expect(settings.ambientOcclusionIntensity, lessThan(1));
      }
    }

    // Other experiences retain their existing standard look.
    VrLook.standard.applyTo(settings, VrQualityPreset.high);
    expect(settings.ambientOcclusionEnabled, isFalse);
  });

  test('Snap Turn 30° and 45° apply exact discrete yaw with anti-bounce hysteresis', () {
    final controller = VirtualHomeLocomotionController();
    final rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.6, 0));

    // Deflect right past threshold -> snaps exactly -30° once and latches.
    final snapped1 = controller.applyStickLook(
      rig,
      0.85,
      0.0,
      1 / 60,
      turnMode: VrTurnMode.snap30,
    );
    expect(snapped1, isTrue);
    expect(rig.yaw, closeTo(-30 * math.pi / 180, 1e-5));

    // Holding stick deflected does NOT spin repeatedly.
    final held = controller.applyStickLook(
      rig,
      0.90,
      0.0,
      1 / 60,
      turnMode: VrTurnMode.snap30,
    );
    expect(held, isFalse);
    expect(rig.yaw, closeTo(-30 * math.pi / 180, 1e-5));

    // Centering below 0.25 re-arms, then deflecting left snaps +45°.
    controller.applyStickLook(
      rig,
      0.10,
      0.0,
      1 / 60,
      turnMode: VrTurnMode.snap45,
    );
    final snapped2 = controller.applyStickLook(
      rig,
      -0.80,
      0.0,
      1 / 60,
      turnMode: VrTurnMode.snap45,
    );
    expect(snapped2, isTrue);
    expect(rig.yaw, closeTo(15 * math.pi / 180, 1e-5));
  });
}
