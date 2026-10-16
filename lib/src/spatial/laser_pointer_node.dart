import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart' show CameraRig, VrControllerArmModel;

/// 3D laser pointer for the 2nd-smartphone remote, styled like a Quest 3
/// controller ray.
///
/// Renders:
/// 1. A miniature handheld controller body at the user's hand position.
/// 2. A **short emissive stub** leaving the controller that fades out within
///    [stubLength]. The beam is deliberately *not* drawn all the way to the
///    target: a full-length ray reads as a solid rod in stereo, hides what it
///    points at and wobbles with every 3DoF jitter.
/// 3. A **flat circular reticle** in the laser color on the surface being
///    pointed at, sized for a constant angular radius so it looks the same at
///    0.5 m and at 8 m, aligned to the surface (or to the viewer at grazing
///    angles) and shrunk while the trigger is held.
///
/// The host feeds the hit each frame with [setHit]; with nothing under the
/// ray only the stub is visible, exactly like an empty room on Quest.
class LaserPointerNode {
  final Node rootNode;
  final Node controllerMeshNode;
  final Node joystickKnobNode;

  /// Parent of the fading stub segments. Kept under its historical name.
  final Node laserBeamNode;

  /// The surface reticle. Kept under its historical name.
  final Node pointerDotNode;

  final List<PhysicallyBasedMaterial> _stubMats;
  final PhysicallyBasedMaterial _dotMat;
  final PhysicallyBasedMaterial _stickMat;
  final VrControllerArmModel _armModel = VrControllerArmModel();
  final vm.Vector3 _handPosition = vm.Vector3.zero();

  /// Visible length of the stub leaving the controller.
  static const double stubLength = 0.42;

  /// Alpha of each stub segment, hand → tip: the stub dissolves, it does not
  /// end with a cut.
  static const List<double> stubSegmentAlphas = [0.95, 0.55, 0.22];

  /// Reticle radius per meter of distance (≈ 0.7° of visual angle).
  static const double reticleRadiusPerMeter = 0.012;
  static const double reticleMinRadius = 0.006;
  static const double reticleMaxRadius = 0.16;

  /// Trigger-held shrink factor: the press is visible at the target.
  static const double reticlePressedScale = 0.7;

  /// Below this |normal · toViewer| the surface is seen edge-on and the
  /// reticle faces the viewer instead, so it never collapses to a line.
  static const double reticleGrazingCosine = 0.35;

  /// Lift off the surface to avoid z-fighting with what it sits on.
  static const double reticleSurfaceOffset = 0.006;

  /// Historical beam length, retained for callers that used it as a default
  /// pointing range. The rendered stub is [stubLength].
  static const double beamLength = 7.0;

  bool _beamActive = true;
  bool _visible = false;
  bool _hasHit = false;
  bool _triggerHeld = false;
  bool get visible => _visible;
  set visible(bool value) {
    _visible = value;
    rootNode.localTransform = value
        ? _lastTransform
        : vm.Matrix4.translation(vm.Vector3(0, -999, 0));
  }

  vm.Matrix4 _lastTransform = vm.Matrix4.identity();
  static final vm.Matrix4 _hidden = vm.Matrix4.translation(
    vm.Vector3(0, -999, 0),
  );

  LaserPointerNode._({
    required this.rootNode,
    required this.controllerMeshNode,
    required this.joystickKnobNode,
    required this.laserBeamNode,
    required this.pointerDotNode,
    required List<PhysicallyBasedMaterial> stubMats,
    required PhysicallyBasedMaterial dotMat,
    required PhysicallyBasedMaterial stickMat,
  }) : _stubMats = stubMats,
       _dotMat = dotMat,
       _stickMat = stickMat;

