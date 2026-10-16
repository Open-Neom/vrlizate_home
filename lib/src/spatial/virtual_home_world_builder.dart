import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_world/vrlizate_world.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart'
    show VrLook, VrTextBitmap, VrTextLabel, VrTextRaster;

import '../theme/vr_home_theme.dart';
import '../ecosystem/vr_home_ecosystem_room.dart';
import 'home_architecture_batch.dart';
import 'home_ecosystem_layout.dart';
import 'home_lobby_layout.dart';
import 'home_room_identity.dart';
import 'home_surface_textures.dart';
import 'home_showcase.dart';
import 'virtual_home_models.dart';

/// Static living-room architecture behind Home's world-locked app library.
///
/// The front volume reserved by HomeLobbyLayout belongs to the library, not to floating
/// demo objects. Low/medium bake static face lighting into vertex colors;
/// high/ultra use rasterized PBR. Neither path performs ray tracing.
class VirtualHomeWorldBuilder {
  static const roomSignForeground = Color(0xFFF9FCFF);
  static const roomSignBackground = Color(0xFF111C26);

  /// Contact detail is enabled only by VrLook's high/ultra quality gate.
  /// Low/medium retain the same natural palette without an extra AO pass.
  static const naturalLook = VrLook(
    bloomIntensity: .15,
    ambientOcclusion: true,
  );

  VirtualHomeWorldBuilder({
    Iterable<HomeExhibit> exhibits = const [],
    Iterable<VrHomeEcosystemRoom> ecosystemRooms = const [],
    this.theme = VrHomeThemeData.aurora,
    Iterable<VrWorldEntity>? worldObjects,
  }) : exhibits = List<HomeExhibit>.unmodifiable(exhibits),
       ecosystemLayout = HomeEcosystemLayout(
         ecosystemRooms,
         worldObjects: worldObjects,
       );
  final List<HomeExhibit> exhibits;
  final HomeEcosystemLayout ecosystemLayout;
  VrHomeThemeData theme;
  final List<FloorWaypoint> waypoints = [];

  /// Compatibility with older Home callers. Apps now live in the library.
  final List<PortalPedestal> pedestals = [];

  Node? _environmentRoot;
  DirectionalLight? _sunLight;
  FloorWaypoint? _hoveredWaypoint;
  final Map<Node, HomeExhibit> _exhibits = Map.identity();
  final Map<Node, VrHomeEcosystemRoom> _rooms = Map.identity();
  final Set<Node> _occluders = Set.identity();
  final List<_HomeArchitectureVariant> _architecture = [];
  Future<void> _materialsReady = Future<void>.value();
  final List<HomeShowcase> _showcases = [];
  VrAvatarAppearance? _avatarAppearance;

  void setAvatarAppearance(VrAvatarAppearance? appearance) {
    _avatarAppearance = appearance;
    for (final showcase in _showcases) {
      showcase.setAppearance(appearance);
    }
  }

  List<HomeShowcase> get showcases => List.unmodifiable(_showcases);
  Future<void> get showcaseReady =>
      Future.wait(_showcases.map((showcase) => showcase.ready)).then((_) {});

  void observe(vm.Vector3 eye) {
    for (final showcase in _showcases) {
      showcase.observe(eye);
    }
  }

  /// Diagnostic/authoring hosts can wait for finishes before capturing a view.
  Future<void> get materialsReady => _materialsReady;
  bool _bakedArchitecture = true;
  int _generation = 0;

  HomeExhibit? exhibitFor(Node? node) => _exhibits[node];
  bool ownsExhibitNode(Node node) => _exhibits.containsKey(node);
  bool blocksPointer(Node node) => _occluders.contains(node);
  VrHomeEcosystemRoom? roomFor(Node? node) => _rooms[node];
  bool ownsRoomNode(Node node) => _rooms.containsKey(node);

