import 'dart:math' as math;
import 'dart:typed_data';

import 'home_lobby_layout.dart';

/// CPU-only static batching. A room/finish remains independently culled and
/// raycastable, while shelves and shopfront trim do not each add a draw call.
/// Collision keeps using the original authored boxes, never a batch's bounds.
class HomeArchitectureBatch {
  HomeArchitectureBatch._(this.zone, this.finish, List<HomeLobbyBox> boxes)
    : boxes = List.unmodifiable(boxes);

  final String zone;
  final HomeLobbyFinish finish;
  final List<HomeLobbyBox> boxes;

  static List<HomeArchitectureBatch> group(Iterable<HomeLobbyBox> boxes) {
    final groups = <(String, HomeLobbyFinish), List<HomeLobbyBox>>{};
    for (final box in boxes) {
      groups.putIfAbsent((box.zone, box.finish), () => []).add(box);
    }
    return List.unmodifiable([
      for (final entry in groups.entries)
        HomeArchitectureBatch._(entry.key.$1, entry.key.$2, entry.value),
    ]);
  }

  HomeArchitectureMeshData build({
    required int defaultColor,
    bool bakedVertexShading = false,
  }) {
    final mesh = _ArchitectureMeshBuilder(bakedVertexShading);
    for (final box in boxes) {
      mesh.add(box, defaultColor);
    }
    return mesh.finish();
  }
}

/// Curved primitives are tessellated once into the same room/material batch.
/// Twelve radial segments and eight latitude bands keep one full tree's two
/// crowns at 336 triangles; no foliage alpha layers or per-frame work are used.
class _ArchitectureMeshBuilder {
  _ArchitectureMeshBuilder(this.baked);

  final bool baked;
  final positions = <double>[];
  final normals = <double>[];
  final colors = <double>[];
  final textureCoordinates = <double>[];
  final indices = <int>[];
  late HomeLobbyBox box;
  late List<double> color;
  static const radialSegments = 12;
  static const latitudeBands = 8;
  static final _sunLength = math.sqrt(.3 * .3 + .8 * .8 + .55 * .55);

  void add(HomeLobbyBox value, int defaultColor) {
    box = value;
    final argb = box.color ?? defaultColor;
    color = [
      _linear((argb >> 16) & 255),
      _linear((argb >> 8) & 255),
      _linear(argb & 255),
      1,
    ];
    switch (box.shape) {
      case HomeLobbyShape.cuboid:
        _cuboid();
      case HomeLobbyShape.cylinder:
        _cylinder();
      case HomeLobbyShape.ellipsoid:
        _ellipsoid();
      case HomeLobbyShape.beveledBox:
        _beveledBox();
    }
  }

  List<double> get half => [box.width / 2, box.height / 2, box.depth / 2];

  int _vertex(List<double> p, List<double> n, [List<double>? uvMeters]) {
    final index = positions.length ~/ 3;
    final world = [p[0] + box.x, p[1] + box.y, p[2] + box.z];
    positions.addAll(world);
    normals.addAll(n);
    colors.addAll(baked ? _bakeColor(color, n) : color);
    final uv = uvMeters ?? _planarUv(world, n);
    final tile = box.finish.textureTileMeters;
    textureCoordinates.addAll([uv[0] / tile, uv[1] / tile]);
    return index;
  }

  // World-space planar coordinates give adjacent panels the same texture
  // density and phase. Curves supply measured arc lengths instead.
  static List<double> _planarUv(List<double> p, List<double> n) {
    final x = n[0].abs(), y = n[1].abs(), z = n[2].abs();
    if (y >= x && y >= z) return [p[0], p[2]];
    if (x >= z) return [p[2], p[1]];
    return [p[0], p[1]];
  }

  void _triangle(int a, int b, int c) {
    final ia = a * 3, ib = b * 3, ic = c * 3;
    final abx = positions[ib] - positions[ia];
    final aby = positions[ib + 1] - positions[ia + 1];
    final abz = positions[ib + 2] - positions[ia + 2];
    final acx = positions[ic] - positions[ia];
    final acy = positions[ic + 1] - positions[ia + 1];
    final acz = positions[ic + 2] - positions[ia + 2];
    final dot =
        (aby * acz - abz * acy) * normals[ia] +
        (abz * acx - abx * acz) * normals[ia + 1] +
        (abx * acy - aby * acx) * normals[ia + 2];
    // Model-space CCW, matching Flutter Scene 0.24's buildCuboidArrays.
    // Its Y-down rasterizer uses clockwise front faces after projection;
    // that does not reverse the outward model-space cross-product normal.
    indices.addAll(dot < 0 ? [a, c, b] : [a, b, c]);
  }

