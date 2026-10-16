// Independent desktop diagnostic of the SDK's production world builder.
// Run this target, not example/lib/main.dart. No application/Firebase imports.
// PNGs: Directory.systemTemp/vrlizate_home_spatial_probe/<UTC run>/.
// SPATIAL_PROBE logs identify actual captures and incomplete resource loads.
// Optional: --dart-define=SPATIAL_PROBE_AUTO=false for manual inspection.
// Optional: --dart-define=SPATIAL_PROBE_CONTROLS=false hides the control panel.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/vrlizate_home_spatial.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';
// ignore: implementation_imports
import 'package:vrlizate_scene/src/vr_controller_feedback_visuals.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

const _avatarSpeciesProbe = bool.fromEnvironment('AVATAR_SPECIES_PROBE');
const _controllerProbe = bool.fromEnvironment('CONTROLLER_VISUAL_PROBE');

const _automaticCaptures = bool.fromEnvironment(
  'SPATIAL_PROBE_AUTO',
  defaultValue: true,
);
const _showControls = bool.fromEnvironment(
  'SPATIAL_PROBE_CONTROLS',
  defaultValue: true,
);
const _exitOnComplete = bool.fromEnvironment('SPATIAL_PROBE_EXIT_ON_COMPLETE');
const _resourceTimeout = Duration(seconds: 30);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _log('starting', {
    'platform': Platform.operatingSystem,
    'renderer': 'SceneView/mono',
    'automatic_captures': _automaticCaptures,
  });
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: VrGpuResourceGate(builder: (_) => const _SpatialProbe()),
      ),
    ),
  );
}

void _log(String event, Map<String, Object?> fields) => debugPrintSynchronously(
  'SPATIAL_PROBE ${jsonEncode({'event': event, ...fields})}',
);

class _Viewpoint {
  _Viewpoint(
    this.id,
    this.title,
    this.eye,
    this.target, {
    this.pose,
    this.appearance,
  });

  final String id, title;
  final vm.Vector3 eye, target;
  final VrActorAction? pose;
  final VrAvatarAppearance? appearance;

  PerspectiveCamera camera() => PerspectiveCamera(
    position: eye.clone(),
    target: target.clone(),
    up: vm.Vector3(0, 1, 0),
    fovRadiansY: 55 * math.pi / 180,
    fovNear: .05,
    fovFar: 100,
  );
}

class _SpatialProbe extends StatefulWidget {
  const _SpatialProbe();

  @override
  State<_SpatialProbe> createState() => _SpatialProbeState();
}

class _SpatialProbeState extends State<_SpatialProbe> {
  final _captureKey = GlobalKey();
  final List<ui.FrameTiming> _frameTimings = [];
  late final Scene _scene;
  late final VirtualHomeWorldBuilder _world;
  VrControllerFeedbackVisuals? _controllerVisuals;
  LaserPointerNode? _laserPointer;
  late final List<_Viewpoint> _views;
  late final Set<String> _expectedLabels;
  late PerspectiveCamera _camera;
  Future<Directory>? _outputDirectory;
  Timer? _advanceTimer;
  VrQualityPreset _quality = VrQualityPreset.medium;
  int _index = 0;
  int _generation = 0;
  int _captureCount = 0;
  bool _automatic = _automaticCaptures;
  bool _ready = false;
  bool _capturing = false;
  String _status = 'Esperando materiales y rótulos…';

  void _onFrameTimings(List<ui.FrameTiming> timings) {
    _frameTimings.addAll(timings);
    if (_frameTimings.length > 60) {
      _frameTimings.removeRange(0, _frameTimings.length - 60);
    }
  }

