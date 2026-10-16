import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/spatial/home_lobby_layout.dart';
import 'package:vrlizate_home/src/spatial/home_walk_space.dart';
import 'package:vrlizate_home/src/spatial/virtual_home_locomotion_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Scene vectors use float32 storage; accumulated metres allow 0.1 mm drift.

  vm.Vector3 step(
    VirtualHomeLocomotionController controller,
    vm.Vector3 position, {
    double x = 0,
    double y = 1,
    double dt = .1,
    HomeWalkSpace? space,
  }) => controller.applySmoothLocomotion(
    currentEyeCenter: position,
    headOrientation: vm.Quaternion.identity(),
    stickX: x,
    stickY: y,
    dt: dt,
    speed: 1.6,
    maxSpeed: 4.8,
    accelerationSeconds: 2.4,
    maxRadius: 1000,
    walkSpace: space,
  );

  vm.Vector3 accelerate(VirtualHomeLocomotionController controller) {
    var position = vm.Vector3(0, 1.6, 0);
    for (var frame = 0; frame < 24; frame++) {
      position = step(controller, position);
    }
    return position;
  }

  test('firm held stick ramps smoothly and caps at three times base speed', () {
    final controller = VirtualHomeLocomotionController();
    var position = vm.Vector3(0, 1.6, 0);
    var previousSpeed = 1.6;
    for (var frame = 0; frame < 60; frame++) {
      position = step(controller, position);
      expect(controller.currentWalkSpeed, greaterThanOrEqualTo(previousSpeed));
      expect(controller.currentWalkSpeed, lessThanOrEqualTo(4.8 + 1e-6));
      expect(position.y, closeTo(1.6, 1e-6));
      if (frame == 0) {
        expect(controller.currentWalkSpeed, lessThan(1.8));
        expect(position.z, closeTo(-1.0 / 6, 1e-6));
      }
      previousSpeed = controller.currentWalkSpeed;
    }
    expect(controller.currentWalkSpeed, closeTo(4.8, 1e-6));
  });

  test('travel distance is equal at 30, 60 and 120 Hz', () {
    for (final hz in [30, 60, 120]) {
      final controller = VirtualHomeLocomotionController();
      var position = vm.Vector3(0, 1.6, 0);
      for (var frame = 0; frame < hz * 4; frame++) {
        position = step(controller, position, dt: 1 / hz);
      }
      // 2.4s averaging 3.2m/s, then 1.6s at 4.8m/s.
      expect(position.z, closeTo(-15.36, 1e-4), reason: '$hz Hz');
    }
  });

  test('light stick stays precise, including immediately after a fast run', () {
    final controller = VirtualHomeLocomotionController();
    var position = accelerate(controller);
    final start = position.clone();
    for (var frame = 0; frame < 40; frame++) {
      position = step(controller, position, y: .5);
    }
    expect(start.z - position.z, closeTo(3.2, 1e-4));
    expect(controller.currentWalkSpeed, closeTo(.8, 1e-6));
    final resumed = step(controller, position);
    expect(position.z - resumed.z, closeTo(1.0 / 6, 1e-6));
  });

  test(
    'gentle BLE movement survives shaping and never builds running speed',
    () {
      final controller = VirtualHomeLocomotionController();
      var position = vm.Vector3(0, 1.6, 0);
      expect(
        step(controller, position, x: 1 / 127, y: 1 / 127),
        same(position),
      );
      expect(controller.currentWalkSpeed, 0);
      for (var frame = 0; frame < 40; frame++) {
        position = step(controller, position, y: 2 / 127);
      }
      expect(position.z, closeTo(-1.6 * (2 / 127) * 4, 1e-6));
      expect(controller.currentWalkSpeed, closeTo(1.6 * (2 / 127), 1e-9));
      expect(step(controller, position, y: 0), same(position));
      expect(controller.currentWalkSpeed, 0);
    },
  );

  test('neutral stops immediately and the next movement starts slowly', () {
    final controller = VirtualHomeLocomotionController();
    final position = accelerate(controller);
    expect(step(controller, position, y: 0), same(position));
    expect(controller.currentWalkSpeed, 0);
    expect(position.z - step(controller, position).z, closeTo(1.0 / 6, 1e-6));
  });

  test(
    'reverse or sudden strafe does not inherit the forward running speed',
    () {
      for (final input in [(0.0, -1.0), (1.0, 0.0)]) {
        final controller = VirtualHomeLocomotionController();
        final position = accelerate(controller);
        final moved = step(controller, position, x: input.$1, y: input.$2);
        expect((moved - position).length, closeTo(1.0 / 6, 1e-6));
        expect(controller.currentWalkSpeed, lessThan(1.8));
      }
    },
  );

  test(
    'B/suspension stops in place until stick release and resets the boost',
    () {
      final controller = VirtualHomeLocomotionController();
      final position = accelerate(controller)..x = 5;
      controller.cancelJump(); // same operation used by Home B
      expect(controller.currentWalkSpeed, 0);
      for (var frame = 0; frame < 20; frame++) {
        expect(step(controller, position), same(position));
      }
      final (after, arrived, name) = controller.tick(.1, position);
      expect(after, same(position));
      expect(arrived, isFalse);
      expect(name, isNull);
      expect(after.x, 5);
      expect(after.z, closeTo(-7.68, 1e-4));
      step(controller, position, y: 0);
      expect(position.z - step(controller, position).z, closeTo(1.0 / 6, 1e-6));
    },
  );

  test('cancelling an arc holds its current location without arriving', () {
    final controller = VirtualHomeLocomotionController();
    final start = vm.Vector3(5, 1.6, 6);
    controller.startJump(
      from: start,
      to: vm.Vector3(10, 1.6, 0),
      targetName: 'Another room',
      duration: 1,
    );
    final (midpoint, _, _) = controller.tick(.5, start);
    controller.cancelJump();
    final (after, arrived, name) = controller.tick(1, midpoint);
    expect(after, same(midpoint));
    expect(after.x, closeTo(7.5, 1e-6));
    expect(after.z, closeTo(3, 1e-6));
    expect(arrived, isFalse);
    expect(name, isNull);
    expect(step(controller, midpoint), same(midpoint));
    expect(controller.currentWalkSpeed, 0);
  });

  test('diagonal travel has the same speed budget as straight travel', () {
    final straight = VirtualHomeLocomotionController();
    final diagonal = VirtualHomeLocomotionController();
    var a = vm.Vector3(0, 1.6, 0);
    var b = a.clone();
    for (var frame = 0; frame < 40; frame++) {
      a = step(straight, a);
      b = step(diagonal, b, x: 1);
    }
    expect(vm.Vector2(b.x, b.z).length, closeTo(a.z.abs(), 1e-4));
    expect(b.x, lessThan(0)); // renderer screen-right
  });

  test(
    'accelerated collision travel cannot cross a thin wall or bank speed',
    () {
      final space = HomeWalkSpace(
        rooms: const [HomeRoom('test', 'Test', -100, 100, -100, 100)],
        boxes: const [
          HomeLobbyBox(
            'wall',
            x: 0,
            y: 1.5,
            z: -2,
            width: 10,
            height: 3,
            depth: .1,
            finish: HomeLobbyFinish.plaster,
          ),
        ],
      );
      final controller = VirtualHomeLocomotionController();
      var position = vm.Vector3(0, 1.6, 0);
      for (var frame = 0; frame < 60; frame++) {
        position = step(controller, position, space: space);
        expect(space.canStand(position.x, position.z), isTrue);
        expect(position.z, greaterThanOrEqualTo(-1.7 - 1e-6));
      }
      expect(controller.currentWalkSpeed, 0);
      final moved = step(controller, position, y: -1, space: space);
      expect(moved.z - position.z, closeTo(1.0 / 6, 1e-6));
    },
  );

  test('stalled/invalid frames cannot grant an instant speed boost', () {
    final controller = VirtualHomeLocomotionController();
    final start = vm.Vector3(0, 1.6, 0);
    final moved = step(controller, start, dt: 10);
    expect(start.z - moved.z, closeTo(1.0 / 6, 1e-6));
    expect(step(controller, moved, dt: double.infinity), same(moved));
    expect(controller.currentWalkSpeed, 0);
  });
}
