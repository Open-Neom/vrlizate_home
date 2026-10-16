import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'demo_preview_data.dart';

/// Optional alternate/headless text backend; placement and hit policy stay
/// owned by the panel, regardless of the returned node's name or transform.
typedef DemoPreviewTextNodeBuilder =
    Future<Node> Function(String text, String? actionName);

/// Immutable world-space pose used by the demo confirmation panel.
///
/// The pose is calculated once when the user opens a portal. It deliberately
/// does not follow subsequent head movement: the panel occupies a real place
/// in the scene and the gaze ray moves over it.
class DemoPreviewWorldPose {
  const DemoPreviewWorldPose._({
    required this.center,
    required this.yaw,
    required this.right,
    required this.up,
    required this.normal,
  });

  final vm.Vector3 center;
  final double yaw;
  final vm.Vector3 right;
  final vm.Vector3 up;
  final vm.Vector3 normal;

  factory DemoPreviewWorldPose.fromViewer({
    required vm.Vector3 eye,
    required vm.Vector3 forward,
    double distance = 1.8,
  }) {
    final direction = forward.clone();
    if (direction.length2 < 0.0001) direction.setValues(0, 0, -1);
    direction.normalize();

    // Authored distance is independent of lens convergence. The vertical clamp
    // prevents an extreme sensor pose from placing it below the floor or far
    // overhead; its complete billboard basis still faces the opening pose.
    final center = eye + direction * distance;
    center.y = center.y.clamp(0.55, 2.65);
    final toViewer = eye - center;
    if (toViewer.length2 < 0.0001) toViewer.setValues(0, 0, 1);
    toViewer.normalize();

    // Build a roll-free billboard basis. Unlike a yaw-only panel this remains
    // readable and raycastable when the visor is aimed upward or downward.
    final right = vm.Vector3(0, 1, 0).cross(toViewer);
    if (right.length2 < 0.0001) right.setValues(1, 0, 0);
    right.normalize();
    final up = toViewer.cross(right);
    up.normalize();
    final yaw = math.atan2(toViewer.x, toViewer.z);
    return DemoPreviewWorldPose._(
      center: center,
      yaw: yaw,
      right: right,
      up: up,
      normal: toViewer,
    );
  }

  vm.Vector3 localToWorld(double x, double y, double z) {
    return center + right * x + up * y + normal * z;
  }

  vm.Matrix4 transformAt(double x, double y, double z) {
    final origin = localToWorld(x, y, z);
    return vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(right.x, right.y, right.z, 0))
      ..setColumn(1, vm.Vector4(up.x, up.y, up.z, 0))
      ..setColumn(2, vm.Vector4(normal.x, normal.y, normal.z, 0))
      ..setColumn(3, vm.Vector4(origin.x, origin.y, origin.z, 1));
  }
}

/// A confirmation card made entirely from flutter_scene nodes.
///
/// Unlike a Flutter overlay, this panel stays fixed in world space. Its two
/// buttons are normal gaze/laser raycast targets and can also be focused with
/// a joystick before pressing A/trigger.
class DemoPreviewWorldPanel {
  DemoPreviewWorldPanel._({
    required this.data,
    required this.pose,
    required this.onEnter,
    required this.onBack,
    required Node plate,
    required VrButton3D enterButton,
    required VrButton3D backButton,
    required List<Node> labels,
  }) : _plate = plate,
       _enterButton = enterButton,
       _backButton = backButton,
       _labels = labels {
    _registry.register(_enterButton);
    _registry.register(_backButton);
    _nodes = List.unmodifiable([
      _plate,
      ..._enterButton.nodes,
      ..._backButton.nodes,
      ..._labels,
    ]);
    for (final node in _enterButton.nodes) {
      _actionByNode[node] = 0;
    }
    for (final node in _backButton.nodes) {
      _actionByNode[node] = 1;
    }
    _actionByNode[_labels[4]] = 0;
    _actionByNode[_labels[5]] = 1;
    setFocusedIndex(0);
  }

  static const String enterNodeName = 'demo_preview_enter';
  static const String backNodeName = 'demo_preview_back';

