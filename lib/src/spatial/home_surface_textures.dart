import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'home_lobby_layout.dart';
import 'home_surface_texture_data.dart';

/// Shared 256px procedural PBR finishes, independent of app assets and services.
/// Low tier uploads color only (`2x` anisotropy); medium/high/ultra uploads
/// detail maps (normal + Toksvig-filtered glTF ORM occlusion / roughness /
/// metallic) encoded in a single background isolate pass as hardware
/// block-compressed `KTX2` (`ASTC 4x4` / `ETC2` / `BC`).
abstract final class HomeSurfaceTextures {
  static final _bundles = <HomeSurface, Future<_HomeEncodedSurfaceBundle>>{};
  static final _colors =
      <(HomeSurface, int), Future<TextureSource>>{};
  static final _details =
      <(HomeSurface, int), Future<(TextureSource, TextureSource)>>{};

  static HomeSurface surfaceFor(HomeLobbyFinish finish) => switch (finish) {
    HomeLobbyFinish.stone => HomeSurface.limestone,
    HomeLobbyFinish.oak => HomeSurface.oak,
    HomeLobbyFinish.trim => HomeSurface.brushedMetal,
    HomeLobbyFinish.fabric || HomeLobbyFinish.rug => HomeSurface.wovenFabric,
    HomeLobbyFinish.plaster => HomeSurface.plaster,
  };

  /// Selects anisotropy based on lobby finish role and detail tier (`2x` on
  /// low unlit/baked visits; `8x` on oblique floors/rugs and `4x` on vertical
  /// walls/trims in medium/high/ultra PBR visits).
  static TextureSampling samplingFor(
    HomeLobbyFinish finish, {
    required bool details,
  }) {
    if (!details) return const TextureSampling(maxAnisotropy: 2);
    final isFloorLike =
        finish == HomeLobbyFinish.stone ||
        finish == HomeLobbyFinish.oak ||
        finish == HomeLobbyFinish.rug;
    return TextureSampling(maxAnisotropy: isFloorLike ? 8 : 4);
  }

  static Future<_HomeEncodedSurfaceBundle> _bundle(HomeSurface surface) =>
      _bundles[surface] ??= compute(
        _generateAndEncodeSurfaceBundle,
        surface,
        debugLabel: 'home-ktx2-bundle:${surface.name}',
      );

  static Future<TextureSource> _color(
    HomeSurface surface,
    TextureSampling sampling,
  ) => _colors[(surface, sampling.maxAnisotropy)] ??= () async {
    try {
      final bundle = await _bundle(surface);
      try {
        return await VrKtx2TextureLoader.load(
          bundle.colorKtx2,
          content: TextureContent.color,
          sampling: sampling,
        );
      } on Object {
        return Texture2D.fromPixels(
          bundle.data.color,
          bundle.data.size,
          bundle.data.size,
          content: TextureContent.color,
          sampling: sampling,
        );
      }
    } catch (_) {
      _colors.remove((surface, sampling.maxAnisotropy));
      _bundles.remove(surface);
      rethrow;
    }
  }();

  static Future<(TextureSource, TextureSource)> _detail(
    HomeSurface surface,
    TextureSampling sampling,
  ) => _details[(surface, sampling.maxAnisotropy)] ??= () async {
    try {
      final bundle = await _bundle(surface);
      const ormSampling = TextureSampling(maxAnisotropy: 4);
      try {
        final sources = await VrKtx2TextureLoader.loadBatch(
          <VrKtx2LoadRequest>[
            VrKtx2LoadRequest(
              bytes: bundle.normalKtx2,
              content: TextureContent.normal,
              sampling: sampling,
            ),
            VrKtx2LoadRequest(
              bytes: bundle.ormKtx2,
              content: TextureContent.data,
              sampling: ormSampling,
            ),
          ],
        );
        return (sources[0], sources[1]);
      } on Object {
        return (
          Texture2D.fromPixels(
            bundle.data.normal,
            bundle.data.size,
            bundle.data.size,
            content: TextureContent.normal,
            sampling: sampling,
          ),
          Texture2D.fromPixels(
            bundle.data.roughness,
            bundle.data.size,
            bundle.data.size,
            content: TextureContent.data,
            sampling: ormSampling,
          ),
        );
      }
    } catch (_) {
      _details.remove((surface, sampling.maxAnisotropy));
      _bundles.remove(surface);
      rethrow;
    }
  }();

  static Future<void> apply({
    required HomeLobbyFinish finish,
    required PhysicallyBasedMaterial pbr,
    required UnlitMaterial baked,
    required bool details,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return;
    final surface = surfaceFor(finish);
    final sampling = samplingFor(finish, details: details);
    final color = await _color(surface, sampling);
    if (!isCurrent()) return;
    pbr.baseColorTexture = color;
    baked.baseColorTexture = color;
    if (!details) return;
    final (normal, orm) = await _detail(surface, sampling);
    if (!isCurrent()) return;
    pbr
      ..normalTexture = normal
      ..normalScale = .72
      ..metallicRoughnessTexture = orm
      ..occlusionTexture = orm
      ..occlusionStrength = .72
      ..roughnessFactor = 1
      ..metallicFactor = finish == HomeLobbyFinish.trim ? 1 : 0;
  }
}

final class _HomeEncodedSurfaceBundle {
  const _HomeEncodedSurfaceBundle({
    required this.data,
    required this.colorKtx2,
    required this.normalKtx2,
    required this.ormKtx2,
  });

  final HomeSurfaceTextureData data;
  final Uint8List colorKtx2;
  final Uint8List normalKtx2;
  final Uint8List ormKtx2;
}

_HomeEncodedSurfaceBundle _generateAndEncodeSurfaceBundle(HomeSurface surface) {
  final data = HomeSurfaceTextureData.generate(surface);
  final coupled = VrToksvigFilter.generateCoupledPbrMipChain(
    albedoRgba: data.color,
    normalRgba: data.normal,
    ormRgba: data.roughness,
    width: data.size,
    height: data.size,
  );
  return _HomeEncodedSurfaceBundle(
    data: data,
    colorKtx2: VrKtx2Codec.encodeMipChainToKtx2(coupled.albedo, srgb: true),
    normalKtx2: VrKtx2Codec.encodeMipChainToKtx2(coupled.normal, srgb: false),
    ormKtx2: VrKtx2Codec.encodeMipChainToKtx2(coupled.orm, srgb: false),
  );
}
