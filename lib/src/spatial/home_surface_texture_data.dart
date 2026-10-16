import 'dart:math' as math;
import 'dart:typed_data';

/// Small, seamless neutral finishes. The authored room color remains in the
/// mesh; the texture contributes grain rather than replacing the room palette.
enum HomeSurface { limestone, plaster, oak }

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
  static HomeSurfaceTextureData generate(HomeSurface surface) {
    const size = resolution;
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
        double height, tone, rough;
        switch (surface) {
          case HomeSurface.limestone:
            final vein = math.sin(math.pi * 2 * (u * 3 + v * 2) + broad * 2);
            height = .48 + broad * .045 + fine * .025 + grain * .012;
            tone = .91 + broad * .035 + fine * .017 + vein * .014;
            rough = .83 + fine * .04;
          case HomeSurface.oak:
            // Long, irregular grain rather than equally spaced dark stripes.
            // Integer frequencies keep the grain seamless across meter tiles.
            final warp = _noise(u * 2, v, 3, 97) * .8;
            final growth = math.sin((u * 9 + warp) * math.pi * 2);
            final fiber = _noise(u * 8, v, 8, 41);
            height = .5 + growth * .012 + fiber * .006 + grain * .004;
            tone = .90 + growth * .023 + fiber * .018 + broad * .012;
            rough = .72 + fine * .045;
          case HomeSurface.plaster:
            height = .5 + fine * .012 + grain * .008;
            tone = .966 + broad * .008 + fine * .01 + grain * .006;
            rough = .94 + fine * .02;
        }
        final p = (y * size + x) * 4;
        final value = (tone.clamp(0.0, 1.0) * 255).round();
        color[p] = color[p + 1] = color[p + 2] = value;
        color[p + 3] = 255;
        heights[y * size + x] = height;
        roughness[p] = 255;
        roughness[p + 1] = (rough.clamp(0.0, 1.0) * 255).round();
        roughness[p + 2] = 0; // Dielectrics, never accidentally metallic.
        roughness[p + 3] = 255;
      }
    }
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        double h(int dx, int dy) =>
            heights[((y + dy) % size) * size + (x + dx) % size];
        final nx = (h(-1, 0) - h(1, 0)) * 2;
        final ny = (h(0, -1) - h(0, 1)) * 2;
        final length = math.sqrt(nx * nx + ny * ny + 1);
        final p = (y * size + x) * 4;
        normal[p] = ((nx / length * .5 + .5) * 255).round();
        normal[p + 1] = ((ny / length * .5 + .5) * 255).round();
        normal[p + 2] = ((1 / length * .5 + .5) * 255).round();
        normal[p + 3] = 255;
      }
    }
    return HomeSurfaceTextureData(size, color, normal, roughness);
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
