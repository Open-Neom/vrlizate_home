import 'package:flutter_test/flutter_test.dart';
// Compare CPU arrays with the actual resolved renderer, without creating GPU
// geometry. These generators are intentionally not in Scene's public barrel.
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/primitives.dart'
    show buildCuboidArrays;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/home_architecture_batch.dart';
import 'package:vrlizate_home/src/spatial/home_ecosystem_layout.dart';
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';

void main() {
  test(
    'batches keep spatial/material boundaries, not separate color draws',
    () {
      final boxes = [
        _box('first', 0, color: 0xFFFF0000),
        _box('second', 4, color: 0xFF00FF00),
        _box('other-room', 8, zone: 'other'),
      ];
      final batches = HomeArchitectureBatch.group(boxes);
      expect(batches, hasLength(2));
      final data = batches.first.build(defaultColor: 0xFF0000FF);
      expect(data.positions, hasLength(48 * 3));
      expect(data.indices, hasLength(72));
      expect(data.colors.take(4), [1, 0, 0, 1]);
      expect(data.colors.skip(24 * 4).take(4), [0, 1, 0, 1]);
      for (var i = 0; i < data.indices.length; i += 3) {
        expect(
          data.indices.sublist(i, i + 3).map((v) => v ~/ 24).toSet(),
          hasLength(1),
          reason: 'Triangles cannot bridge gaps between boxes.',
        );
      }
      expect(() => batches.first.boxes.clear(), throwsUnsupportedError);
    },
  );

  test('world-space cube faces retain bounds, normals and Scene winding', () {
    final data = HomeArchitectureBatch.group([
      _box('cube', 4),
    ]).single.build(defaultColor: 0xFFFFFFFF);
    final vertices = [
      for (var i = 0; i < data.positions.length; i += 3)
        vm.Vector3(
          data.positions[i],
          data.positions[i + 1],
          data.positions[i + 2],
        ),
    ];
    expect(vertices.map((v) => v.x).toSet(), {3, 5});
    expect(vertices.map((v) => v.y).toSet(), {0, 2});
    expect(vertices.map((v) => v.z).toSet(), {-1, 1});
    final renderer = buildCuboidArrays(vm.Vector3.all(2));
    expect(data.indices, renderer.indices);
    expect(data.normals, renderer.normals);
    for (var i = 0; i < data.positions.length; i += 3) {
      expect(data.positions[i], renderer.positions[i] + 4);
      expect(data.positions[i + 1], renderer.positions[i + 1] + 1);
      expect(data.positions[i + 2], renderer.positions[i + 2]);
    }
    for (var i = 0; i < data.indices.length; i += 3) {
      final a = data.indices[i];
      final edge1 = vertices[data.indices[i + 1]] - vertices[a];
      final edge2 = vertices[data.indices[i + 2]] - vertices[a];
      final normal = vm.Vector3(
        data.normals[a * 3],
        data.normals[a * 3 + 1],
        data.normals[a * 3 + 2],
      );
      expect(normal.length, closeTo(1, 1e-6));
      expect(
        edge1.cross(edge2).dot(normal) * _rendererWindingSign(),
        greaterThan(0),
      );
    }
  });

  test('baked lighting preserves geometry, alpha and authored albedo', () {
    final batch = HomeArchitectureBatch.group([
      _box('white', 0),
      _box('red', 4, color: 0xFFFF0000),
    ]).single;
    final pbr = batch.build(defaultColor: 0xFFFFFFFF);
    final baked = batch.build(
      defaultColor: 0xFFFFFFFF,
      bakedVertexShading: true,
    );

    // A quality switch must not alter collision, ray hits, culling or faces.
    expect(baked.positions, pbr.positions);
    expect(baked.normals, pbr.normals);
    expect(baked.indices, pbr.indices);
    expect(baked.textureCoordinates, pbr.textureCoordinates);
    final brightness = <int, double>{};
    for (var vertex = 0; vertex < 24; vertex++) {
      final color = baked.colors.sublist(vertex * 4, vertex * 4 + 4);
      expect(color[3], 1);
      for (final channel in color.take(3)) {
        expect(channel.isFinite, isTrue);
        expect(channel, inInclusiveRange(.6, 1.1));
      }
      final yNormal = baked.normals[vertex * 3 + 1].toInt();
      brightness[yNormal] = color.take(3).reduce((a, b) => a + b);
    }
    expect(brightness[1], greaterThan(brightness[0]!));
    expect(brightness[0], greaterThan(brightness[-1]!));
    // Opposing side faces retain directionality instead of reading flat.
    expect(baked.colors[4 * 4], greaterThan(baked.colors[12 * 4]));
    for (var vertex = 24; vertex < 48; vertex++) {
      expect(baked.colors[vertex * 4 + 1], 0);
      expect(baked.colors[vertex * 4 + 2], 0);
      expect(baked.colors[vertex * 4 + 3], 1);
    }
    // Building a baked variant never contaminates the high-quality source.
    expect(batch.build(defaultColor: 0xFFFFFFFF).colors, pbr.colors);
    expect(pbr.colors.take(4), [1, 1, 1, 1]);
  });

  test('door rays and shop windows survive static batching', () {
    final layout = HomeEcosystemLayout(VrHomeEcosystemRoom.defaults);
    final batches = HomeArchitectureBatch.group(layout.boxes);
    // Architectural detail scales in vertices, not in individual draw calls.
    expect(
      batches.length,
      lessThanOrEqualTo(12 + VrHomeEcosystemRoom.defaults.length * 6),
    );
    expect(batches.length * 4, lessThan(layout.boxes.length));
    final meshes = [
      for (final batch in batches) batch.build(defaultColor: 0xFFFFFFFF),
    ];
    // Count the real curved mesh, not twelve triangles per collider box.
    final triangles = meshes.fold<int>(
      0,
      (sum, mesh) => sum + mesh.indices.length ~/ 3,
    );
    expect(triangles, lessThan(12000));
    expect(triangles, greaterThan(layout.boxes.length * 12));
    for (final portal in layout.portals) {
      for (final offset in [0.0, -portal.displayOffset, portal.displayOffset]) {
        final ray = vm.Ray.originDirection(
          vm.Vector3(0, 1.6, portal.z + offset),
          vm.Vector3(portal.side, 0, 0),
        );
        final distances = [
          for (final mesh in meshes) ..._rayDistances(ray, mesh),
        ];
        expect(distances, isNotEmpty);
        final nearest = distances.reduce((a, b) => a < b ? a : b);
        expect(
          nearest,
          greaterThan(portal.doorX.abs() + .4),
          reason: '${portal.room.id}: no triangles across doors/windows.',
        );
        if (offset == 0) {
          expect(nearest, closeTo(portal.outerX.abs() - .1, .001));
        }
      }
    }
  });

  for (final shape in HomeLobbyShape.values) {
    test('$shape has bounded solid geometry, unit normals and metric UVs', () {
      final box = _shapeBox(shape);
      final mesh = HomeArchitectureBatch.group([
        box,
      ]).single.build(defaultColor: 0xFFFFFFFF);
      final vertexCount = mesh.positions.length ~/ 3;
      expect(mesh.normals.length, vertexCount * 3);
      expect(mesh.colors.length, vertexCount * 4);
      expect(mesh.textureCoordinates.length, vertexCount * 2);
      expect(mesh.textureCoordinates.every((value) => value.isFinite), isTrue);
      final points = <vm.Vector3>[];
      final normals = <vm.Vector3>[];
      for (var i = 0; i < vertexCount; i++) {
        final p = vm.Vector3(
          mesh.positions[i * 3],
          mesh.positions[i * 3 + 1],
          mesh.positions[i * 3 + 2],
        );
        final n = vm.Vector3(
          mesh.normals[i * 3],
          mesh.normals[i * 3 + 1],
          mesh.normals[i * 3 + 2],
        );
        points.add(p);
        normals.add(n);
        expect(n.length, closeTo(1, 1e-6));
        expect(p.x, inInclusiveRange(-1.000001, 1.000001));
        expect(p.y, inInclusiveRange(-1.500001, 1.500001));
        expect(p.z, inInclusiveRange(-.500001, .500001));
      }
      for (final (axis, extent) in [(0, 1.0), (1, 1.5), (2, .5)]) {
        final values = points.map((p) => p[axis]);
        expect(values.reduce((a, b) => a < b ? a : b), closeTo(-extent, 1e-6));
        expect(values.reduce((a, b) => a > b ? a : b), closeTo(extent, 1e-6));
      }
      for (var i = 0; i < mesh.indices.length; i += 3) {
        final a = mesh.indices[i],
            b = mesh.indices[i + 1],
            c = mesh.indices[i + 2];
        expect(a, inInclusiveRange(0, vertexCount - 1));
        expect(b, inInclusiveRange(0, vertexCount - 1));
        expect(c, inInclusiveRange(0, vertexCount - 1));
        final cross = (points[b] - points[a]).cross(points[c] - points[a]);
        expect(
          cross.dot(normals[a]) * _rendererWindingSign(),
          greaterThan(1e-8),
          reason: 'No degenerate triangles; winding must match the renderer.',
        );
      }
      final expectedTriangles = switch (shape) {
        HomeLobbyShape.cuboid => 12,
        HomeLobbyShape.cylinder => 48,
        HomeLobbyShape.ellipsoid => 168,
        HomeLobbyShape.beveledBox => 44,
      };
      expect(mesh.indices.length ~/ 3, expectedTriangles);
      final baked = HomeArchitectureBatch.group([
        box,
      ]).single.build(defaultColor: 0xFFFFFFFF, bakedVertexShading: true);
      expect(baked.positions, mesh.positions);
      expect(baked.normals, mesh.normals);
      expect(baked.textureCoordinates, mesh.textureCoordinates);
      expect(baked.indices, mesh.indices);
    });
  }

  test(
    'all finishes use authored world meters instead of stretching one tile',
    () {
      for (final finish in HomeLobbyFinish.values) {
        final box = HomeLobbyBox(
          'floor',
          x: 4,
          y: -1,
          z: 3,
          width: 6,
          height: 2,
          depth: 8,
          finish: finish,
        );
        final mesh = HomeArchitectureBatch.group([
          box,
        ]).single.build(defaultColor: 0xFFFFFFFF);
        for (var i = 16; i < 20; i++) {
          // Top face maps the real XZ coordinates, including tile phase.
          expect(
            mesh.textureCoordinates[i * 2],
            closeTo(mesh.positions[i * 3] / finish.textureTileMeters, 1e-6),
          );
          expect(
            mesh.textureCoordinates[i * 2 + 1],
            closeTo(mesh.positions[i * 3 + 2] / finish.textureTileMeters, 1e-6),
          );
        }
      }
      for (final shape in [HomeLobbyShape.cylinder, HomeLobbyShape.ellipsoid]) {
        final a = HomeArchitectureBatch.group([
          _shapeBox(shape),
        ]).single.build(defaultColor: 0xFFFFFFFF);
        final b = HomeArchitectureBatch.group([
          _shapeBox(shape, scale: 2),
        ]).single.build(defaultColor: 0xFFFFFFFF);
        for (var i = 0; i < a.textureCoordinates.length; i++) {
          expect(
            b.textureCoordinates[i],
            closeTo(a.textureCoordinates[i] * 2, 1e-6),
          );
        }
      }
    },
  );

  test('curved normals and baked shading follow the ellipsoid surface', () {
    final batch = HomeArchitectureBatch.group([
      _shapeBox(HomeLobbyShape.ellipsoid),
    ]).single;
    final mesh = batch.build(
      defaultColor: 0xFFFFFFFF,
      bakedVertexShading: true,
    );
    // Equator, angular sample 30 degrees; inverse-radius normal, not the
    // uncorrected position vector, is needed on a nonuniform ellipsoid.
    const vertex = 4 * 13 + 1;
    final p = vm.Vector3(
      mesh.positions[vertex * 3],
      mesh.positions[vertex * 3 + 1],
      mesh.positions[vertex * 3 + 2],
    );
    final n = vm.Vector3(
      mesh.normals[vertex * 3],
      mesh.normals[vertex * 3 + 1],
      mesh.normals[vertex * 3 + 2],
    );
    final expected = vm.Vector3(p.x, p.y / 2.25, p.z / .25)..normalize();
    expect((n - expected).length, lessThan(1e-6));
    expect(n.x.abs(), greaterThan(.1));
    expect(n.z.abs(), greaterThan(.1));
    // All vertices of a crown must not receive a single flat lighting value.
    expect(
      {for (var i = 0; i < mesh.colors.length; i += 4) mesh.colors[i]}.length,
      greaterThan(12),
    );
  });
}