  void _face(List<List<double>> points, List<double> normal) {
    final vertices = [for (final p in points) _vertex(p, normal)];
    for (var i = 1; i < vertices.length - 1; i++) {
      _triangle(vertices[0], vertices[i], vertices[i + 1]);
    }
  }

  void _cuboid() {
    final h = half;
    final corners = [
      [-h[0], -h[1], -h[2]],
      [h[0], -h[1], -h[2]],
      [h[0], h[1], -h[2]],
      [-h[0], h[1], -h[2]],
      [-h[0], -h[1], h[2]],
      [h[0], -h[1], h[2]],
      [h[0], h[1], h[2]],
      [-h[0], h[1], h[2]],
    ];
    // Keep the original 24-vertex ordering for the default box representation.
    const faces = <(List<int>, List<double>)>[
      ([0, 1, 2, 3], [0, 0, -1]),
      ([1, 5, 6, 2], [1, 0, 0]),
      ([5, 4, 7, 6], [0, 0, 1]),
      ([4, 0, 3, 7], [-1, 0, 0]),
      ([3, 2, 6, 7], [0, 1, 0]),
      ([4, 5, 1, 0], [0, -1, 0]),
    ];
    for (final (cornersForFace, normal) in faces) {
      final v = [for (final i in cornersForFace) _vertex(corners[i], normal)];
      _triangle(v[0], v[1], v[3]);
      _triangle(v[3], v[1], v[2]);
    }
  }

  /// A chamfered box with six broad faces, twelve edge strips and eight corner
  /// triangles (44 triangles total). Its bounds remain the authored collider.
  void _beveledBox() {
    final h = half;
    final radius = math.min(.11, h.reduce(math.min) * .56);
    final inset = [for (final value in h) value - radius];
    const signs = [-1.0, 1.0];
    for (var axis = 0; axis < 3; axis++) {
      final a = (axis + 1) % 3;
      for (final sign in signs) {
        final normal = [0.0, 0.0, 0.0]..[axis] = sign;
        final points = <List<double>>[];
        for (final (sa, sb) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
          points.add([
            for (var i = 0; i < 3; i++)
              i == axis ? sign * h[i] : (i == a ? sa : sb) * inset[i],
          ]);
        }
        _face(points, normal);
      }
    }
    for (var a = 0; a < 3; a++) {
      for (var b = a + 1; b < 3; b++) {
        final c = 3 - a - b;
        for (final sa in signs) {
          for (final sb in signs) {
            final normal = [0.0, 0.0, 0.0]
              ..[a] = sa / math.sqrt(2)
              ..[b] = sb / math.sqrt(2);
            List<double> point(bool firstFace, double end) => [
              for (var i = 0; i < 3; i++)
                if (i == a)
                  sa * (firstFace ? h[i] : inset[i])
                else if (i == b)
                  sb * (firstFace ? inset[i] : h[i])
                else
                  end * inset[c],
            ];
            _face([
              point(true, -1),
              point(false, -1),
              point(false, 1),
              point(true, 1),
            ], normal);
          }
        }
      }
    }
    for (final sx in signs) {
      for (final sy in signs) {
        for (final sz in signs) {
          final sign = [sx, sy, sz];
          _face(
            [
              for (var axis = 0; axis < 3; axis++)
                [
                  for (var i = 0; i < 3; i++)
                    sign[i] * (i == axis ? h[i] : inset[i]),
                ],
            ],
            [for (final s in sign) s / math.sqrt(3)],
          );
        }
      }
    }
  }

  /// Cumulative distances along a sampled horizontal ellipse, including its
  /// seam. Unlike normalized 0..1 UVs, a bigger primitive repeats its texture.
  List<double> _ellipseDistances(double rx, double rz) {
    final result = <double>[0];
    var x = rx, z = 0.0;
    for (var i = 1; i <= radialSegments; i++) {
      final angle = i * 2 * math.pi / radialSegments;
      final nextX = rx * math.cos(angle), nextZ = rz * math.sin(angle);
      result.add(
        result.last +
            math.sqrt(math.pow(nextX - x, 2) + math.pow(nextZ - z, 2)),
      );
      x = nextX;
      z = nextZ;
    }
    return result;
  }