  final DemoPreviewData data;
  DemoPreviewWorldPose pose;
  final VoidCallback onEnter;
  final VoidCallback onBack;
  final Node _plate;
  final VrButton3D _enterButton;
  final VrButton3D _backButton;
  final List<Node> _labels;
  late final List<Node> _nodes;
  final Map<Node, int> _actionByNode = Map<Node, int>.identity();
  final VrControlRegistry _registry = VrControlRegistry();

  static const List<double> _labelY = [0.42, 0.25, 0.07, -0.13, -0.32, -0.60];

  int _focusedIndex = 0;
  int? _lastHoveredIndex;
  int get focusedIndex => _focusedIndex;
  String get focusedLabel =>
      _focusedIndex == 0 ? 'Entrar al demo' : 'Volver al Home';

  List<Node> get nodes => _nodes;

  /// True only for the two actionable modal targets (including their labels).
  bool ownsInteractiveNode(Node node) => _actionByNode.containsKey(node);

  static Future<DemoPreviewWorldPanel> create({
    required DemoPreviewData data,
    required DemoPreviewWorldPose pose,
    required VoidCallback onEnter,
    required VoidCallback onBack,
    VrControlMeshBuilder? meshBuilder,
    DemoPreviewTextNodeBuilder? textNodeBuilder,
  }) async {
    final accent = vm.Vector4(data.color.r, data.color.g, data.color.b, 1);
    final plateMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.025, 0.035, 0.075, 0.98)
      ..metallicFactor = 0.55
      ..roughnessFactor = 0.22
      ..emissiveFactor = vm.Vector4(
        data.color.r * 0.07,
        data.color.g * 0.07,
        data.color.b * 0.07,
        0,
      );
    final plate =
        Node(
            // The backdrop never builds dwell progress; only actual actions do.
            name: '',
            mesh:
                meshBuilder?.call() ??
                Mesh(
                  CuboidGeometry(vm.Vector3(1.78, 1.40, 0.055)),
                  plateMaterial,
                ),
          )
          ..raycastable = false
          ..localTransform = pose.transformAt(0, -0.03, 0);

    final enterButton = VrButton3D(
      name: enterNodeName,
      label: 'Entrar al demo',
      center: pose.localToWorld(0, -0.32, 0.055),
      color: accent,
      width: 1.50,
      height: 0.26,
      onPressed: onEnter,
      meshBuilder: meshBuilder,
    );
    enterButton.nodes.first.localTransform = pose.transformAt(0, -0.32, 0.055);

    final backButton = VrButton3D(
      name: backNodeName,
      label: 'Volver al Home / Ocultar',
      center: pose.localToWorld(0, -0.60, 0.055),
      color: vm.Vector4(0.32, 0.38, 0.48, 1),
      width: 1.50,
      height: 0.24,
      onPressed: onBack,
      meshBuilder: meshBuilder,
    );
    backButton.nodes.first.localTransform = pose.transformAt(0, -0.60, 0.055);

    final labels = await Future.wait([
      _label(
        data.title.toUpperCase(),
        pose: pose,
        y: 0.42,
        height: 0.115,
        color: data.color,
        weight: FontWeight.w800,
        textNodeBuilder: textNodeBuilder,
      ),
      _label(
        '${data.category}  ·  ${data.subtitle}',
        pose: pose,
        y: 0.25,
        height: 0.068,
        color: const Color(0xFFCBD5E1),
        textNodeBuilder: textNodeBuilder,
      ),
      _label(
        data.description,
        pose: pose,
        y: 0.07,
        height: 0.15,
        color: const Color(0xFFE2E8F0),
        maxLines: 2,
        maxWidthPx: 1350,
        textNodeBuilder: textNodeBuilder,
      ),
      _label(
        '${data.controls}  ·  ESTÉREO 3D',
        pose: pose,
        y: -0.13,
        height: 0.06,
        color: const Color(0xFF94A3B8),
        textNodeBuilder: textNodeBuilder,
      ),
      _label(
        'ENTRAR AL DEMO',
        pose: pose,
        y: -0.32,
        height: 0.085,
        color: Colors.white,
        weight: FontWeight.w800,
        name: enterNodeName,
        textNodeBuilder: textNodeBuilder,
      ),
      _label(
        '✕  OCULTAR / VOLVER AL HOME',
        pose: pose,
        y: -0.60,
        height: 0.072,
        color: Colors.white,
        weight: FontWeight.w700,
        name: backNodeName,
        textNodeBuilder: textNodeBuilder,
      ),
    ]);

