import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'home_lobby_layout.dart';
import 'home_surface_texture_data.dart';

/// Shared 256px procedural PBR finishes, independent of app assets and services.
/// Low/medium uploads color only (`2x` anisotropy); detail maps (normal +
/// Toksvig-filtered glTF ORM occlusion / roughness / metallic) are lazy and
/// uploaded as hardware block-compressed `KTX2` (`ASTC 4x4` / `ETC2` / `BC`)
/// once on high/ultra visits.
abstract final class HomeSurfaceTextures {
  static final _pixels = <HomeSurface, Future<HomeSurfaceTextureData>>{};
  static final _colors =
      <(HomeSurface, int), Future<TextureSource>>{};
  static final _details =
      <HomeSurface, Future<(TextureSource, TextureSource)>>{};

  static HomeSurface surfaceFor(HomeLobbyFinish finish) => switch (finish) {
    HomeLobbyFinish.stone => HomeSurface.limestone,
    HomeLobbyFinish.oak => HomeSurface.oak,
    HomeLobbyFinish.trim => HomeSurface.brushedMetal,
    HomeLobbyFinish.fabric || HomeLobbyFinish.rug => HomeSurface.wovenFabric,
    HomeLobbyFinish.plaster => HomeSurface.plaster,
  };

  /// Selects anisotropy based on lobby finish role and detail tier (`2x` on
  /// low/medium unlit/baked visits; `8x` on oblique floors/rugs and `4x` on
  /// vertical walls/trims in high/ultra PBR visits).
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

  static Future<HomeSurfaceTextureData> _data(HomeSurface surface) =>
      _pixels[surface] ??= compute(
        HomeSurfaceTextureData.generate,
        surface,
        debugLabel: 'home:${surface.name}',
      );

  static Future<TextureSource> _color(
    HomeSurface surface,
    TextureSampling sampling,
  ) => _colors[(surface, sampling.maxAnisotropy)] ??= () async {
    try {
      final data = await _data(surface);
      final ktx2 = await compute(
        _encodeColorKtx2,
        data,
        debugLabel: 'home-color-ktx2:${surface.name}',
      );
      try {
        return await VrKtx2TextureLoader.load(
          ktx2,
          content: TextureContent.color,
          sampling: sampling,
        );
      } on Object {
        return Texture2D.fromPixels(
          data.color,
          data.size,
          data.size,
          content: TextureContent.color,
          sampling: sampling,
        );
      }
    } catch (_) {
      _colors.remove((surface, sampling.maxAnisotropy));
      _pixels.remove(surface);
      rethrow;
    }
  }();

  static Future<(TextureSource, TextureSource)> _detail(
    HomeSurface surface,
    TextureSampling sampling,
  ) => _details[surface] ??= () async {
    try {
      final data = await _data(surface);
      const ormSampling = TextureSampling(maxAnisotropy: 4);
      final encoded = await compute(
        _encodeDetailKtx2,
        data,
        debugLabel: 'home-detail-ktx2:${surface.name}',
      );
      try {
        final sources = await VrKtx2TextureLoader.loadBatch(
          <VrKtx2LoadRequest>[
            VrKtx2LoadRequest(
              bytes: encoded.$1,
              content: TextureContent.normal,
              sampling: sampling,
            ),
            VrKtx2LoadRequest(
              bytes: encoded.$2,
              content: TextureContent.data,
              sampling: ormSampling,
            ),
          ],
        );
        return (sources[0], sources[1]);
      } on Object {
        return (
          Texture2D.fromPixels(
            data.normal,
            data.size,
            data.size,
            content: TextureContent.normal,
            sampling: sampling,
          ),
          Texture2D.fromPixels(
            data.roughness,
            data.size,
            data.size,
            content: TextureContent.data,
            sampling: ormSampling,
          ),
        );
      }
    } catch (_) {
      _details.remove(surface);
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

Uint8List _encodeColorKtx2(HomeSurfaceTextureData data) {
  final mips = VrToksvigFilter.downsampleColorMipChain(
    data.color,
    data.size,
    data.size,
  );
  return VrKtx2Codec.encodeMipChainToKtx2(mips, srgb: true);
}

(Uint8List, Uint8List) _encodeDetailKtx2(HomeSurfaceTextureData data) {
  final coupled = VrToksvigFilter.generateCoupledPbrMipChain(
    albedoRgba: Uint8List(4)..fillRange(0, 4, 255),
    normalRgba: data.normal,
    ormRgba: data.roughness,
    width: data.size,
    height: data.size,
  );
  return (
    VrKtx2Codec.encodeMipChainToKtx2(coupled.normal, srgb: false),
    VrKtx2Codec.encodeMipChainToKtx2(coupled.orm, srgb: false),
  );
}
