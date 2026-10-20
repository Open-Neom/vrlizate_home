import '../../utils/constants/vr_home_constants.dart';
import '../../utils/constants/vr_home_translation_constants.dart';
import '../spatial/vr_demo_library_model.dart';

/// Portable room metadata. Routes, identity, content and permissions belong to
/// the host; a room does not imply that a remote service has been connected.
enum VrHomeRoomPurpose {
  profile,
  social,
  creation,
  reading,
  music,
  meditation,
  cinema,
  avatar,
  openSourceGames,
  portableWorld,
}

enum VrHomeRoomIcon {
  person,
  forum,
  studio,
  book,
  music,
  spa,
  movie,
  avatar,
  gamepad,
  world,
}

class VrHomeEcosystemRoom {
  const VrHomeEcosystemRoom({
    required this.id,
    required this.title,
    required this.description,
    required this.accent,
    required this.icon,
    required this.purpose,
    this.targetRouteId,
  });

  const VrHomeEcosystemRoom.portableWorld({
    required this.id,
    required this.title,
    String? description,
    this.accent = VrHomeConstants.portableWorldDefaultAccent,
    this.targetRouteId,
  }) : description =
           description ?? VrHomeTranslationConstants.portableWorldDefaultSubtitle,
       icon = VrHomeRoomIcon.world,
       purpose = VrHomeRoomPurpose.portableWorld;

  final String id, title, description;
  final int accent;
  final VrHomeRoomIcon icon;
  final VrHomeRoomPurpose purpose;
  final String? targetRouteId;

  /// Dynamically expands the Mall room inventory with a dedicated 3D storefront
  /// ("local") for every `.vrlw` / `worlds` entry in [catalogEntries].
  static List<VrHomeEcosystemRoom> expandWithWorldCatalog(
    Iterable<VrHomeEcosystemRoom> baseRooms,
    Iterable<VrDemoLibraryEntry> catalogEntries,
  ) {
    final result = <VrHomeEcosystemRoom>[...baseRooms];
    if (result.isEmpty) return const [];
    final existingIds = <String>{for (final room in result) room.id};
    final existingRoutes = <String>{
      for (final room in result)
        if (room.targetRouteId != null) room.targetRouteId!,
    };
    for (final entry in catalogEntries) {
      final isWorldPackage = entry.tags.contains(VrHomeConstants.portableWorldTag);
      if (!isWorldPackage || existingRoutes.contains(entry.id)) continue;
      final sanitized = entry.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final candidateId = '${VrHomeConstants.portableWorldRoomPrefix}$sanitized';
      if (!existingIds.add(candidateId)) continue;
      existingRoutes.add(entry.id);
      result.add(
        VrHomeEcosystemRoom.portableWorld(
          id: candidateId,
          title: entry.title,
          description: entry.subtitle.isNotEmpty
              ? entry.subtitle
              : VrHomeTranslationConstants.portableWorldDefaultSubtitle,
          accent: entry.accent,
          targetRouteId: entry.id,
        ),
      );
    }
    return List<VrHomeEcosystemRoom>.unmodifiable(result);
  }

  /// Opt-in gallery. The host supplies the game catalog, availability,
  /// attribution links and launchers; this metadata does not install a runtime.
  static const openSourceGames = VrHomeEcosystemRoom(
    id: 'open_source_games',
    title: 'Juegos Open Source',
    description: 'Explora juegos de la comunidad y conoce a sus creadores.',
    accent: 0xFFB6A0FF,
    icon: VrHomeRoomIcon.gamepad,
    purpose: VrHomeRoomPurpose.openSourceGames,
  );

  static const defaults = <VrHomeEcosystemRoom>[
    VrHomeEcosystemRoom(
      id: 'profile',
      title: 'Mi perfil',
      description: 'Tu identidad y tu espacio personal.',
      accent: 0xFF85BAFF,
      icon: VrHomeRoomIcon.person,
      purpose: VrHomeRoomPurpose.profile,
    ),
    VrHomeEcosystemRoom(
      id: 'social',
      title: 'Muro social',
      description: 'Encuentros, publicaciones y comunidad.',
      accent: 0xFFF0B878,
      icon: VrHomeRoomIcon.forum,
      purpose: VrHomeRoomPurpose.social,
    ),
    VrHomeEcosystemRoom(
      id: 'creator',
      title: 'Estudio creador',
      description: 'Prepara tus experiencias y proyectos .vrlz.',
      accent: 0xFFC8AAFF,
      icon: VrHomeRoomIcon.studio,
      purpose: VrHomeRoomPurpose.creation,
    ),
    VrHomeEcosystemRoom(
      id: 'emxi',
      title: 'EMXI',
      description: 'Un lugar para libros y audiolibros.',
      accent: 0xFFE3CB91,
      icon: VrHomeRoomIcon.book,
      purpose: VrHomeRoomPurpose.reading,
    ),
    VrHomeEcosystemRoom(
      id: 'gigmeout',
      title: 'Gigmeout',
      description: 'Descubre música y espacios para escuchar.',
      accent: 0xFFF49AAF,
      icon: VrHomeRoomIcon.music,
      purpose: VrHomeRoomPurpose.music,
    ),
    VrHomeEcosystemRoom(
      id: 'cyberneom',
      title: 'Cyberneom',
      description: 'Un espacio para meditación y bienestar.',
      accent: 0xFF8AE4CC,
      icon: VrHomeRoomIcon.spa,
      purpose: VrHomeRoomPurpose.meditation,
    ),
    VrHomeEcosystemRoom(
      id: 'cinema',
      title: 'Cine VR',
      description: 'Una gran pantalla y un espacio de cine dentro de VR.',
      accent: 0xFFFFD18A,
      icon: VrHomeRoomIcon.movie,
      purpose: VrHomeRoomPurpose.cinema,
    ),
    VrHomeEcosystemRoom(
      id: 'avatar',
      title: 'Mi avatar',
      description:
          'Diseña tu presencia virtual y tus preferencias de convivencia.',
      accent: 0xFF7EF0DD,
      icon: VrHomeRoomIcon.avatar,
      purpose: VrHomeRoomPurpose.avatar,
    ),
  ];
}
