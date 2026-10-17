import '../../utils/constants/vr_home_constants.dart';
import '../../utils/enums/vr_home_zone_kind.dart';
import 'vr_home_room_blueprint.dart';

/// Declarative mall/lobby layout configuration for VRlizate Home with
/// structural and duplicate-room validation.
class VrHomeMallBlueprint {
  VrHomeMallBlueprint({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.corridorWidthMeters = VrHomeConstants.defaultCorridorWidthMeters,
    required this.spawnRoomId,
    required List<VrHomeRoomBlueprint> rooms,
  }) : rooms = List<VrHomeRoomBlueprint>.unmodifiable(rooms);

  final String id;
  final String title;
  final String subtitle;
  final double corridorWidthMeters;
  final String spawnRoomId;
  final List<VrHomeRoomBlueprint> rooms;

  /// Validates the mall layout, returning a list of human-readable issues
  /// (empty when valid).
  List<String> validate() {
    final issues = <String>[];
    if (id.trim().isEmpty) {
      issues.add('Mall id must not be empty.');
    }
    if (title.trim().isEmpty) {
      issues.add('Mall title must not be empty.');
    }
    if (corridorWidthMeters < VrHomeConstants.minCorridorWidthMeters ||
        corridorWidthMeters > VrHomeConstants.maxCorridorWidthMeters) {
      issues.add('Corridor width is out of bounds.');
    }
    if (rooms.isEmpty) {
      issues.add('Mall must contain at least one room.');
    }
    if (rooms.length > VrHomeConstants.maxRoomsPerMall) {
      issues.add('Mall exceeds maximum rooms limit.');
    }
    final seenIds = <String>{};
    for (final room in rooms) {
      if (!room.isValid) {
        issues.add('Invalid room blueprint: "${room.id}".');
      }
      if (!seenIds.add(room.id)) {
        issues.add('Duplicate room id: "${room.id}".');
      }
    }
    if (!seenIds.contains(spawnRoomId)) {
      issues.add('spawnRoomId "$spawnRoomId" does not match any room.');
    }
    return List<String>.unmodifiable(issues);
  }

  /// Whether [validate] reports zero structural issues.
  bool get isValid => validate().isEmpty;

  /// Looks up a room blueprint by [roomId], or returns `null`.
  VrHomeRoomBlueprint? findRoomById(String roomId) {
    for (final room in rooms) {
      if (room.id == roomId) {
        return room;
      }
    }
    return null;
  }

  /// Returns all room blueprints matching [zoneKind].
  List<VrHomeRoomBlueprint> roomsByZone(VrHomeZoneKind zoneKind) =>
      List<VrHomeRoomBlueprint>.unmodifiable(
        rooms.where((room) => room.zoneKind == zoneKind),
      );

  Map<String, Object?> toJson() => <String, Object?>{
    VrHomeConstants.keyId: id,
    VrHomeConstants.keyTitle: title,
    VrHomeConstants.keySubtitle: subtitle,
    VrHomeConstants.keyCorridorWidthMeters: corridorWidthMeters,
    VrHomeConstants.keySpawnRoomId: spawnRoomId,
    VrHomeConstants.keyRooms: rooms.map((room) => room.toJson()).toList(),
  };

  factory VrHomeMallBlueprint.fromJson(Map<String, Object?> json) {
    final corridorRaw = json[VrHomeConstants.keyCorridorWidthMeters];
    final rawRooms = json[VrHomeConstants.keyRooms];
    final parsedRooms = <VrHomeRoomBlueprint>[];
    if (rawRooms is List) {
      for (final item in rawRooms) {
        if (item is Map<String, Object?>) {
          parsedRooms.add(VrHomeRoomBlueprint.fromJson(item));
        } else if (item is Map) {
          parsedRooms.add(
            VrHomeRoomBlueprint.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }
    return VrHomeMallBlueprint(
      id: (json[VrHomeConstants.keyId] as String?) ?? '',
      title: (json[VrHomeConstants.keyTitle] as String?) ?? '',
      subtitle: (json[VrHomeConstants.keySubtitle] as String?) ?? '',
      corridorWidthMeters: corridorRaw is num
          ? corridorRaw.toDouble()
          : VrHomeConstants.defaultCorridorWidthMeters,
      spawnRoomId: (json[VrHomeConstants.keySpawnRoomId] as String?) ?? '',
      rooms: parsedRooms,
    );
  }
}