  /// Factory constructor initializing meshes and materials.
  factory LaserPointerNode() {
    PhysicallyBasedMaterial pbr(
      double r,
      double g,
      double b, {
      double roughness = 0.35,
      double metallic = 0.0,
      double emissive = 0.25,
      int depthLayer = 0,
    }) => PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(r, g, b, 1.0)
      ..emissiveFactor = vm.Vector4(
        r * emissive,
        g * emissive,
        b * emissive,
        1.0,
      )
      ..roughnessFactor = roughness
      ..metallicFactor = metallic
      ..depthLayer = depthLayer;

    Node boxPart(
      String name,
      vm.Vector3 size,
      vm.Vector3 pos,
      PhysicallyBasedMaterial mat,
    ) =>
        Node(name: name, mesh: Mesh(CuboidGeometry(size), mat))
          ..localTransform = vm.Matrix4.translation(pos)
          ..raycastable = false
          ..shadowCastingMode = ShadowCastingMode.off;

    // 1. Landscape Smartphone Chassis & OLED Screen (matches PhoneControllerPage)
    final controllerMat = pbr(
      0.08,
      0.11,
      0.18,
      roughness: 0.28,
      metallic: 0.88,
      emissive: 0.0,
    );
    final controllerNode = Node(
      name: 'remote_controller_body',
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(0.144, 0.010, 0.072)),
        controllerMat,
      ),
    )..raycastable = false;

    final screenMat = pbr(
      0.03,
      0.05,
      0.10,
      roughness: 0.14,
      metallic: 0.10,
      emissive: 0.08,
      depthLayer: 1,
    );
    controllerNode.add(
      boxPart(
        'remote_phone_screen',
        vm.Vector3(0.136, 0.002, 0.065),
        vm.Vector3(0, 0.0055, 0),
        screenMat,
      ),
    );

    // 1.a Ergonomic L / R / Y / X / B / A button bands around the stick wells
    // Local +X projects LEFT in flutter_scene when pointing along −Z.
    for (final (id, size, pos, mat) in [
      (
        'btn_l',
        vm.Vector3(0.034, 0.0022, 0.013),
        vm.Vector3(0.044, 0.0068, -0.022),
        pbr(0.00, 0.65, 0.71, depthLayer: 2),
      ),
      (
        'btn_r',
        vm.Vector3(0.034, 0.0022, 0.013),
        vm.Vector3(-0.044, 0.0068, -0.022),
        pbr(1.00, 0.57, 0.00, depthLayer: 2),
      ),
      (
        'btn_y',
        vm.Vector3(0.012, 0.0022, 0.026),
        vm.Vector3(0.060, 0.0068, 0.001),
        pbr(1.00, 0.84, 0.31, depthLayer: 2),
      ),
      (
        'btn_b',
        vm.Vector3(0.012, 0.0022, 0.026),
        vm.Vector3(-0.060, 0.0068, 0.001),
        pbr(1.00, 0.32, 0.32, depthLayer: 2),
      ),
      (
        'btn_x',
        vm.Vector3(0.034, 0.0022, 0.013),
        vm.Vector3(0.044, 0.0068, 0.023),
        pbr(0.16, 0.47, 1.00, depthLayer: 2),
      ),
      (
        'btn_a',
        vm.Vector3(0.034, 0.0022, 0.013),
        vm.Vector3(-0.044, 0.0068, 0.023),
        pbr(0.06, 0.73, 0.51, depthLayer: 2),
      ),
      (
        'center_panel',
        vm.Vector3(0.036, 0.0018, 0.056),
        vm.Vector3(0, 0.0064, 0),
        pbr(0.06, 0.09, 0.16, emissive: 0.10, depthLayer: 2),
      ),
      (
        'recenter_pill',
        vm.Vector3(0.030, 0.0024, 0.010),
        vm.Vector3(0, 0.0072, -0.016),
        pbr(0.88, 0.47, 0.08, emissive: 0.35, depthLayer: 3),
      ),
    ]) {
      controllerNode.add(boxPart('remote_$id', size, pos, mat));
    }

    // 1.b Dual thumbstick wells + interactive 3D left cyan knob & right orange knob
    final wellMat = pbr(
      0.06,
      0.08,
      0.16,
      roughness: 0.4,
      emissive: 0.05,
      depthLayer: 3,
    );
    final cyanRimMat = pbr(
      0.0,
      0.90,
      1.0,
      roughness: 0.2,
      emissive: 0.45,
      depthLayer: 2,
    );
    final orangeRimMat = pbr(
      1.0,
      0.57,
      0.0,
      roughness: 0.2,
      emissive: 0.45,
      depthLayer: 2,
    );
    final pipMat = pbr(
      1.0,
      1.0,
      1.0,
      roughness: 0.15,
      emissive: 0.60,
      depthLayer: 4,
    );

    for (final (tag, x, scale, rimMat) in [
      ('left', 0.038, 1.0, cyanRimMat),
      ('right', -0.038, 0.82, orangeRimMat),
    ]) {
      controllerNode.add(
        Node(
            name: 'remote_stick_rim_$tag',
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: 0.0165 * scale,
                topRadius: 0.0165 * scale,
                height: 0.0018,
              ),
              rimMat,
            ),
          )
          ..localTransform = vm.Matrix4.translation(vm.Vector3(x, 0.0066, 0.002))
          ..raycastable = false
          ..shadowCastingMode = ShadowCastingMode.off,
      );
      controllerNode.add(
        Node(
            name: 'remote_stick_well_$tag',
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: 0.0148 * scale,
                topRadius: 0.0148 * scale,
                height: 0.0022,
              ),
              wellMat,
            ),
          )
          ..localTransform = vm.Matrix4.translation(vm.Vector3(x, 0.0069, 0.002))
          ..raycastable = false
          ..shadowCastingMode = ShadowCastingMode.off,
      );
    }

    final stickMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.0, 0.9, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(0.0, 0.4, 0.8, 1.0)
      ..roughnessFactor = 0.2;

    final joystickKnob =
        Node(
            name: 'remote_joystick_knob',
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: 0.0085,
                topRadius: 0.010,
                height: 0.0055,
              ),
              stickMat,
            ),
          )
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(0.038, 0.010, 0.002),
          )
          ..raycastable = false
          ..add(
            Node(
                name: 'remote_joystick_pip',
                mesh: Mesh(
                  CylinderGeometry(
                    bottomRadius: 0.0032,
                    topRadius: 0.0032,
                    height: 0.0016,
                  ),
                  pipMat,
                ),
              )
              ..localTransform = vm.Matrix4.translation(
                vm.Vector3(0, 0.0032, 0),
              )
              ..raycastable = false
              ..shadowCastingMode = ShadowCastingMode.off,
          );

    final lookKnob =
        Node(
            name: 'remote_look_knob',
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: 0.0072,
                topRadius: 0.0085,
                height: 0.0050,
              ),
              orangeRimMat,
            ),
          )
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(-0.038, 0.0098, 0.002),
          )
          ..raycastable = false
          ..shadowCastingMode = ShadowCastingMode.off
          ..add(
            Node(
                name: 'remote_look_pip',
                mesh: Mesh(
                  CylinderGeometry(
                    bottomRadius: 0.0028,
                    topRadius: 0.0028,
                    height: 0.0014,
                  ),
                  pipMat,
                ),
              )
              ..localTransform = vm.Matrix4.translation(
                vm.Vector3(0, 0.0029, 0),
              )
              ..raycastable = false
              ..shadowCastingMode = ShadowCastingMode.off,
          );

    controllerNode
      ..add(joystickKnob)
      ..add(lookKnob);

    // 2. Fading stub: three translucent emissive segments along −Z.
    final stubRoot = Node(name: 'remote_laser_beam')..raycastable = false;
    final stubMats = <PhysicallyBasedMaterial>[];
    final segment = stubLength / stubSegmentAlphas.length;
    for (var i = 0; i < stubSegmentAlphas.length; i++) {
      final mat = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.0, 0.95, 1.0, stubSegmentAlphas[i])
        ..emissiveFactor = vm.Vector4(0.0, 0.95, 1.0, 1.0)
        ..roughnessFactor = 0.05
        ..alphaMode = AlphaMode.blend;
      stubMats.add(mat);
      final taper = 1 - i / stubSegmentAlphas.length;
      stubRoot.add(
        Node(
            name: 'remote_laser_stub_$i',
            mesh: Mesh(
              CylinderGeometry(
                bottomRadius: 0.0032 * (0.6 + 0.4 * taper),
                topRadius: 0.0026 * (0.5 + 0.5 * taper),
                height: segment,
              ),
              mat,
            ),
          )
          ..localTransform = (vm.Matrix4.translation(
            vm.Vector3(0, 0, -(i + 0.5) * segment),
          )..rotateX(math.pi / 2))
          ..raycastable = false,
      );
    }

    // 3. Surface reticle: a unit disc (radius 1, wafer thin), scaled per hit.
    final dotMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.6, 1.0, 1.0, 0.95)
      ..emissiveFactor = vm.Vector4(0.2, 1.2, 1.5, 1.0)
      ..roughnessFactor = 0.0
      ..alphaMode = AlphaMode.blend;

    final reticle =
        Node(
            name: 'remote_pointer_dot',
            mesh: Mesh(
              CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 0.004),
              dotMat,
            ),
          )
          ..localTransform = _hidden.clone()
          ..raycastable = false;

    final root = Node(name: 'laser_pointer_root')
      ..add(controllerNode)
      ..add(stubRoot)
      ..add(reticle);

    // Initially hidden until connected
    root.localTransform = vm.Matrix4.translation(vm.Vector3(0, -999, 0));

    return LaserPointerNode._(
      rootNode: root,
      controllerMeshNode: controllerNode,
      joystickKnobNode: joystickKnob,
      laserBeamNode: stubRoot,
      pointerDotNode: reticle,
      stubMats: stubMats,
      dotMat: dotMat,
      stickMat: stickMat,
    );
  }

  /// Sets whether the ray is emitted (laser mode) or hidden (joystick mode).
  void setLaserBeamActive(bool active) {
    if (_beamActive == active) return;
    _beamActive = active;
    laserBeamNode.localTransform = active
        ? vm.Matrix4.identity()
        : _hidden.clone();
    if (!active) {
      _hasHit = false;
      pointerDotNode.localTransform = _hidden.clone();
    }
  }

  /// Updates 3D mini-joystick knob deflection on top of the phone mesh.
  void setStickDeflection(double x, double y) {
    joystickKnobNode.localTransform = vm.Matrix4.translation(
      vm.Vector3(0.038 - x * 0.009, 0.010, 0.002 - y * 0.009),
    );
  }

  /// Places the reticle on the surface the ray touches, or hides it.
  ///
  /// [point] and [normal] are world space (the normal facing the ray origin,
  /// as `SceneRaycastHit.worldNormal` reports); [eye] is the viewer's eye
  /// center, used for the constant angular size and the grazing fallback.
  /// Call after [update] each frame so the reticle is expressed in the
  /// controller's current frame.
  void setHit({
    required vm.Vector3? point,
    vm.Vector3? normal,
    required vm.Vector3 eye,
  }) {
    if (point == null || !_beamActive) {
      if (_hasHit) pointerDotNode.localTransform = _hidden.clone();
      _hasHit = false;
      return;
    }
    _hasHit = true;
    final toViewer = eye - point;
    final distance = toViewer.length;
    final axis = reticleAxis(normal: normal, toViewer: toViewer);
    final radius = reticleRadius(distance, pressed: _triggerHeld);
    final world = reticleWorldTransform(
      point: point,
      axis: axis,
      radius: radius,
    );
    // Express in the controller's frame: the reticle is a child of the root.
    final inverse = _lastTransform.clone()..invert();
    pointerDotNode.localTransform = inverse * world;
  }

  /// Reticle radius for a target at [distance]: a constant visual angle,
  /// clamped so it never vanishes up close nor covers a far wall.
  static double reticleRadius(double distance, {bool pressed = false}) {
    if (!distance.isFinite) return reticleMinRadius;
    final r = (distance * reticleRadiusPerMeter).clamp(
      reticleMinRadius,
      reticleMaxRadius,
    );
    return pressed ? r * reticlePressedScale : r;
  }

  /// Disc axis: the surface normal when the surface is seen frontally
  /// enough, otherwise the direction to the viewer so a grazing hit does not
  /// collapse the disc into a line. Always unit length.
  static vm.Vector3 reticleAxis({
    required vm.Vector3? normal,
    required vm.Vector3 toViewer,
  }) {
    final view = toViewer.length2 > 1e-12
        ? toViewer.normalized()
        : vm.Vector3(0, 0, 1);
    if (normal == null || normal.length2 < 1e-12) return view;
    final n = normal.normalized();
    // Face the viewer's side of the surface.
    final oriented = n.dot(view) < 0 ? -n : n;
    return oriented.dot(view).abs() < reticleGrazingCosine ? view : oriented;
  }

  /// World transform of a unit disc lying on [point], its axis along [axis],
  /// scaled to [radius] and lifted [reticleSurfaceOffset] off the surface.
  static vm.Matrix4 reticleWorldTransform({
    required vm.Vector3 point,
    required vm.Vector3 axis,
    required double radius,
  }) {
    final y = axis.normalized();
    // Any perpendicular pair completes the basis; pick a stable helper.
    final helper = y.y.abs() < 0.9 ? vm.Vector3(0, 1, 0) : vm.Vector3(1, 0, 0);
    final x = helper.cross(y)..normalize();
    final z = y.cross(x)..normalize();
    final position = point + y * reticleSurfaceOffset;
    final m = vm.Matrix4.identity();
    m.setColumn(0, vm.Vector4(x.x * radius, x.y * radius, x.z * radius, 0));
    m.setColumn(1, vm.Vector4(y.x, y.y, y.z, 0));
    m.setColumn(2, vm.Vector4(z.x * radius, z.y * radius, z.z * radius, 0));
    m.setColumn(3, vm.Vector4(position.x, position.y, position.z, 1));
    return m;
  }

  /// Computes the forward ray and hand position from the eye center and controller orientation.
  static (vm.Vector3, vm.Vector3) computeRay({
    required vm.Vector3 eyeCenter,
    required vm.Quaternion orientation,
  }) {
    final handOffset = vm.Vector3(0.22, -0.42, -0.28);
    final handPosition = eyeCenter + handOffset;
    final forwardDir = orientation.rotate(vm.Vector3(0, 0, -1)).normalized();
    return (handPosition, forwardDir);
  }

  /// Updates the 3D position and orientation of the controller and stub.
  ///
  /// Returns the forward pointing ray: [origin, direction]. Follow with
  /// [setHit] once the ray has been cast against the scene.
  (vm.Vector3, vm.Vector3) update({
    required CameraRig cameraRig,
    required vm.Quaternion orientation,
    vm.Vector3? forwardDirection,
    double? rangeMeters,
    bool isTriggerPressed = false,
    double dt = 1 / 60,
  }) {
    _armModel.update(
      cameraRig: cameraRig,
      controllerOrientation: orientation,
      dt: dt,
      out: _handPosition,
    );

    // If explicit range distance is provided, modulate distance from camera
    if (rangeMeters != null && rangeMeters > 0.1 && rangeMeters < 3.0) {
      final eyePos = cameraRig.position;
      final armVector = _handPosition - eyePos;
      if (armVector.length2 > 1e-4) {
        final currentDist = armVector.length;
        final scale = rangeMeters / currentDist;
        _handPosition.setFrom(eyePos + (armVector * scale));
      }
    }

    final forwardDir =
        forwardDirection ??
        orientation.rotate(vm.Vector3(0, 0, -1)).normalized();

    // Compose local transform matrix: Translation * Rotation
    final transform = vm.Matrix4.compose(
      _handPosition,
      orientation,
      vm.Vector3.all(1.0),
    );

    _lastTransform = transform;
    if (_visible) {
      rootNode.localTransform = transform;
    }

    // Trigger pulse: the stub, the reticle and the knob turn magenta/gold.
    _triggerHeld = isTriggerPressed;
    for (var i = 0; i < _stubMats.length; i++) {
      final alpha = stubSegmentAlphas[i];
      if (isTriggerPressed) {
        _stubMats[i].emissiveFactor = vm.Vector4(1.0, 0.1, 0.6, 1.0);
        _stubMats[i].baseColorFactor = vm.Vector4(1.0, 0.2, 0.7, alpha);
      } else {
        _stubMats[i].emissiveFactor = vm.Vector4(0.0, 0.95, 1.0, 1.0);
        _stubMats[i].baseColorFactor = vm.Vector4(0.0, 0.95, 1.0, alpha);
      }
    }
    if (isTriggerPressed) {
      _dotMat.emissiveFactor = vm.Vector4(1.5, 0.2, 0.8, 1.0);
      _dotMat.baseColorFactor = vm.Vector4(1.0, 0.6, 0.9, 0.95);
      _stickMat.emissiveFactor = vm.Vector4(1.0, 0.2, 0.8, 1.0);
    } else {
      _dotMat.emissiveFactor = vm.Vector4(0.2, 1.2, 1.5, 1.0);
      _dotMat.baseColorFactor = vm.Vector4(0.6, 1.0, 1.0, 0.95);
      _stickMat.emissiveFactor = vm.Vector4(0.0, 0.4, 0.8, 1.0);
    }

    return (_handPosition, forwardDir);
  }
}
