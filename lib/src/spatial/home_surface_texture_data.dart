import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vrlizate_scene/vrlizate_scene.dart' show VrToksvigFilter;

/// Seamless architectural PBR finishes (`256px` on low/medium, `512px` on
/// high/ultra). Multi-tone micro-color variation, tactile height-derived normal
/// relief, physically calibrated roughness contrast, and glTF ORM micro-cavity
/// ambient occlusion give surfaces realistic depth instead of flat monochrome.
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
  /// - Channel G: Toksvig-filtered perceptual roughness (`0..255`)
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
        final mid = _noise(u, v, 18, 29);
        final fine = _noise(u, v, 64, 37);
        final grain = _noise(u, v, 128, 71);
        double height, rTone, gTone, bTone, rough, ao;
        var metal = 0.0;
        switch (surface) {
          case HomeSurface.limestone:
            // Honed Italian travertine / architectural limestone slabs:
            // staggered ashlar coursing, subtle slab-to-slab mineral shift,
            // sedimentary veining, crisp beveled grout, satin-honed sheen.
            final row = (v * 2).floor();
            final rowV = v * 2 - row;
            final shiftedU = (u + (row.isOdd ? .5 : 0.0)) % 1.0;
            final col = (shiftedU * 2).floor();
            final colU = shiftedU * 2 - col;
            final slabHash = _cellHash(col, row, 109);
            final jointDist = math.min(
              math.min(colU, 1.0 - colU) * .5,
              math.min(rowV, 1.0 - rowV) * .5,
            );
            final coursing = _smoothstep(.007, .026, jointDist);
            final veinWarp = broad * 1.65 + mid * .55;
            final vein = math.sin(math.pi * 2 * (u * 2 + v * 3) + veinWarp);
            final veinBand = _smoothstep(.35, .92, vein.abs());
            final pore = _smoothstep(.58, .88, fine.abs()) * .018;
            height =
                .40 +
                coursing * .085 +
                broad * .026 +
                mid * .014 +
                fine * .015 +
                grain * .008 -
                pore;
            final baseLuma =
                (.87 + coursing * .075 + slabHash * .038) +
                broad * .024 -
                veinBand * .045 +
                fine * .012;
            // Warm travertine tint in slabs, slightly cooler mineral grout.
            final warm = coursing * .038 + veinBand * .014;
            rTone = baseLuma + warm * .75;
            gTone = baseLuma + warm * .32;
            bTone = baseLuma - warm * .65;
            // Honed satin slab centers catch subtle IBL/SSR; mortar stays matte.
            rough =
                .52 +
                (1.0 - coursing) * .36 +
                veinBand * .07 +
                fine * .045 +
                pore * 2.2;
            ao = .72 + coursing * .24 - pore * 1.4 + fine * .018;
          case HomeSurface.oak:
            // Natural European architectural oak planks with cathedral rings,
            // plank-to-plank warmth variation, micro-pores & beveled seams.
            final plankIdx = (u * 4).floor();
            final plankU = (u * 4) - plankIdx;
            final plankShift = _cellHash(plankIdx, 0, 211);
            final plankEdge = _smoothstep(
              .010,
              .042,
              math.min(plankU, 1.0 - plankU),
            );
            final warp =
                _noise(u * 2, v + plankShift * .35, 3, 97) * .85 +
                _noise(u * 4, v * 2, 6, 61) * .22;
            final ringPhase = (u * 10 + warp + plankShift * .7) * math.pi * 2;
            final growth = math.sin(ringPhase);
            final latewood = _smoothstep(.25, .95, growth);
            final fiber = _noise(u * 12, v * 2, 16, 41);
            height =
                .44 +
                plankEdge * .058 -
                latewood * .012 +
                fiber * .009 +
                grain * .005;
            final baseLuma =
                (.84 + plankEdge * .072 + plankShift * .045) -
                latewood * .065 +
                fiber * .022 +
                broad * .014;
            // Natural warm honey-amber oak micro-chroma.
            rTone = baseLuma + .055 - latewood * .018;
            gTone = baseLuma + .012 - latewood * .022;
            bTone = baseLuma - .058 - latewood * .010;
            rough =
                .53 +
                (1.0 - plankEdge) * .24 +
                latewood * .085 +
                fine * .038;
            ao = .74 + plankEdge * .22 - latewood * .028 + fiber * .014;
          case HomeSurface.plaster:
            // Warm Venetian architectural limewash / microcement with soft
            // multi-scale trowel clouds and fine mineral silica grain.
            final trowel = _noise(u, v, 8, 53);
            final cloud = _noise(u, v, 4, 131);
            height =
                .50 +
                trowel * .022 +
                mid * .012 +
                fine * .010 +
                grain * .007;
            final baseLuma =
                .948 +
                cloud * .022 +
                trowel * .016 +
                fine * .010 +
                grain * .005;
            rTone = baseLuma + .014;
            gTone = baseLuma + .006;
            bTone = baseLuma - .014;
            rough = .84 + trowel * .045 + fine * .028;
            ao = .93 + trowel * .024 + fine * .020;
          case HomeSurface.brushedMetal:
            // Anodized architectural champagne-bronze / satin titanium:
            // crisp directional micro-brush streaks & low glossy-satin roughness.
            final brush = _noise(u * .5, v * 4, 32, 83);
            final microBrush = _noise(u * .25, v * 8, 64, 157);
            final groove = math.sin(math.pi * 2 * (v * 56 + broad * .28));
            height =
                .50 +
                groove * .014 +
                brush * .015 +
                microBrush * .008 +
                grain * .004;
            final baseLuma =
                .92 +
                groove * .020 +
                brush * .028 +
                microBrush * .018 +
                broad * .012;
            // Subtle warm champagne-titanium micro-tint.
            rTone = baseLuma + .024;
            gTone = baseLuma + .012;
            bTone = baseLuma - .016;
            rough = .27 + brush * .048 + microBrush * .030 + fine * .022;
            ao = .90 + (groove * .5 + .5) * .07 + brush * .015;
            metal = .42;
          case HomeSurface.wovenFabric:
            // Architectural wool bouclé / twill herringbone weave for lounge
            // seating and rugs with rich micro-cavity shading.
            const threads = 36;
            final warpWave = .5 + .5 * math.sin(u * threads * math.pi * 2);
            final weftWave = .5 + .5 * math.sin(v * threads * math.pi * 2);
            final cell = (u * threads).floor() + (v * threads).floor();
            final over = (cell & 1) == 0;
            final weave = over
                ? warpWave * .70 + weftWave * .30
                : weftWave * .70 + warpWave * .30;
            final heather = mid * .028 + fine * .018;
            height = .40 + weave * .095 + fine * .014 + grain * .009;
            final baseLuma = .86 + weave * .10 + broad * .018 + heather;
            final yarnWarm = over ? .018 : -.008;
            rTone = baseLuma + yarnWarm;
            gTone = baseLuma + yarnWarm * .45;
            bTone = baseLuma - yarnWarm * .65;
            rough = .91 + (1.0 - weave) * .045 + grain * .025;
            ao = .72 + weave * .25 + fine * .015;
        }
        final p = (y * size + x) * 4;
        color[p] = (rTone.clamp(0.0, 1.0) * 255).round();
        color[p + 1] = (gTone.clamp(0.0, 1.0) * 255).round();
        color[p + 2] = (bTone.clamp(0.0, 1.0) * 255).round();
        color[p + 3] = 255;
        heights[y * size + x] = height;
        roughness[p] = (ao.clamp(0.0, 1.0) * 255).round();
        roughness[p + 1] = (rough.clamp(0.0, 1.0) * 255).round();
        roughness[p + 2] = (metal.clamp(0.0, 1.0) * 255).round();
        roughness[p + 3] = 255;
      }
    }
    final slopeGain = 2.8 * (size / 256.0);
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

  static double _cellHash(int ix, int iy, int seed) {
    var h = ix * 374761393 + iy * 668265263 + seed;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
    return (h & 65535) / 32767.5 - 1.0;
  }

  static double _noise(double u, double v, int period, int seed) {
    final x = u * period, y = v * period;
    final ix = x.floor(), iy = y.floor();
    final fx = x - ix, fy = y - iy;
    final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    double value(int x, int y) => _cellHash(x % period, y % period, seed);

    final a = value(ix, iy), b = value(ix + 1, iy);
    final c = value(ix, iy + 1), d = value(ix + 1, iy + 1);
    return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy;
  }
}
