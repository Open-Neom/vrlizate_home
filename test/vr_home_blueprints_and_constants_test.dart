import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/vrlizate_home.dart';
import 'package:vrlizate_home/vrlizate_home_spatial.dart';

void main() {
  group('VrHomeZoneKind & VrHomeRoomBlueprint', () {
    test('validates room dimensions, computes floor area, and roundtrips JSON', () {
      const room = VrHomeRoomBlueprint(
        id: 'room_arcade',
        title: 'Neon Arcade Hall',
        subtitle: 'Retro 2.5D & NES cabinets',
        zoneKind: VrHomeZoneKind.arcadeHall,
        widthMeters: 12.0,
        depthMeters: 10.0,
        heightMeters: 4.5,
        accentColorArgb: 0xFF00F0FF,
        maxExhibits: 12,
        allowPortals: true,
        allowArcadeCabinets: true,
      );

      expect(room.isValid, isTrue);
      expect(room.floorAreaSquareMeters, closeTo(120.0, 1e-6));
      final restored = VrHomeRoomBlueprint.fromJson(room.toJson());
      expect(restored, equals(room));

      final invalidRoom = room.copyWith(widthMeters: 1.0);
      expect(invalidRoom.isValid, isFalse);
    });
  });

  group('VrHomeMallBlueprint', () {
    test('validates mall layout and detects missing spawn or duplicate rooms', () {
      const atrium = VrHomeRoomBlueprint(
        id: 'atrium',
        title: 'Central Atrium',
        zoneKind: VrHomeZoneKind.centralAtrium,
      );
      const sanctuary = VrHomeRoomBlueprint(
        id: 'sanctuary',
        title: 'Relaxation Sanctuary',
        zoneKind: VrHomeZoneKind.relaxationSanctuary,
      );

      final mall = VrHomeMallBlueprint(
        id: 'open_neom_plaza',
        title: 'Open Neom Plaza',
        subtitle: 'Main VRlizate Home Mall',
        corridorWidthMeters: 6.5,
        spawnRoomId: 'atrium',
        rooms: const <VrHomeRoomBlueprint>[atrium, sanctuary],
      );

      expect(mall.isValid, isTrue);
      expect(mall.validate(), isEmpty);
      expect(mall.findRoomById('sanctuary'), equals(sanctuary));
      expect(
        mall.roomsByZone(VrHomeZoneKind.centralAtrium),
        <VrHomeRoomBlueprint>[atrium],
      );

      final restoredMall = VrHomeMallBlueprint.fromJson(mall.toJson());
      expect(restoredMall.isValid, isTrue);
      expect(restoredMall.rooms.length, 2);

      final brokenMall = VrHomeMallBlueprint(
        id: 'broken_plaza',
        title: 'Broken Plaza',
        spawnRoomId: 'non_existent',
        rooms: const <VrHomeRoomBlueprint>[atrium, atrium],
      );
      expect(brokenMall.isValid, isFalse);
      expect(brokenMall.validate().length, greaterThanOrEqualTo(2));
    });
  });

  group('VrHomeTranslationConstants & VrHomeConstants', () {
    test('exposes non-empty translation and widget key constants', () {
      expect(VrHomeTranslationConstants.brandTitle, 'VRlizate');
      expect(VrHomeTranslationConstants.heroHeadline, isNotEmpty);
      expect(VrHomeTranslationConstants.visorTitle, isNotEmpty);
      expect(VrHomeTranslationConstants.controllerTitle, isNotEmpty);
      expect(VrHomeTranslationConstants.handheldTitle, isNotEmpty);
      expect(VrHomeConstants.startVisorKey, 'start_visor');
      expect(VrHomeConstants.startControllerKey, 'start_controller');
    });

    test(
      'initial Library spawn distance (4.8 m) is within mainMenuNearbyRadiusMeters for A/L actions and occludes background portals',
      () async {
        expect(
          VrHomeConstants.mainMenuNearbyRadiusMeters,
          greaterThanOrEqualTo(HomeSpatialMetrics.libraryDistance + 1.0),
        );

        final eye = vm.Vector3(0, 1.60, 0);
        final libraryPos = vm.Vector3(
          0,
          1.67,
          -HomeSpatialMetrics.libraryDistance,
        );
        expect(
          isHomeLibraryInFrontOfViewer(
            eyePosition: eye,
            viewerForward: vm.Vector3(0, 0, -1),
            libraryPosition: libraryPos,
            libraryVisible: true,
            libraryHiddenByUser: false,
          ),
          isTrue,
        );
        expect(
          isHomeLibraryInFrontOfViewer(
            eyePosition: eye,
            viewerForward: vm.Vector3(0, 0, 1),
            libraryPosition: libraryPos,
            libraryVisible: true,
            libraryHiddenByUser: false,
          ),
          isFalse,
        );
        expect(
          isHomeLibraryInFrontOfViewer(
            eyePosition: vm.Vector3(0, 1.60, 3.0),
            viewerForward: vm.Vector3(0, 0, -1),
            libraryPosition: libraryPos,
            libraryVisible: true,
            libraryHiddenByUser: false,
          ),
          isFalse,
          reason: '7.8 m exceeds mainMenuNearbyRadiusMeters (6.0 m)',
        );
        expect(
          isHomeLibraryInFrontOfViewer(
            eyePosition: eye,
            viewerForward: vm.Vector3(0, 0, -1),
            libraryPosition: libraryPos,
            libraryVisible: true,
            libraryHiddenByUser: true,
          ),
          isFalse,
        );

        final opened = <String>[];
        final panel = await VrDemoLibraryPanel.create(
          catalog: VrDemoCatalog(const <VrDemoLibraryEntry>[
            VrDemoLibraryEntry(
              id: 'riviera_rush',
              title: 'Riviera Rush VR',
              subtitle: 'Conducción costera',
              category: VrDemoLibraryCategory.games,
              accent: 0xFF00E5FF,
              icon: 'motorsport',
              featured: true,
            ),
          ]),
          onOpen: (entry) => opened.add(entry.id),
          onAction: (_) {},
          boxBuilder: (_, _, _, _) => Node(),
          surfaceBuilder: (_, _, _) async => Node(),
        );
        addTearDown(panel.dispose);

        // Horizontal gaze hits y_local = -0.0795 (inter-row gap) at t = 4.8 m.
        // Background portal at 12.0 m is occluded, closer object at 2.5 m is not.
        expect(
          panel.occludesRay(
            origin: eye,
            direction: vm.Vector3(0, 0, -1),
            maxDistance: 12.0,
          ),
          isTrue,
        );
        expect(
          panel.occludesRay(
            origin: eye,
            direction: vm.Vector3(0, 0, -1),
            maxDistance: 2.5,
          ),
          isFalse,
        );
        expect(
          panel.occludesRay(
            origin: eye,
            direction: vm.Vector3(0.75, 0, -0.66)..normalize(),
            maxDistance: 12.0,
          ),
          isFalse,
          reason: 'Ray aimed well beside the 3.94 * 0.88 panel is not occluded',
        );

        panel.activateFocused();
        expect(opened, <String>['riviera_rush']);
      },
    );
  });
}
