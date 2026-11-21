import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/vrlizate_home_spatial.dart';

void main() {
  group('Multi-elevation walkability (terraces, arched bridges, sunken bowls)', () {
    test('flat default HomeWalkSpace preserves y=0 and 1.60m eye height', () {
      final flat = HomeWalkSpace();
      expect(flat.groundHeightAt(0, 0), 0.0);
      expect(flat.eyeHeightAt(0, 0), closeTo(1.60, 1e-6));
    });

    test('terrace, smooth ramp, arched bridge, and radial sunken amphitheater interpolate smoothly', () {
      const rooms = <HomeRoom>[
        HomeRoom('pavilion', 'Pabellón', -20, 20, -20, 20),
      ];
      const elevations = <HomeWalkableElevation>[
        // North overlook terrace (+1.2 m)
        HomeWalkableElevation.terrace(
          id: 'north_overlook',
          minX: -6,
          maxX: 6,
          minZ: 10,
          maxZ: 16,
          elevationMeters: 1.2,
        ),
        // Smooth ramp climbing from 0.0 m -> +1.2 m along +Z
        HomeWalkableElevation.ramp(
          id: 'north_ramp',
          minX: -2,
          maxX: 2,
          minZ: 4,
          maxZ: 10,
          startElevationMeters: 0.0,
          endElevationMeters: 1.2,
          axis: HomeElevationAxis.posZ,
        ),
        // Arched Venetian/Kyoto bridge along +X (0 -> 0 with +1.5 m arch apex)
        HomeWalkableElevation.ramp(
          id: 'canal_bridge',
          minX: 6,
          maxX: 14,
          minZ: -2,
          maxZ: 2,
          startElevationMeters: 0.0,
          endElevationMeters: 0.0,
          axis: HomeElevationAxis.posX,
          archHeightMeters: 1.5,
        ),
        // Sunken social amphitheater bowl (-0.7 m center, smooth rim to 0.0 m)
        HomeWalkableElevation.radialBowl(
          id: 'sunken_court',
          centerX: -10,
          centerZ: 0,
          innerRadius: 2.0,
          outerRadius: 5.0,
          centerElevationMeters: -0.7,
        ),
      ];

      final space = HomeWalkSpace(
        rooms: rooms,
        boxes: const [],
        elevations: elevations,
      );

      // Terrace
      expect(space.groundHeightAt(0, 12), closeTo(1.2, 1e-6));
      expect(space.eyeHeightAt(0, 12), closeTo(2.8, 1e-6));

      // Smooth ramp endpoints and midpoint
      expect(space.groundHeightAt(0, 4.0), closeTo(0.0, 1e-6));
      expect(space.groundHeightAt(0, 7.0), closeTo(0.6, 1e-6));
      expect(space.groundHeightAt(0, 10.0), closeTo(1.2, 1e-6));

      // Arched bridge entry, exact mid-arch apex (+1.5 m), and exit
      expect(space.groundHeightAt(6.0, 0), closeTo(0.0, 1e-6));
      expect(space.groundHeightAt(10.0, 0), closeTo(1.5, 1e-6));
      expect(space.groundHeightAt(14.0, 0), closeTo(0.0, 1e-6));

      // Sunken circular amphitheater bowl
      expect(space.groundHeightAt(-10.0, 0), closeTo(-0.7, 1e-6));
      expect(space.groundHeightAt(-13.5, 0), closeTo(-0.35, 1e-6));
      expect(space.groundHeightAt(-15.0, 0), closeTo(0.0, 1e-6));

      // Walking onto the ramp elevates moved eye smoothly
      final moved = space.move(vm.Vector3(0, 1.60, 6.5), 0.0, 0.5);
      expect(moved.z, closeTo(7.0, 1e-5));
      expect(moved.y, closeTo(2.20, 1e-5));
    });

    test('parabolic jump and smoothVerticalEyeFollow bridge distinct elevations smoothly', () {
      final controller = VirtualHomeLocomotionController();
      controller.startJump(
        from: vm.Vector3(0, 0.90, 0), // sunken court (-0.7 + 1.6)
        to: vm.Vector3(0, 2.80, 12), // raised terrace (+1.2 + 1.6)
        targetName: 'Mirador Norte',
        duration: 1.0,
      );

      final (midPos, finishedMid, _) = controller.tick(
        0.5,
        vm.Vector3(0, 0.90, 0),
      );
      expect(finishedMid, isFalse);
      // Midpoint baseY = (0.90 + 2.80) / 2 = 1.85, plus +0.28 m parabolic apex
      expect(midPos.y, closeTo(1.85 + 0.28, 1e-5));

      final (endPos, finishedEnd, name) = controller.tick(0.5, midPos);
      expect(finishedEnd, isTrue);
      expect(name, 'Mirador Norte');
      expect(endPos.y, closeTo(2.80, 1e-5));

      // Smooth exponential damper avoids sudden single-frame vertical step jumps
      final damped = VirtualHomeLocomotionController.smoothVerticalEyeFollow(
        currentY: 1.60,
        targetGroundY: 1.20,
        dt: 1 / 60,
      );
      expect(damped, greaterThan(1.60));
      expect(damped, lessThan(2.00));
    });
  });
}
