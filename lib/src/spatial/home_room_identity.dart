import '../ecosystem/vr_home_ecosystem_room.dart';

/// Architectural identity only. These labels do not assert remote availability.
class HomeRoomIdentity {
  const HomeRoomIdentity(this.category, this.floor, this.wall, this.furniture);

  final String category;
  final int floor, wall, furniture;

  static HomeRoomIdentity forPurpose(VrHomeRoomPurpose purpose) =>
      switch (purpose) {
        VrHomeRoomPurpose.avatar => const HomeRoomIdentity(
          'ESTUDIO DE AVATARES',
          0xFFABCAC5,
          0xFFD6E8E3,
          0xFF4F8B87,
        ),
        VrHomeRoomPurpose.profile => const HomeRoomIdentity(
          'GALERÍA PERSONAL',
          0xFFCAD8E1,
          0xFFCEDAE7,
          0xFF7693AD,
        ),
        VrHomeRoomPurpose.social => const HomeRoomIdentity(
          'ENCUENTROS Y COMUNIDAD',
          0xFFD4B99E,
          0xFFE3D6C7,
          0xFFB77650,
        ),
        VrHomeRoomPurpose.creation => const HomeRoomIdentity(
          'TALLER DE EXPERIENCIAS',
          0xFFBCC0C8,
          0xFFD9D4E4,
          0xFF807096,
        ),
        VrHomeRoomPurpose.reading => const HomeRoomIdentity(
          'LIBROS Y AUDIOLIBROS',
          0xFFC7A57A,
          0xFFE7D7B8,
          0xFF805E40,
        ),
        VrHomeRoomPurpose.music => const HomeRoomIdentity(
          'MÚSICA Y ESCUCHA',
          0xFF676271,
          0xFF847485,
          0xFF44394E,
        ),
        VrHomeRoomPurpose.meditation => const HomeRoomIdentity(
          'PAUSA Y BIENESTAR',
          0xFFBBC7AB,
          0xFFD8E3D0,
          0xFF879775,
        ),
        VrHomeRoomPurpose.cinema => const HomeRoomIdentity(
          'PANTALLA Y BUTACAS',
          0xFF615159,
          0xFF76606A,
          0xFF9C3E4F,
        ),
      };
}
