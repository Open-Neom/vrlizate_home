import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';
import 'package:vrlizate/vrlizate.dart' show VrSpatialInputState;

import '../../utils/constants/vr_home_constants.dart';
import '../../utils/constants/vr_home_translation_constants.dart';
import 'laser_pointer_node.dart';
import 'demo_preview_data.dart';
import 'home_spatial_metrics.dart';
import 'home_walk_space.dart';
import 'home_showcase.dart';
import 'portal_gaze_rearm.dart';
import 'virtual_home_hud_coordinator.dart';
import 'virtual_home_locomotion_controller.dart';
import 'virtual_home_models.dart';
import 'virtual_home_world_builder.dart';
import 'vr_demo_library_model.dart';
import 'vr_demo_library_panel.dart';
import 'vr_home_input_policy.dart';
import 'vr_home_loading_splash_overlay.dart';
import 'vr_home_spatial_bindings.dart';
import 'vr_home_room_panel.dart';
import '../ecosystem/vr_home_room_controller.dart';
import '../ecosystem/vr_home_room_presentation.dart';
import '../theme/vr_home_theme.dart';
import '../ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

/// Compact readable assistant output; never allocate an unbounded text texture.
String vrHomeAssistantDescription(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) {
    return 'Habla con el asistente, pregunta qué estás viendo o pide ayuda aquí.';
  }
  final characters = compact.runes.take(701).toList(growable: false);
  return characters.length <= 700
      ? String.fromCharCodes(characters)
      : '${String.fromCharCodes(characters.take(699))}…';
}

/// A JSON-only snapshot in Home world units; orientation is explicitly radians.
/// No Flutter/scene nodes, controller objects or device identifiers cross the
/// host assistant boundary.
Map<String, Object?> vrHomeAssistantContext({
  required String zone,
  required vm.Vector3 eye,
  required vm.Vector3 forward,
  required double yaw,
  required double pitch,
  Map<String, String>? target,
  String? buttonId,
  String? buttonLabel,
}) {
  double finite(double value) => value.isFinite ? value : 0;
  Map<String, Object?> vector(vm.Vector3 value) => {
    'x': finite(value.x),
    'y': finite(value.y),
    'z': finite(value.z),
  };
  return {
    'experience': 'home',
    'zone': zone,
    'camera': {
      'position': vector(eye),
      'forward': vector(forward),
      'orientation': {
        'yaw': finite(yaw),
        'pitch': finite(pitch),
        'unit': 'radians',
      },
    },
    if (target != null) 'target': Map<String, String>.of(target),
    if (buttonId != null)
      'button': {'id': buttonId, if (buttonLabel != null) 'label': buttonLabel},
  };
}

