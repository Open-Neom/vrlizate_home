import 'dart:async';

import 'package:flutter/foundation.dart';

import 'vr_home_ecosystem_room.dart';
import 'vr_home_room_presentation.dart';

/// A null action requests the room's initial or refreshed presentation.
typedef VrHomeRoomPresenter =
    Future<VrHomeRoomPresentation> Function(
      VrHomeEcosystemRoom room,
      String? actionId,
    );

/// Coordinates a room's presentation while leaving services with its host.
///
/// Closing or invalidating a request prevents its result from being displayed.
/// The host remains responsible for cancelling work and revoking access itself.
class VrHomeRoomController extends ChangeNotifier {
  VrHomeRoomController({
    VrHomeRoomPresenter? callback,
    Listenable? roomChanges,
    VoidCallback? onInvalidated,
  }) : _callback = callback,
       _roomChanges = roomChanges,
       _onInvalidated = onInvalidated {
    _roomChanges?.addListener(_handleRoomChanges);
  }

  final VrHomeRoomPresenter? _callback;
  final Listenable? _roomChanges;
  final VoidCallback? _onInvalidated;

  VrHomeEcosystemRoom? _room;
  VrHomeRoomPresentation? _presentation;
  String? _error;
  bool _busy = false;
  bool _disposed = false;
  bool _needsHostInvalidation = false;
  int _generation = 0;

  VrHomeEcosystemRoom? get room => _room;
  VrHomeRoomPresentation? get presentation => _presentation;
  bool get busy => _busy;
  bool get isOpen => _room != null;
  String? get error => _error;

  void openRoom(VrHomeEcosystemRoom room) {
    if (_disposed) return;
    final replacesOpenRoom = _room != null;
    _room = room;
    unawaited(_load(invalidateHost: replacesOpenRoom));
  }

  /// Ignores unknown, disabled or obsolete actions and duplicate activations.
  Future<void> activate(String actionId) async {
    if (_disposed || _busy || _room == null) return;
    final available = _presentation?.actions.any(
      (action) => action.id == actionId && action.enabled,
    );
    if (available != true) return;
    await _load(actionId: actionId);
  }

  Future<void> retry() async {
    if (_disposed || _busy || _room == null) return;
    await _load();
  }

  void close() {
    if (_disposed || _room == null) return;
    _generation++;
    _room = null;
    _presentation = null;
    _error = null;
    _busy = false;
    notifyListeners();
  }

  void _handleRoomChanges() {
    if (_disposed || _room == null) return;
    unawaited(_load(invalidateHost: true));
  }

  Future<void> _load({String? actionId, bool invalidateHost = false}) async {
    final room = _room;
    if (_disposed || room == null) return;
    final generation = ++_generation;
    if (invalidateHost) _needsHostInvalidation = true;
    _presentation = null;
    _error = null;
    _busy = true;
    notifyListeners();
    if (!_isCurrent(generation)) return;

    try {
      // Replacements must revoke the previous host operation before reload.
      if (_needsHostInvalidation) _onInvalidated?.call();
      if (!_isCurrent(generation)) return;
      _needsHostInvalidation = false;
      final callback = _callback;
      final result = callback == null
          ? VrHomeRoomPresentation(
              title: room.title,
              description: room.description,
            )
          : await callback(room, actionId);
      if (!_isCurrent(generation)) return;
      _presentation = result;
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _error = 'No se pudo cargar la sala. Inténtalo de nuevo.';
    }
    if (!_isCurrent(generation)) return;
    _busy = false;
    notifyListeners();
  }

  bool _isCurrent(int generation) =>
      !_disposed && _room != null && generation == _generation;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _roomChanges?.removeListener(_handleRoomChanges);
    _room = null;
    _presentation = null;
    _error = null;
    _busy = false;
    super.dispose();
  }
}
