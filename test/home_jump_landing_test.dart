import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';

void main() {
  final space = HomeWalkSpace(
    rooms: const [HomeRoom('test', 'Test room', 4, 16, -8, 8)],
    boxes: const [
      HomeLobbyBox(
        'wall',
        x: 10,
        y: 1.5,
        z: 0,
        width: .2,
        height: 3,
        depth: 6,
        finish: HomeLobbyFinish.plaster,
      ),
    ],
  );

  test('cancelling in open floor preserves XZ and settles eye height', () {
    final current = vm.Vector3(12, 1.88, 2);
    final result = space.settleCancelledJump(
      current: current,
      jumpStart: vm.Vector3(6, 1.6, 2),
      lastSafe: vm.Vector3(11, 1.6, 2),
    )!;
    expect(result, vm.Vector3(12, 1.6, 2));
    expect(current.y, closeTo(1.88, 1e-6));
    expect(space.canStand(result.x, result.z), isTrue);
  });

  test('cancelling inside a wall uses the last traversable arc position', () {
    final result = space.settleCancelledJump(
      current: vm.Vector3(10, 1.88, 2),
      jumpStart: vm.Vector3(6, 1.6, 2),
      lastSafe: vm.Vector3(9.5, 1.6, 2),
    )!;
    expect(result, vm.Vector3(9.5, 1.6, 2));
    expect(space.canStand(result.x, result.z), isTrue);
    final moved = space.move(result, -.2, 0);
    expect(moved.x, lessThan(result.x));
  });

  test('a stale unsafe point falls back to this jump start', () {
    final result = space.settleCancelledJump(
      current: vm.Vector3(10, 1.88, 2),
      jumpStart: vm.Vector3(6, 1.6, 2),
      lastSafe: vm.Vector3(10, 1.6, 1),
    )!;
    expect(result, vm.Vector3(6, 1.6, 2));
    expect(space.canStand(result.x, result.z), isTrue);
  });

  test('no valid candidate never invents a global origin destination', () {
    expect(
      space.settleCancelledJump(
        current: vm.Vector3(10, 1.88, 2),
        jumpStart: vm.Vector3(10, 1.6, 1),
      ),
      isNull,
    );
  });
}
