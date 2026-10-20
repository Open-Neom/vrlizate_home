import 'package:flutter/material.dart';

import '../ecosystem/vr_home_ecosystem_room.dart';
import '../theme/vr_home_theme.dart';

/// Accessible, non-GPU entrance to host-supplied ecosystem rooms.
class VrHomeEcosystemLobby extends StatefulWidget {
  const VrHomeEcosystemLobby({
    super.key,
    this.rooms = VrHomeEcosystemRoom.defaults,
    required this.onOpenRoom,
    this.theme = VrHomeThemeData.aurora,
    this.onBack,
    this.onExperiences,
    this.unavailableReasons = const {},
  });

  final List<VrHomeEcosystemRoom> rooms;
  final Future<void> Function(VrHomeEcosystemRoom) onOpenRoom;
  final VrHomeThemeData theme;
  final VoidCallback? onBack, onExperiences;
  final Map<String, String> unavailableReasons;

  @override
  State<VrHomeEcosystemLobby> createState() => _VrHomeEcosystemLobbyState();
}

class _VrHomeEcosystemLobbyState extends State<VrHomeEcosystemLobby> {
  String? _opening, _failed;

  Future<void> _open(VrHomeEcosystemRoom room) async {
    if (_opening != null || widget.unavailableReasons.containsKey(room.id)) {
      return;
    }
    setState(() {
      _opening = room.id;
      _failed = null;
    });
    try {
      await widget.onOpenRoom(room);
    } catch (_) {
      if (mounted) setState(() => _failed = room.title);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Theme(
      data: theme.materialTheme,
      child: Scaffold(
        backgroundColor: theme.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (widget.onBack != null)
                          TextButton.icon(
                            key: const ValueKey('ecosystem_back'),
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('Inicio'),
                          ),
                        if (widget.onExperiences != null)
                          OutlinedButton.icon(
                            key: const ValueKey('ecosystem_experiences'),
                            onPressed: _opening == null
                                ? widget.onExperiences
                                : null,
                            icon: const Icon(Icons.view_in_ar_rounded),
                            label: const Text('Explorar experiencias'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Tu casa en VRlizate',
                      style: theme.materialTheme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Elige una habitación. Puedes entrar desde tu teléfono, sin visor.',
                      style: TextStyle(color: theme.muted, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    if (_failed != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          'No se pudo abrir $_failed. Inténtalo de nuevo.',
                          key: const ValueKey('ecosystem_open_error'),
                          style: TextStyle(
                            color: theme.materialTheme.colorScheme.error,
                          ),
                        ),
                      ),
                    if (widget.rooms.isEmpty)
                      const Text(
                        'Este anfitrión todavía no ofrece habitaciones.',
                      ),
                    LayoutBuilder(
                      builder: (_, constraints) {
                        final columns = constraints.maxWidth >= 900
                            ? 3
                            : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 16) /
                            columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final room in widget.rooms)
                              SizedBox(width: width, child: _card(room)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(VrHomeEcosystemRoom room) {
    final reason = widget.unavailableReasons[room.id];
    final theme = widget.theme;
    return Card(
      color: theme.surface,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon(room.icon), color: Color(room.accent), size: 32),
            const SizedBox(height: 18),
            Text(room.title, style: theme.materialTheme.textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              room.description,
              style: TextStyle(color: theme.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            if (reason != null) ...[
              Text(reason, style: TextStyle(color: theme.muted)),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              key: ValueKey('ecosystem_room_${room.id}'),
              onPressed: _opening == null && reason == null
                  ? () => _open(room)
                  : null,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                _opening == room.id ? 'Abriendo…' : 'Entrar a ${room.title}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(VrHomeRoomIcon icon) => switch (icon) {
    VrHomeRoomIcon.gamepad => Icons.sports_esports_outlined,
    VrHomeRoomIcon.avatar => Icons.accessibility_new_rounded,
    VrHomeRoomIcon.person => Icons.person_outline_rounded,
    VrHomeRoomIcon.forum => Icons.forum_outlined,
    VrHomeRoomIcon.studio => Icons.design_services_outlined,
    VrHomeRoomIcon.book => Icons.menu_book_rounded,
    VrHomeRoomIcon.music => Icons.headphones_rounded,
    VrHomeRoomIcon.spa => Icons.spa_outlined,
    VrHomeRoomIcon.movie => Icons.movie_outlined,
    VrHomeRoomIcon.world => Icons.public_rounded,
  };
}
