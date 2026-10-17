import '../../utils/constants/vr_home_constants.dart';
import '../../utils/enums/vr_home_zone_kind.dart';

/// Declarative room configuration blueprint for developers building custom
/// zones inside VRlizate Home.
class VrHomeRoomBlueprint {
  const VrHomeRoomBlueprint({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.zoneKind = VrHomeZoneKind.customRoom,
    this.widthMeters = VrHomeConstants.defaultRoomWidthMeters,
    this.depthMeters = VrHomeConstants.defaultRoomDepthMeters,
    this.heightMeters = VrHomeConstants.defaultRoomHeightMeters,
    this.accentColorArgb = VrHomeConstants.defaultAccentColorArgb,
    this.maxExhibits = VrHomeConstants.defaultMaxExhibits,
    this.allowPortals = true,
    this.allowArcadeCabinets = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final VrHomeZoneKind zoneKind;
  final double widthMeters;
  final double depthMeters;
  final double heightMeters;
  final int accentColorArgb;
  final int maxExhibits;
  final bool allowPortals;
  final bool allowArcadeCabinets;

  /// Floor surface area in square meters.
  double get floorAreaSquareMeters => widthMeters * depthMeters;

  /// Whether room identity, dimensions, and exhibit capacity are within bounds.
  bool get isValid =>
      id.trim().isNotEmpty &&
      title.trim().isNotEmpty &&
      widthMeters >= VrHomeConstants.minRoomDimensionMeters &&
      widthMeters <= VrHomeConstants.maxRoomDimensionMeters &&
      depthMeters >= VrHomeConstants.minRoomDimensionMeters &&
      depthMeters <= VrHomeConstants.maxRoomDimensionMeters &&
      heightMeters >= VrHomeConstants.minRoomDimensionMeters &&
      heightMeters <= VrHomeConstants.maxRoomDimensionMeters &&
      maxExhibits >= VrHomeConstants.minMaxExhibits &&
      maxExhibits <= VrHomeConstants.maxMaxExhibits;

  VrHomeRoomBlueprint copyWith({
    String? id,
    String? title,
    String? subtitle,
    VrHomeZoneKind? zoneKind,
    double? widthMeters,
    double? depthMeters,
    double? heightMeters,
    int? accentColorArgb,
    int? maxExhibits,
    bool? allowPortals,
    bool? allowArcadeCabinets,
  }) {
    return VrHomeRoomBlueprint(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      zoneKind: zoneKind ?? this.zoneKind,
      widthMeters: widthMeters ?? this.widthMeters,
      depthMeters: depthMeters ?? this.depthMeters,
      heightMeters: heightMeters ?? this.heightMeters,
      accentColorArgb: accentColorArgb ?? this.accentColorArgb,
      maxExhibits: maxExhibits ?? this.maxExhibits,
      allowPortals: allowPortals ?? this.allowPortals,
      allowArcadeCabinets: allowArcadeCabinets ?? this.allowArcadeCabinets,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    VrHomeConstants.keyId: id,
    VrHomeConstants.keyTitle: title,
    VrHomeConstants.keySubtitle: subtitle,
    VrHomeConstants.keyZoneKind: zoneKind.id,
    VrHomeConstants.keyWidthMeters: widthMeters,
    VrHomeConstants.keyDepthMeters: depthMeters,
    VrHomeConstants.keyHeightMeters: heightMeters,
    VrHomeConstants.keyAccentColorArgb: accentColorArgb,
    VrHomeConstants.keyMaxExhibits: maxExhibits,
    VrHomeConstants.keyAllowPortals: allowPortals,
    VrHomeConstants.keyAllowArcadeCabinets: allowArcadeCabinets,
  };

  factory VrHomeRoomBlueprint.fromJson(Map<String, Object?> json) {
    final widthRaw = json[VrHomeConstants.keyWidthMeters];
    final depthRaw = json[VrHomeConstants.keyDepthMeters];
    final heightRaw = json[VrHomeConstants.keyHeightMeters];
    final accentRaw = json[VrHomeConstants.keyAccentColorArgb];
    final maxExhibitsRaw = json[VrHomeConstants.keyMaxExhibits];
    return VrHomeRoomBlueprint(
      id: (json[VrHomeConstants.keyId] as String?) ?? '',
      title: (json[VrHomeConstants.keyTitle] as String?) ?? '',
      subtitle: (json[VrHomeConstants.keySubtitle] as String?) ?? '',
      zoneKind: VrHomeZoneKind.fromId(
        (json[VrHomeConstants.keyZoneKind] as String?) ?? '',
      ),
      widthMeters: widthRaw is num
          ? widthRaw.toDouble()
          : VrHomeConstants.defaultRoomWidthMeters,
      depthMeters: depthRaw is num
          ? depthRaw.toDouble()
          : VrHomeConstants.defaultRoomDepthMeters,
      heightMeters: heightRaw is num
          ? heightRaw.toDouble()
          : VrHomeConstants.defaultRoomHeightMeters,
      accentColorArgb: accentRaw is int
          ? accentRaw
          : VrHomeConstants.defaultAccentColorArgb,
      maxExhibits: maxExhibitsRaw is int
          ? maxExhibitsRaw
          : VrHomeConstants.defaultMaxExhibits,
      allowPortals: (json[VrHomeConstants.keyAllowPortals] as bool?) ?? true,
      allowArcadeCabinets:
          (json[VrHomeConstants.keyAllowArcadeCabinets] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VrHomeRoomBlueprint &&
          id == other.id &&
          title == other.title &&
          subtitle == other.subtitle &&
          zoneKind == other.zoneKind &&
          widthMeters == other.widthMeters &&
          depthMeters == other.depthMeters &&
          heightMeters == other.heightMeters &&
          accentColorArgb == other.accentColorArgb &&
          maxExhibits == other.maxExhibits &&
          allowPortals == other.allowPortals &&
          allowArcadeCabinets == other.allowArcadeCabinets;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    subtitle,
    zoneKind,
    widthMeters,
    depthMeters,
    heightMeters,
    accentColorArgb,
    maxExhibits,
    allowPortals,
    allowArcadeCabinets,
  );
}
