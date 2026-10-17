import '../constants/vr_home_constants.dart';

/// Architectural zone classifications inside the VRlizate Home spatial lobby.
enum VrHomeZoneKind {
  centralAtrium,
  arcadeHall,
  appGallery,
  worldPortalBay,
  relaxationSanctuary,
  customRoom;

  /// Stable identifier for serialization and blueprint definitions.
  String get id => switch (this) {
    VrHomeZoneKind.centralAtrium => VrHomeConstants.zoneCentralAtriumId,
    VrHomeZoneKind.arcadeHall => VrHomeConstants.zoneArcadeHallId,
    VrHomeZoneKind.appGallery => VrHomeConstants.zoneAppGalleryId,
    VrHomeZoneKind.worldPortalBay => VrHomeConstants.zoneWorldPortalBayId,
    VrHomeZoneKind.relaxationSanctuary =>
      VrHomeConstants.zoneRelaxationSanctuaryId,
    VrHomeZoneKind.customRoom => VrHomeConstants.zoneCustomRoomId,
  };

  /// Resolves a [VrHomeZoneKind] from [id], defaulting to [customRoom].
  static VrHomeZoneKind fromId(String id) {
    for (final kind in VrHomeZoneKind.values) {
      if (kind.id == id || kind.name == id) {
        return kind;
      }
    }
    return VrHomeZoneKind.customRoom;
  }
}