  void _cylinder() {
    final h = half;
    final distances = _ellipseDistances(h[0], h[2]);
    final sides = <List<int>>[];
    for (var i = 0; i <= radialSegments; i++) {
      final angle = i * 2 * math.pi / radialSegments;
      final x = math.cos(angle), z = math.sin(angle);
      final normal = _normalized([x / h[0], 0, z / h[2]]);
      sides.add([
        _vertex([h[0] * x, -h[1], h[2] * z], normal, [distances[i], 0]),
        _vertex([h[0] * x, h[1], h[2] * z], normal, [distances[i], box.height]),
      ]);
      if (i == 0) continue;
      _triangle(sides[i - 1][0], sides[i][0], sides[i - 1][1]);
      _triangle(sides[i - 1][1], sides[i][0], sides[i][1]);
    }
    for (final sign in [-1.0, 1.0]) {
      final normal = [0.0, sign, 0.0];
      final center = _vertex([0, sign * h[1], 0], normal);
      final ring = <int>[];
      for (var i = 0; i < radialSegments; i++) {
        final angle = i * 2 * math.pi / radialSegments;
        ring.add(
          _vertex([
            h[0] * math.cos(angle),
            sign * h[1],
            h[2] * math.sin(angle),
          ], normal),
        );
      }
      for (var i = 0; i < radialSegments; i++) {
        _triangle(center, ring[i], ring[(i + 1) % radialSegments]);
      }
    }
  }

  void _ellipsoid() {
    final h = half;
    final distances = _ellipseDistances(h[0], h[2]);
    final rings = <List<int>>[];
    final meridians = List<double>.filled(radialSegments + 1, 0);
    for (var row = 0; row <= latitudeBands; row++) {
      final theta = row * math.pi / latitudeBands;
      final sin = math.sin(theta), cos = math.cos(theta);
      final previousTheta = (row - 1) * math.pi / latitudeBands;
      final ring = <int>[];
      for (var col = 0; col <= radialSegments; col++) {
        final phi = col * 2 * math.pi / radialSegments;
        final cx = math.cos(phi), sz = math.sin(phi);
        final p = [h[0] * sin * cx, h[1] * cos, h[2] * sin * sz];
        if (row > 0) {
          final ds = sin - math.sin(previousTheta);
          final dy = h[1] * (cos - math.cos(previousTheta));
          meridians[col] += math.sqrt(
            math.pow(h[0] * ds * cx, 2) + dy * dy + math.pow(h[2] * ds * sz, 2),
          );
        }
        final normal = _normalized([
          sin * cx / h[0],
          cos / h[1],
          sin * sz / h[2],
        ]);
        ring.add(_vertex(p, normal, [distances[col], meridians[col]]));
      }
      rings.add(ring);
      if (row == 0) continue;
      for (var col = 0; col < radialSegments; col++) {
        // The poles are duplicated for the UV seam, but degenerate triangles
        // are never emitted. Twelve segments include all four cardinal bounds.
        if (row > 1) {
          _triangle(rings[row - 1][col], ring[col], rings[row - 1][col + 1]);
        }
        if (row < latitudeBands) {
          _triangle(rings[row - 1][col + 1], ring[col], ring[col + 1]);
        }
      }
    }
  }

  static List<double> _normalized(List<double> vector) {
    final length = math.sqrt(vector.fold<double>(0, (sum, v) => sum + v * v));
    return [for (final value in vector) value / length];
  }

  static List<double> _bakeColor(List<double> color, List<double> normal) {
    // Opposite the world's sunlight travel direction (-.3, -.8, .55).
    final sun =
        .22 *
        math.max(
          0.0,
          (normal[0] * .3 + normal[1] * .8 - normal[2] * .55) / _sunLength,
        );
    final sky = .18 * (.5 + .5 * normal[1]);
    const ambient = .68;
    return [
      color[0] * (ambient + sky * .94 + sun),
      color[1] * (ambient + sky * .98 + sun * .97),
      color[2] * (ambient + sky + sun * .91),
      color[3],
    ];
  }

  static double _linear(int channel) {
    final value = channel / 255;
    return value <= .04045
        ? value / 12.92
        : math.pow((value + .055) / 1.055, 2.4).toDouble();
  }

  HomeArchitectureMeshData finish() => HomeArchitectureMeshData(
    Float32List.fromList(positions),
    Float32List.fromList(normals),
    Float32List.fromList(colors),
    indices,
    Float32List.fromList(textureCoordinates),
  );
}

class HomeArchitectureMeshData {
  const HomeArchitectureMeshData(
    this.positions,
    this.normals,
    this.colors,
    this.indices,
    this.textureCoordinates,
  );
  final Float32List positions, normals, colors, textureCoordinates;
  final List<int> indices;
}