  /// Builds only the environment; the caller owns the library and Home bar.
  /// Rebuilding removes this builder's previous subtree, not the caller's UI.
  void build(
    Scene scene, {
    bool enableShadows = false,
    int shadowMapResolution = 1024,
    bool? bakedArchitecture,
  }) {
    for (final showcase in _showcases) {
      showcase.dispose();
    }
    _showcases.clear();
    final previousRoot = _environmentRoot;
    if (previousRoot != null) previousRoot.parent?.remove(previousRoot);
    waypoints.clear();
    pedestals.clear();
    _hoveredWaypoint = null;
    _exhibits.clear();
    _rooms.clear();
    _occluders.clear();
    _architecture.clear();
    _bakedArchitecture = bakedArchitecture ?? !enableShadows;
    final generation = ++_generation;

    final root = Node(name: 'home_lobby_environment');
    _environmentRoot = root;
    _setupLighting(
      root,
      enableShadows: enableShadows,
      shadowMapResolution: shadowMapResolution,
    );
    _setupArchitecture(root);
    _setupPanorama(root);
    _setupWaypoints(root);
    _setupExhibits(root);
    _setupEcosystem(root);
    _setupShowcases(scene, root);
    scene.add(root);
    _setupLabels(root, generation);
  }

  void setShadowsEnabled(
    bool enabled, {
    int? shadowMapResolution,
    bool? bakedArchitecture,
  }) {
    final sun = _sunLight;
    if (sun == null) return;
    sun.castsShadow = enabled;
    if (shadowMapResolution != null) {
      sun.shadowMapResolution = shadowMapResolution;
    }
    final baked = bakedArchitecture ?? !enabled;
    if (_bakedArchitecture != baked) {
      _bakedArchitecture = baked;
      for (final architecture in _architecture) {
        architecture.apply(baked: baked);
      }
      _materialsReady = _dressArchitecture(_generation);
    }
  }

