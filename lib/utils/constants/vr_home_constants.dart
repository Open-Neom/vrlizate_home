/// Constants for `vrlizate_home` widget keys, spatial zone identifiers,
/// and declarative room/mall blueprint validation limits.
abstract final class VrHomeConstants {
  static const String startNoticeKey = 'start_notice';
  static const String startVisorKey = 'start_visor';
  static const String startControllerKey = 'start_controller';
  static const String startEcosystemKey = 'start_ecosystem';
  static const String resumeControllerKey = 'resume_controller';
  static const String forgetControllerKey = 'forget_controller';
  static const String startBottomInfoCardKey = 'start_bottom_info_card';
  static const String startPhoneDemosKey = 'start_phone_demos';
  static const String startSettingsCardKey = 'start_settings_card';
  static const String robotoFontFamily = 'Roboto';

  static const String zoneCentralAtriumId = 'central_atrium';
  static const String zoneArcadeHallId = 'arcade_hall';
  static const String zoneAppGalleryId = 'app_gallery';
  static const String zoneWorldPortalBayId = 'world_portal_bay';
  static const String zoneRelaxationSanctuaryId = 'relaxation_sanctuary';
  static const String zoneCustomRoomId = 'custom_room';

  static const double defaultRoomWidthMeters = 8.0;
  static const double defaultRoomDepthMeters = 8.0;
  static const double defaultRoomHeightMeters = 4.2;
  static const double minRoomDimensionMeters = 2.5;
  static const double maxRoomDimensionMeters = 64.0;
  static const int defaultMaxExhibits = 8;
  static const int minMaxExhibits = 1;
  static const int maxMaxExhibits = 64;
  static const int defaultAccentColorArgb = 0xFF00E5FF;

  static const double defaultCorridorWidthMeters = 6.0;
  static const double minCorridorWidthMeters = 2.0;
  static const double maxCorridorWidthMeters = 24.0;
  static const int maxRoomsPerMall = 32;

  static const String keyId = 'id';
  static const String keyTitle = 'title';
  static const String keySubtitle = 'subtitle';
  static const String keyZoneKind = 'zoneKind';
  static const String keyWidthMeters = 'widthMeters';
  static const String keyDepthMeters = 'depthMeters';
  static const String keyHeightMeters = 'heightMeters';
  static const String keyAccentColorArgb = 'accentColorArgb';
  static const String keyMaxExhibits = 'maxExhibits';
  static const String keyAllowPortals = 'allowPortals';
  static const String keyAllowArcadeCabinets = 'allowArcadeCabinets';
  static const String keyCorridorWidthMeters = 'corridorWidthMeters';
  static const String keySpawnRoomId = 'spawnRoomId';
  static const String keyRooms = 'rooms';

  static const String portableWorldRoomPrefix = 'vrlw_room_';
  static const String portableWorldTag = 'worlds';
  static const int portableWorldDefaultAccent = 0xFF63E6BE;
  static const String worldPortalEnterActionId = 'enter_world';

  static const double mainMenuNearbyRadiusMeters = 4.5;
  static const double mainMenuMinForwardDot = 0.32;
  static const double mainMenuFallbackDistanceMeters = 2.45;

  static const String optionsActionId = 'options';
  static const String lookActionId = 'look';
  static const String qualityActionId = 'quality';
  static const String spatialSettingsActionId = 'spatial_settings';
  static const String recenterActionId = 'recenter';
  static const String optionsPanelName = 'vr_home_options';
}
