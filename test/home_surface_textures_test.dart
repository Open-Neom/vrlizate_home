import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_surface_texture_data.dart';
import 'package:vrlizate_home/src/spatial/home_surface_textures.dart';

void main() {
  group('HomeSurfaceTextureData & HomeSurfaceTextures', () {
    test('maps architectural finishes to dedicated surface generators', () {
      expect(
        HomeSurfaceTextures.surfaceFor(HomeLobbyFinish.stone),
        HomeSurface.limestone,
      );
      expect(
        HomeSurfaceTextures.surfaceFor(HomeLobbyFinish.oak),
        HomeSurface.oak,
      );
      expect(
        HomeSurfaceTextures.surfaceFor(HomeLobbyFinish.plaster),
        HomeSurface.plaster,
      );
      expect(
        HomeSurfaceTextures.surfaceFor(HomeLobbyFinish.trim),
        HomeSurface.brushedMetal,
      );
      expect(
        HomeSurfaceTextures.surfaceFor(HomeLobbyFinish.fabric),
        HomeSurface.wovenFabric,
      );
      expect(
        HomeSurfaceTextures.surfaceFor(HomeLobbyFinish.rug),
        HomeSurface.wovenFabric,
      );
    });

    test('generates seamless RGBA color, unit normals and glTF ORM channels', () {
      for (final surface in HomeSurface.values) {
        final data = HomeSurfaceTextureData.generate(surface);
        const n = HomeSurfaceTextureData.resolution;
        expect(data.size, n);
        expect(data.color.length, n * n * 4);
        expect(data.normal.length, n * n * 4);
        expect(data.roughness.length, n * n * 4);

        var meanAo = 0.0;
        var meanRough = 0.0;
        var meanMetal = 0.0;
        for (var i = 0; i < data.normal.length; i += 4) {
          final nx = data.normal[i] / 127.5 - 1.0;
          final ny = data.normal[i + 1] / 127.5 - 1.0;
          final nz = data.normal[i + 2] / 127.5 - 1.0;
          final len = math.sqrt(nx * nx + ny * ny + nz * nz);
          expect(len, closeTo(1.0, 0.025), reason: '$surface normal length');
          expect(nz, greaterThan(0.3), reason: '$surface front-facing normal');
          expect(data.color[i + 3], 255);
          expect(data.normal[i + 3], 255);
          expect(data.roughness[i + 3], 255);

          meanAo += data.roughness[i] / 255.0;
          meanRough += data.roughness[i + 1] / 255.0;
          meanMetal += data.roughness[i + 2] / 255.0;
        }
        final texels = n * n;
        meanAo /= texels;
        meanRough /= texels;
        meanMetal /= texels;

        expect(meanAo, inInclusiveRange(0.70, 0.99), reason: '$surface AO');
        if (surface == HomeSurface.brushedMetal) {
          expect(meanMetal, closeTo(0.42, 0.02));
          expect(meanRough, lessThan(0.45));
        } else {
          expect(meanMetal, 0.0, reason: '$surface is dielectric');
          expect(meanRough, greaterThan(0.55));
        }
      }
    });
  });
}