  void _setupLighting(
    Node root, {
    required bool enableShadows,
    required int shadowMapResolution,
  }) {
    _sunLight = DirectionalLight(
      color: vm.Vector3(1, 0.97, 0.91),
      intensity: 2.5,
      castsShadow: enableShadows,
      // Keep the shadow budget local to the plaza instead of the renderer's
      // four cascades extending 150 m. These are rasterized shadow maps.
      shadowCascadeCount: 2,
      shadowMaxDistance: 55,
      shadowMapResolution: shadowMapResolution,
      shadowFadeRange: 6,
      shadowSoftness: .12,
    );
    root.add(
      Node(name: 'lobby_daylight')
        ..addComponent(
          DirectionalLightComponent.aimed(
            _sunLight!,
            vm.Vector3(-0.3, -0.8, 0.55),
          ),
        )
        ..localTransform = vm.Matrix4.translation(vm.Vector3(3, 7, -8)),
    );
    for (final room in HomeLobbyLayout.rooms.skip(1)) {
      root.add(
        Node(name: '${room.id}_fill')
          ..addComponent(
            PointLightComponent(
              PointLight(
                color: vm.Vector3(0.98, 0.96, 0.91),
                intensity: 2.5,
                range: 8,
              ),
            ),
          )
          ..localTransform = vm.Matrix4.translationValues(
            (room.minX + room.maxX) / 2,
            3.8,
            (room.minZ + room.maxZ) / 2,
          ),
      );
    }
    for (final portal in ecosystemLayout.portals) {
      final fill = Color.lerp(Colors.white, Color(portal.room.accent), .18)!;
      root.add(
        Node(name: 'ecosystem_${portal.room.id}_fill')
          ..addComponent(
            PointLightComponent(
              PointLight(
                color: vm.Vector3(fill.r, fill.g, fill.b),
                intensity: 2.4,
                range: 7,
              ),
            ),
          )
          ..localTransform = vm.Matrix4.translationValues(
            portal.roomCenterX,
            3.8,
            portal.z,
          ),
      );
    }
    root.add(
      Node(name: 'lobby_ceiling_fill')
        ..addComponent(
          PointLightComponent(
            PointLight(
              color: vm.Vector3(0.92, 0.96, 1),
              intensity: 3,
              range: 14,
            ),
          ),
        )
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 3.9, 0)),
    );
  }

  void _setupArchitecture(Node root) {
    // Vertex colors keep authored room palettes in six shared matte materials.
    // Static boxes are batched by room/finish, retaining per-room culling and
    // exact triangle raycasts without a draw call per book or facade detail.
    final palette = <HomeLobbyFinish, int>{
      HomeLobbyFinish.stone: Color.lerp(
        theme.surface,
        theme.foreground,
        .38,
      )!.toARGB32(),
      HomeLobbyFinish.plaster: Color.lerp(
        theme.surface,
        theme.foreground,
        .55,
      )!.toARGB32(),
      HomeLobbyFinish.oak: Color.lerp(
        const Color(0xFFBBA183),
        theme.secondary,
        .25,
      )!.toARGB32(),
      HomeLobbyFinish.trim: theme.border.toARGB32(),
      HomeLobbyFinish.fabric: Color.lerp(
        theme.accent,
        theme.muted,
        .5,
      )!.toARGB32(),
      HomeLobbyFinish.rug: theme.muted.toARGB32(),
    };
    const roughness = <HomeLobbyFinish, double>{
      HomeLobbyFinish.stone: .84,
      HomeLobbyFinish.plaster: .95,
      HomeLobbyFinish.oak: .8,
      HomeLobbyFinish.trim: .74,
      HomeLobbyFinish.fabric: .98,
      HomeLobbyFinish.rug: 1,
    };
    final materials = {
      for (final finish in HomeLobbyFinish.values)
        finish: _matte(0xFFFFFFFF, roughness: roughness[finish]!)
          ..vertexColorWeight = 1,
    };
    final bakedMaterials = {
      for (final finish in HomeLobbyFinish.values)
        finish: UnlitMaterial()
          ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
          ..vertexColorWeight = 1,
    };
    const skyName = 'ecosystem_atrium_sky';
    final solidBoxes = ecosystemLayout.boxes.where(
      (box) =>
          box.name != skyName &&
          !box.name.contains('_avatar_mannequin_') &&
          !box.name.endsWith('_showcase_lounge_clearance'),
    );
    for (final batch in HomeArchitectureBatch.group(solidBoxes)) {
      final node = Node(name: 'lobby_${batch.zone}_${batch.finish.name}')
        ..shadowStatic = true;
      final architecture = _HomeArchitectureVariant(
        node: node,
        batch: batch,
        defaultColor: palette[batch.finish]!,
        pbrMaterial: materials[batch.finish]!,
        bakedMaterial: bakedMaterials[batch.finish]!,
      )..apply(baked: _bakedArchitecture);
      _architecture.add(architecture);
      root.add(node);
      _occluders.add(node);
    }
    _materialsReady = _dressArchitecture(_generation);
    // This is an authored sky backdrop, not an opaque roof that should block
    // daylight. Keep real beams in the static shadow batches, and render the
    // sky separately so its color is independent of direct scene lighting.
    for (final box in ecosystemLayout.boxes.where(
      (box) => box.name == skyName,
    )) {
      final color = Color(box.color ?? 0xFFB8D9E5);
      root.add(
        Node(
            name: 'lobby_${box.name}_backdrop',
            mesh: Mesh(
              CuboidGeometry(vm.Vector3(box.width, box.height, box.depth)),
              UnlitMaterial()
                ..baseColorFactor = vm.Vector4(
                  _linearChannel(color.r),
                  _linearChannel(color.g),
                  _linearChannel(color.b),
                  1,
                ),
            ),
          )
          ..localTransform = vm.Matrix4.translationValues(box.x, box.y, box.z)
          ..raycastable = false
          ..shadowCastingMode = ShadowCastingMode.off,
      );
    }
  }

  void _setupShowcases(Scene scene, Node root) {
    for (final portal in ecosystemLayout.portals.where(
      (portal) => portal.room.purpose == VrHomeRoomPurpose.avatar,
    )) {
      final prefix = 'ecosystem_${portal.room.id}_';
      final platform = ecosystemLayout.boxes.firstWhere(
        (box) => box.name == '${prefix}avatar_platform',
      );
      final lounge = ecosystemLayout.boxes.firstWhere(
        (box) => box.name == '${prefix}showcase_lounge_clearance',
      );
      final fallback = Node(name: '${prefix}mannequin_fallback');
      final boxes = ecosystemLayout.boxes.where(
        (box) => box.name.startsWith('${prefix}avatar_mannequin_'),
      );
      for (final batch in HomeArchitectureBatch.group(boxes)) {
        final node = Node(name: '${prefix}fallback_${batch.finish.name}');
        _HomeArchitectureVariant(
          node: node,
          batch: batch,
          defaultColor: 0xFF76B6AA,
          pbrMaterial: _matte(0xFF76B6AA, roughness: .75),
          bakedMaterial: UnlitMaterial()..vertexColorWeight = 1,
        ).apply(baked: false);
        fallback.add(node);
      }
      final showcase = HomeShowcase(
        scene: scene,
        parent: root,
        portal: portal,
        platform: platform,
        lounge: lounge,
        actorFallback: fallback,
      );
      _showcases.add(showcase);
      showcase.setAppearance(_avatarAppearance);
    }
  }

  Future<void> _dressArchitecture(int generation) async {
    final seen = <HomeLobbyFinish>{};
    for (final architecture in _architecture.toList()) {
      if (generation != _generation) return;
      if (!seen.add(architecture.batch.finish)) continue;
      try {
        await HomeSurfaceTextures.apply(
          finish: architecture.batch.finish,
          pbr: architecture.pbrMaterial,
          baked: architecture.bakedMaterial,
          details: !_bakedArchitecture,
          isCurrent: () => generation == _generation,
        );
      } catch (error) {
        debugPrint('Home finish ${architecture.batch.finish.name}: $error');
      }
    }
  }

  void _setupEcosystem(Node root) {
    for (final portal in ecosystemLayout.portals) {
      final room = portal.room;
      final accent = _matte(
        Color.lerp(Color(room.accent), Colors.black, .65)!.toARGB32(),
        roughness: .65,
      );
      final terminal =
          Node(
              name: 'ecosystem_${room.id}_terminal',
              mesh: Mesh(CuboidGeometry(vm.Vector3(.14, 1.45, 2.3)), accent),
            )
            ..localTransform = vm.Matrix4.translationValues(
              portal.terminalX,
              1.75,
              portal.z,
            );
      root.add(terminal);
      _rooms[terminal] = room;
      // Architectural furniture carries each room's silhouette. Interaction
      // stays on its clearly labeled terminal, separate from the static batch.
    }
  }

  void _setupExhibits(Node root) {
    for (final exhibit in exhibits) {
      final group = Node(name: 'exhibit_${exhibit.id}')
        ..localTransform = vm.Matrix4.translationValues(
          exhibit.x,
          0,
          exhibit.z,
        ).multiplied(vm.Matrix4.rotationY(exhibit.yaw));
      root.add(group);
      final material = _matte(exhibit.accent, roughness: 0.55);
      void part(String name, Geometry geometry, double x, double y, double z) {
        final node = Node(
          name: '${exhibit.id}_$name',
          mesh: Mesh(geometry, material),
        )..localTransform = vm.Matrix4.translationValues(x, y, z);
        group.add(node);
        _exhibits[node] = exhibit;
      }

      switch (exhibit.id) {
        case 'planet':
          part(
            'planet',
            SphereGeometry(radius: 0.47, segments: 16, rings: 10),
            0,
            1.4,
            0,
          );
          part(
            'ring',
            RingGeometry(innerRadius: 0.62, outerRadius: 0.78, segments: 24),
            0,
            1.4,
            0,
          );
        case 'ideas':
          for (var i = 0; i < 3; i++) {
            final height = 0.5 + i * 0.3;
            part(
              'column_$i',
              CuboidGeometry(vm.Vector3(0.35, height, 0.4)),
              (i - 1) * 0.48,
              0.78 + height / 2,
              0,
            );
          }
        case 'materials':
          for (var i = 0; i < 3; i++) {
            part(
              'gem_$i',
              SphereGeometry(
                radius: 0.28,
                segments: 6 + i * 3,
                rings: 4 + i * 2,
              ),
              (i - 1) * 0.55,
              1.15 + (i == 1 ? 0.3 : 0),
              0,
            );
          }
        case 'kiosk_visor':
          part(
            'pedestal',
            CuboidGeometry(vm.Vector3(0.55, 0.95, 0.45)),
            0,
            0.475,
            0,
          );
          part(
            'visor_shell',
            CuboidGeometry(vm.Vector3(0.46, 0.24, 0.28)),
            0,
            1.38,
            0,
          );
          for (final side in const [-1.0, 1.0]) {
            part(
              'lens_$side',
              SphereGeometry(radius: 0.075, segments: 12, rings: 8),
              side * 0.11,
              1.38,
              0.14,
            );
          }
          part(
            'controller_twin',
            CuboidGeometry(vm.Vector3(0.36, 0.04, 0.18)),
            0,
            1.08,
            0.08,
          );
        case 'kiosk_motor':
          part(
            'pedestal',
            CuboidGeometry(vm.Vector3(0.55, 0.95, 0.45)),
            0,
            0.475,
            0,
          );
          part(
            'wheel_ring',
            RingGeometry(innerRadius: 0.22, outerRadius: 0.32, segments: 20),
            0,
            1.42,
            0,
          );
          part(
            'chassis',
            CuboidGeometry(vm.Vector3(0.52, 0.14, 0.28)),
            0,
            1.08,
            0,
          );
        case 'kiosk_arcade':
          part(
            'cabinet_base',
            CuboidGeometry(vm.Vector3(0.56, 1.15, 0.46)),
            0,
            0.575,
            0,
          );
          part(
            'cabinet_screen',
            CuboidGeometry(vm.Vector3(0.48, 0.38, 0.12)),
            0,
            1.36,
            0.08,
          );
          for (final side in const [-1.0, 1.0]) {
            part(
              'gem_$side',
              SphereGeometry(radius: 0.12, segments: 8, rings: 6),
              side * 0.36,
              1.25,
              0,
            );
          }
        case 'kiosk_strategy':
          part(
            'table_base',
            CuboidGeometry(vm.Vector3(0.62, 0.95, 0.52)),
            0,
            0.475,
            0,
          );
          for (var i = 0; i < 3; i++) {
            part(
              'tower_$i',
              CuboidGeometry(vm.Vector3(0.16, 0.32 + i * 0.12, 0.16)),
              (i - 1) * 0.22,
              1.12 + i * 0.06,
              0,
            );
          }
          part(
            'crest_orb',
            SphereGeometry(radius: 0.16, segments: 12, rings: 8),
            0,
            1.56,
            0,
          );
        case 'kiosk_worlds':
          part(
            'island_base',
            CuboidGeometry(vm.Vector3(0.68, 0.95, 0.52)),
            0,
            0.475,
            0,
          );
          part(
            'mountain_peak',
            SphereGeometry(radius: 0.28, segments: 12, rings: 8),
            -0.12,
            1.22,
            0,
          );
          part(
            'beacon_tower',
            CuboidGeometry(vm.Vector3(0.14, 0.48, 0.14)),
            0.18,
            1.28,
            0,
          );
        case 'kiosk_labs':
          part(
            'pedestal',
            CuboidGeometry(vm.Vector3(0.58, 0.95, 0.46)),
            0,
            0.475,
            0,
          );
          for (final side in const [-1.0, 1.0]) {
            part(
              'probe_sphere_$side',
              SphereGeometry(radius: 0.19, segments: 14, rings: 10),
              side * 0.22,
              1.36,
              0,
            );
          }
          part(
            'bridge_bar',
            CuboidGeometry(vm.Vector3(0.48, 0.08, 0.08)),
            0,
            1.36,
            0,
          );
        case 'rotunda_openworld':
          for (final side in const [-1.0, 1.0]) {
            part(
              'arch_pillar_$side',
              CuboidGeometry(vm.Vector3(0.28, 1.95, 0.28)),
              side * 0.92,
              0.975,
              0,
            );
          }
          part(
            'arch_lintel',
            CuboidGeometry(vm.Vector3(2.15, 0.26, 0.32)),
            0,
            1.98,
            0,
          );
          part(
            'portal_globe',
            SphereGeometry(radius: 0.42, segments: 16, rings: 10),
            0,
            1.25,
            0,
          );
          part(
            'compass_ring',
            RingGeometry(innerRadius: 0.54, outerRadius: 0.68, segments: 24),
            0,
            1.25,
            0,
          );
      }
      part(
        'placard',
        CuboidGeometry(vm.Vector3(2.15, 0.5, 0.08)),
        0,
        2.35,
        0.04,
      );
    }
  }

  Future<void> _setupLabels(Node root, int generation) async {
    try {
      await Scene.initializeStaticResources();
      if (!Scene.isReadyToRender || generation != _generation) return;
      for (final exhibit in exhibits) {
        final label = await VrTextLabel.create(
          '${exhibit.title}\nA · Abrir experiencia',
          center: vm.Vector3.zero(),
          height: 0.28,
          maxLines: 2,
          maxWidthPx: 1100,
          name: '${exhibit.id}_label',
        );
        if (generation != _generation) return;
        label.node.localTransform =
            vm.Matrix4.translationValues(exhibit.x, 2.35, exhibit.z)
              ..rotateY(exhibit.yaw)
              ..translateByVector3(vm.Vector3(0, 0, 0.09))
              ..rotateX(math.pi / 2)
              ..scaleByVector3(vm.Vector3(-1, 1, 1));
        label.node.shadowCastingMode = ShadowCastingMode.off;
        root.add(label.node);
        _exhibits[label.node] = exhibit;
      }
      for (final portal in ecosystemLayout.portals) {
        final identity = HomeRoomIdentity.forPurpose(portal.room.purpose);
        for (final atDoor in const [true, false]) {
          final label = await _createRoomSign(
            atDoor
                ? '${portal.room.title}\n${identity.category}'
                : '${portal.room.title}\nA · Explorar en VR',
            height: atDoor ? .50 : .58,
            maxWorldWidth: atDoor ? 3.12 : 2.04,
            maxLines: 2,
            maxWidthPx: 1700,
            name: 'ecosystem_${portal.room.id}_${atDoor ? 'sign' : 'action'}',
          );
          if (generation != _generation) return;
          label.node.localTransform =
              vm.Matrix4.translationValues(
                  atDoor ? portal.signX : portal.terminalX,
                  atDoor ? 3.55 : 1.85,
                  portal.z,
                )
                ..rotateY(portal.yaw)
                ..translateByVector3(vm.Vector3(0, 0, .16))
                ..rotateX(math.pi / 2)
                ..scaleByVector3(vm.Vector3(-1, 1, 1));
          root.add(label.node);
          if (!atDoor) {
            _rooms[label.node] = portal.room;
          } else {
            label.node.raycastable = false;
          }
        }
        // Public room proposal stays on its wall in both eyes. It is not a
        // claim that a remote catalog/account has already been connected.
        final proposal = await _createRoomSign(
          portal.room.description,
          height: .38,
          maxWorldWidth: 2.5,
          maxLines: 3,
          maxWidthPx: 1500,
          name: 'ecosystem_${portal.room.id}_proposal',
        );
        if (generation != _generation) return;
        proposal.node
          ..raycastable = false
          ..shadowCastingMode = ShadowCastingMode.off
          ..localTransform =
              (vm.Matrix4.translationValues(portal.terminalX, 2.675, portal.z)
                ..rotateY(portal.yaw)
                ..translateByVector3(vm.Vector3(0, 0, .17))
                ..rotateX(math.pi / 2)
                ..scaleByVector3(vm.Vector3(-1, 1, 1)));
        root.add(proposal.node);
      }
      if (ecosystemLayout.portals.isNotEmpty) {
        final sign = await _createRoomSign(
          'PLAZA VRLIZATE\nExplora sus espacios',
          height: .42,
          maxWorldWidth: 2.1,
          maxLines: 2,
          maxWidthPx: 1300,
          name: 'ecosystem_wing_sign',
        );
        if (generation != _generation) return;
        sign.node.localTransform = vm.Matrix4.translationValues(0, 3.7, 12.34)
          ..rotateY(math.pi)
          ..rotateX(math.pi / 2)
          ..scaleByVector3(vm.Vector3(-1, 1, 1));
        sign.node.raycastable = false;
        root.add(sign.node);
      }
      final instructions = await VrTextLabel.create(
        ecosystemLayout.portals.isEmpty
            ? 'Explora las salas · Stick izquierdo: caminar · Derecho: mirar · A: elegir'
            : 'Plaza: detrás de la galería · Stick izquierdo: caminar · A: elegir',
        center: vm.Vector3(0, 3.25, -5.0),
        height: 0.12,
        maxWidthPx: 2200,
        name: 'home_walk_instructions',
      );
      instructions.node.shadowCastingMode = ShadowCastingMode.off;
      if (generation == _generation) root.add(instructions.node);
    } catch (error) {
      // Geometry remains usable if optional labels cannot allocate GPU text.
      debugPrint('Home room labels unavailable: $error');
    }
  }

  /// The backing is composited into the existing text texture. No extra mesh,
  /// light-sensitive material or invisible picking surface is introduced.
  /// This CPU raster stage can be tested without a Flutter GPU context.
  @visibleForTesting
  static Future<VrTextBitmap> rasterizeRoomSign(
    String text, {
    int maxLines = 2,
    double maxWidthPx = 1700,
  }) async {
    final bitmap = await VrTextRaster.rasterize(
      text,
      color: roomSignForeground,
      fontWeight: FontWeight.w800,
      fontSize: 96,
      paddingPx: 24,
      maxLines: maxLines,
      maxWidthPx: maxWidthPx,
    );
    final pixels = Uint8List.fromList(bitmap.pixels);
    final argb = roomSignBackground.toARGB32();
    final background = [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255];
    for (var i = 0; i < pixels.length; i += 4) {
      final alpha = pixels[i + 3];
      for (var channel = 0; channel < 3; channel++) {
        pixels[i + channel] =
            (pixels[i + channel] * alpha +
                background[channel] * (255 - alpha) +
                127) ~/
            255;
      }
      pixels[i + 3] = 255;
    }
    return VrTextBitmap(pixels, bitmap.width, bitmap.height);
  }

  Future<VrTextLabel> _createRoomSign(
    String text, {
    required double height,
    required double maxWorldWidth,
    required String name,
    int maxLines = 2,
    double maxWidthPx = 1700,
  }) async {
    final bitmap = await rasterizeRoomSign(
      text,
      maxLines: maxLines,
      maxWidthPx: maxWidthPx,
    );
    final label = VrTextLabel.fromBitmap(
      bitmap,
      text,
      center: vm.Vector3.zero(),
      height: math.min(height, maxWorldWidth / bitmap.aspect),
      name: name,
    );
    label.node.shadowCastingMode = ShadowCastingMode.off;
    return label;
  }

  void dispose() {
    _generation++;
    for (final showcase in _showcases) {
      showcase.dispose();
    }
    _showcases.clear();
    _environmentRoot?.parent?.remove(_environmentRoot!);
    _environmentRoot = null;
    _exhibits.clear();
    _rooms.clear();
    _occluders.clear();
    _architecture.clear();
  }

  PhysicallyBasedMaterial _matte(int argb, {required double roughness}) {
    final color = Color(argb);
    return PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(
        _linearChannel(color.r),
        _linearChannel(color.g),
        _linearChannel(color.b),
        1,
      )
      ..roughnessFactor = roughness
      ..metallicFactor = 0
      ..vertexColorWeight = 0;
  }

  // PBR factors are linear; Color channels encode the authored sRGB palette.
  double _linearChannel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  void _setupPanorama(Node root) {
    // One opaque, static mesh: muted ground, bright horizon, blue-gray sky.
    // It is far behind the window and leaves the entire UI volume clear.
    final rows = <(double, Color)>[
      (-12, theme.surface),
      (0.2, theme.muted),
      (1.8, theme.foreground),
      (13, theme.secondary),
    ];
    final positions = Float32List(rows.length * 6);
    final colors = Float32List(rows.length * 8);
    final indices = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final (y, color) = rows[i];
      final r = _linearChannel(color.r);
      final g = _linearChannel(color.g);
      final b = _linearChannel(color.b);
      positions.setAll(i * 6, [-40, y, -24, 40, y, -24]);
      colors.setAll(i * 8, [r, g, b, 1, r, g, b, 1]);
      if (i == rows.length - 1) continue;
      final vertex = i * 2;
      indices.addAll([
        vertex,
        vertex + 1,
        vertex + 3,
        vertex,
        vertex + 3,
        vertex + 2,
      ]);
    }
    root.add(
      Node(
        name: 'lobby_distant_panorama',
        mesh: Mesh(
          MeshGeometry.fromArrays(
            positions: positions,
            colors: colors,
            indices: indices,
          ),
          UnlitMaterial()
            // Visible from the room despite the renderer's view-basis winding.
            ..doubleSided = true
            ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
            ..vertexColorWeight = 1,
        ),
      )..shadowCastingMode = ShadowCastingMode.off,
    );
  }

  void _setupWaypoints(Node root) {
    final color = theme.accent;
    for (final def in ecosystemLayout.waypoints) {
      final material = _matte(color.toARGB32(), roughness: 0.9);
      final node =
          Node(
              name: 'waypoint_${def.id}',
              mesh: Mesh(
                CuboidGeometry(vm.Vector3(0.38, 0.014, 0.38)),
                material,
              ),
            )
            ..localTransform = vm.Matrix4.translation(
              vm.Vector3(def.x, 0.018, def.z),
            );
      root.add(node);
      waypoints.add(
        FloorWaypoint(
          id: def.id,
          name: def.name,
          position: vm.Vector3(def.x, 0, def.z),
          color: color,
          node: node,
          material: material,
        ),
      );
    }
  }

  /// Selection feedback and proximity for the bounded animation pilot.
  void tick(
    double time, {
    FloorWaypoint? hoveredWaypoint,
    PortalPedestal? hoveredPedestal,
    vm.Vector3? eyePosition,
  }) {
    if (eyePosition != null) observe(eyePosition);
    if (identical(_hoveredWaypoint, hoveredWaypoint)) return;
    _hoveredWaypoint?.material.emissiveFactor.setValues(0, 0, 0, 1);
    _hoveredWaypoint = hoveredWaypoint;
    hoveredWaypoint?.material.emissiveFactor.setValues(0.06, 0.09, 0.1, 1);
  }

  /// Alias for consumers that use update rather than Home's existing tick.
  void update(
    double time, {
    FloorWaypoint? hoveredWaypoint,
    PortalPedestal? hoveredPedestal,
    vm.Vector3? eyePosition,
  }) => tick(
    time,
    hoveredWaypoint: hoveredWaypoint,
    hoveredPedestal: hoveredPedestal,
    eyePosition: eyePosition,
  );
}

