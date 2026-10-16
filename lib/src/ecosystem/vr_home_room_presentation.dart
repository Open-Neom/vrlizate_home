import 'package:flutter/foundation.dart';

/// Host-owned content that a Home room can display without owning its services.
@immutable
class VrHomeRoomPresentation {
  VrHomeRoomPresentation({
    required this.title,
    this.subtitle = '',
    this.description = '',
    List<VrHomeRoomAction> actions = const [],
  }) : actions = List<VrHomeRoomAction>.unmodifiable(actions) {
    final ids = <String>{};
    for (final action in this.actions) {
      if (action.id.trim().isEmpty || !ids.add(action.id)) {
        throw ArgumentError.value(
          action.id,
          'actions',
          'Action IDs must be nonempty and unique.',
        );
      }
    }
  }

  final String title;
  final String subtitle;
  final String description;
  final List<VrHomeRoomAction> actions;
}

/// An opaque host action. Home forwards only enabled, currently visible IDs.
@immutable
class VrHomeRoomAction {
  const VrHomeRoomAction({
    required this.id,
    required this.label,
    this.enabled = true,
  });

  final String id;
  final String label;
  final bool enabled;
}