  Map<String, Object?> _frameTimingSummary() {
    if (_frameTimings.isEmpty) {
      return const {'sample_count': 0};
    }
    double avg(Iterable<int> micros) =>
        micros.fold<int>(0, (a, b) => a + b) / _frameTimings.length / 1000.0;
    final buildMs = avg(_frameTimings.map((t) => t.buildDuration.inMicroseconds));
    final rasterMs = avg(
      _frameTimings.map((t) => t.rasterDuration.inMicroseconds),
    );
    final totalMs = avg(_frameTimings.map((t) => t.totalSpan.inMicroseconds));
    return {
      'sample_count': _frameTimings.length,
      'avg_build_ms': double.parse(buildMs.toStringAsFixed(3)),
      'avg_raster_ms': double.parse(rasterMs.toStringAsFixed(3)),
      'avg_total_span_ms': double.parse(totalMs.toStringAsFixed(3)),
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
    // Mounted only after the shared GPU gate verifies renderer readiness.
    _scene = Scene();
    _world = VirtualHomeWorldBuilder(
      ecosystemRooms: VrHomeEcosystemRoom.defaults,
    )..build(_scene);
    final planter = _world.ecosystemLayout.boxes.firstWhere(
      (box) =>
          box.name.startsWith('ecosystem_planter_') &&
          !box.name.contains('_rim_') &&
          box.x > 0 &&
          box.z < HomeEcosystemLayout.firstRowZ,
    );
    final stage = _world.ecosystemLayout.boxes.firstWhere(
      (box) => box.name == 'ecosystem_avatar_avatar_platform',
    );
    if (_controllerProbe) {
      _controllerVisuals = VrControllerFeedbackVisuals(
        _scene.root,
        gazeFilterEnabled: false,
      );
      _laserPointer = LaserPointerNode();
      _scene.root.add(_laserPointer!.rootNode);
    }
    _views = _controllerProbe
        ? [
            _Viewpoint(
              'controller_hud_visor',
              'Mando 3D en modo visor · HUD gemelo de PhoneControllerPage',
              vm.Vector3(stage.x - 3.7, 1.8, stage.z + 1.3),
              vm.Vector3(stage.x, 1.3, stage.z),
              appearance: VrAvatarAppearance(
                species: VrAvatarSpecies.fox,
                bodyColorArgb: 0xff287e87,
                accentColorArgb: 0xffa8ecd2,
                headScale: 1.2,
                featureScale: 1.3,
                pattern: VrAvatarPattern.spots,
              ),
            ),
            _Viewpoint(
              'controller_hand_laser',
              'Mando 3D de mano y puntero láser · LaserPointerNode',
              vm.Vector3(stage.x - 3.7, 1.8, stage.z + 1.3),
              vm.Vector3(stage.x, 1.3, stage.z),
              appearance: VrAvatarAppearance(
                species: VrAvatarSpecies.axolotl,
                bodyColorArgb: 0xffae80d5,
                accentColorArgb: 0xffffd267,
                headScale: 1.15,
                featureScale: 1.4,
                pattern: VrAvatarPattern.stripes,
              ),
            ),
          ]
        : _avatarSpeciesProbe
        ? [
            for (final species in VrAvatarSpecies.values)
              _Viewpoint(
                'avatar_${species.name}',
                'Avatar · ${const VrAvatarLabels().speciesName(species)}',
                vm.Vector3(stage.x - 3.7, 1.8, stage.z + 1.3),
                vm.Vector3(stage.x, 1.3, stage.z),
                appearance: VrAvatarAppearance(
                  species: species,
                  bodyColorArgb: switch (species) {
                    VrAvatarSpecies.fox => 0xffcc704d,
                    VrAvatarSpecies.axolotl => 0xffe9a2bd,
                    VrAvatarSpecies.sprout => 0xff289b85,
                    VrAvatarSpecies.robot => 0xffd2ad45,
                    VrAvatarSpecies.orb => 0xff8258c9,
                    VrAvatarSpecies.human => 0xff3978c6,
                  },
                  accentColorArgb: 0xfff4e9d1,
                  heightMeters: 1.7,
                ),
              ),
            _Viewpoint(
              'avatar_fox_custom',
              'Zorro · proporciones y manchas',
              vm.Vector3(stage.x - 3.7, 1.8, stage.z + 1.3),
              vm.Vector3(stage.x, 1.3, stage.z),
              appearance: VrAvatarAppearance(
                species: VrAvatarSpecies.fox,
                bodyColorArgb: 0xff287e87,
                accentColorArgb: 0xffa8ecd2,
                headScale: 1.2,
                featureScale: 1.3,
                pattern: VrAvatarPattern.spots,
              ),
            ),
            _Viewpoint(
              'avatar_axolotl_custom',
              'Ajolote · proporciones y franjas',
              vm.Vector3(stage.x - 3.7, 1.8, stage.z + 1.3),
              vm.Vector3(stage.x, 1.3, stage.z),
              appearance: VrAvatarAppearance(
                species: VrAvatarSpecies.axolotl,
                bodyColorArgb: 0xffae80d5,
                accentColorArgb: 0xffffd267,
                headScale: 1.15,
                featureScale: 1.4,
                pattern: VrAvatarPattern.stripes,
              ),
            ),
          ]
        : [
            _Viewpoint(
              'arrival',
              'Llegada a la plaza',
              vm.Vector3(0, 1.6, 15),
              vm.Vector3(0, 2.8, 40),
            ),
            _Viewpoint(
              'diagonal',
              'Jardines y fachadas',
              vm.Vector3(-8.5, 1.6, 18),
              vm.Vector3(10, 2.3, 36),
            ),
            _Viewpoint(
              'planter',
              'Jardinera · forma y materiales',
              vm.Vector3(planter.x - 3.2, 1.6, planter.z - 3.3),
              vm.Vector3(planter.x + .5, 1.5, planter.z),
            ),
            _Viewpoint(
              'showcase_room',
              'Mi avatar · modelos GLB y materiales PBR',
              vm.Vector3(stage.x - 6.2, 2, stage.z + 2.7),
              vm.Vector3(stage.x, 1.3, stage.z + 2.4),
              pose: VrActorAction.idle,
            ),
            _Viewpoint(
              'showcase_walk',
              'Mi avatar · Walking',
              vm.Vector3(stage.x - 3.4, 1.8, stage.z + 1.8),
              vm.Vector3(stage.x, 1.3, stage.z),
              pose: VrActorAction.walk,
            ),
            _Viewpoint(
              'showcase_wave',
              'Mi avatar · Wave',
              vm.Vector3(stage.x - 3.4, 1.8, stage.z + 1.8),
              vm.Vector3(stage.x, 1.3, stage.z),
              pose: VrActorAction.wave,
            ),
          ];
    _expectedLabels = {
      for (final exhibit in _world.exhibits) '${exhibit.id}_label',
      for (final portal in _world.ecosystemLayout.portals)
        for (final kind in ['sign', 'action', 'proposal'])
          'ecosystem_${portal.room.id}_$kind',
      if (_world.ecosystemLayout.portals.isNotEmpty) 'ecosystem_wing_sign',
      'home_walk_instructions',
    };
    _camera = _views.first.camera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_select(0, automatic: _automatic));
    });
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  List<String> _missingLabels() => [
    for (final name in _expectedLabels)
      if (_scene.root.getChildByName(name) == null) name,
  ];

  void _applyQuality() {
    VirtualHomeWorldBuilder.naturalLook.applyToScene(_scene, _quality);
    _scene.antiAliasingMode = _quality.antiAliasing;
    _world.setShadowsEnabled(
      _quality.tier == VrQualityTier.high,
      shadowMapResolution: _quality.shadowMapResolution,
    );
  }

  Future<void> _select(
    int index, {
    required bool automatic,
    VrQualityPreset? quality,
  }) async {
    if (!mounted || _capturing) return;
    _advanceTimer?.cancel();
    _frameTimings.clear();
    final generation = ++_generation;
    setState(() {
      _index = index % _views.length;
      _quality = quality ?? _quality;
      _camera = _views[_index].camera();
      _automatic = automatic;
      _ready = false;
      _status = 'Esperando materiales y rótulos…';
      _applyQuality();
    });
    _log('view_changed', _viewFields());
    try {
      await _world.materialsReady.timeout(_resourceTimeout);
      if (!_isCurrent(generation)) return;
      await _world.showcaseReady.timeout(_resourceTimeout);
      if (!_isCurrent(generation)) return;
      _world.setAvatarAppearance(_views[_index].appearance);
      _world.observe(_views[_index].eye);
      if (_controllerProbe) {
        await _configureControllerProbe(_views[_index]);
        if (!_isCurrent(generation)) return;
      } else if (_views[_index].appearance case final appearance?) {
        _verifyAvatarResources(appearance);
      }
      for (final showcase in _world.showcases) {
        if (showcase.loadErrors.isNotEmpty) {
          throw StateError('Showcase asset load: ${showcase.loadErrors}');
        }
        final pose = _views[_index].pose;
        if (_views[_index].appearance != null) {
          showcase.showPose(VrActorAction.idle, 0);
        } else if (pose != null) {
          showcase.showPose(pose, pose == VrActorAction.walk ? .3 : .8);
        }
      }
      await Scene.preload().timeout(_resourceTimeout);
      if (!_isCurrent(generation)) return;
      final labelClock = Stopwatch()..start();
      while (_missingLabels().isNotEmpty) {
        if (labelClock.elapsed >= _resourceTimeout) {
          throw TimeoutException('Missing labels: ${_missingLabels()}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!_isCurrent(generation)) return;
      }
      // Observe painted frames after the actual async builder work. This is
      // not a GPU timing claim; toImage performs the real image readback.
      for (var frame = 0; frame < 3; frame++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrent(generation)) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!_isCurrent(generation)) return;
      setState(() {
        _ready = true;
        _status = 'Materiales procesados · rótulos completos';
      });
      _log('view_ready', {
        ..._viewFields(),
        // The builder reports finish-load errors separately; completion of
        // materialsReady means its work settled, not a fabricated GPU verdict.
        'materials_settled': true,
        'labels_complete': true,
        'expected_labels': _expectedLabels.length,
        'frame_timings_mono_debug': _frameTimingSummary(),
      });
      if (_automatic && await _capture(generation)) {
        _scheduleNext(generation);
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _automatic = false;
        _ready = false;
        _status = 'Carga incompleta · revisar SPATIAL_PROBE';
      });
      _log('resources_failed', {
        ..._viewFields(),
        'error': '$error',
        'missing_labels': _missingLabels(),
      });
    }
  }

  Map<String, Object?> _viewFields() {
    final view = _views[_index];
    return {
      'generation': _generation,
      'id': view.id,
      'quality': _quality.tier.name,
      'eye': [view.eye.x, view.eye.y, view.eye.z],
      'target': [view.target.x, view.target.y, view.target.z],
      'architecture_lighting': _quality.tier == VrQualityTier.high
          ? 'pbr'
          : 'baked_vertex',
      'actor_pose': view.pose?.name,
      'avatar_appearance': view.appearance?.toJson(),
      'showcase_errors': [
        for (final showcase in _world.showcases) ...showcase.loadErrors,
      ],
    };
  }

  Future<void> _configureControllerProbe(_Viewpoint view) async {
    final visuals = _controllerVisuals;
    final laser = _laserPointer;
    if (visuals == null || laser == null) return;
    final forward = (view.target - view.eye)..normalize();
    final screenRight = vm.Vector3(0, 1, 0).cross(forward)..normalize();
    final camUp = forward.cross(screenRight)..normalize();

    if (view.id == 'controller_hud_visor') {
      laser.visible = false;
      visuals.setState(
        const VrControllerFeedbackState(
          connected: true,
          btnA: true,
          btnR: true,
          moveX: .34,
          moveY: -.38,
          lookX: -.24,
          lookY: .18,
          laserX: .15,
          laserY: -.10,
          throttle: .65,
          brake: .25,
          actions: {
            'A': 'Seleccionar',
            'B': 'Volver',
            'X': 'Menú',
            'Y': 'Vista',
            'L': 'Anterior',
            'R': 'Gatillo',
            'GRIP': 'Recentrar',
          },
        ),
      );
      await visuals.ready.timeout(_resourceTimeout);
      if (visuals.artworkPending case final pending?) {
        await pending.timeout(_resourceTimeout);
      }
      final center = view.eye + forward * 1.05 - camUp * .13;
      const scale = 0.92;
      final pose = vm.Matrix4.identity();
      for (var i = 0; i < 3; i++) {
        pose.setEntry(i, 0, -screenRight[i] * scale);
        pose.setEntry(i, 1, camUp[i] * scale);
        pose.setEntry(i, 2, -forward[i] * scale);
        pose.setEntry(i, 3, center[i]);
      }
      visuals.root
        ..visible = true
        ..localTransform = pose;
    } else {
      visuals.root.visible = false;
      laser.visible = true;
      laser.setLaserBeamActive(true);
      laser.setStickDeflection(.42, .48);
      final handCenter = view.eye + forward * .22 - camUp * .052;
      final basis = vm.Matrix4.identity();
      for (var i = 0; i < 3; i++) {
        basis.setEntry(i, 0, -screenRight[i]);
        basis.setEntry(i, 1, camUp[i]);
        basis.setEntry(i, 2, -forward[i]);
        basis.setEntry(i, 3, handCenter[i]);
      }
      basis.rotateX(.58);
      laser.rootNode.localTransform = basis;
    }
  }

  // Runs against real GPU resources, inside the production world. Flutter's
  // headless test engine cannot create these meshes; CPU tests cover the plan.
  void _verifyAvatarResources(VrAvatarAppearance appearance) {
    List<(Node, InstancedMesh)> batches(Node node) => [
      for (final component in node.getComponents<InstancedMeshComponent>())
        (node, component.instancedMesh),
      for (final child in node.children) ...batches(child),
    ];
    void check(bool condition, String message) {
      if (!condition) throw StateError(message);
    }

    final plan = VrAvatarPlan.build(appearance);
    final nearCount = plan.partsFor(VrAvatarDetail.near).length;
    final farCount = plan.partsFor(VrAvatarDetail.far).length;
    for (final showcase in _world.showcases) {
      // Reset is idempotent even after the asynchronous GLB import completed.
      // Node.add throws if a still-mounted fallback is inserted twice.
      showcase.setAppearance(null);
      showcase.setAppearance(null);
      check(
        showcase.root.getChildByName('showcase_robot_placement') != null,
        'Reset failed to restore the reference actor',
      );
      showcase.setAppearance(appearance);
      check(
        showcase.root.getChildByName('showcase_robot_placement') == null,
        'Personal appearance left the reference actor mounted',
      );
      final placement = showcase.root.getChildByName(
        'showcase_personal_avatar',
      );
      check(placement != null, 'Personal avatar is missing');
      final original = batches(placement!);
      check(
        original.fold<int>(0, (n, b) => n + b.$2.instanceCount) == nearCount,
        'Near detail instance budget differs from the authored plan',
      );
      showcase.setAppearance(
        appearance.copyWith(
          bodyColorArgb: 0xff157c8a,
          heightMeters: 1.8,
          headScale: 1.1,
          featureScale: .9,
        ),
      );
      final resized = batches(placement);
      check(original.length == resized.length, 'Editing rebuilt avatar groups');
      for (var i = 0; i < original.length; i++) {
        check(
          identical(original[i].$1, resized[i].$1) &&
              identical(original[i].$2, resized[i].$2),
          'Editing replaced a retained node/mesh',
        );
      }
      showcase.setAppearance(appearance);

      // Verify localized idle motion updates in place without rebuilding nodes.
      showcase.resumeDemonstration();
      showcase.beforeTick(.05);
      final afterTick = batches(placement);
      check(
        afterTick.length == original.length,
        'Idle animation tick rebuilt avatar batches',
      );
      // Reset back to rest pose for deterministic capture comparison.
      showcase.setAppearance(appearance.copyWith(heightMeters: 1.8));
      showcase.setAppearance(appearance);

      // Continuous traversal hysteresis verification across 8/12 m and 18/22 m.
      final traversal = <(double, bool, int)>[
        (6.5, true, nearCount),
        (10.0, true, nearCount), // 8..12 m hysteresis holds near
        (13.5, true, farCount), // >= 12 m switches to far
        (20.0, true, farCount), // 18..22 m hysteresis stays mounted
        (24.0, false, farCount), // >= 22 m detaches showcase
        (20.0, false, farCount), // 18..22 m hysteresis stays detached
        (16.5, true, farCount), // < 18 m remounts at far detail
        (10.0, true, farCount), // 8..12 m hysteresis holds far
        (6.5, true, nearCount), // < 8 m restores near detail
      ];
      for (final (dist, expectedMounted, expectedInstances) in traversal) {
        showcase.observe(showcase.center + vm.Vector3(dist, 0, 0));
        check(
          (showcase.root.parent != null) == expectedMounted,
          'Traversal at ${dist}m mounted=${showcase.root.parent != null}, expected $expectedMounted',
        );
        if (expectedMounted) {
          final currentCount = batches(
            placement,
          ).fold<int>(0, (n, b) => n + b.$2.instanceCount);
          check(
            currentCount == expectedInstances,
            'Traversal at ${dist}m instances=$currentCount, expected $expectedInstances',
          );
        }
      }
      showcase.observe(_views[_index].eye);
      _log('avatar_resources_verified', {
        'species': appearance.species.name,
        'pattern': appearance.pattern.name,
        'quality': _quality.tier.name,
        'near_triangles': plan.triangleCount(VrAvatarDetail.near),
        'far_triangles': plan.triangleCount(VrAvatarDetail.far),
        'near_groups': plan.batchCount(VrAvatarDetail.near),
        'far_groups': plan.batchCount(VrAvatarDetail.far),
        'retained_edit_resources': true,
        'localized_idle_tick_verified': true,
        'continuous_hysteresis_traversal': true,
        'distance_detach_and_restore': true,
        'idempotent_reset_and_restore': true,
      });
    }
  }

  Future<Directory> _createOutputDirectory() async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final directory = await Directory(
      '${Directory.systemTemp.path}/vrlizate_home_spatial_probe/$stamp',
    ).create(recursive: true);
    _log('output_directory', {'path': directory.path});
    return directory;
  }

  Future<bool> _capture(int generation) async {
    if (!_isCurrent(generation) || !_ready || _capturing) return false;
    final scenePixelRatio =
        MediaQuery.devicePixelRatioOf(context) * _quality.pixelRatioScale;
    setState(() => _capturing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!_isCurrent(generation)) return false;
      final boundary = _captureKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) {
        throw StateError('No painted scene boundary is available.');
      }
      // SceneView paints the renderer's GPU image into Canvas; this captures
      // that production output, excluding our sibling diagnostic controls.
      // Fixed 1x logical pixels keeps comparisons at the same output size.
      final image = await boundary.toImage(pixelRatio: 1);
      late final int width, height;
      late final ByteData png;
      try {
        width = image.width;
        height = image.height;
        final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
        if (encoded == null) throw StateError('PNG readback returned no data.');
        png = encoded;
      } finally {
        image.dispose();
      }
      if (!_isCurrent(generation)) return false;
      final directory = await (_outputDirectory ??= _createOutputDirectory());
      if (!_isCurrent(generation)) return false;
      final serial = (++_captureCount).toString().padLeft(2, '0');
      final file = File(
        '${directory.path}/${serial}_${_quality.tier.name}_${_views[_index].id}.png',
      );
      await file.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      if (!_isCurrent(generation)) return false;
      _log('captured', {
        ..._viewFields(),
        'path': file.path,
        'width': width,
        'height': height,
        'capture': 'RenderRepaintBoundary.toImage/SceneView',
        'scene_pixel_ratio': scenePixelRatio,
        'frame_timings_mono_debug': _frameTimingSummary(),
      });
      setState(() => _status = 'PNG guardado: ${file.uri.pathSegments.last}');
      return true;
    } catch (error) {
      if (_isCurrent(generation)) {
        setState(() {
          _automatic = false;
          _status = 'Captura no disponible · usar captura de pantalla';
        });
        _log('capture_failed', {..._viewFields(), 'error': '$error'});
      }
      return false;
    } finally {
      if (_isCurrent(generation)) setState(() => _capturing = false);
    }
  }

  void _scheduleNext(int generation) {
    if (!_isCurrent(generation) || !_automatic) return;
    if (_index == _views.length - 1 && _quality.tier == VrQualityTier.high) {
      setState(() => _automatic = false);
      _log('automatic_complete', {'captures': _captureCount});
      if (_exitOnComplete) exit(0);
      return;
    }
    _advanceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!_isCurrent(generation) || !_automatic) return;
      final nextQuality = _index == _views.length - 1
          ? VrQualityPreset.high
          : _quality;
      unawaited(_select(_index + 1, automatic: true, quality: nextQuality));
    });
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    _advanceTimer?.cancel();
    _world.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        key: _captureKey,
        child: ColoredBox(
          color: Colors.black,
          child: SceneView(
            _scene,
            camera: _camera,
            pixelRatio:
                MediaQuery.devicePixelRatioOf(context) *
                _quality.pixelRatioScale,
          ),
        ),
      ),
      if (_showControls)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.black.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'SDK · ${_index + 1}/${_views.length} '
                      '${_views[_index].title}\n$_status',
                      style: const TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      onPressed: _capturing
                          ? null
                          : () => unawaited(
                              _select(
                                _index,
                                automatic: false,
                                quality: _quality.tier == VrQualityTier.medium
                                    ? VrQualityPreset.high
                                    : VrQualityPreset.medium,
                              ),
                            ),
                      child: Text(
                        _quality.tier == VrQualityTier.high
                            ? 'ALTA · SOMBRAS'
                            : 'MEDIA',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _capturing
                          ? null
                          : () => unawaited(
                              _select(_index + 1, automatic: false),
                            ),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Siguiente'),
                    ),
                    TextButton.icon(
                      onPressed: !_ready || _capturing
                          ? null
                          : () {
                              _advanceTimer?.cancel();
                              setState(() => _automatic = false);
                              unawaited(_capture(_generation));
                            },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Guardar PNG'),
                    ),
                    if (_automatic)
                      TextButton(
                        onPressed: () {
                          _advanceTimer?.cancel();
                          setState(() => _automatic = false);
                        },
                        child: const Text('Detener recorrido'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
