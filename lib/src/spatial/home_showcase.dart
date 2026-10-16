import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'home_ecosystem_layout.dart';
import 'home_lobby_layout.dart';

/// Authored, bundled graphics pilot. This does not relax the static .vrlw
/// import profile or execute downloaded animation code.
final class HomeShowcase extends SceneTickListener {
  HomeShowcase({
    required this.scene,
    required Node parent,
    required HomeEcosystemPortal portal,
    required HomeLobbyBox platform,
    required HomeLobbyBox lounge,
    required Node actorFallback,
  }) : _parent = parent,
       _platform = platform,
       _side = portal.side,
       _actorFallback = actorFallback,
       center = vm.Vector3(platform.x, 1.6, portal.z) {
    root.add(actorFallback);
    final stageTopY = platform.y + platform.height / 2;
    final stagePlinth = Node(name: 'showcase_stage_plinth')
      ..localTransform = vm.Matrix4.translationValues(
        platform.x,
        stageTopY,
        platform.z,
      )
      ..add(
        Node(
          name: 'showcase_stage_rim',
          mesh: Mesh(
            CylinderGeometry(topRadius: .86, bottomRadius: .90, height: .010),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(.08, .12, .14, 1)
              ..roughnessFactor = .72
              ..metallicFactor = .12
              ..depthLayer = 1,
          ),
        )..localTransform = vm.Matrix4.translationValues(0, -.005, 0),
      )
      ..add(
        Node(
          name: 'showcase_stage_mat',
          mesh: Mesh(
            CylinderGeometry(topRadius: .74, bottomRadius: .76, height: .004),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(.04, .065, .08, 1)
              ..roughnessFactor = .88
              ..metallicFactor = .04
              ..depthLayer = 2,
          ),
        )..localTransform = vm.Matrix4.translationValues(0, -.001, 0),
      );
    _disablePicking(stagePlinth);
    _markStatic(stagePlinth);
    root.add(stagePlinth);

    final loungeFallback = Node(name: 'showcase_lounge_fallback')
      ..localTransform = vm.Matrix4.translationValues(lounge.x, .38, lounge.z)
      ..add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(1.3, .42, .65)),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(.15, .24, .22, 1)
              ..roughnessFactor = .85,
          ),
        ),
      );
    root.add(loungeFallback);
    // Bounded local lights with a 2.3:1 key-to-fill ratio so curved avatar
    // silhouettes model cleanly without extra shadow-map passes.
    for (final offset in [-1.5, 1.5]) {
      final isKey = offset < 0;
      final light = SpotLight(
        color: isKey ? vm.Vector3(1, .90, .78) : vm.Vector3(.68, .82, 1),
        intensity: isKey ? 10.5 : 4.6,
        range: 5.5,
        direction: vm.Vector3(-portal.side * 1.2, -2.4, -offset).normalized(),
        innerConeAngle: isKey ? .32 : .38,
        outerConeAngle: isKey ? .76 : .84,
      );
      root.add(
        Node(name: 'showcase_softbox_$offset')
          ..addComponent(SpotLightComponent(light))
          ..localTransform = vm.Matrix4.translationValues(
            platform.x + portal.side * 1.2,
            3.6,
            platform.z + offset,
          ),
      );
    }
    root.visible = false;
    scene.addTickListener(this);
    ready = Future.wait([
      _loadActor(platform, portal.side, actorFallback),
      _loadLounge(lounge, loungeFallback),
    ]).then((_) {});
  }

  static const robotAsset =
      'packages/vrlizate_home/assets/showcase/robot_expressive.glb';
  static const loungeAsset =
      'packages/vrlizate_home/assets/showcase/lounge.glb';
  // Bounds, license and reproducible measurements are beside the source GLB.
  static const robotScale = .411402412;
  static const robotFloorOffset = .020304421325820776 * robotScale;
  static final _templates = VrGlbTemplateCache(maxEntries: 2);

  /// Drops retained templates on memory pressure; mounted clones keep their
  /// resources. Future Home instances can import the bundled files again.
  static void clearAssetCache() => _templates.clear();

  final Scene scene;
  final Node _parent, _actorFallback;
  final HomeLobbyBox _platform;
  final double _side;
  final vm.Vector3 center;
  final Node root = Node(name: 'home_authored_showcase');
  final List<String> _loadErrors = [];
  late final Future<void> ready;
  VrActorAnimation? _animation;
  VrAvatarNode? _avatar;
  Node? _robotPlacement, _avatarPlacement;
  VrAvatarDetail _detail = VrAvatarDetail.far;
  bool _disposed = false;
  bool _near = false;
  bool _manualPose = false;
  VrActorAction _poseAction = VrActorAction.idle;
  double _poseSeconds = 0;
  double _cycle = 0;

  List<String> get loadErrors => List.unmodifiable(_loadErrors);
  VrActorAnimation? get animation => _animation;
  bool get active => _near && !_disposed;

  Future<void> _loadActor(
    HomeLobbyBox platform,
    double side,
    Node fallback,
  ) async {
    try {
      final model = await _templates.instantiate(robotAsset);
      if (_disposed) return;
      final animation = VrActorAnimation(actor: model, autoplay: false);
      final placement = Node(name: 'showcase_robot_placement')
        ..localTransform =
            vm.Matrix4.translationValues(
                  platform.x,
                  platform.y + platform.height / 2 + robotFloorOffset,
                  platform.z,
                )
                .multiplied(vm.Matrix4.rotationY(side * math.pi / 2))
                .multiplied(
                  vm.Matrix4.diagonal3Values(
                    robotScale,
                    robotScale,
                    robotScale,
                  ),
                )
        ..add(model);
      _disablePicking(placement);
      _robotPlacement = placement;
      if (_avatar == null) root.add(placement);
      fallback.visible = false;
      _animation = animation;
      if (_manualPose) {
        showPose(_poseAction, _poseSeconds);
      } else if (_near && _avatar == null) {
        _greet();
      }
    } catch (error) {
      if (_disposed) return;
      _loadErrors.add('robot: $error');
      debugPrint('Home showcase robot kept fallback: $error');
    }
  }

  Future<void> _loadLounge(HomeLobbyBox bounds, Node fallback) async {
    try {
      final model = await _templates.instantiate(loungeAsset);
      if (_disposed) return;
      final placement = Node(name: 'showcase_lounge_placement')
        ..localTransform = vm.Matrix4.translationValues(bounds.x, 0, bounds.z)
        ..add(model);
      _disablePicking(placement);
      _markStatic(placement);
      root.add(placement);
      fallback.visible = false;
    } catch (error) {
      if (_disposed) return;
      _loadErrors.add('lounge: $error');
      debugPrint('Home showcase lounge kept fallback: $error');
    }
  }

  static void _disablePicking(Node node) {
    node.raycastable = false;
    for (final child in node.children) {
      _disablePicking(child);
    }
  }

  static void _markStatic(Node node) {
    node.shadowStatic = true;
    for (final child in node.children) {
      _markStatic(child);
    }
  }

  /// Live semantic edits from the host. Profile identity and persistence stay
  /// outside Home. Materials are owned by this avatar, never by GLB templates.
  void setAppearance(VrAvatarAppearance? appearance) {
    if (_disposed) return;
    if (appearance == null) {
      // A session may publish the neutral appearance more than once. Scene
      // rejects adding a child that already belongs to this root.
      if (_avatar == null) return;
      _avatarPlacement?.parent?.remove(_avatarPlacement!);
      _avatarPlacement = null;
      _avatar?.dispose();
      _avatar = null;
      if (_robotPlacement case final placement?) {
        if (placement.parent != root) root.add(placement);
      }
      _actorFallback.visible = _robotPlacement == null;
      if (_near && !_manualPose) _greet();
      return;
    }
    _animation?.pause();
    _robotPlacement?.parent?.remove(_robotPlacement!);
    _actorFallback.visible = false;
    if (_avatar case final avatar?) {
      avatar.updateAppearance(appearance);
      return;
    }
    final avatar = VrAvatarNode(appearance: appearance, detail: _detail);
    _avatar = avatar;
    final placement = Node(name: 'showcase_personal_avatar')
      ..localTransform = vm.Matrix4.translationValues(
        _platform.x,
        _platform.y + _platform.height / 2,
        _platform.z,
      ).multiplied(vm.Matrix4.rotationY(-_side * math.pi / 2))
      ..add(avatar.root);
    _disablePicking(placement);
    _avatarPlacement = placement;
    root.add(placement);
  }

  /// Hysteresis avoids starting/stopping when standing on a distance boundary.
  /// Hidden Scene nodes skip animation evaluation and render-item refresh.
  void observe(vm.Vector3 eye) {
    if (_disposed) return;
    final distance = eye.distanceToSquared(center);
    final detail = distance < (_detail == VrAvatarDetail.near ? 12 * 12 : 8 * 8)
        ? VrAvatarDetail.near
        : VrAvatarDetail.far;
    if (detail != _detail) {
      _detail = detail;
      _avatar?.setDetail(detail);
    }
    final near = distance < (_near ? 22 * 22 : 18 * 18);
    if (near == _near) return;
    _near = near;
    root.visible = near;
    if (near) {
      _parent.add(root);
    } else {
      root.parent?.remove(root);
    }
    if (near && !_manualPose && _avatar == null) {
      _greet();
    } else {
      _animation?.pause();
    }
  }

  void _greet() {
    _cycle = 0;
    _animation?.play(VrActorAction.wave, restart: true);
    _animation?.resume();
  }

  /// Reproducible authoring capture, using the real skeleton and clip time.
  /// Regular Home never calls this; it runs the proximity demonstration.
  void showPose(VrActorAction action, double seconds) {
    if (!seconds.isFinite) throw ArgumentError.value(seconds, 'seconds');
    _manualPose = true;
    _poseAction = action;
    _poseSeconds = seconds;
    _animation?.play(action, restart: true, transitionSeconds: 0);
    _animation?.seek(seconds);
    _animation?.pause();
  }

  void resumeDemonstration() {
    _manualPose = false;
    if (_near && _avatar == null) _greet();
  }

  @override
  void beforeTick(double deltaSeconds) {
    if (_disposed || !_near || _manualPose || !deltaSeconds.isFinite) return;
    if (_avatar case final avatar?) {
      avatar.tick(deltaSeconds.clamp(0.0, .1));
      return;
    }
    final animation = _animation;
    if (animation == null) return;
    final dt = deltaSeconds.clamp(0.0, .1);
    animation.tick(dt);
    _cycle += dt;
    // Walking is authored in place: the actor remains on its reserved stage.
    final phase = _cycle % 16;
    if (phase >= 7 && phase < 11) {
      animation.play(VrActorAction.walk);
    } else if (animation.action == VrActorAction.walk) {
      animation.play(VrActorAction.idle);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scene.removeTickListener(this);
    _animation?.dispose();
    _animation = null;
    _avatar?.dispose();
    _avatar = null;
    root.parent?.remove(root);
  }
}
