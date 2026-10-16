import 'package:vector_math/vector_math.dart' as vm;

/// A dismissed portal cannot reopen under an unchanged gaze. Moving the
/// viewing direction at least six degrees rearms it; elapsed time alone does
/// not. The direction is copied because a rig's vectors may be mutable.
class PortalGazeRearm {
  static const double _releaseDot = 0.9945218953682733;
  final vm.Vector3 _dismissedDirection = vm.Vector3.zero();
  String? _blockedId;

  String? get blockedId => _blockedId;

  void block(String portalId, vm.Vector3 forward) {
    if (forward.length2 < 1e-10) return;
    _blockedId = portalId;
    _dismissedDirection.setFrom(forward);
    _dismissedDirection.normalize();
  }

  void update(vm.Vector3 forward) {
    if (_blockedId == null || forward.length2 < 1e-10) return;
    final dot = _dismissedDirection.dot(forward) / forward.length;
    if (dot < _releaseDot) _blockedId = null;
  }

  bool allows(String portalId) => _blockedId != portalId;
}
