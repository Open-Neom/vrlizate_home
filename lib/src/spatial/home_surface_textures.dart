import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'home_lobby_layout.dart';
import 'home_surface_texture_data.dart';

/// Shared procedural PBR finishes (`256px` on low/medium, `512px` on
/// high/ultra), independent of app assets and services.
///
/// Low tier uploads color only (`2x` anisotropy); medium/high/ultra uploads
/// color + normal + Toksvig-filtered glTF ORM (`occlusion / roughness /
/// metallic`) in a **single batched KTX2 upload** transcoded off the UI thread
/// directly to hardware `ASTC 4×4` / `ETC2` / `BC` block compression (4× less
/// VRAM than RGBA8) with optional persistent flash caching.
abstract final class HomeSurfaceTextures {
  static final _bundles =
      <(HomeSurface, int), Future<_HomeEncodedSurfaceBundle>>{};
  static final _colorOnly =
      <(HomeSurface, int, int), Future<TextureSource>>{};
  static final _fullPbr =
      <(HomeSurface, int, int), Future<(TextureSource, TextureSource, TextureSource)>>{};

  static HomeSurface surfaceFor(HomeLobbyFinish finish) => switch (finish) {
    HomeLobbyFinish.stone => HomeSurface.limestone,
    HomeLobbyFinish.oak => HomeSurface.oak,
    HomeLobbyFinish.trim => HomeSurface.brushedMetal,
    HomeLobbyFinish.fabric || HomeLobbyFinish.rug => HomeSurface.wovenFabric,
    HomeLobbyFinish.plaster => HomeSurface.plaster,
  };

  /// Selects procedural PBR resolution for [tier]:
  /// - `low` / `medium`: `256×256` (`~85 KB` ASTC 4×4 VRAM per map)
  /// - `high` / `ultra`: `512×512` (`~341 KB` ASTC 4×4 VRAM per map — 4×
  ///   crisper architectural grain & joints while using less VRAM than a
  ///   single uncompressed `256×256` RGBA8 texture).
  static int resolutionForTier(VrQualityTier tier) =>
      (tier == VrQualityTier.high || tier == VrQualityTier.ultra) ? 512 : 256;

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

  static Future<_HomeEncodedSurfaceBundle> _bundle(
    HomeSurface surface,
    int resolution,
  ) => _bundles[(surface, resolution)] ??= () async {
    final cachePrefix = 'home_v2|${surface.name}|$resolution';
    final cachedColor = await PbrTextureLibrary.readCookedKtx2(
      '$cachePrefix|color',
    );
    final cachedNormal = await PbrTextureLibrary.readCookedKtx2(
      '$cachePrefix|normal',
    );
    final cachedOrm = await PbrTextureLibrary.readCookedKtx2(
      '$cachePrefix|orm',
    );
    if (cachedColor != null && cachedNormal != null && cachedOrm != null) {
      return _HomeEncodedSurfaceBundle(
        resolution: resolution,
        data: null,
        colorKtx2: cachedColor,
        normalKtx2: cachedNormal,
        ormKtx2: cachedOrm,
      );
    }

    final bundle = await compute(
      _generateAndEncodeSurfaceBundle,
      (surface: surface, resolution: resolution),
      debugLabel: 'home-ktx2-bundle:${surface.name}@$resolution',
    );
    PbrTextureLibrary.writeCookedKtx2('$cachePrefix|color', bundle.colorKtx2);
    PbrTextureLibrary.writeCookedKtx2('$cachePrefix|normal', bundle.normalKtx2);
    PbrTextureLibrary.writeCookedKtx2('$cachePrefix|orm', bundle.ormKtx2);
    return bundle;
  }();

  static Future<TextureSource> _loadColorOnly(
    HomeSurface surface,
    int resolution,
    TextureSampling sampling,
  ) => _colorOnly[(surface, resolution, sampling.maxAnisotropy)] ??= () async {
    try {
      final bundle = await _bundle(surface, resolution);
      try {
        return await VrKtx2TextureLoader.load(
          bundle.colorKtx2,
          content: TextureContent.color,
          sampling: sampling,
        );
      } on Object catch (error) {
        VrKtx2TextureLoader.recordFallback(
          error,
          uncompressedBytes: resolution * resolution * 4,
        );
        final fallback =
            bundle.data ??
            HomeSurfaceTextureData.generate(surface, resolution: resolution);
        return Texture2D.fromPixels(
          fallback.color,
          fallback.size,
          fallback.size,
          content: TextureContent.color,
          sampling: sampling,
        );
      }
    } catch (_) {
      _colorOnly.remove((surface, resolution, sampling.maxAnisotropy));
      _bundles.remove((surface, resolution));
      rethrow;
    }
  }();

