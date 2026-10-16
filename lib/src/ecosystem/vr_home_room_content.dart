import 'package:flutter/widgets.dart';

/// Host-owned presentation for a room's proportional world-space surface.
/// Services, access checks and data loading remain in the host application.
@immutable
class VrHomeRoomContent {
  const VrHomeRoomContent({required this.child, required this.logicalSize});

  final Widget child;
  final Size logicalSize;
}
