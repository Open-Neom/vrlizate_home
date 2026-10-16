import 'package:vrlizate_joystick/vrlizate_joystick.dart';

/// Touch aim is retained after release while offset. Centered, inactive input
/// returns pointing to head gaze (the controller's Vista mode).
/// IMU quaternions remain in the transport for steering and other clients, but
/// must never replace the viewer's retained touch aim in Home or a demo.
abstract final class VrPhonePointerPolicy {
  static bool isPointing(RemoteControllerState state) =>
      !state.isNeutralized &&
      (state.mode == RemoteControllerMode.laser ||
          state.laserSlideActive ||
          state.laserX.abs() > .015 ||
          state.laserY.abs() > .015);

  static void writePayload(
    Map<String, dynamic> payload,
    RemoteControllerState state,
  ) {
    payload['laserX'] = state.laserX;
    payload['laserY'] = state.laserY;
    payload['relativeToHead'] = true;
    payload.remove('orientation');
  }
}
