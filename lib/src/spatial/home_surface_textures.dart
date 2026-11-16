import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

import 'home_lobby_layout.dart';
import 'home_surface_texture_data.dart';

/// Shared 256px procedural PBR finishes, independent of app assets and services.
/// Low/medium uploads color only; detail maps (normal + glTF ORM occlusion /
/// roughness / metallic) are lazy and uploaded once on high/ultra visits.
abstract final class HomeSurfaceTextures {
  static final _pixels = <HomeSurface, Future<HomeSurfaceTextureData>>{};
  static final _colors = <HomeSurface, Future<Texture2D>>{};
  static final _details = <HomeSurface, Future<(Texture2D, Texture2D)>>{};
  static const _sampling = TextureSampling(maxAnisotropy: 8);

  static HomeSurface surfaceFor(HomeLobbyFinish finish) => switch (finish) {
    HomeLobbyFinish.stone => HomeSurface.limestone,
    HomeLobbyFinish.oak => HomeSurface.oak,
    HomeLobbyFinish.trim => HomeSurface.brushedMetal,
    HomeLobbyFinish.fabric || HomeLobbyFinish.rug => HomeSurface.wovenFabric,
    HomeLobbyFinish.plaster => HomeSurface.plaster,
  };

  static Future<HomeSurfaceTextureData> _data(HomeSurface surface) =>
      _pixels[surface] ??= compute(
        HomeSurfaceTextureData.generate,
        surface,
        debugLabel: 'home:${surface.name}',
      );

  static Future<Texture2D> _color(HomeSurface surface) =>
      _colors[surface] ??= () async {
        try {
          final data = await _data(surface);
          return Texture2D.fromPixels(
            data.color,
            data.size,
            data.size,
            content: TextureContent.color,
            sampling: _sampling,
          );
        } catch (_) {
          _colors.remove(surface);
          _pixels.remove(surface);
          rethrow;
        }
      }();

  static Future<(Texture2D, Texture2D)> _detail(HomeSurface surface) =>
      _details[surface] ??= () async {
        try {
          final data = await _data(surface);
          return (
            Texture2D.fromPixels(
              data.normal,
              data.size,
              data.size,
              content: TextureContent.normal,
              sampling: _sampling,
            ),
            Texture2D.fromPixels(
              data.roughness,
              data.size,
              data.size,
              content: TextureContent.data,
              sampling: _sampling,
            ),
          );
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
    final color = await _color(surface);
    if (!isCurrent()) return;
    pbr.baseColorTexture = color;
    baked.baseColorTexture = color;
    if (!details) return;
    final (normal, orm) = await _detail(surface);
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
