import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/src/spatial/virtual_home_world_builder.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

void main() {
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
}
