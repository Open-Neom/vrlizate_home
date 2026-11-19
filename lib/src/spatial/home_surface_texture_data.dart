import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vrlizate_scene/vrlizate_scene.dart' show VrToksvigFilter;

/// Small, seamless neutral finishes. The authored room color remains in the
/// mesh; the texture contributes grain, normal relief, roughness variation,
/// and glTF ORM micro-cavity ambient occlusion rather than replacing the room palette.
enum HomeSurface { limestone, plaster, oak, brushedMetal, wovenFabric }

class HomeSurfaceTextureData {
  const HomeSurfaceTextureData(
    this.size,
    this.color,
    this.normal,
    this.roughness,
  );

  final int size;
  final Uint8List color, normal, roughness;

  static const resolution = 256;

  /// Pure CPU authoring, run once per finish in a worker isolate. All noise is
  /// periodic, including derivatives at the tile edges.
  ///
  /// `roughness` uses standard glTF 2.0 ORM channel packing:
  /// - Channel R: micro-cavity ambient occlusion (`0..255`)
  /// - Channel G: perceptual roughness (`0..255`)
  /// - Channel B: metalness (`0..255`)
  /// - Channel A: `255`
  static HomeSurfaceTextureData generate(
    HomeSurface surface, {
    int resolution = HomeSurfaceTextureData.resolution,
  }) {
    final size = resolution.clamp(64, 1024);
    final heights = Float32List(size * size);
    final color = Uint8List(size * size * 4);
    final normal = Uint8List(color.length);
    final roughness = Uint8List(color.length);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final u = x / size;
        final v = y / size;
        final broad = _noise(u, v, 6, 12);
        final fine = _noise(u, v, 64, 37);
        final grain = _noise(u, v, 128, 71);
        double height, tone, rough, ao;
        var metal = 0.0;
        switch (surface) {
          case HomeSurface.limestone:
            final vein = math.sin(math.pi * 2 * (u * 3 + v * 2) + broad * 2);
            // Subtle ashlar stone coursing (2 rows × 1 staggered joint per tile).
            final row = (v * 2).floor();
            final rowV = v * 2 - row;
            final colU = (u + (row.isOdd ? .5 : 0.0)) % 1.0;
            final jointDist = math.min(
              math.min(colU, 1.0 - colU),
              math.min(rowV, 1.0 - rowV) * .5,
            );
            final coursing = _smoothstep(.008, .032, jointDist);
            height =
                .44 + coursing * .065 + broad * .04 + fine * .022 + grain * .01;
            tone =
                (.89 + coursing * .045) +
                broad * .032 +
                fine * .016 +
                vein * .014;
            rough = .70 + (1.0 - coursing) * .16 + fine * .045;
            ao = .76 + coursing * .22 + fine * .02;
          case HomeSurface.oak:
            // Long, irregular cathedral grain with subtle plank micro-joints.
            final warp = _noise(u * 2, v, 3, 97) * .8;
            final growth = math.sin((u * 9 + warp) * math.pi * 2);
            final fiber = _noise(u * 8, v, 8, 41);
            final plankU = (u * 3) - (u * 3).floor();
            final plankEdge = _smoothstep(
              .01,
              .045,
              math.min(plankU, 1.0 - plankU),
            );
            height =
                .46 +
                plankEdge * .045 +
                growth * .014 +
                fiber * .007 +
                grain * .004;
            tone =
                (.88 + plankEdge * .035) +
                growth * .026 +
                fiber * .018 +
                broad * .012;
            rough = .62 + (1.0 - plankEdge) * .14 + growth * .035 + fine * .04;
            ao = .78 + plankEdge * .20 + growth * .02;
          case HomeSurface.plaster:
            final trowel = _noise(u, v, 12, 53);
            height = .5 + trowel * .018 + fine * .012 + grain * .008;
            tone = .962 + broad * .009 + trowel * .008 + fine * .01 + grain * .005;
            rough = .88 + fine * .025;
            ao = .95 + fine * .025 + trowel * .015;
          case HomeSurface.brushedMetal:
            // Anodized architectural aluminum/bronze: directional brushed grooves.
            final brush = _noise(u * .5, v * 4, 32, 83);
            final groove = math.sin(math.pi * 2 * (v * 48 + broad * .35));
            height = .5 + groove * .016 + brush * .014 + grain * .006;
            tone = .94 + groove * .018 + brush * .022 + broad * .012;
            rough = .36 + brush * .045 + fine * .03;
            ao = .91 + (groove * .5 + .5) * .07 + brush * .015;
            metal = .42;
          case HomeSurface.wovenFabric:
            // Architectural twill weave for lounge seating and rugs.
            const threads = 32;
            final warpWave = .5 + .5 * math.sin(u * threads * math.pi * 2);
            final weftWave = .5 + .5 * math.sin(v * threads * math.pi * 2);
            final over = ((u * threads).floor() + (v * threads).floor()).isEven;
            final weave = over
                ? warpWave * .68 + weftWave * .32
                : weftWave * .68 + warpWave * .32;
            height = .42 + weave * .085 + fine * .014 + grain * .008;
            tone = .88 + weave * .09 + broad * .016 + fine * .012;
            rough = .93 + grain * .03;
            ao = .74 + weave * .24 + fine * .015;
        }
        final p = (y * size + x) * 4;
        final value = (tone.clamp(0.0, 1.0) * 255).round();
        color[p] = color[p + 1] = color[p + 2] = value;
        color[p + 3] = 255;
        heights[y * size + x] = height;
        roughness[p] = (ao.clamp(0.0, 1.0) * 255).round();
        roughness[p + 1] = (rough.clamp(0.0, 1.0) * 255).round();
        roughness[p + 2] = (metal.clamp(0.0, 1.0) * 255).round();
        roughness[p + 3] = 255;
      }
    }
    final slopeGain = 2.4 * (size / 256.0);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        double h(int dx, int dy) =>
            heights[((y + dy) % size) * size + (x + dx) % size];
        final nx = (h(-1, 0) - h(1, 0)) * slopeGain;
        final ny = (h(0, -1) - h(0, 1)) * slopeGain;
        final length = math.sqrt(nx * nx + ny * ny + 1);
        final p = (y * size + x) * 4;
        normal[p] = ((nx / length * .5 + .5) * 255).round();
        normal[p + 1] = ((ny / length * .5 + .5) * 255).round();
        normal[p + 2] = ((1 / length * .5 + .5) * 255).round();
        normal[p + 3] = 255;
      }
    }
    final filteredOrm = VrToksvigFilter.regularizeBaseOrmRoughness(
      normalRgba: normal,
      ormRgba: roughness,
      width: size,
      height: size,
      strength: 0.48,
    );
    return HomeSurfaceTextureData(size, color, normal, filteredOrm);
  }

  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _noise(double u, double v, int period, int seed) {
    final x = u * period, y = v * period;
    final ix = x.floor(), iy = y.floor();
    final fx = x - ix, fy = y - iy;
    final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    double value(int x, int y) {
      var h = (x % period) * 374761393 + (y % period) * 668265263 + seed;
      h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
      return (h & 65535) / 32767.5 - 1;
    }

    final a = value(ix, iy), b = value(ix + 1, iy);
    final c = value(ix, iy + 1), d = value(ix + 1, iy + 1);
    return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy;
  }
}