  static Future<(TextureSource, TextureSource, TextureSource)> _loadFullPbr(
    HomeSurface surface,
    int resolution,
    TextureSampling sampling,
  ) => _fullPbr[(surface, resolution, sampling.maxAnisotropy)] ??= () async {
    try {
      final bundle = await _bundle(surface, resolution);
      const ormSampling = TextureSampling(maxAnisotropy: 4);
      try {
        // Upload Color + Normal + Toksvig ORM in ONE batched glTF/ASTC hop.
        final sources = await VrKtx2TextureLoader.loadBatch(<VrKtx2LoadRequest>[
          VrKtx2LoadRequest(
            bytes: bundle.colorKtx2,
            content: TextureContent.color,
            sampling: sampling,
          ),
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
        ]);
        VrKtx2TextureLoader.recordToksvigMaterial();
        return (sources[0], sources[1], sources[2]);
      } on Object catch (error) {
        VrKtx2TextureLoader.recordFallback(
          error,
          uncompressedBytes: resolution * resolution * 4 * 3,
        );
        final fallback =
            bundle.data ??
            HomeSurfaceTextureData.generate(surface, resolution: resolution);
        return (
          Texture2D.fromPixels(
            fallback.color,
            fallback.size,
            fallback.size,
            content: TextureContent.color,
            sampling: sampling,
          ),
          Texture2D.fromPixels(
            fallback.normal,
            fallback.size,
            fallback.size,
            content: TextureContent.normal,
            sampling: sampling,
          ),
          Texture2D.fromPixels(
            fallback.roughness,
            fallback.size,
            fallback.size,
            content: TextureContent.data,
            sampling: ormSampling,
          ),
        );
      }
    } catch (_) {
      _fullPbr.remove((surface, resolution, sampling.maxAnisotropy));
      _bundles.remove((surface, resolution));
      rethrow;
    }
  }();

  static Future<void> apply({
    required HomeLobbyFinish finish,
    required PhysicallyBasedMaterial pbr,
    required UnlitMaterial baked,
    required bool details,
    required bool Function() isCurrent,
    VrQualityTier? qualityTier,
  }) async {
    if (!isCurrent()) return;
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return;
    final surface = surfaceFor(finish);
    final tier = qualityTier ?? PbrTextureLibrary.defaultQualityTier;
    final resolution = resolutionForTier(tier);
    final sampling = samplingFor(finish, details: details);

    if (!details) {
      final color = await _loadColorOnly(surface, resolution, sampling);
      if (!isCurrent()) return;
      pbr.baseColorTexture = color;
      baked.baseColorTexture = color;
      return;
    }

    final (color, normal, orm) = await _loadFullPbr(
      surface,
      resolution,
      sampling,
    );
    if (!isCurrent()) return;
    pbr
      ..baseColorTexture = color
      ..normalTexture = normal
      ..normalScale = .72
      ..metallicRoughnessTexture = orm
      ..occlusionTexture = orm
      ..occlusionStrength = .72
      ..roughnessFactor = 1
      ..metallicFactor = finish == HomeLobbyFinish.trim ? 1 : 0;
    baked.baseColorTexture = color;
  }
}

final class _HomeEncodedSurfaceBundle {
  const _HomeEncodedSurfaceBundle({
    required this.resolution,
    required this.data,
    required this.colorKtx2,
    required this.normalKtx2,
    required this.ormKtx2,
  });

  final int resolution;
  final HomeSurfaceTextureData? data;
  final Uint8List colorKtx2;
  final Uint8List normalKtx2;
  final Uint8List ormKtx2;
}

_HomeEncodedSurfaceBundle _generateAndEncodeSurfaceBundle(
  ({HomeSurface surface, int resolution}) args,
) {
  final data = HomeSurfaceTextureData.generate(
    args.surface,
    resolution: args.resolution,
  );
  final coupled = VrToksvigFilter.generateCoupledPbrMipChain(
    albedoRgba: data.color,
    normalRgba: data.normal,
    ormRgba: data.roughness,
    width: data.size,
    height: data.size,
  );
  return _HomeEncodedSurfaceBundle(
    resolution: data.size,
    data: data,
    colorKtx2: VrKtx2Codec.encodeMipChainToKtx2(
      coupled.albedo,
      srgb: true,
      supercompress: true,
    ),
    normalKtx2: VrKtx2Codec.encodeMipChainToKtx2(
      coupled.normal,
      srgb: false,
      supercompress: true,
    ),
    ormKtx2: VrKtx2Codec.encodeMipChainToKtx2(
      coupled.orm,
      srgb: false,
      supercompress: true,
    ),
  );
}
