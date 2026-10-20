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
}

class VrHomeEcosystemRoom {
  const VrHomeEcosystemRoom({
    required this.id,
    required this.title,
    required this.description,
    required this.accent,
    required this.icon,
    required this.purpose,
  });

  final String id, title, description;
  final int accent;
  final VrHomeRoomIcon icon;
  final VrHomeRoomPurpose purpose;

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