/// Keeps one node/picking identity while switching quality. Each GPU variant
/// uploads at most once per world build, and only if that quality is requested.
class _HomeArchitectureVariant {
  _HomeArchitectureVariant({
    required this.node,
    required this.batch,
    required this.defaultColor,
    required this.pbrMaterial,
    required this.bakedMaterial,
  });

  final Node node;
  final HomeArchitectureBatch batch;
  final int defaultColor;
  final PhysicallyBasedMaterial pbrMaterial;
  final UnlitMaterial bakedMaterial;
  Mesh? _pbrMesh, _bakedMesh;

  void apply({required bool baked}) {
    // Assign through Node.mesh so Scene refreshes cached render items and
    // bounds. Directly changing a MeshPrimitive would leave cached materials.
    node.mesh = baked
        ? (_bakedMesh ??= _createMesh(baked: true))
        : (_pbrMesh ??= _createMesh(baked: false));
  }

  Mesh _createMesh({required bool baked}) {
    final data = batch.build(
      defaultColor: defaultColor,
      bakedVertexShading: baked,
    );
    return Mesh(
      MeshGeometry.fromArrays(
        positions: data.positions,
        normals: data.normals,
        texCoords: data.textureCoordinates,
        colors: data.colors,
        indices: data.indices,
      ),
      baked ? bakedMaterial : pbrMaterial,
    );
  }
}