double _rendererWindingSign() {
  final reference = buildCuboidArrays(vm.Vector3.all(2));
  vm.Vector3 at(int i) => vm.Vector3(
    reference.positions[i * 3],
    reference.positions[i * 3 + 1],
    reference.positions[i * 3 + 2],
  );
  final a = reference.indices[0],
      b = reference.indices[1],
      c = reference.indices[2];
  final n = vm.Vector3(
    reference.normals![a * 3],
    reference.normals![a * 3 + 1],
    reference.normals![a * 3 + 2],
  );
  return (at(b) - at(a)).cross(at(c) - at(a)).dot(n).sign;
}

HomeLobbyBox _shapeBox(HomeLobbyShape shape, {double scale = 1}) =>
    HomeLobbyBox(
      'shape',
      x: 0,
      y: 0,
      z: 0,
      width: 2 * scale,
      height: 3 * scale,
      depth: scale,
      finish: HomeLobbyFinish.stone,
      shape: shape,
    );

HomeLobbyBox _box(String name, double x, {int? color, String zone = 'room'}) =>
    HomeLobbyBox(
      name,
      x: x,
      y: 1,
      z: 0,
      width: 2,
      height: 2,
      depth: 2,
      finish: HomeLobbyFinish.stone,
      color: color,
      zone: zone,
    );

Iterable<double> _rayDistances(
  vm.Ray ray,
  HomeArchitectureMeshData mesh,
) sync* {
  vm.Vector3 vertex(int index) => vm.Vector3(
    mesh.positions[index * 3],
    mesh.positions[index * 3 + 1],
    mesh.positions[index * 3 + 2],
  );
  for (var i = 0; i < mesh.indices.length; i += 3) {
    final distance = ray.intersectsWithTriangle(
      vm.Triangle.points(
        vertex(mesh.indices[i]),
        vertex(mesh.indices[i + 1]),
        vertex(mesh.indices[i + 2]),
      ),
    );
    if (distance != null && distance > 0) yield distance;
  }
}
