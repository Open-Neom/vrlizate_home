/// Authored world distances, independent of the user's optical calibration.
/// Changing lens convergence must never pull a modal onto the user's face.
abstract final class HomeSpatialMetrics {
  static const double libraryDistance = 4.8;
  static const double modalDistance = 3.0;

  /// Comfortable deeper viewing distance for 3D communication, dialogue, and
  /// room panels so wide optical margins surround the card in both VR lenses
  /// and `1D` handheld view without overlapping side joysticks.
  static const double communicationDistance = 4.05;
}
