/// Authored world distances, independent of the user's optical calibration.
/// Changing lens convergence must never pull a modal onto the user's face.
abstract final class HomeSpatialMetrics {
  static const double libraryDistance = 4.8;
  static const double modalDistance = 3.0;
}