/// Host-independent spatial presentation. The callbacks are also the input
/// targets for gaze, the controller's A button and the laser.
Future<VrWorldActionPanel3D> createVrHomeAssistantPanel({
  required VrHomeSpatialBindings bindings,
  required VrWorldPose pose,
  required String text,
  required bool busy,
  required bool listening,
  required void Function(String) onAction,
  required void Function(VrHomePrompt) onPrompt,
  required VoidCallback onClose,
  required VoidCallback onTogglePrompts,
  bool showPrompts = false,
  VrHomeThemeData theme = VrHomeThemeData.aurora,
  VrControlMeshBuilder? meshBuilder,
  VrWorldTextNodeBuilder? textNodeBuilder,
}) {
  final hasAssistant = bindings.onAssistantAction != null;
  final shortcutPage = hasAssistant && showPrompts;
  final actions = <VrWorldAction>[
    if (hasAssistant && !shortcutPage) ...[
      VrWorldAction(
        id: 'assistant:listen',
        label: listening ? 'Terminar voz' : 'Hablar',
        enabled: !busy || listening,
        onPressed: () => onAction('listen'),
      ),
      VrWorldAction(
        id: 'assistant:vision',
        label: 'Qué estoy viendo',
        enabled: !busy && !listening,
        onPressed: () => onAction('vision'),
      ),
      VrWorldAction(
        id: 'assistant:help',
        label: 'Ayuda aquí',
        enabled: !busy && !listening,
        onPressed: () => onAction('help'),
      ),
      VrWorldAction(
        id: 'assistant:cancel',
        label: 'Detener',
        onPressed: () => onAction('cancel'),
      ),
    ],
    if (!hasAssistant || shortcutPage)
      for (final prompt in bindings.prompts)
        VrWorldAction(
          id: 'prompt:${prompt.id}',
          label: prompt.displayLabel,
          color: prompt.isCloseAction ? theme.muted : theme.accent,
          onPressed: () => onPrompt(prompt),
        ),
    if (hasAssistant && bindings.prompts.isNotEmpty)
      VrWorldAction(
        id: 'assistant:shortcuts',
        label: shortcutPage ? 'Conversar' : 'Accesos rápidos',
        onPressed: onTogglePrompts,
      ),
    if ((hasAssistant && !shortcutPage) ||
        !bindings.prompts.any((prompt) => prompt.isCloseAction))
      VrWorldAction(
        id: 'close',
        label: 'Cerrar · B',
        color: theme.muted,
        onPressed: onClose,
      ),
  ];
  return VrWorldActionPanel3D.create(
    name: 'itzli',
    pose: pose,
    title: bindings.assistantTitle,
    subtitle: shortcutPage
        ? 'ACCESOS RÁPIDOS · ELIGE CON EL MANDO'
        : listening
        ? 'ESCUCHANDO · TERMINAR VOZ PARA ENVIAR'
        : busy
        ? 'PENSANDO · PUEDES DETENER'
        : 'ELIGE CON MIRADA, LÁSER O JOYSTICK',
    description: hasAssistant ? '' : 'Este panel queda fijo en el mundo.',
    content: hasAssistant && !shortcutPage
        ? VrWidgetSurface3D(
            name: 'itzli_response',
            availableWidth: 1.72,
            maxHeight: .74,
            logicalSize: const Size(1120, 450),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ColoredBox(
                color: const Color(0xFF080816),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  // Keep short answers near the panel's middle when the viewer
                  // tilts down and the top of this world-anchored card leaves FOV.
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      vrHomeAssistantDescription(text),
                      maxLines: 11,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontFamily: 'Roboto',
                        fontSize: 30,
                        height: 1.24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        : null,
    actions: actions,
    columns: actions.length > 1 ? 2 : 1,
    width: 2.0,
    buttonHeight: .18,
    actionSpacing: .045,
    columnSpacing: .07,
    accentColor: theme.accent,
    meshBuilder: meshBuilder,
    textNodeBuilder: textNodeBuilder,
  );
}

/// Spatial 3D Options & Quick Menu panel summonable from anywhere in the Mall
/// via the Joystick (`R` button or `Opciones` dock action).
Future<VrWorldActionPanel3D> createVrHomeOptionsPanel({
  required VrHomeSpatialBindings bindings,
  required VrWorldPose pose,
  required String lookName,
  required VrQualityPreset qualityPreset,
  required bool hasMallPortals,
  required void Function(String actionId) onAction,
  required VoidCallback onClose,
  VrHomeThemeData theme = VrHomeThemeData.aurora,
  VrControlMeshBuilder? meshBuilder,
  VrWorldTextNodeBuilder? textNodeBuilder,
}) {
  final actions = <VrWorldAction>[
    VrWorldAction(
      id: VrHomeConstants.lookActionId,
      label: '${VrHomeTranslationConstants.optionsLookPrefix}$lookName',
      onPressed: () => onAction(VrHomeConstants.lookActionId),
    ),
    VrWorldAction(
      id: VrHomeConstants.qualityActionId,
      label:
          '${VrHomeTranslationConstants.optionsQualityPrefix}${qualityPreset.tier.name.toUpperCase()}',
      onPressed: () => onAction(VrHomeConstants.qualityActionId),
    ),
    VrWorldAction(
      id: VrHomeConstants.recenterActionId,
      label: VrHomeTranslationConstants.optionsRecenterLabel,
      onPressed: () => onAction(VrHomeConstants.recenterActionId),
    ),
    if (hasMallPortals)
      VrWorldAction(
        id: 'rooms',
        label: VrHomeTranslationConstants.optionsMallPlazaLabel,
        onPressed: () => onAction('rooms'),
      ),
    if (bindings.onOpenSpatialSettings != null)
      VrWorldAction(
        id: VrHomeConstants.spatialSettingsActionId,
        label: VrHomeTranslationConstants.optionsSpatialSensorsLabel,
        onPressed: () => onAction(VrHomeConstants.spatialSettingsActionId),
      ),
    if (bindings.onOpenCastSettings != null)
      VrWorldAction(
        id: 'cast',
        label: VrHomeTranslationConstants.optionsCastLabel,
        onPressed: () => onAction('cast'),
      ),
    if (bindings.onPair != null)
      VrWorldAction(
        id: 'pair',
        label: VrHomeTranslationConstants.optionsPairLabel,
        onPressed: () => onAction('pair'),
      ),
    if (bindings.calibrationExperienceId != null)
      VrWorldAction(
        id: 'calibrate',
        label: VrHomeTranslationConstants.optionsCalibrateLensesLabel,
        onPressed: () => onAction('calibrate'),
      ),
    VrWorldAction(
      id: 'close',
      label: 'Cerrar · B',
      color: theme.muted,
      onPressed: onClose,
    ),
  ];
  return VrWorldActionPanel3D.create(
    name: VrHomeConstants.optionsPanelName,
    pose: pose,
    title: VrHomeTranslationConstants.optionsPanelTitle,
    subtitle: VrHomeTranslationConstants.optionsPanelSubtitle,
    description: VrHomeTranslationConstants.optionsPanelDescription,
    actions: actions,
    columns: 2,
    width: 2.1,
    buttonHeight: .18,
    actionSpacing: .045,
    columnSpacing: .07,
    accentColor: theme.accent,
    meshBuilder: meshBuilder,
    textNodeBuilder: textNodeBuilder,
  );
}

/// Reusable stereoscopic lobby with world-anchored catalog and navigation.
///
/// The host supplies experiences and optional controller/assistant capabilities.
/// This scene owns rendering, collision, locomotion and its input subscriptions;
/// permissions, transport startup, inference and route construction stay outside.
class VirtualHomeScene extends StatefulWidget {
  const VirtualHomeScene({
    super.key,
    required this.bindings,
    this.theme = VrHomeThemeData.aurora,
    this.openPairingOnStart = false,
    this.startInHeadsetMode = false,
  });

  final VrHomeSpatialBindings bindings;
  final VrHomeThemeData theme;

  final bool openPairingOnStart;

  /// Enter stereoscopic interaction immediately; hosts can prepare pairing first.
  final bool startInHeadsetMode;

  @override
  State<VirtualHomeScene> createState() => _VirtualHomeSceneState();
}

class _VirtualHomeSceneState extends State<VirtualHomeScene>
    with WidgetsBindingObserver {
  late final Scene _scene;
  late final StereoHeadRig _rig;

  // Visual Quality & Looks
  VrLook _currentLook = VirtualHomeWorldBuilder.naturalLook;
  String _lookName = 'Natural';
  late VrQualityPreset _qualityPreset;

  // Modular Subsystems
  late VirtualHomeWorldBuilder _worldBuilder;
  final VirtualHomeLocomotionController _locomotion =
      VirtualHomeLocomotionController();
  late HomeWalkSpace _walkSpace;
  vm.Vector3? _lastSafePosition;
  final VrSpatialInputState _gamepadMotion = VrSpatialInputState();
  final PortalGazeRearm _portalRearm = PortalGazeRearm();
  VrDemoLibraryPanel? _library;
  int _libraryGeneration = 0;
  int _hostGeneration = 0;

  // Hardware Computer Vision, Voice & 2nd Phone Controller Services
  VrHomeSpatialBindings get _bindings => widget.bindings;
  VrRemoteControllerService get _remoteController => _bindings.remoteController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _gamepadAttached = false;
  late final LaserPointerNode _laserPointer;

  /// Farthest surface the laser reticle lands on; beyond it only the stub
  /// shows, as with an empty room on Quest.
  static const double _laserReticleRange = 40.0;
  final VrHomeRemotePointer _remotePointer = VrHomeRemotePointer();
  final VrHomeGamepadPolicy _homeGamepad = VrHomeGamepadPolicy();
  late final VrInputArbiter _arbiter;
  late final VrGamepadDriver _gamepadDriver;
  bool _remotePrimaryDown = false;
  bool _remoteBackDown = false;
  bool _remoteXDown = false, _remoteYDown = false;
  bool _remoteMenuDown = false, _remoteOptionsDown = false;
  bool _libraryHiddenByUser = false;
  bool _modalLaserTriggerQueued = false;
  Node? _modalLaserTarget;
  bool _isDemoActive = false;
  bool _isEnteringDemo = false;
  bool _routeVisible = true;
  bool get _homeSurfaceActive => _routeVisible && !_isDemoActive;
  bool _modalNavigationLatched = false;

  bool _isRemoteConnected = false;
  bool _remoteLaserMode = false;
  bool _remoteLaserHitsTarget = false;
  bool _lastRemoteRecenter = false;

  // Interaction State
  FloorWaypoint? _hoveredWaypoint;
  PortalPedestal? _hoveredPedestal;
  DemoPreviewData? _demoAfterJump;
  late VrHomeRoomController _roomController;
  VrWorldActionPanel3D? _roomPanel;
  VrWorldPose? _roomPose;
  VrHomeRoomPresentation? _roomPresentation;
  int _roomPanelGeneration = 0;
  int _roomPage = 0;
  bool _suppressRoomRebuild = false;
  bool _foreground = true;
  bool _homeProducersSuspended = false;
  VrWorldActionPanel3D? _itzliPanel;
  bool _itzliOpen = false;
  int _itzliGeneration = 0;
  int _assistantSession = 0;
  VrWorldPose? _itzliPose;
  VrWorldActionPanel3D? _optionsPanel;
  bool _optionsOpen = false;
  int _optionsGeneration = 0;
  VrWorldPose? _optionsPose;
  Listenable? _assistantChanges;
  ValueListenable<VrAvatarAppearance?>? _avatarAppearance;

  List<VrHomeEcosystemRoom> get _expandedEcosystemRooms =>
      VrHomeEcosystemRoom.expandWithWorldCatalog(
        _bindings.ecosystemRooms,
        _bindings.catalog.entries,
      );

  void _bindAvatarAppearance() {
    _avatarAppearance?.removeListener(_avatarAppearanceChanged);
    _avatarAppearance = _bindings.avatarAppearance;
    _avatarAppearance?.addListener(_avatarAppearanceChanged);
    _avatarAppearanceChanged();
  }

  void _avatarAppearanceChanged() {
    _worldBuilder.setAvatarAppearance(_avatarAppearance?.value);
  }

  @override
  void didHaveMemoryPressure() => HomeShowcase.clearAssetCache();
  Timer? _assistantRefreshTimer;
  bool _assistantPanelBuilding = false;
  bool _assistantRebuildQueued = false;
  bool _assistantCapturing = false;
  (String, bool, bool, bool)? _assistantPanelSnapshot;
  bool _assistantShowPrompts = false;
  String? _assistantError;
  Map<String, String>? _assistantTarget;
  bool get _hasAssistant =>
      _bindings.prompts.isNotEmpty || _bindings.onAssistantAction != null;
  String _currentZoneName = 'Biblioteca';
  double _time = 0.0;
  String _statusMessage =
      'Izq.: caminar; borde sostenido: girar · Der.: mirar · A: elegir · B: detener';
  // Open in touch-only preparation; hiding controls enters headset interaction.
  bool _hudHidden = false;

  bool get _hasWorldModal =>
      _itzliOpen || _roomController.isOpen || _optionsOpen;
  bool get _worldModalReady =>
      _itzliPanel != null || _roomPanel != null || _optionsPanel != null;

  static const _navigationControllerActions = {
    'A': 'Seleccionar',
    'B': 'Detener',
    'X': 'Categoría −',
    'Y': 'Categoría +',
    'L': VrHomeTranslationConstants.controllerMenuActionLabel,
    'R': VrHomeTranslationConstants.optionsDockLabel,
  };
  static const _modalControllerActions = {
    'A': 'Seleccionar',
    'B': 'Cerrar',
    'X': 'Sin acción',
    'Y': 'Sin acción',
    'L': VrHomeTranslationConstants.controllerMenuActionLabel,
    'R': VrHomeTranslationConstants.optionsDockLabel,
  };

  @override
  void initState() {
    super.initState();
    _hudHidden = widget.startInHeadsetMode;
    _qualityPreset = _bindings.initialQuality;
    _worldBuilder = VirtualHomeWorldBuilder(
      exhibits: _bindings.exhibits,
      ecosystemRooms: _expandedEcosystemRooms,
      worldObjects: _bindings.worldObjects,
      theme: widget.theme,
    );
    _walkSpace = HomeWalkSpace(
      rooms: _worldBuilder.ecosystemLayout.rooms,
      boxes: _worldBuilder.ecosystemLayout.boxes,
    );
    _scene = Scene();
    _createRoomController();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _rig = StereoHeadRig(eyeCenter: vm.Vector3(0, 1.60, 0));
    _arbiter = VrInputArbiter();

    // 0. Attach Reference Gamepad Driver & Physical Hardware Adapter
    _gamepadDriver = VrGamepadDriver();
    _arbiter.attachDriver(_gamepadDriver);
    _setGamepadAttached(true);

    _arbiter.addListener((event) {
      if (!_foreground ||
          _homeProducersSuspended ||
          _isDemoActive ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      if (event.source == VrInputSource.gamepad) {
        if (event.handled) return;
        switch (_homeGamepad.handle(event)) {
          case VrHomeGamepadAction.back:
            _handleBackAction();
          case VrHomeGamepadAction.primary:
            if (_hasWorldModal) {
              _activateWorldModalFocused();
            } else {
              _handleRemoteTrigger();
            }
          case VrHomeGamepadAction.previousCategory:
            if (!_hasWorldModal) _cycleLibraryCategory(-1);
          case VrHomeGamepadAction.nextCategory:
            if (!_hasWorldModal) _cycleLibraryCategory(1);
          case VrHomeGamepadAction.toggleMainMenu:
            _summonOrToggleMainMenu(toggleIfAlreadyHere: true);
          case VrHomeGamepadAction.none:
            break;
        }
        if (event.type == VrInputType.navigate) {
          _gamepadMotion.handleEvent(event);
          final x = (event.data?['x'] as num?)?.toDouble() ?? 0.0;
          final y = (event.data?['y'] as num?)?.toDouble() ?? 0.0;
          if (_hasWorldModal && event.data?['stick'] != VrGamepadStick.right) {
            _handleWorldModalNavigation(x, y);
          }
        }
      }
    });

    // 1. Build the 3D Virtual Home World
    final enableShadows =
        _qualityPreset.tier == VrQualityTier.high ||
        _qualityPreset.tier == VrQualityTier.ultra;
    _worldBuilder.build(
      _scene,
      enableShadows: enableShadows,
      shadowMapResolution: _qualityPreset.shadowMapResolution,
    );
    _bindAvatarAppearance();
    _buildLibrary();

    // 2. Initialize 3D Laser Pointer for 2nd Phone Remote Controller
    _laserPointer = LaserPointerNode();
    _laserPointer.controllerMeshNode.visible = true;
    _scene.add(_laserPointer.rootNode);

    // 4. Initialize Hardware Services
    _pendingInitialPairing = widget.openPairingOnStart;
    _bindHost(openPairing: widget.openPairingOnStart, initial: true);
    vrHandheldConsoleMode.addListener(_onHandheldModeChanged);

    // The shared VrViewerProfileScope is the single optical profile owner.
  }

  bool _pendingInitialPairing = false;
  bool _isReturningFromPairing = false;
  int _postPairingFrames = 0;
  Timer? _pairingSplashTimer;

  void _onHandheldModeChanged() {
    if (!mounted) return;
    setState(() {
      if (vrHandheldConsoleMode.value) {
        _hudHidden = true;
      }
    });
  }

  @override
  void didUpdateWidget(covariant VirtualHomeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.openPairingOnStart && widget.openPairingOnStart) {
      _pendingInitialPairing = true;
    }
    final bindingsChanged = !identical(oldWidget.bindings, widget.bindings);
    final themeChanged = !identical(oldWidget.theme, widget.theme);
    final coreHostChanged =
        bindingsChanged &&
        (!identical(
              oldWidget.bindings.remoteController,
              widget.bindings.remoteController,
            ) ||
            !identical(
              oldWidget.bindings.assistantChanges,
              widget.bindings.assistantChanges,
            ) ||
            !identical(
              oldWidget.bindings.roomChanges,
              widget.bindings.roomChanges,
            ) ||
            !identical(oldWidget.bindings.exhibits, widget.bindings.exhibits) ||
            oldWidget.bindings.ecosystemRooms.length !=
                widget.bindings.ecosystemRooms.length ||
            oldWidget.bindings.catalog.entries.length !=
                widget.bindings.catalog.entries.length ||
            oldWidget.bindings.worldObjects?.length !=
                widget.bindings.worldObjects?.length);

    if (coreHostChanged) {
      _assistantChanges?.removeListener(_assistantStateChanged);
      _assistantChanges = null;
      _dismissItzliPanel(
        announce: false,
        haptic: false,
        cancelAssistant: false,
        rebuild: false,
      );
      _dismissOptionsPanel(announce: false, haptic: false, rebuild: false);
      final hadRoom = _roomController.isOpen;
      _closeRoomPanel(rebuild: false, notifyHost: false);
      _roomController.dispose();
      if (hadRoom) oldWidget.bindings.onRoomClosed?.call();
      _createRoomController();
      if (_gamepadAttached) {
        oldWidget.bindings.onGamepadConnectionChanged?.call(
          _gamepadDriver,
          false,
        );
        _gamepadAttached = false;
      }
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      _worldBuilder.dispose();
      _worldBuilder = VirtualHomeWorldBuilder(
        exhibits: _bindings.exhibits,
        ecosystemRooms: _expandedEcosystemRooms,
        worldObjects: _bindings.worldObjects,
        theme: widget.theme,
      );
      _walkSpace = HomeWalkSpace(
        rooms: _worldBuilder.ecosystemLayout.rooms,
        boxes: _worldBuilder.ecosystemLayout.boxes,
      );
      if (!_walkSpace.canStand(_rig.eyeCenter.x, _rig.eyeCenter.z)) {
        _rig.eyeCenter = vm.Vector3(0, 1.6, 0);
        _locomotion.cancelJump();
      }
      _bindHost(openPairing: _pendingInitialPairing);
      if (!_isDemoActive) _resumeHomeProducers();
    }
    if (coreHostChanged || themeChanged) {
      _assistantPanelSnapshot = null;
      _assistantStateChanged();
      _worldBuilder.theme = widget.theme;
      _worldBuilder.build(
        _scene,
        enableShadows:
            _qualityPreset.tier == VrQualityTier.high ||
            _qualityPreset.tier == VrQualityTier.ultra,
        shadowMapResolution: _qualityPreset.shadowMapResolution,
      );
      _bindAvatarAppearance();
      _hoveredWaypoint = null;
      _hoveredPedestal = null;
      // Keep the same rig, view pose, page and manually placed library transform.
      // An old in-flight rasterization is invalidated before the replacement.
      _buildLibrary();
      if (_roomController.isOpen) _roomStateChanged();
    } else if (bindingsChanged) {
      _buildLibrary();
      if (_roomController.isOpen) _roomStateChanged();
    }
  }

  Future<void> _buildLibrary() async {
    final generation = ++_libraryGeneration;
    final previous = _library;
    final previousState = previous?.state;
    final catalog = _bindings.catalog;
    final theme = widget.theme;
    try {
      await Scene.initializeStaticResources();
      if (!Scene.isReadyToRender) throw StateError('GPU resources unavailable');
      if (!mounted || generation != _libraryGeneration) return;
      final panel = await VrDemoLibraryPanel.create(
        catalog: catalog,
        theme: theme,
        initialState: previousState == null
            ? null
            : VrDemoLibraryState(
                catalog: catalog,
                category: previousState.category,
                query: previousState.query,
                pageIndex: previousState.pageIndex,
                focusedId: previousState.focusedId,
              ),
        dockActions: [
          ('library', 'Biblioteca'),
          if (_expandedEcosystemRooms.isNotEmpty) ('rooms', 'Salas'),
          (
            VrHomeConstants.optionsActionId,
            VrHomeTranslationConstants.optionsDockLabel,
          ),
          if (_bindings.onPair != null) ('pair', 'Mando QR'),
          if (_bindings.onOpenCastSettings != null) ('cast', 'Compartir vista'),
          if (_bindings.calibrationExperienceId != null)
            ('calibrate', 'Lentes'),
          ('place', 'Colocar'),
          if (_hasAssistant) ('itzli', 'Asistente'),
        ],
        onOpen: (entry) => _openDemo(
          _bindings.preview(
            demoId: entry.id,
            title: entry.title,
            subtitle: entry.subtitle,
            color: Color(entry.accent),
          ),
        ),
        onAction: _libraryAction,
      );
      if (!mounted || generation != _libraryGeneration) {
        panel.dispose();
        return;
      }
      if (previous != null) {
        panel.root.localTransform = previous.root.localTransform.clone();
        panel.root.visible = previous.root.visible;
        _scene.remove(previous.root);
        previous.dispose();
      }
      panel.root.visible = !_hasWorldModal && !_libraryHiddenByUser;
      _library = panel;
      _scene.add(panel.root);
      setState(
        () => _statusMessage =
            'Explora las salas · Izquierdo: caminar · Derecho: mirar · A: elegir',
      );
    } catch (error) {
      if (mounted && generation == _libraryGeneration) {
        setState(() {
          _hudHidden = false;
          _statusMessage = 'Biblioteca no disponible · $error';
        });
      }
    }
  }

  void _libraryAction(String action) {
    switch (action) {
      case 'rooms':
        if (_hasWorldModal || _worldBuilder.ecosystemLayout.portals.isEmpty) {
          return;
        }
        _locomotion.suspendSmoothLocomotion();
        _locomotion.startJump(
          from: _rig.eyeCenter,
          to: vm.Vector3(
            0,
            1.6,
            _worldBuilder.ecosystemLayout.portals.first.z + 2,
          ),
          targetName: 'Plaza de experiencias',
        );
        setState(() {
          _hudHidden = true;
          _statusMessage = 'Entrando a la plaza de experiencias';
        });
      case VrHomeConstants.optionsActionId:
        _showOptionsPanel();
      case 'pair':
        _showPairing();
      case 'cast':
        _locomotion.suspendSmoothLocomotion();
        _bindings.onOpenCastSettings?.call(context);
      case 'calibrate':
        final id = _bindings.calibrationExperienceId;
        final entry = id == null ? null : _bindings.catalog.resolveRoute(id);
        if (entry != null) _openDemoById(entry.id, entry.title);
      case 'itzli':
        _showItzliPanel();
      case 'place':
        final placement = _walkSpace.placePanel(
          eye: _rig.eyeCenter,
          forward: _rig.forward,
          distance: HomeSpatialMetrics.libraryDistance,
          width: 4.2,
        );
        if (placement == null) {
          setState(
            () => _statusMessage =
                'No cabe la biblioteca aquí · Busca un espacio más amplio',
          );
          return;
        }
        _libraryHiddenByUser = false;
        _library?.place(
          VrWorldPose.fromViewer(
            eye: _rig.eyeCenter,
            forward: placement.forward,
            distance: placement.distance,
          ),
        );
        setState(
          () => _statusMessage =
              'Biblioteca colocada aquí · No seguirá tu cabeza',
        );
    }
  }

  bool _isLibraryInFrontOfViewer() {
    final library = _library;
    if (library == null || _libraryHiddenByUser || !library.root.visible) {
      return false;
    }
    final libPos = library.worldPosition;
    final dx = libPos.x - _rig.eyeCenter.x;
    final dz = libPos.z - _rig.eyeCenter.z;
    final horizontalDist = math.sqrt(dx * dx + dz * dz);
    if (horizontalDist > VrHomeConstants.mainMenuNearbyRadiusMeters ||
        horizontalDist < 0.05) {
      return false;
    }
    final dirX = dx / horizontalDist;
    final dirZ = dz / horizontalDist;
    final forwardLen = math.sqrt(
      _rig.forward.x * _rig.forward.x + _rig.forward.z * _rig.forward.z,
    );
    if (forwardLen < 1e-4) return true;
    final dot =
        (dirX * (_rig.forward.x / forwardLen)) +
        (dirZ * (_rig.forward.z / forwardLen));
    return dot >= VrHomeConstants.mainMenuMinForwardDot;
  }

  void _summonOrToggleMainMenu({bool toggleIfAlreadyHere = true}) {
    if (!mounted || _isEnteringDemo || _isDemoActive) return;
    if (!_hasWorldModal && toggleIfAlreadyHere && _isLibraryInFrontOfViewer()) {
      _libraryHiddenByUser = true;
      _library?.root.visible = false;
      HapticFeedback.selectionClick();
      setState(() {
        _statusMessage = VrHomeTranslationConstants.mainMenuHiddenStatus;
      });
      return;
    }
    if (_hasWorldModal) {
      _dismissWorldModal();
    }
    final placement = _walkSpace.placePanel(
      eye: _rig.eyeCenter,
      forward: _rig.forward,
      distance: HomeSpatialMetrics.libraryDistance,
      width: 4.2,
    );
    final pose = placement != null
        ? VrWorldPose.fromViewer(
            eye: _rig.eyeCenter,
            forward: placement.forward,
            distance: placement.distance,
          )
        : VrWorldPose.fromViewer(
            eye: _rig.eyeCenter,
            forward: _rig.forward,
            distance: VrHomeConstants.mainMenuFallbackDistanceMeters,
          );
    _libraryHiddenByUser = false;
    _library?.place(pose);
    _library?.root.visible = !_hasWorldModal;
    _locomotion.suspendSmoothLocomotion();
    HapticFeedback.selectionClick();
    setState(() {
      _hudHidden = true;
      _statusMessage = VrHomeTranslationConstants.mainMenuSummonedStatus;
    });
  }

  void _cycleLibraryCategory(int direction) {
    final library = _library;
    if (library == null || library.busy) return;
    if (!_isLibraryInFrontOfViewer()) {
      _summonOrToggleMainMenu(toggleIfAlreadyHere: false);
    }
    final categories = VrDemoLibraryCategory.values;
    library.setCategory(
      categories[(library.state.category.index + direction) %
          categories.length],
    );
  }

  void _selectScreenPoint(Offset point) {
    if (_isDemoActive || !_hudHidden) return;
    final size = MediaQuery.sizeOf(context);
    final vm.Ray ray;
    if (vrHandheldConsoleMode.value) {
      ray = _rig.centerCamera().screenPointToRay(point, size);
    } else {
      final half = size.width / 2;
      final right = point.dx >= half;
      final camera = _rig.eyeCamera(right ? StereoEye.right : StereoEye.left);
      ray = camera.screenPointToRay(
        Offset(point.dx - (right ? half : 0), point.dy),
        Size(half, size.height),
      );
    }
    final hit = _scene.raycast(
      ray,
      where: _hasWorldModal
          ? _worldModalOwnsInteractiveNode
          : _homeRaycastCandidate,
    );
    if (hit != null && !_worldBuilder.blocksPointer(hit.node)) {
      final event = _arbiter.acquire(
        type: VrInputType.select,
        source: VrInputSource.touch,
      );
      // This screen-position ray owns the action; do not also select head gaze.
      event.consume();
      _arbiter.submit(event);
      _arbiter.release(event);
      if (_hasWorldModal) {
        _handleWorldModalSelect(hit.node);
      } else {
        _onSelect(hit.node);
      }
    } else if (!vrHandheldConsoleMode.value &&
        shouldRevealHomePreparationOnMiss(
          controlsHidden: _hudHidden,
          hasWorldModal: _hasWorldModal,
        )) {
      setState(() => _hudHidden = false);
    }
  }

  void _handleBackAction() {
    // B cancels the current interaction in place. Returning to the plaza's
    // entrance must never be an accidental side effect of braking or closing
    // a room panel, regardless of which controller sent the button.
    _demoAfterJump = null;
    _cancelJumpSafely();
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
    if (_hasWorldModal) {
      _dismissWorldModal();
      return;
    }
    HapticFeedback.selectionClick();
    setState(
      () => _statusMessage =
          'Recorrido detenido · Suelta el stick para volver a caminar',
    );
  }

  void _rememberWalkablePosition() {
    if (!_walkSpace.canStand(_rig.eyeCenter.x, _rig.eyeCenter.z)) return;
    (_lastSafePosition ??= vm.Vector3.zero()).setValues(
      _rig.eyeCenter.x,
      1.6,
      _rig.eyeCenter.z,
    );
  }

  void _cancelJumpSafely() {
    final jump = _locomotion.currentJump;
    if (jump != null) {
      final landing = _walkSpace.settleCancelledJump(
        current: _rig.eyeCenter,
        jumpStart: jump.from,
        lastSafe: _lastSafePosition,
      );
      if (landing != null) _rig.eyeCenter = landing;
    }
    _locomotion.cancelJump();
    _rememberWalkablePosition();
  }

  void _setGamepadAttached(bool attached) {
    if (_gamepadAttached == attached) return;
    _gamepadAttached = attached;
    _bindings.onGamepadConnectionChanged?.call(_gamepadDriver, attached);
  }

  void _syncControllerActions({bool initial = false}) {
    if (!mounted ||
        _isDemoActive ||
        (!initial && !(ModalRoute.of(context)?.isCurrent ?? true))) {
      return;
    }
    // Update only at ownership/modal transitions, never from the frame loop.
    // The service deduplicates unchanged captions and preserves held inputs.
    _remoteController.requestControllerMode(
      RemoteControllerMode.joystick,
      actions: _hasWorldModal
          ? _modalControllerActions
          : _navigationControllerActions,
      horizontalLook: true,
    );
  }

  void _bindHost({bool openPairing = false, bool initial = false}) {
    final generation = ++_hostGeneration;
    _assistantChanges = _bindings.assistantChanges;
    _assistantChanges?.addListener(_assistantStateChanged);
    if (!initial) _locomotion.suspendSmoothLocomotion();
    final guidance = _bindings.guidance;
    if (guidance != null) {
      _subscriptions.add(guidance.listen(_onItzliGuidance));
    }
    final statuses = _bindings.statuses;
    if (statuses != null) {
      _subscriptions.add(
        statuses.listen((status) {
          if (mounted && !_isDemoActive) {
            setState(() => _statusMessage = status);
          }
        }),
      );
    }
    // initState must not look up the inherited ModalRoute. Later host changes
    // and resumes must check route ownership before replacing demo captions.
    _syncControllerActions(initial: initial);
    _isRemoteConnected = _remoteController.isConnected;
    if (_isRemoteConnected) {
      _hudHidden = true;
      _seedHeldRemoteButtons();
      final showLaser = _remoteController.latestState.controllerVisible;
      _laserPointer.visible = showLaser;
      _laserPointer.setLaserBeamActive(showLaser);
    }
    _arbiter.setDwellSuppressed(VrInputSource.remotePhone, _isRemoteConnected);
    _subscriptions.add(
      _remoteController.onConnectionChanged.listen((connected) {
        if (mounted) {
          _arbiter.setDwellSuppressed(VrInputSource.remotePhone, connected);
          _gamepadMotion.reset();
          _locomotion.suspendSmoothLocomotion();
          _bindings.onSound?.call(
            connected ? VrHomeSound.connected : VrHomeSound.disconnected,
          );
          setState(() {
            _isRemoteConnected = connected;
            if (connected) {
              // Remembered controllers can reconnect without reopening the QR
              // route. Enter headset mode on that authenticated edge as well.
              _hudHidden = true;
              _seedHeldRemoteButtons();
            }
            if (!connected) {
              _remoteLaserMode = false;
              _remoteLaserHitsTarget = false;
              _remotePrimaryDown = false;
              _remoteBackDown = false;
              _remotePointer.reset();
              _remoteXDown = _remoteYDown = false;
              _remoteMenuDown = _remoteOptionsDown = false;
              _modalLaserTriggerQueued = false;
              _modalLaserTarget = null;
            }
            final showLaser =
                connected && _remoteController.latestState.controllerVisible;
            _laserPointer.visible = showLaser;
            _laserPointer.setLaserBeamActive(showLaser);
            _statusMessage = connected
                ? '🎮 2º Smartphone conectado como Mando/Joystick VR!'
                : 'Mando remoto desconectado';
          });
        }
      }),
    );

    _subscriptions.add(
      _remoteController.onState.listen((state) {
        if (!mounted ||
            !_foreground ||
            _homeProducersSuspended ||
            _isDemoActive ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }
        if (!_isRemoteConnected && _remoteController.isConnected) {
          _arbiter.setDwellSuppressed(VrInputSource.remotePhone, true);
          setState(() {
            _isRemoteConnected = true;
            _hudHidden = true;
          });
        }
        if (state.isNeutralized) {
          // The watchdog's synthetic release cancels travel and its heading
          // target, but cannot count as the user's fresh neutral gesture.
          _locomotion.suspendSmoothLocomotion();
        }
        final hasLaserAim =
            state.laserX.abs() > 0.04 || state.laserY.abs() > 0.04;
        final laserMode = VrHomeRemotePointer.isPointing(state);
        if (_remoteLaserMode != laserMode) {
          setState(() {
            _remoteLaserMode = laserMode;
            _remoteLaserHitsTarget = false;
            _modalLaserTriggerQueued = false;
            _modalLaserTarget = null;
            _hoveredPedestal = null;
            _hoveredWaypoint = null;
          });
        }
        _laserPointer.visible = _isRemoteConnected && state.controllerVisible;
        _laserPointer.setLaserBeamActive(
          _isRemoteConnected && state.controllerVisible,
        );
        _laserPointer.setStickDeflection(
          hasLaserAim ? state.laserX : state.stickX,
          hasLaserAim ? state.laserY : state.stickY,
          lookX: state.lookX,
          lookY: state.lookY,
        );

        final isManipulating =
            state.isTriggerPressed ||
            state.btnA ||
            state.btnB ||
            state.btnX ||
            state.btnY ||
            state.btnL ||
            state.btnR ||
            state.stickClick ||
            state.btnGrip ||
            state.laserSlideActive ||
            state.stickX.abs() > 0.015 ||
            state.stickY.abs() > 0.015 ||
            state.turnRate.abs() > 0.015 ||
            state.pitchRate.abs() > VrStickLook.verticalDeadZone ||
            hasLaserAim;

        final event = _arbiter.acquire(
          // Home owns discrete selection below. This only renews dwell suppression.
          type: VrInputType.navigate,
          source: VrInputSource.remotePhone,
          active: isManipulating,
        );
        _arbiter.submit(event);
        _arbiter.release(event);

        final backPressed = state.btnB || state.isActionPressed;
        final primaryPressed = state.btnA;
        final menuPressed = state.btnL || state.stickClick;
        final optionsPressed = state.btnR;
        if (menuPressed && !_remoteMenuDown) {
          _summonOrToggleMainMenu(toggleIfAlreadyHere: true);
        }
        if (optionsPressed && !_remoteOptionsDown) {
          if (_optionsOpen) {
            _dismissOptionsPanel();
          } else {
            _showOptionsPanel();
          }
        }
        _remoteMenuDown = menuPressed;
        _remoteOptionsDown = optionsPressed;
        if (!_hasWorldModal) {
          if (state.btnX && !_remoteXDown) _cycleLibraryCategory(-1);
          if (state.btnY && !_remoteYDown) _cycleLibraryCategory(1);
        }
        _remoteXDown = state.btnX;
        _remoteYDown = state.btnY;
        if (_hasWorldModal) {
          _handleWorldModalNavigation(state.stickX, state.stickY);
        }
        if (backPressed && !_remoteBackDown) {
          _handleBackAction();
        } else if (primaryPressed && !_remotePrimaryDown && !backPressed) {
          if (laserMode) {
            // Consume this edge after the same frame's touch-pad raycast;
            // a press must never activate a stale/default modal option.
            if (!_hasWorldModal || _worldModalReady) {
              _modalLaserTriggerQueued = true;
            }
          } else {
            _handleRemoteTrigger();
          }
        }
        _remoteBackDown = backPressed;
        _remotePrimaryDown = primaryPressed;
        // Grip is generated automatically by a held touch pad. It is not a
        // calibration command; manual recenter remains explicit on the remote.
      }),
    );

    final shouldOpenPairing = openPairing || _pendingInitialPairing;
    unawaited(
      (_bindings.ready ?? Future<void>.value())
          .then((_) {
            if (mounted && generation == _hostGeneration && shouldOpenPairing) {
              _pendingInitialPairing = false;
              _showPairing();
            }
          })
          .catchError((Object error) {
            if (mounted && generation == _hostGeneration) {
              setState(() => _statusMessage = 'Mando no disponible: $error');
            }
          }),
    );
  }

  Future<void> _showPairing() async {
    if (!mounted ||
        _isDemoActive ||
        _hasWorldModal ||
        _bindings.onPair == null) {
      return;
    }
    setState(() => _isDemoActive = true);
    var paired = false;
    try {
      _suspendHomeProducers();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      paired = await _bindings.onPair!(context);
      if (mounted && paired && _remoteController.isConnected) {
        // The authenticated route result enters headset mode automatically.
        // A held during pairing must be released before opening anything.
        _hudHidden = true;
        _statusMessage = 'Mando listo · A: elegir · B: detener / cerrar';
      }
    } catch (error, stackTrace) {
      debugPrint('Could not open Home pairing: $error\n$stackTrace');
      if (mounted) {
        _hudHidden = false;
        _statusMessage = 'No se pudo abrir el emparejamiento';
      }
    } finally {
      if (mounted) {
        _pairingSplashTimer?.cancel();
        _postPairingFrames = 0;
        setState(() {
          _isDemoActive = false;
          _isReturningFromPairing = true;
        });
        _pairingSplashTimer = Timer(const Duration(milliseconds: 700), () {
          if (mounted && _isReturningFromPairing) {
            setState(() => _isReturningFromPairing = false);
          }
        });
        _resumeHomeProducers();
      }
    }
  }

  /// A/B used by a covered route are not fresh Home actions on return.
  void _seedHeldRemoteButtons() {
    final state = _remoteController.latestState;
    _remotePrimaryDown = state.btnA;
    _remoteBackDown = state.btnB || state.isActionPressed;
    _remoteXDown = state.btnX;
    _remoteYDown = state.btnY;
    _remoteMenuDown = state.btnL || state.stickClick;
    _remoteOptionsDown = state.btnR;
    _remoteLaserMode =
        _isRemoteConnected && VrHomeRemotePointer.isPointing(state);
    _remoteLaserHitsTarget = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
  }

  void _resumeHomeProducers() {
    // A reconnect can update button edges while another route owns hardware.
    // Only completion of the covered operation may reattach Home's adapter.
    if (!_foreground ||
        !TickerMode.valuesOf(context).enabled ||
        _isDemoActive ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _homeProducersSuspended = false;
    final connectedNow = _remoteController.isConnected;
    if (_isRemoteConnected != connectedNow) {
      _isRemoteConnected = connectedNow;
    }
    _arbiter.setDwellSuppressed(VrInputSource.remotePhone, _isRemoteConnected);
    _seedHeldRemoteButtons();
    _syncControllerActions();
    _setGamepadAttached(true);
  }

  /// StereoSceneView owns its IMU/spatial producers and stops them on unmount.
  /// Home only suspends its additional input producers here.
  void _suspendHomeProducers({bool rebuild = true}) {
    if (_homeProducersSuspended) return;
    _homeProducersSuspended = true;
    _dismissItzliPanel(
      announce: false,
      haptic: false,
      cancelAssistant: false,
      rebuild: rebuild,
    );
    _dismissOptionsPanel(announce: false, haptic: false, rebuild: rebuild);
    _closeRoomPanel(rebuild: rebuild);
    _demoAfterJump = null;
    _cancelJumpSafely();
    _setGamepadAttached(false);
    _bindings.onSuspend?.call();
    _remotePointer.reset();
    _homeGamepad.reset();
    _gamepadMotion.reset();
    _locomotion.suspendSmoothLocomotion();
    _remoteLaserHitsTarget = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
  }

  Future<void> _showCatalog() async {
    if (!mounted ||
        _isDemoActive ||
        _hasWorldModal ||
        _bindings.onCatalog == null) {
      return;
    }
    setState(() => _isDemoActive = true);
    VrHomeCatalogExit? result;
    Object? openError;
    try {
      _suspendHomeProducers();
      // Remove the GPU surface before pushing the catalog or any of its demos.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      result = await _bindings.onCatalog!(context);
    } catch (error, stackTrace) {
      openError = error;
      debugPrint('Could not open Home catalog: $error\n$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _isDemoActive = false;
          if (openError != null) _hudHidden = false;
          _statusMessage = openError == null
              ? 'Biblioteca · El mando conserva su emparejamiento'
              : 'No se pudo abrir el catálogo';
        });
        _resumeHomeProducers();
      }
    }
    if (mounted && result == VrHomeCatalogExit.pairController) {
      await _showPairing();
    }
  }

  void _createRoomController() {
    _roomController = VrHomeRoomController(
      callback: (room, actionId) async {
        if (room.purpose == VrHomeRoomPurpose.portableWorld &&
            room.targetRouteId != null) {
          if (actionId == VrHomeConstants.worldPortalEnterActionId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _closeRoomPanel();
              _openDemoById(room.targetRouteId!, room.title);
            });
          }
          return VrHomeRoomPresentation(
            title: room.title,
            subtitle: VrHomeTranslationConstants.portableWorldEyebrow,
            description: room.description,
            actions: const [
              VrHomeRoomAction(
                id: VrHomeConstants.worldPortalEnterActionId,
                label: VrHomeTranslationConstants.portableWorldEnterActionLabel,
              ),
            ],
          );
        }
        final hostCallback = _bindings.onRoomAction;
        if (hostCallback != null) {
          return hostCallback(room, actionId);
        }
        return VrHomeRoomPresentation(
          title: room.title,
          description: room.description,
        );
      },
      roomChanges: _bindings.roomChanges,
      onInvalidated: () => _bindings.onRoomClosed?.call(),
    )..addListener(_roomStateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A room callback can push a route without going through _enterDemo.
    // Rebuild already follows this inherited dependency change: remove the
    // live GPU surface while preserving Home's retained scene and camera rig.
    _routeVisible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (!_foreground || !_routeVisible) {
      _suspendHomeProducers(rebuild: false);
    } else {
      _resumeHomeProducers();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _suspendHomeProducers();
    } else {
      _resumeHomeProducers();
    }
  }

  Future<void> _openEcosystemRoom(VrHomeEcosystemRoom room) async {
    if (!mounted ||
        !_foreground ||
        _isEnteringDemo ||
        _isDemoActive ||
        _hasWorldModal ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final placement = _modalPlacement();
    if (placement == null) return;
    _locomotion.cancelJump();
    _locomotion.suspendSmoothLocomotion();
    _roomPose = VrWorldPose.fromViewer(
      eye: _rig.eyeCenter.clone(),
      forward: placement.forward,
      distance: placement.distance,
    );
    _hudHidden = true;
    _hoveredPedestal = null;
    _hoveredWaypoint = null;
    _roomController.openRoom(room);
  }

  void _roomStateChanged() {
    // Remove old content before any asynchronous rasterization or host request.
    // Account invalidation therefore never leaves the previous user's panel up.
    final generation = ++_roomPanelGeneration;
    _roomPanel?.removeFrom(_scene);
    _roomPanel = null;
    _modalNavigationLatched = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
    final controller = _roomController;
    final room = controller.room;
    final pose = _roomPose;
    if (!identical(_roomPresentation, controller.presentation)) {
      _roomPresentation = controller.presentation;
      _roomPage = 0;
    }
    _statusMessage = room == null
        ? 'Explora las salas · A: elegir'
        : '${room.title} · ${controller.busy ? "Cargando…" : "B: cerrar"}';
    if (mounted && !_suppressRoomRebuild) {
      _syncControllerActions();
      setState(() {});
    }
    if (!mounted || room == null || pose == null) return;
    unawaited(
      createVrHomeRoomPanel(
            room: room,
            pose: pose,
            presentation: controller.presentation,
            content:
                !controller.busy &&
                    controller.error == null &&
                    controller.presentation != null
                ? _bindings.roomContentBuilder?.call(
                    room,
                    controller.presentation!,
                  )
                : null,
            busy: controller.busy,
            error: controller.error,
            pageIndex: _roomPage,
            onAction: (id) => unawaited(controller.activate(id)),
            onRetry: () => unawaited(controller.retry()),
            onClose: _closeRoomPanel,
            onPage: (page) {
              _roomPage = page;
              _roomStateChanged();
            },
          )
          .then((panel) {
            if (!mounted ||
                generation != _roomPanelGeneration ||
                !identical(controller, _roomController) ||
                !controller.isOpen) {
              return;
            }
            // The pose captured at opening stays unchanged while catalog pages load.
            panel.addTo(_scene);
            _roomPanel = panel;
            setState(
              () => _statusMessage =
                  '${room.title} · Mirada, A o láser · B: cerrar',
            );
          })
          .catchError((Object error, StackTrace stack) {
            if (!mounted || generation != _roomPanelGeneration) return;
            debugPrint('Could not create spatial room panel: $error\n$stack');
            // B still closes a panel whose GPU allocation failed.
            setState(
              () => _statusMessage = 'No se pudo dibujar la sala · B: cerrar',
            );
          }),
    );
  }

  void _closeRoomPanel({bool rebuild = true, bool notifyHost = true}) {
    if (!_roomController.isOpen) return;
    final room = _roomController.room;
    _suppressRoomRebuild = !rebuild;
    _roomController.close();
    _suppressRoomRebuild = false;
    _roomPose = null;
    _roomPresentation = null;
    _locomotion.suspendSmoothLocomotion();
    if (room != null) _portalRearm.block('room:${room.id}', _rig.forward);
    if (notifyHost) _bindings.onRoomClosed?.call();
  }

  void _handleRemoteTrigger() {
    if (!_hudHidden && !_isRemoteConnected) return;
    if (_hasWorldModal) {
      _activateWorldModalFocused();
      return;
    }
    // First prefer the exact interactive target under head gaze.
    final hit = _scene.raycast(
      vm.Ray.originDirection(_rig.eyeCenter, _rig.forward),
      where: _homeRaycastCandidate,
    );
    if (hit != null && !_worldBuilder.blocksPointer(hit.node)) {
      _onSelect(hit.node);
      return;
    }
    // When facing the Library panel (for example when un-reticled head gaze
    // rests on a card frame, gap, title or panel background), A activates the
    // highlighted card/action without ever opening a stale card after walking away.
    final library = _library;
    if (library != null && _isLibraryInFrontOfViewer()) {
      _bindings.onSound?.call(VrHomeSound.open);
      library.activateFocused();
    }
  }

  void _onItzliGuidance(VrHomeGuidance g) {
    if (!mounted ||
        _isDemoActive ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    if (_itzliOpen) {
      if (g.actionType != VrHomeActionType.conversationalGuidance) {
        _dismissItzliPanel(
          announce: false,
          haptic: false,
          cancelAssistant: false,
        );
      }
    }
    setState(() => _statusMessage = '✨ ${g.speechResponse}');
    switch (g.actionType) {
      case VrHomeActionType.jumpToWing:
        if (g.targetWingId != null) {
          _jumpToWaypointId(g.targetWingId!);
        }
        break;
      case VrHomeActionType.launchExperience:
        if (g.targetWingId != null) {
          _jumpToWaypointId(g.targetWingId!);
        }
        if (g.targetDemoId != null) {
          _openDemoById(g.targetDemoId!, g.targetDemoTitle ?? g.targetDemoId!);
        }
        break;
      case VrHomeActionType.changeLook:
        if (g.targetLook != null) {
          setState(() {
            _currentLook = g.targetLook == VrLook.standard
                ? VirtualHomeWorldBuilder.naturalLook
                : g.targetLook!;
            if (_currentLook == VirtualHomeWorldBuilder.naturalLook) {
              _lookName = 'Natural';
            }
            if (_currentLook == VrLook.cyberpunk) _lookName = 'Cyberpunk Neón';
            if (_currentLook == VrLook.stellar) {
              _lookName = '🌌 Nebulosa Estelar';
            }
            if (_currentLook == VrLook.cinematic) {
              _lookName = '🎬 Cinematográfica';
            }
            if (_currentLook == VrLook.night) _lookName = '🌙 Espacio Profundo';
          });
        }
        break;
      case VrHomeActionType.changeResolution:
        if (g.targetPreset != null) {
          final enableShadows =
              g.targetPreset!.tier == VrQualityTier.high ||
              g.targetPreset!.tier == VrQualityTier.ultra;
          _worldBuilder.setShadowsEnabled(
            enableShadows,
            shadowMapResolution: g.targetPreset!.shadowMapResolution,
          );
          setState(() => _qualityPreset = g.targetPreset!);
        }
        break;
      case VrHomeActionType.recenter:
        _recenterView();
        break;
      case VrHomeActionType.switchCatalog2D:
        _showCatalog();
        break;
      case VrHomeActionType.conversationalGuidance:
        break;
    }
  }

  void _recenterView() {
    _locomotion.suspendSmoothLocomotion();
    _rig.recenter();
    HapticFeedback.mediumImpact();
    setState(() => _statusMessage = 'Vista recentrada al frente');
  }

  void _jumpToWaypointId(String id) {
    if (_hasWorldModal) {
      setState(() {
        _statusMessage = 'Elige una opción del panel antes de moverte';
      });
      return;
    }
    // Library replaces locomotion between wings; old voice actions still work.
    if (_library != null) {
      final category = switch (id) {
        'north_games' => VrDemoLibraryCategory.games,
        'east_prod' => VrDemoLibraryCategory.productivity,
        'west_media' => VrDemoLibraryCategory.learn,
        'south_labs' => VrDemoLibraryCategory.lab,
        _ => VrDemoLibraryCategory.featured,
      };
      _library!.setCategory(category);
      return;
    }
    final wp = _worldBuilder.waypoints.firstWhere(
      (w) => w.id == id,
      orElse: () => _worldBuilder.waypoints.first,
    );
    _locomotion.startJump(
      from: _rig.eyeCenter,
      to: vm.Vector3(wp.position.x, 1.60, wp.position.z),
      targetName: wp.name,
    );
    setState(() {
      _statusMessage = 'Saltando a ${wp.name}...';
    });
  }

  @override
  void dispose() {
    _pairingSplashTimer?.cancel();
    vrHandheldConsoleMode.removeListener(_onHandheldModeChanged);
    _avatarAppearance?.removeListener(_avatarAppearanceChanged);
    WidgetsBinding.instance.removeObserver(this);
    _assistantChanges?.removeListener(_assistantStateChanged);
    _assistantRefreshTimer?.cancel();
    _assistantSession++;
    _closeRoomPanel(rebuild: false);
    _roomController.removeListener(_roomStateChanged);
    _roomController.dispose();
    _roomPanelGeneration++;
    _libraryGeneration++;
    _hostGeneration++;
    _itzliGeneration++;
    _optionsGeneration++;
    _itzliPanel?.removeFrom(_scene);
    _optionsPanel?.removeFrom(_scene);
    if (_library != null) {
      _scene.remove(_library!.root);
      _library!.dispose();
    }
    _setGamepadAttached(false);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _worldBuilder.dispose();
    _arbiter.dispose();
    super.dispose();
  }

  // ─── Frame Loop ─────────────────────────────────────────────────────

  void _tick(Duration elapsed, double dt) {
    if (!_foreground ||
        _homeProducersSuspended ||
        _isDemoActive ||
        !TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    if (_isReturningFromPairing) {
      _postPairingFrames++;
      if (_postPairingFrames >= 4) {
        _pairingSplashTimer?.cancel();
        _pairingSplashTimer = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isReturningFromPairing) {
            setState(() => _isReturningFromPairing = false);
          }
        });
      }
    }
    _rememberWalkablePosition();
    _time += dt;
    _portalRearm.update(_rig.forward);

    // 1. Process Parabolic Arc Jump Locomotion
    final (newPos, isFinished, arrivedName) = _locomotion.tick(
      dt,
      _rig.eyeCenter,
    );
    _rig.eyeCenter = newPos;
    if (isFinished && arrivedName != null) {
      setState(() {
        _currentZoneName = arrivedName;
        _statusMessage = 'Llegaste a $_currentZoneName';
      });
      final request = _demoAfterJump;
      _demoAfterJump = null;
      if (request != null) {
        _openDemo(request);
      }
    }

    // Home owns movement because its walls and furniture need XZ collisions.
    // The scene's generic input integration remains disabled below.
    if ((_hudHidden || _isRemoteConnected) && !_locomotion.isJumping) {
      final state = _remoteController.latestState;
      if (_isRemoteConnected && state.recenter && !_lastRemoteRecenter) {
        _recenterView();
      }
      _lastRemoteRecenter = state.recenter;
      final turnRate = _isRemoteConnected
          ? state.turnRate
          : _gamepadMotion.lookX;
      final pitchRate = _isRemoteConnected
          ? state.pitchRate
          : _gamepadMotion.lookY;
      final frameDt = dt.isFinite ? dt.clamp(0.0, 0.1) : 0.0;
      final manualLook =
          turnRate.abs() > 0.015 ||
          pitchRate.abs() > VrStickLook.verticalDeadZone;
      if (manualLook) {
        applyHomeLookRotation(_rig, turnRate, pitchRate, frameDt);
      }
      if (!_hasWorldModal && (!_isRemoteConnected || !state.isNeutralized)) {
        _rig.eyeCenter = _locomotion.applySmoothRigLocomotion(
          rig: _rig,
          stickX: _isRemoteConnected ? state.stickX : _gamepadMotion.moveX,
          stickY: _isRemoteConnected ? state.stickY : _gamepadMotion.moveY,
          atEdge: _isRemoteConnected
              ? state.moveAtEdge
              : _gamepadMotion.moveAtEdge,
          edgeTurnEnabled: _isRemoteConnected || _gamepadMotion.edgeTurnEnabled,
          // The right control may adjust elevation while the left owns the
          // heading. Only an explicit horizontal look overrides that turn.
          manualLook: turnRate.abs() > 0.015,
          dt: frameDt,
          speed: 1.6,
          maxSpeed: 4.8,
          accelerationSeconds: 2.4,
          walkSpace: _walkSpace,
        );
        // The controller's image UVs and acoustic echo are not a measured
        // viewer height. Only the visor's own pose may translate its eyes.
        final room = _walkSpace.roomAt(_rig.eyeCenter.x, _rig.eyeCenter.z);
        if (room != null && room.title != _currentZoneName) {
          setState(() {
            _currentZoneName = room.title;
            _statusMessage =
                '${room.title} · Apunta a una exhibición y pulsa A';
          });
        }
      }
    }

    _rememberWalkablePosition();

    // 2. Static rooms and world-locked UI feedback.
    _worldBuilder.tick(
      _time,
      eyePosition: _rig.eyeCenter,
      hoveredWaypoint: _hoveredWaypoint,
      hoveredPedestal: _hoveredPedestal,
    );
    _itzliPanel?.update(dt);
    _roomPanel?.update(dt);
    _optionsPanel?.update(dt);
    if (_library != null) {
      _library!.root.visible = !_hasWorldModal && !_libraryHiddenByUser;
    }

    // 3. Update 3D Controller & Laser Pointer for 2nd Smartphone Remote Controller
    if (_isRemoteConnected) {
      final state = _remoteController.latestState;
      final hasLaserAim =
          state.laserX.abs() > 0.04 || state.laserY.abs() > 0.04;
      final isLaser = VrHomeRemotePointer.isPointing(state);
      _laserPointer.visible = state.controllerVisible;
      _laserPointer.setLaserBeamActive(state.controllerVisible);
      _laserPointer.setStickDeflection(
        hasLaserAim ? state.laserX : state.stickX,
        hasLaserAim ? state.laserY : state.stickY,
        lookX: state.lookX,
        lookY: state.lookY,
      );

      _remotePointer.resolve(state: state, rig: _rig);
      final (laserOrigin, laserDir) = _laserPointer.update(
        cameraRig: _rig.cameraRig,
        orientation: _remotePointer.orientation,
        forwardDirection: _remotePointer.forward,
        // Acoustic echo range does not identify the other phone. Preserve
        // the 3DoF arm model until a calibrated optical mount supplies pose.
        isTriggerPressed: state.btnA,
        dt: dt,
      );

      // Quest-style ray: the beam is only a short stub at the hand; the
      // target is shown by a reticle on whatever surface the ray touches.
      // The pointer's own meshes are not raycastable, so it never hits itself.
      if (state.controllerVisible) {
        final surface = _scene.raycast(
          vm.Ray.originDirection(laserOrigin, laserDir),
          maxDistance: _laserReticleRange,
        );
        _laserPointer.setHit(
          point: surface?.worldPoint,
          normal: surface?.worldNormal,
          eye: _rig.eyeCenter,
        );
        if (isLaser && (_hudHidden || _isRemoteConnected)) {
          _checkLaserIntersection(laserOrigin, laserDir);
        } else if (!isLaser) {
          if (_remoteLaserHitsTarget) {
            setState(() => _remoteLaserHitsTarget = false);
          }
          _modalLaserTriggerQueued = false;
        }
      } else {
        if (_remoteLaserHitsTarget) {
          setState(() => _remoteLaserHitsTarget = false);
        }
        _laserPointer.setHit(point: null, eye: _rig.eyeCenter);
        if (_modalLaserTriggerQueued) {
          _modalLaserTriggerQueued = false;
          _handleRemoteTrigger();
        }
      }
    }
  }

  void _checkLaserIntersection(vm.Vector3 origin, vm.Vector3 dir) {
    if (_hasWorldModal) {
      final hit = _worldModalReady
          ? _scene.raycast(
              vm.Ray.originDirection(origin, dir),
              where: _worldModalOwnsInteractiveNode,
            )
          : null;
      _modalLaserTarget = hit?.node;
      final target = _modalLaserTarget;
      if (_remoteLaserHitsTarget != (target != null)) {
        setState(() => _remoteLaserHitsTarget = target != null);
      }
      if (target != null) {
        _handleWorldModalHover(target);
      }
      if (_modalLaserTriggerQueued) {
        _modalLaserTriggerQueued = false;
        if (target != null) {
          _handleWorldModalSelect(target);
        } else {
          _activateWorldModalFocused();
        }
      }
      return;
    }

    if (_library != null || _worldBuilder.pedestals.isEmpty) {
      final hit = _scene.raycast(
        vm.Ray.originDirection(origin, dir),
        where: _homeRaycastCandidate,
      );
      final interactiveNode =
          (hit != null && !_worldBuilder.blocksPointer(hit.node))
          ? hit.node
          : null;
      if (_remoteLaserHitsTarget != (interactiveNode != null)) {
        setState(() => _remoteLaserHitsTarget = interactiveNode != null);
      }
      if (interactiveNode != null) {
        _library?.hover(interactiveNode);
        final room = _worldBuilder.roomFor(interactiveNode);
        if (room != null) _announceRoom(room);
        final exhibit = _worldBuilder.exhibitFor(interactiveNode);
        if (exhibit != null) {
          final message = '${exhibit.title} · A: abrir experiencia';
          if (_statusMessage != message) {
            setState(() => _statusMessage = message);
          }
        }
      }
      if (_modalLaserTriggerQueued) {
        _modalLaserTriggerQueued = false;
        if (interactiveNode != null) {
          _onSelect(interactiveNode);
        } else {
          _handleRemoteTrigger();
        }
      }
      return;
    }

    PortalPedestal? closestPedestal;
    double minPedDist = 0.55;

    for (final p in _worldBuilder.pedestals) {
      final toTarget = p.position - origin;
      final t = toTarget.dot(dir);
      if (t > 0.3 && t < 12.0) {
        final closestPoint = origin + (dir * t);
        final dist = (p.position - closestPoint).length;
        if (dist < minPedDist) {
          minPedDist = dist;
          closestPedestal = p;
        }
      }
    }

    if (closestPedestal != null) {
      if (_hoveredPedestal != closestPedestal) {
        _bindings.onSound?.call(VrHomeSound.hover);
        setState(() {
          _hoveredPedestal = closestPedestal;
          _hoveredWaypoint = null;
          _statusMessage =
              '🎯 Láser: ${closestPedestal!.title} (Presiona Gatillo)';
        });
        HapticFeedback.selectionClick();
      }
      return;
    }

    FloorWaypoint? closestWp;
    double minWpDist = 0.75;

    for (final wp in _worldBuilder.waypoints) {
      final toTarget = wp.position - origin;
      final t = toTarget.dot(dir);
      if (t > 0.3 && t < 12.0) {
        final closestPoint = origin + (dir * t);
        final dist = (wp.position - closestPoint).length;
        if (dist < minWpDist) {
          minWpDist = dist;
          closestWp = wp;
        }
      }
    }

    if (closestWp != null) {
      if (_hoveredWaypoint != closestWp) {
        setState(() {
          _hoveredWaypoint = closestWp;
          _hoveredPedestal = null;
          _statusMessage =
              '🎯 Láser: ${closestWp!.name} (Presiona Gatillo para saltar)';
        });
        HapticFeedback.selectionClick();
      }
    } else if (_hoveredWaypoint != null || _hoveredPedestal != null) {
      setState(() {
        _hoveredWaypoint = null;
        _hoveredPedestal = null;
      });
    }
  }

  // ─── Look & Resolution Switchers ───────────────────────────────────

  void _cycleVisualLook() {
    setState(() {
      if (_currentLook == VrLook.cyberpunk) {
        _currentLook = VrLook.stellar;
        _lookName = '🌌 Nebulosa Estelar';
      } else if (_currentLook == VrLook.stellar) {
        _currentLook = VrLook.cinematic;
        _lookName = '🎬 Cinematográfica';
      } else if (_currentLook == VrLook.cinematic) {
        _currentLook = VrLook.night;
        _lookName = '🌙 Espacio Profundo';
      } else {
        _currentLook = VrLook.cyberpunk;
        _lookName = '⚡ Cyberpunk Neón';
      }
      _statusMessage = 'Ajuste visual: $_lookName';
      HapticFeedback.mediumImpact();
    });
  }

  void _toggleResolution() {
    setState(() {
      if (_qualityPreset.tier == VrQualityTier.ultra) {
        _qualityPreset = VrQualityPreset.medium;
        _statusMessage = 'Nivel: MEDIUM 1.0x · Resolución nativa';
      } else if (_qualityPreset.tier == VrQualityTier.medium ||
          _qualityPreset.tier == VrQualityTier.low) {
        _qualityPreset = VrQualityPreset.high;
        _statusMessage = 'Nivel: STANDARD 1.0x (Equilibrado Nativo)';
      } else {
        _qualityPreset = VrQualityPreset.ultra;
        _statusMessage = 'Nivel: PRO 1.15x (Supersampling Máxima Nitidez)';
      }
      final enableShadows =
          _qualityPreset.tier == VrQualityTier.high ||
          _qualityPreset.tier == VrQualityTier.ultra;
      _worldBuilder.setShadowsEnabled(
        enableShadows,
        shadowMapResolution: _qualityPreset.shadowMapResolution,
      );
      HapticFeedback.selectionClick();
    });
  }

  // ─── Gaze & Selection Handlers ─────────────────────────────────────

  void _onHover(Node? node) {
    // The laser owns pointing only while actively hitting an interactive target.
    // Holding the phone flat as a gamepad yields hover back to head gaze.
    if (shouldLaserOwnHomeHover(
      isRemoteConnected: _isRemoteConnected,
      remoteLaserMode: _remoteLaserMode,
      remoteLaserHitsTarget: _remoteLaserHitsTarget,
    )) {
      return;
    }
    if (_hasWorldModal) {
      _handleWorldModalHover(node);
      final label = _worldModalFocusedLabel;
      if (label != null && _statusMessage != label) {
        setState(() => _statusMessage = label);
      }
      return;
    }
    final room = _worldBuilder.roomFor(node);
    if (room != null) {
      _library?.hover(null);
      _announceRoom(room);
      return;
    }
    if (_library != null) {
      _library!.hover(node);
      final exhibit = _worldBuilder.exhibitFor(node);
      if (exhibit != null) {
        final message = '${exhibit.title} · A: abrir experiencia';
        if (_statusMessage != message) setState(() => _statusMessage = message);
      }
      return;
    }

    if (node == null) {
      if (_hoveredPedestal != null || _hoveredWaypoint != null) {
        setState(() {
          _hoveredPedestal = null;
          _hoveredWaypoint = null;
          _statusMessage = !_hasAssistant
              ? 'Zona: $_currentZoneName · Explora las experiencias'
              : 'Zona: $_currentZoneName · Abre ${_bindings.assistantTitle}';
        });
      }
      return;
    }

    for (final wp in _worldBuilder.waypoints) {
      if (node.name.contains(wp.id)) {
        if (_hoveredWaypoint != wp) {
          setState(() {
            _hoveredWaypoint = wp;
            _hoveredPedestal = null;
            _statusMessage =
                'Saltar a: ${wp.name} (Mantén mirada o pulsa el gatillo)';
          });
          HapticFeedback.selectionClick();
        }
        return;
      }
    }

    for (final p in _worldBuilder.pedestals) {
      if (node.name.contains(p.demoId)) {
        if (_hoveredPedestal != p) {
          setState(() {
            _hoveredPedestal = p;
            _hoveredWaypoint = null;
            _statusMessage =
                '${p.title} · ${p.subtitle} (Mantén mirada o toca visor para entrar)';
          });
          HapticFeedback.selectionClick();
          _bindings.onSound?.call(VrHomeSound.hover);
        }
        return;
      }
    }
  }

  void _announceRoom(VrHomeEcosystemRoom room) {
    final message = '${room.title} · A: explorar en VR';
    if (_statusMessage != message) setState(() => _statusMessage = message);
  }

  void _onSelect(Node node) {
    if (_hasWorldModal) {
      _bindings.onSound?.call(VrHomeSound.click);
      _handleWorldModalSelect(node);
      return;
    }
    if (_worldBuilder.blocksPointer(node)) return;
    _bindings.onSound?.call(VrHomeSound.open);
    final room = _worldBuilder.roomFor(node);
    if (room != null) {
      unawaited(_openEcosystemRoom(room));
      return;
    }
    final exhibit = _worldBuilder.exhibitFor(node);
    if (exhibit != null) {
      _openDemoById(exhibit.demoId, exhibit.title);
      return;
    }
    if (_library != null) {
      _library!.select(node);
      return;
    }

    if (_hoveredWaypoint != null && node.name.contains(_hoveredWaypoint!.id)) {
      final wp = _hoveredWaypoint!;
      _locomotion.startJump(
        from: _rig.eyeCenter,
        to: vm.Vector3(wp.position.x, 1.60, wp.position.z),
        targetName: wp.name,
      );
      return;
    }

    if (_hoveredPedestal != null &&
        node.name.contains(_hoveredPedestal!.demoId)) {
      final p = _hoveredPedestal!;
      HapticFeedback.heavyImpact();
      _openDemo(_previewPedestal(p));
    }
  }

  DemoPreviewData _previewPedestal(PortalPedestal pedestal) =>
      _bindings.preview(
        demoId: pedestal.demoId,
        title: pedestal.title,
        subtitle: pedestal.subtitle,
        color: pedestal.color,
      );

  void _openDemoById(String demoId, String title) {
    PortalPedestal? pedestal;
    for (final candidate in _worldBuilder.pedestals) {
      if (candidate.demoId == demoId) {
        pedestal = candidate;
        break;
      }
    }
    _openDemo(
      pedestal != null
          ? _previewPedestal(pedestal)
          : _bindings.preview(demoId: demoId, title: title),
    );
  }

  HomePanelPlacement? _modalPlacement() {
    final placement = _walkSpace.placePanel(
      eye: _rig.eyeCenter,
      forward: _rig.forward,
      distance: HomeSpatialMetrics.modalDistance,
    );
    if (placement == null && mounted) {
      setState(
        () => _statusMessage =
            'Acércate al centro de la sala para abrir la ficha',
      );
    }
    return placement;
  }

  void _openDemo(DemoPreviewData data) {
    if (!mounted || _isEnteringDemo || _isDemoActive) return;
    if (_locomotion.isJumping) {
      _demoAfterJump = data;
      setState(() => _statusMessage = 'Abriendo ${data.title} al llegar');
      return;
    }
    unawaited(_enterDemo(data));
  }

  Future<void> _enterDemo(DemoPreviewData data) async {
    if (!mounted || _isEnteringDemo || _isDemoActive) return;
    _isEnteringDemo = true;
    _locomotion.suspendSmoothLocomotion();
    _remoteLaserHitsTarget = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
    setState(() {
      _isDemoActive = true;
      _statusMessage = 'Abriendo ${data.title}…';
    });
    HapticFeedback.heavyImpact();

    Object? openError;
    try {
      // The Home owns a live flutter_scene surface and head tracker.
      // Release those producers before creating a demo surface so a
      // low-memory Android phone never renders two VR worlds concurrently.
      _suspendHomeProducers();
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      await _bindings.onLaunch(context, data);
    } catch (error, stackTrace) {
      openError = error;
      debugPrint('Could not open ${data.demoId}: $error\n$stackTrace');
    } finally {
      _isEnteringDemo = false;
      if (mounted) {
        _portalRearm.block(data.demoId, _rig.forward);
        setState(() {
          _isDemoActive = false;
          // A failed local package validation must not disappear into a hidden
          // headset HUD. Expose the existing recovery controls and message.
          if (openError != null) _hudHidden = false;
          _statusMessage = openError == null
              ? 'Regresaste de ${data.title}'
              : 'No se pudo abrir ${data.title} · Vuelve a seleccionar la experiencia';
          _hoveredPedestal = null;
          _hoveredWaypoint = null;
        });
        _resumeHomeProducers();
      }
    }
  }

  bool _worldModalOwnsInteractiveNode(Node node) {
    if (_roomController.isOpen) {
      return _roomPanel?.ownsInteractiveNode(node) ?? false;
    }
    if (_optionsOpen) {
      return _optionsPanel?.ownsInteractiveNode(node) ?? false;
    }
    if (_itzliOpen) {
      return !_assistantCapturing &&
          (_itzliPanel?.ownsInteractiveNode(node) ?? false);
    }
    return false;
  }

  bool _gazeFilter(Node node) {
    if (!_hudHidden) return false; // Preparation controls are touch-only 2D UI.
    if (_hasWorldModal) return _worldModalOwnsInteractiveNode(node);
    // Timed gaze dwell is disabled while a remote controller is connected, so
    // re-arm blocking must not hide a card from explicit button A re-entry.
    final blockedId = _isRemoteConnected ? null : _portalRearm.blockedId;
    if (_worldBuilder.blocksPointer(node)) return true;
    final exhibit = _worldBuilder.exhibitFor(node);
    if (exhibit != null) return exhibit.demoId != blockedId;
    final room = _worldBuilder.roomFor(node);
    if (room != null) return 'room:${room.id}' != blockedId;
    return (_library?.owns(node) ?? false) &&
        (blockedId == null || _library!.routeFor(node) != blockedId);
  }

  /// Include opaque architecture so a ray cannot select through a room wall.
  bool _homeRaycastCandidate(Node node) =>
      _worldBuilder.blocksPointer(node) ||
      _worldBuilder.ownsExhibitNode(node) ||
      _worldBuilder.ownsRoomNode(node) ||
      (_library?.owns(node) ?? false);

  String? get _worldModalFocusedLabel {
    if (_roomController.isOpen) return _roomPanel?.focusedAction.label;
    if (_optionsOpen) return _optionsPanel?.focusedAction.label;
    if (_itzliOpen) return _itzliPanel?.focusedAction.label;
    return null;
  }

  void _handleWorldModalHover(Node? node) {
    if (_roomController.isOpen) {
      _roomPanel?.handleHover(node);
      return;
    }
    if (_optionsOpen) {
      _optionsPanel?.handleHover(node);
      return;
    }
    if (_itzliOpen) {
      _itzliPanel?.handleHover(node);
    }
  }

  void _handleWorldModalSelect(Node node) {
    if (_roomController.isOpen) {
      _roomPanel?.handleSelect(node);
      return;
    }
    if (_optionsOpen) {
      _optionsPanel?.handleSelect(node);
      return;
    }
    if (_itzliOpen) {
      _itzliPanel?.handleSelect(node);
    }
  }

  void _activateWorldModalFocused() {
    if (_roomController.isOpen) {
      _roomPanel?.activateFocused();
      return;
    }
    if (_optionsOpen) {
      _optionsPanel?.activateFocused();
      return;
    }
    if (_itzliOpen && !_assistantCapturing) {
      _itzliPanel?.activateFocused();
    }
  }

  void _dismissWorldModal() {
    if (_roomController.isOpen) {
      _closeRoomPanel();
      return;
    }
    if (_optionsOpen) {
      _dismissOptionsPanel();
      return;
    }
    if (_itzliOpen) {
      _dismissItzliPanel();
    }
  }

  void _handleWorldModalNavigation(double x, double y) {
    if (!_worldModalReady) return;
    if (x.abs() < 0.25 && y.abs() < 0.25) {
      _modalNavigationLatched = false;
      return;
    }
    if (_modalNavigationLatched || (x.abs() < 0.55 && y.abs() < 0.55)) {
      return;
    }
    _modalNavigationLatched = true;

    final panel = _roomController.isOpen
        ? _roomPanel
        : (_optionsOpen ? _optionsPanel : _itzliPanel);
    if (panel == null) return;
    if (x.abs() > y.abs()) {
      panel.moveGridFocus(horizontal: x > 0 ? 1 : -1);
    } else {
      panel.moveGridFocus(vertical: y > 0 ? -1 : 1);
    }

    final label = _worldModalFocusedLabel;
    if (mounted && label != null) {
      setState(() => _statusMessage = label);
    }
    HapticFeedback.selectionClick();
  }

  void _showOptionsPanel() {
    if (!mounted || _isEnteringDemo || _isDemoActive || _locomotion.isJumping) {
      return;
    }
    if (_roomController.isOpen) _closeRoomPanel(rebuild: false);
    if (_itzliOpen) {
      _dismissItzliPanel(
        announce: false,
        haptic: false,
        cancelAssistant: false,
        rebuild: false,
      );
    }
    final placement = _walkSpace.placePanel(
      eye: _rig.eyeCenter,
      forward: _rig.forward,
      distance: HomeSpatialMetrics.modalDistance,
    );
    _optionsPose = placement != null
        ? VrWorldPose.fromViewer(
            eye: _rig.eyeCenter.clone(),
            forward: placement.forward,
            distance: placement.distance,
          )
        : VrWorldPose.fromViewer(
            eye: _rig.eyeCenter.clone(),
            forward: _rig.forward,
            distance: HomeSpatialMetrics.modalDistance,
          );
    _locomotion.suspendSmoothLocomotion();
    _optionsPanel?.removeFrom(_scene);
    _optionsPanel = null;
    _modalNavigationLatched = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
    setState(() {
      _optionsOpen = true;
      _hudHidden = true;
      _hoveredPedestal = null;
      _hoveredWaypoint = null;
      _statusMessage = VrHomeTranslationConstants.optionsOpenedStatus;
    });
    _syncControllerActions();
    HapticFeedback.selectionClick();
    unawaited(_rebuildOptionsPanel());
  }

  Future<void> _rebuildOptionsPanel() async {
    if (!mounted || !_optionsOpen || _optionsPose == null) return;
    final generation = ++_optionsGeneration;
    try {
      final panel = await createVrHomeOptionsPanel(
        bindings: _bindings,
        pose: _optionsPose!,
        lookName: _lookName,
        qualityPreset: _qualityPreset,
        hasMallPortals: _worldBuilder.ecosystemLayout.portals.isNotEmpty,
        theme: widget.theme,
        onAction: _handleOptionsAction,
        onClose: _dismissOptionsPanel,
      );
      if (!mounted || generation != _optionsGeneration || !_optionsOpen) return;
      final previous = _optionsPanel;
      if (previous != null) {
        final focused = panel.actions.indexWhere(
          (action) => action.id == previous.focusedAction.id && action.enabled,
        );
        if (focused >= 0) panel.setFocus(focused);
      }
      panel.reanchor(_optionsPose!);
      previous?.removeFrom(_scene);
      _optionsPanel = panel;
      panel.addTo(_scene);
      _modalLaserTarget = null;
      _modalLaserTriggerQueued = false;
      setState(() {});
    } catch (error, stackTrace) {
      if (!mounted || generation != _optionsGeneration) return;
      debugPrint('Could not create Home options panel: $error\n$stackTrace');
    }
  }

  void _handleOptionsAction(String actionId) {
    if (!mounted || !_optionsOpen) return;
    switch (actionId) {
      case VrHomeConstants.lookActionId:
        _cycleVisualLook();
        unawaited(_rebuildOptionsPanel());
      case VrHomeConstants.qualityActionId:
        _toggleResolution();
        unawaited(_rebuildOptionsPanel());
      case VrHomeConstants.recenterActionId:
        _recenterView();
        _optionsPose = VrWorldPose.fromViewer(
          eye: _rig.eyeCenter.clone(),
          forward: _rig.forward,
          distance: HomeSpatialMetrics.modalDistance,
        );
        unawaited(_rebuildOptionsPanel());
      case 'rooms':
        _dismissOptionsPanel(announce: false, haptic: false);
        _libraryAction('rooms');
      case 'itzli':
        _dismissOptionsPanel(announce: false, haptic: false);
        _showItzliPanel();
      case VrHomeConstants.spatialSettingsActionId:
        _dismissOptionsPanel(announce: false, haptic: false);
        _locomotion.suspendSmoothLocomotion();
        _bindings.onOpenSpatialSettings?.call(context);
      case 'cast':
        _dismissOptionsPanel(announce: false, haptic: false);
        _locomotion.suspendSmoothLocomotion();
        _bindings.onOpenCastSettings?.call(context);
      case 'pair':
        _dismissOptionsPanel(announce: false, haptic: false);
        unawaited(_showPairing());
      case 'calibrate':
        _dismissOptionsPanel(announce: false, haptic: false);
        _libraryAction('calibrate');
    }
  }

  void _dismissOptionsPanel({
    bool announce = true,
    bool haptic = true,
    bool rebuild = true,
  }) {
    if (!_optionsOpen || !mounted) return;
    _optionsGeneration++;
    _optionsPanel?.removeFrom(_scene);
    _optionsPanel = null;
    _optionsPose = null;
    _modalNavigationLatched = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
    void dismiss() {
      _optionsOpen = false;
      _hoveredPedestal = null;
      _hoveredWaypoint = null;
      if (announce) {
        _statusMessage = VrHomeTranslationConstants.optionsClosedStatus;
      }
    }

    if (rebuild) {
      setState(dismiss);
    } else {
      dismiss();
    }
    _syncControllerActions();
    if (haptic) HapticFeedback.selectionClick();
  }

  Map<String, String>? _assistantWorldTarget() {
    final hit = _scene.raycast(
      vm.Ray.originDirection(_rig.eyeCenter, _rig.forward),
      where: _homeRaycastCandidate,
    );
    if (hit != null) {
      final exhibit = _worldBuilder.exhibitFor(hit.node);
      if (exhibit != null) {
        return {
          'kind': 'experience',
          'id': exhibit.demoId,
          'label': exhibit.title,
        };
      }
      final room = _worldBuilder.roomFor(hit.node);
      if (room != null) {
        return {'kind': 'room', 'id': room.id, 'label': room.title};
      }
      final entry = _bindings.catalog.resolveRoute(
        _library?.routeFor(hit.node) ?? '',
      );
      if (entry != null) {
        return {'kind': 'experience', 'id': entry.id, 'label': entry.title};
      }
    }
    return null;
  }

  Map<String, Object?> _assistantContext(String action) =>
      vrHomeAssistantContext(
        zone: _currentZoneName,
        eye: _rig.eyeCenter,
        forward: _rig.forward,
        yaw: _rig.yaw,
        pitch: _rig.pitch,
        target: _assistantTarget ?? _assistantWorldTarget(),
        buttonId: action,
        buttonLabel: switch (action) {
          'listen' =>
            (_bindings.assistantListening?.call() ?? false)
                ? 'Terminar voz'
                : 'Hablar',
          'vision' => 'Qué estoy viendo',
          'help' => 'Ayuda aquí',
          'cancel' => 'Detener',
          _ => action,
        },
      );

  void _assistantStateChanged() {
    if (!mounted || !_itzliOpen) return;
    // At most one pending refresh and one rasterization. Token streams can
    // notify often without allocating a new scene panel on every token/frame.
    _assistantRefreshTimer ??= Timer(const Duration(milliseconds: 180), () {
      _assistantRefreshTimer = null;
      if (mounted && _itzliOpen) _rebuildItzliPanel();
    });
  }

  void _showItzliPanel() {
    if (!_hasAssistant || !mounted || _hasWorldModal) return;
    if (_isEnteringDemo || _isDemoActive || _locomotion.isJumping) {
      setState(() {
        _statusMessage = _isEnteringDemo || _isDemoActive
            ? 'Regresa al Home para abrir ${_bindings.assistantTitle}'
            : 'Espera a terminar el salto para abrir ${_bindings.assistantTitle}';
      });
      return;
    }
    final placement = _modalPlacement();
    if (placement == null) return;
    _assistantTarget = _assistantWorldTarget();
    _assistantSession++;
    _itzliGeneration++;
    _assistantPanelSnapshot = null;
    _assistantShowPrompts = false;
    _assistantError = null;
    _itzliPose = VrWorldPose.fromViewer(
      eye: _rig.eyeCenter.clone(),
      forward: placement.forward,
      distance: placement.distance,
    );
    _locomotion.suspendSmoothLocomotion();
    _itzliPanel?.removeFrom(_scene);
    _itzliPanel = null;
    _modalNavigationLatched = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
    setState(() {
      _itzliOpen = true;
      _hudHidden = true;
      _hoveredPedestal = null;
      _hoveredWaypoint = null;
      _statusMessage = 'Preparando ${_bindings.assistantTitle}…';
    });
    _syncControllerActions();
    HapticFeedback.selectionClick();
    _rebuildItzliPanel();
  }

  Future<void> _rebuildItzliPanel() async {
    if (!mounted || !_itzliOpen || _itzliPose == null) return;
    if (_assistantPanelBuilding) {
      _assistantRebuildQueued = true;
      return;
    }
    final snapshot = (
      vrHomeAssistantDescription(
        _assistantError ?? _bindings.assistantText?.call() ?? '',
      ),
      _bindings.assistantBusy?.call() ?? false,
      _bindings.assistantListening?.call() ?? false,
      _assistantShowPrompts,
    );
    if (snapshot == _assistantPanelSnapshot) return;
    _assistantPanelSnapshot = snapshot;
    _assistantPanelBuilding = true;
    final generation = ++_itzliGeneration;
    try {
      final panel = await createVrHomeAssistantPanel(
        bindings: _bindings,
        pose: _itzliPose!,
        text: snapshot.$1,
        busy: snapshot.$2,
        listening: snapshot.$3,
        theme: widget.theme,
        onAction: (action) => unawaited(_performAssistantAction(action)),
        onPrompt: _selectItzliPrompt,
        onClose: _dismissItzliPanel,
        showPrompts: _assistantShowPrompts,
        onTogglePrompts: () {
          _assistantShowPrompts = !_assistantShowPrompts;
          _rebuildItzliPanel();
        },
      );
      if (!mounted || generation != _itzliGeneration || !_itzliOpen) return;
      final previous = _itzliPanel;
      // Once mounted, responses keep precisely the same world pose and focus.
      // Initial rasterization alone may sample the user's latest placement.
      if (previous == null) {
        final readyPlacement = _modalPlacement();
        if (readyPlacement != null) {
          _itzliPose = VrWorldPose.fromViewer(
            eye: _rig.eyeCenter.clone(),
            forward: readyPlacement.forward,
            distance: readyPlacement.distance,
          );
        }
      } else {
        final focused = panel.actions.indexWhere(
          (action) => action.id == previous.focusedAction.id && action.enabled,
        );
        if (focused >= 0) panel.setFocus(focused);
      }
      panel.reanchor(_itzliPose!);
      previous?.removeFrom(_scene);
      _itzliPanel = panel;
      panel.rootNode.visible = !_assistantCapturing;
      panel.addTo(_scene);
      _modalLaserTarget = null;
      _modalLaserTriggerQueued = false;
      setState(() {
        _statusMessage = snapshot.$3
            ? 'Escuchando · Selecciona Terminar voz para enviar'
            : snapshot.$2
            ? 'El asistente está pensando · Detener cancela la consulta'
            : 'Asistente fijo en el mundo · Mira una acción o usa el mando';
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _itzliGeneration) return;
      debugPrint('Could not create Home assistant panel: $error\n$stackTrace');
      _assistantPanelSnapshot = null;
      setState(() {
        _statusMessage = 'No se pudo actualizar el asistente · B para cerrar';
      });
    } finally {
      _assistantPanelBuilding = false;
      if (_assistantRebuildQueued) {
        _assistantRebuildQueued = false;
        _assistantStateChanged();
      }
    }
  }

  Future<void> _performAssistantAction(String action) async {
    final callback = _bindings.onAssistantAction;
    if (!mounted || !_itzliOpen || callback == null) return;
    if (_assistantCapturing && action != 'cancel') return;
    final session = _assistantSession;
    final context = _assistantContext(action);
    _assistantError = null;
    try {
      if (action == 'vision') {
        setState(() => _assistantCapturing = true);
        _itzliPanel?.rootNode.visible = false;
        _laserPointer.rootNode.visible = false;
        // The host performs its own capture after this clean immersive frame.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || session != _assistantSession || !_itzliOpen) return;
      }
      await callback(action, context);
    } catch (_) {
      if (mounted && session == _assistantSession && _itzliOpen) {
        _assistantError =
            'No se pudo completar la solicitud. Inténtalo de nuevo.';
      }
    } finally {
      if (mounted && session == _assistantSession && _itzliOpen) {
        if (action == 'vision') {
          setState(() => _assistantCapturing = false);
          _itzliPanel?.rootNode.visible = true;
          _laserPointer.rootNode.visible = true;
        }
        _assistantStateChanged();
      }
    }
  }

  void _selectItzliPrompt(VrHomePrompt prompt) {
    if (!_itzliOpen) return;
    final guidance = prompt.guidance;
    _dismissItzliPanel(
      announce: prompt.isCloseAction,
      cancelAssistant: prompt.isCloseAction,
    );
    if (guidance != null) _onItzliGuidance(guidance);
  }

  void _dismissItzliPanel({
    bool announce = true,
    bool haptic = true,
    bool cancelAssistant = true,
    bool rebuild = true,
  }) {
    if (!_itzliOpen || !mounted) return;
    final callback = cancelAssistant ? _bindings.onAssistantAction : null;
    final context = callback == null ? null : _assistantContext('cancel');
    _assistantSession++;
    _itzliGeneration++;
    _assistantRefreshTimer?.cancel();
    _assistantRefreshTimer = null;
    _assistantPanelSnapshot = null;
    _assistantRebuildQueued = false;
    _assistantCapturing = false;
    _laserPointer.rootNode.visible = true;
    _itzliPanel?.removeFrom(_scene);
    _itzliPanel = null;
    _itzliPose = null;
    _assistantTarget = null;
    _modalNavigationLatched = false;
    _modalLaserTriggerQueued = false;
    _modalLaserTarget = null;
    void dismiss() {
      _itzliOpen = false;
      _hoveredPedestal = null;
      _hoveredWaypoint = null;
      if (announce) _statusMessage = 'Asistente cerrado · Continúa explorando';
    }

    if (rebuild) {
      setState(dismiss);
    } else {
      dismiss();
    }
    _syncControllerActions();
    if (haptic) HapticFeedback.selectionClick();
    if (callback != null && context != null) {
      // Closing is the only implicit cancel. Dispatching actions and updating
      // their response must never cancel the host's newly started request.
      unawaited(
        Future<void>.sync(
          () => callback('cancel', context),
        ).catchError((Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = PopScope(
      canPop: !_hasWorldModal,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasWorldModal) _dismissWorldModal();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _selectScreenPoint(details.localPosition),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Stereoscopic 3D Spatial Scene with Head-Tracking and Dual Holographic Hands
              if (_homeSurfaceActive)
                StereoSceneView(
                  scene: _scene,
                  rig: _rig,
                  arbiter: _arbiter,
                  look: _currentLook,
                  quality: _qualityPreset,
                  enableHandTracking: false,
                  enableTempleTap: true,
                  templeDoubleTapToRecenter: false,
                  touchFallback: true,
                  locomotionEnabled: false,
                  lookInputEnabled: false,
                  gazeEnabled:
                      _hudHidden &&
                      !shouldLaserOwnHomeHover(
                        isRemoteConnected: _isRemoteConnected,
                        remoteLaserMode: _remoteLaserMode,
                        remoteLaserHitsTarget: _remoteLaserHitsTarget,
                      ),
                  showReticle:
                      _hudHidden &&
                      !_assistantCapturing &&
                      !_isRemoteConnected &&
                      !_arbiter.isGazeSuppressed,
                  onQualityChanged: (preset) {
                    // The scene is the single owner of adaptive quality. Its
                    // initial callback may run during build.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _qualityPreset != preset) {
                        final enableShadows =
                            preset.tier == VrQualityTier.high ||
                            preset.tier == VrQualityTier.ultra;
                        _worldBuilder.setShadowsEnabled(
                          enableShadows,
                          shadowMapResolution: preset.shadowMapResolution,
                        );
                        setState(() => _qualityPreset = preset);
                      }
                    });
                  },
                  // When a joystick is connected, timed gaze auto-click is disabled
                  // so users can freely read cards and signs without accidentally
                  // launching experiences; pressing A selects the hovered target.
                  gazeDwellSeconds: VrHomeConstants.defaultGazeDwellSeconds,
                  gazeFilter: _gazeFilter,
                  onGazeHoverChanged: _onHover,
                  onGazeSelect:
                      (_isRemoteConnected || _arbiter.isGazeSuppressed)
                      ? null
                      : _onSelect,
                  onTick: _tick,
                ),

              // 2. Single 2D preparation status, hidden while wearing the visor.
              if (_homeSurfaceActive &&
                  _hudHidden &&
                  _bindings.statusOverlayBuilder != null)
                _bindings.statusOverlayBuilder!(context),

              if (_homeSurfaceActive &&
                  !_hudHidden &&
                  (!_hasWorldModal || !_worldModalReady))
                VirtualHomeHudCoordinator.buildCenterSweetSpotHud(
                  theme: widget.theme,
                  zoneName: _currentZoneName,
                  statusMessage: [
                    _statusMessage,
                    if (_bindings.spatialStatus?.call(context)
                        case final String status)
                      status,
                  ].join(' · '),
                  isRealHandInCamera: false,
                  isVoiceListening: false,
                  isRemoteConnected: _isRemoteConnected,
                ),

              // Monoscopic preparation with only the host-provided capabilities.
              if (_homeSurfaceActive && !_hasWorldModal && !_hudHidden)
                VirtualHomeHudCoordinator.buildTopQuickControls(
                  hidden: _hudHidden,
                  theme: widget.theme,
                  onExit: _bindings.onExit == null
                      ? null
                      : () => _bindings.onExit!(context),
                  assistantLabel: _bindings.assistantTitle,
                  onToggleHidden: () {
                    _locomotion.suspendSmoothLocomotion();
                    setState(() => _hudHidden = !_hudHidden);
                  },
                  onRecenterTap: _recenterView,
                  onItzliTap: !_hasAssistant ? null : _showItzliPanel,
                  onLookTap: _cycleVisualLook,
                  onResolutionTap: _toggleResolution,
                  onRemotePairTap: _bindings.onPair == null
                      ? null
                      : _showPairing,
                  onCatalogTap: _bindings.onCatalog == null
                      ? null
                      : _showCatalog,
                  onCastTap: _bindings.onOpenCastSettings == null
                      ? null
                      : () => _bindings.onOpenCastSettings!(context),
                  onSpatialSettingsTap: _bindings.onOpenSpatialSettings == null
                      ? null
                      : () => _bindings.onOpenSpatialSettings!(context),
                  lookName: _lookName,
                  qualityPreset: _qualityPreset,
                ),

              // Smooth spatial transition veil when jumping between places or launching an app/game.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isEnteringDemo
                      ? 0.88
                      : (_locomotion.isJumping ? 0.24 : 0.0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: const ColoredBox(color: Color(0xFF060913)),
                ),
              ),

              if (_isReturningFromPairing)
                VrHomeLoadingSplashOverlay(
                  visible: _isReturningFromPairing,
                  isSyncingController: _isRemoteConnected,
                ),
            ],
          ),
        ),
      ),
    );
    return Theme(
      data: widget.theme.materialTheme,
      child:
          _bindings.wrapContent?.call(context, _homeSurfaceActive, content) ??
          content,
    );
  }
}
