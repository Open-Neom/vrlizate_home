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
    this.isForLease = false,
    this.boothCode,
    this.doorBadge,
    this.terminalActionLabel,
  });

  const VrHomeEcosystemRoom.portableWorld({
    required this.id,
    required this.title,
    String? description,
    this.accent = VrHomeConstants.portableWorldDefaultAccent,
    this.targetRouteId,
    this.isForLease = false,
    this.boothCode,
    this.doorBadge,
    this.terminalActionLabel,
  }) : description =
           description ?? VrHomeTranslationConstants.portableWorldDefaultSubtitle,
       icon = VrHomeRoomIcon.world,
       purpose = VrHomeRoomPurpose.portableWorld;

  /// Commercial storefront ("puesto / local") currently available for rent to
  /// host a `.vrlz` or `.vrlw` experience inside a Famous Mall / Plaza.
  const VrHomeEcosystemRoom.forLease({
    required this.id,
    required this.title,
    required this.description,
    required String this.boothCode,
    this.accent = 0xFFF59E0B,
    this.targetRouteId,
    String? doorBadge,
    String? terminalActionLabel,
  }) : icon = VrHomeRoomIcon.studio,
       purpose = VrHomeRoomPurpose.creation,
       isForLease = true,
       doorBadge = doorBadge ?? 'EN RENTA · ESPACIO .VRLZ',
       terminalActionLabel =
           terminalActionLabel ?? 'A · Ficha en renta / Demo';

  final String id, title, description;
  final int accent;
  final VrHomeRoomIcon icon;
  final VrHomeRoomPurpose purpose;
  final String? targetRouteId;
  final bool isForLease;
  final String? boothCode;
  final String? doorBadge;
  final String? terminalActionLabel;

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

  /// Opt-in gateway to architectural digital-twin Plazas & Famous Malls where
  /// each booth hosts a VR experience and vacant booths are marked "EN RENTA".
  static const famousMalls = VrHomeEcosystemRoom(
    id: 'famous_malls',
    title: 'Plazas y Malls Famosos',
    description:
        'Duplicados 3D de Milán, Artz México, Dubái y Marina Bay con puestos VR y espacios EN RENTA.',
    accent: 0xFFF59E0B,
    icon: VrHomeRoomIcon.world,
    purpose: VrHomeRoomPurpose.creation,
    doorBadge: 'PLAZAS VR · LOCALES EN RENTA',
    terminalActionLabel: 'A · Viajar a Plazas Famosas',
  );

  /// Opt-in Multiplex pavilion for free 24/7 linear FAST channels, public-domain
  /// & official YouTube films/series, and verified external FAST portals.
  static const freeStreamingTv = VrHomeEcosystemRoom(
    id: 'free_streaming_tv',
    title: 'Multiplex TV & Cine Gratis',
    description:
        'Canales 24/7 con guía EPG en vivo, cine UNAM/clásico, series y portales FAST (Pluto TV, Tubi, ViX).',
    accent: 0xFF00E5FF,
    icon: VrHomeRoomIcon.movie,
    purpose: VrHomeRoomPurpose.cinema,
    doorBadge: 'TV GRATIS 24/7 · EPG EN VIVO',
    terminalActionLabel: 'A · Entrar a TV & Cine Gratis',
  );

  /// Opt-in flagship commercial storefront inside the main Grand Plaza showing
  /// visitors how rentable spaces host interactive HTTPS VR domains & `.vrlz` apps.
  static const rentableDomainShowcase = VrHomeEcosystemRoom.forLease(
    id: 'rentable_domain_vr',
    boothCode: 'VR-01',
    title: 'Local EN RENTA · Tu Dominio VR',
    description:
        'Visualiza tu propio dominio web (.com) de forma interactiva en VR o monta tu experiencia .vrlz aquí.',
    accent: 0xFFF59E0B,
    doorBadge: '★ EN RENTA · TU DOMINIO .COM EN VR',
    terminalActionLabel: 'A · Probar tu dominio web aquí',
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
