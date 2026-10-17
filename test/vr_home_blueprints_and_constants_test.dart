import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

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
  });
}