    return DemoPreviewWorldPanel._(
      data: data,
      pose: pose,
      onEnter: onEnter,
      onBack: onBack,
      plate: plate,
      enterButton: enterButton,
      backButton: backButton,
      labels: labels,
    );
  }

  static Future<Node> _label(
    String text, {
    required DemoPreviewWorldPose pose,
    required double y,
    required double height,
    required Color color,
    FontWeight weight = FontWeight.w600,
    int maxLines = 1,
    double maxWidthPx = 1100,
    String? name,
    DemoPreviewTextNodeBuilder? textNodeBuilder,
  }) async {
    final node = textNodeBuilder != null
        ? await textNodeBuilder(text, name)
        : (await VrTextLabel.create(
            text,
            center: pose.localToWorld(0, y, 0.09),
            height: height,
            fontSize: 84,
            color: color,
            fontWeight: weight,
            maxLines: maxLines,
            maxWidthPx: maxWidthPx,
            name: name,
          )).node;
    node.name = name ?? '';
    node.raycastable = name == enterNodeName || name == backNodeName;
    node.localTransform = pose.transformAt(0, y, 0.09)
      ..rotateX(math.pi / 2)
      ..scaleByVector3(vm.Vector3(-1, 1, 1));
    return node;
  }

  /// Moves the completed panel to a freshly sampled viewer pose.
  ///
  /// Text rasterization is asynchronous and may take long enough for the
  /// headset pose to change. The caller therefore samples the rig again just
  /// before adding these nodes to the scene. This is a one-shot placement:
  /// frame updates never call this method, so the panel remains world-locked
  /// after it becomes visible.
  void reanchor(DemoPreviewWorldPose nextPose) {
    pose = nextPose;
    _plate.localTransform = pose.transformAt(0, -0.03, 0);
    _enterButton.nodes.first.localTransform = pose.transformAt(0, -0.32, 0.055);
    _backButton.nodes.first.localTransform = pose.transformAt(0, -0.60, 0.055);
    for (var i = 0; i < _labels.length; i++) {
      _labels[i].localTransform = pose.transformAt(0, _labelY[i], 0.09)
        ..rotateX(math.pi / 2)
        ..scaleByVector3(vm.Vector3(-1, 1, 1));
    }
  }

  void addTo(Scene scene) {
    for (final node in nodes) {
      scene.add(node);
    }
  }

  void removeFrom(Scene scene) {
    _registry.handleHover(null);
    _lastHoveredIndex = null;
    for (final node in nodes) {
      if (node.parent != null) scene.remove(node);
    }
  }

  void update(double dt) => _registry.update(dt);

  void handleHover(Node? node) {
    final index = _actionByNode[node];
    if (index == null) {
      _lastHoveredIndex = null;
      return;
    }
    if (_lastHoveredIndex == index) return;
    _lastHoveredIndex = index;
    setFocusedIndex(index);
  }

  bool handleSelect(Node node) {
    final index = _actionByNode[node];
    if (index == null) return false;
    setFocusedIndex(index);
    return _registry.handleSelect(
      index == 0 ? _enterButton.nodes.first : _backButton.nodes.first,
    );
  }

  void setFocusedIndex(int index) {
    _focusedIndex = index.clamp(0, 1);
    _registry.handleHover(
      _focusedIndex == 0 ? _enterButton.nodes.first : _backButton.nodes.first,
    );
  }

  void activateFocused() {
    _registry.handleSelect(
      _focusedIndex == 0 ? _enterButton.nodes.first : _backButton.nodes.first,
    );
  }
}
