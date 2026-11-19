import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_world/vrlizate_world.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import 'package:vector_math/vector_math.dart' as vm;

import 'demo_preview_data.dart';
import 'home_ecosystem_layout.dart';
import 'home_lobby_layout.dart';
import 'vr_demo_library_model.dart';
import '../ecosystem/vr_home_ecosystem_room.dart';
import '../ecosystem/vr_home_room_presentation.dart';
import '../ecosystem/vr_home_room_content.dart';

enum VrHomeCatalogExit { home, pairController }

enum VrHomeSound { connected, disconnected, hover, click, open }

/// Semantic spatial actions; inference and permissions belong to the host.
enum VrHomeActionType {
  jumpToWing,
  launchExperience,
  changeLook,
  changeResolution,
  recenter,
  switchCatalog2D,
  conversationalGuidance,
  moveInSpace,
  goToPoint,
}

class VrHomeGuidance {
  const VrHomeGuidance({
    required this.actionType,
    required this.speechResponse,
    this.targetWingId,
    this.targetDemoId,
    this.targetDemoTitle,
    this.targetLook,
    this.targetPreset,
    this.stickX = 0.0,
    this.stickY = 0.0,
    this.turnRate = 0.0,
    this.durationSeconds = 0.0,
    this.targetPointQuery,
    this.targetX,
    this.targetZ,
    this.distanceMeters,
    this.useGazeTarget = false,
  });

  final VrHomeActionType actionType;
  final String speechResponse;
  final String? targetWingId, targetDemoId, targetDemoTitle;
  final VrLook? targetLook;
  final VrQualityPreset? targetPreset;
  final double stickX;
  final double stickY;
  final double turnRate;
  final double durationSeconds;
  final String? targetPointQuery;
  final double? targetX;
  final double? targetZ;
  final double? distanceMeters;
  final bool useGazeTarget;
}

class VrHomePrompt {
  const VrHomePrompt({
    required this.id,
    required this.displayLabel,
    this.guidance,
  });

  final String id, displayLabel;
  final VrHomeGuidance? guidance;
  bool get isCloseAction => guidance == null;
}

/// Pure-SDK metadata describing a nearby plaza NPC when the player initiates
/// spatial conversation. Inference and TTS belong strictly to the host app.
class VrHomeNpcDescriptor {
  const VrHomeNpcDescriptor({
    required this.id,
    required this.displayName,
    required this.role,
    required this.speciesName,
    required this.ambientComment,
    required this.position,
    this.nearestRoomTitle,
    this.plazaBanner,
  });

  final String id;
  final String displayName;
  final String role;
  final String speciesName;
  final String ambientComment;
  final vm.Vector3 position;
  final String? nearestRoomTitle;
  final String? plazaBanner;
}

/// Pure-SDK avatar speech/thought bubble projected by the player via WordSphere
/// so nearby plaza visitors and multiplayer peers can see what the user spoke
/// (`isThought: false`) or thought (`isThought: true`).
class VrHomeAvatarBubble {
  const VrHomeAvatarBubble({
    required this.text,
    this.isThought = false,
    this.authorName = 'Tú',
    this.duration = const Duration(seconds: 9),
  });

  final String text;
  final bool isThought;
  final String authorName;
  final Duration duration;
}

typedef VrHomePreviewResolver =
    DemoPreviewData Function({
      required String demoId,
      required String title,
      String? subtitle,
      Color? color,
    });

/// Host-owned capabilities borrowed by a spatial Home session.
///
/// This object never starts a server, requests permission, chooses an inference
/// backend or constructs an application route. The host owns every supplied
/// service. The scene cancels only its own subscriptions on disposal.
class VrHomeSpatialBindings {
  VrHomeSpatialBindings({
    required this.catalog,
    required this.remoteController,
    required this.onLaunch,
    this.onBeforeSuspendForLaunch,
    this.onAfterResumeFromLaunch,
    this.ready,
    this.onPair,
    this.onExit,
    this.onCatalog,
    this.onOpenRoom,
    this.onRoomAction,
    this.roomContentBuilder,
    this.roomChanges,
    this.avatarAppearance,
    this.onRoomClosed,
    this.previewResolver,
    this.onGamepadConnectionChanged,
    this.onSuspend,
    this.onSound,
    this.onVisitorGreeted,
    this.onOpenAvatarWordsphere,
    this.avatarBubbles,
    this.peerSnapshots,
    this.peerRemovals,
    this.guidance,
    this.statuses,
    this.wrapContent,
    this.statusOverlayBuilder,
    this.spatialStatus,
    this.onOpenSpatialSettings,
    this.onOpenCastSettings,
    this.onAssistantAction,
    this.assistantChanges,
    this.assistantText,
    this.assistantBusy,
    this.assistantListening,
    this.onNpcAction,
    this.npcChanges,
    this.npcText,
    this.npcBusy,
    this.npcListening,
    this.npcSpeakingTts,
    this.npcSubtitle,
    this.npcWriteEnabled = false,
    this.npcLatestBark,
    this.initialQuality = VrQualityPreset.medium,
    this.calibrationExperienceId,
    this.assistantTitle = 'Asistente espacial',
    this.plazaTopology = HomePlazaTopology.boulevard,
    this.customEcosystemLayout,
    this.includeLobbyBackdrop = true,
    this.plazaBannerText,
    this.initialEyePosition,
    this.startWithLibraryHidden = false,
    this.onExhibitSelected,
    this.onCustomDockAction,
    Iterable<(String, String)> extraDockActions = const [],
    Iterable<VrHomePrompt> prompts = const [],
    Iterable<HomeExhibit> exhibits = const [],
    List<VrHomeEcosystemRoom> ecosystemRooms = const [],
    Iterable<VrWorldEntity>? worldObjects,
  }) : extraDockActions = List<(String, String)>.unmodifiable(extraDockActions),
       prompts = List<VrHomePrompt>.unmodifiable(prompts),
       exhibits = List<HomeExhibit>.unmodifiable(exhibits),
       ecosystemRooms = List<VrHomeEcosystemRoom>.unmodifiable(ecosystemRooms),
       worldObjects = worldObjects == null
           ? null
           : List<VrWorldEntity>.unmodifiable(worldObjects);

  final VrDemoCatalog catalog;

  /// Public joystick state/transport service. It may remain unstarted when a
  /// host has no remote controller; construction itself starts no transport.
  final VrRemoteControllerService remoteController;

  /// Completes when host preparation (if any) is ready. The scene does not own
  /// this operation and cannot cancel it when a route is closed.
  final Future<void>? ready;
  final Future<void> Function(BuildContext, DemoPreviewData) onLaunch;
  final Future<void> Function(BuildContext, DemoPreviewData)?
  onBeforeSuspendForLaunch;
  final VoidCallback? onAfterResumeFromLaunch;
  final Future<bool> Function(BuildContext)? onPair;
  final void Function(BuildContext)? onExit;
  final Future<VrHomeCatalogExit?> Function(BuildContext)? onCatalog;

  /// Legacy host route hook. Spatial terminals use onRoomAction exclusively.
  final Future<void> Function(BuildContext, VrHomeEcosystemRoom)? onOpenRoom;
  final Future<VrHomeRoomPresentation> Function(
    VrHomeEcosystemRoom room,
    String? actionId,
  )?
  onRoomAction;

  /// Called only for a completed presentation. The host must revalidate access
  /// before exposing private widgets. Changes use [roomChanges] as usual.
  final VrHomeRoomContent? Function(
    VrHomeEcosystemRoom room,
    VrHomeRoomPresentation presentation,
  )?
  roomContentBuilder;
  final Listenable? roomChanges;

  /// Local, host-owned appearance. Semantic edits update the stage model;
  /// neither animation frames nor private account/preferences cross this API.
  /// Null values restore the neutral showcase, e.g. while identity changes.
  final ValueListenable<VrAvatarAppearance?>? avatarAppearance;

  /// Release only content borrowed by this room, not shared application services.
  final VoidCallback? onRoomClosed;
  final VrHomePreviewResolver? previewResolver;
  final void Function(VrGamepadDriver driver, bool attached)?
  onGamepadConnectionChanged;
  final VoidCallback? onSuspend;
  final void Function(VrHomeSound)? onSound;
  final void Function(vm.Vector3 visitorPosition, StereoHeadRig rig)?
  onVisitorGreeted;

  /// Optional host callback invoked when the player presses `X` to open
  /// WordSphere and write a spoken/thought message shown on their avatar.
  final VoidCallback? onOpenAvatarWordsphere;

  /// Optional stream of spoken/thought avatar messages projected by the player.
  final Stream<VrHomeAvatarBubble>? avatarBubbles;

  /// Optional 10–20 Hz remote multiplayer user avatar snapshots rendered inside
  /// the same shared `VrPeerAvatarStage` instanced batches as plaza NPCs.
  final Stream<VrPeerAvatarSnapshot>? peerSnapshots;
  final Stream<String>? peerRemovals;
  final Stream<VrHomeGuidance>? guidance;
  final Stream<String>? statuses;
  final Widget Function(BuildContext, bool active, Widget child)? wrapContent;
  final WidgetBuilder? statusOverlayBuilder;
  final String? Function(BuildContext)? spatialStatus;
  final void Function(BuildContext)? onOpenSpatialSettings;

  /// Optional host-owned spectator sharing. Home does not create a transport.
  final void Function(BuildContext)? onOpenCastSettings;

  /// Optional host assistant. Actions are `listen` (start/finish speech),
  /// `vision`, `help`, and `cancel`. Context contains only JSON values: Home's
  /// zone, camera position/direction and radians, plus a target/button if known.
  /// The host owns permissions, capture, inference, audio and cancellation.
  ///
  /// For `vision`, Home hides its assistant/laser until this future completes.
  /// Complete after capturing the scene; continue inference independently and
  /// notify [assistantChanges] as the answer becomes available. Other actions
  /// should also return promptly after dispatching their host operation.
  final Future<void> Function(String action, Map<String, Object?> context)?
  onAssistantAction;

  /// Changes are sampled only while the assistant is open, coalesced, and never
  /// read from Home's frame loop. Home borrows this notifier without disposing it.
  final Listenable? assistantChanges;
  final String Function()? assistantText;
  final bool Function()? assistantBusy;
  final bool Function()? assistantListening;

  /// Optional host-backed NPC dialogue & optional TTS (`open`, `recommend`,
  /// `about_place`, `surprise`, `listen`, `tts`, `cancel`).
  final Future<void> Function(
    String action,
    VrHomeNpcDescriptor npc,
    Map<String, Object?> context,
  )?
  onNpcAction;
  final Listenable? npcChanges;
  final String Function()? npcText;
  final bool Function()? npcBusy;
  final bool Function()? npcListening;
  final bool Function()? npcSpeakingTts;
  final String Function()? npcSubtitle;
  final bool npcWriteEnabled;
  final String? Function(String visitorId)? npcLatestBark;
  final VrQualityPreset initialQuality;
  final String? calibrationExperienceId;
  final String assistantTitle;
  final HomePlazaTopology plazaTopology;
  final HomeEcosystemLayout? customEcosystemLayout;
  final bool includeLobbyBackdrop;
  final String? plazaBannerText;
  final vm.Vector3? initialEyePosition;
  final bool startWithLibraryHidden;
  final bool Function(BuildContext, HomeExhibit)? onExhibitSelected;
  final void Function(BuildContext, String actionId)? onCustomDockAction;
  final List<(String, String)> extraDockActions;
  final List<VrHomePrompt> prompts;
  final List<HomeExhibit> exhibits;
  final List<VrHomeEcosystemRoom> ecosystemRooms;

  /// Static placements. Null keeps the authored trees; an empty list removes
  /// them. Runtime participant motion must not replace the Home bindings.
  final List<VrWorldEntity>? worldObjects;

  DemoPreviewData preview({
    required String demoId,
    required String title,
    String? subtitle,
    Color? color,
  }) {
    final resolver = previewResolver;
    if (resolver != null) {
      return resolver(
        demoId: demoId,
        title: title,
        subtitle: subtitle,
        color: color,
      );
    }
    final entry = catalog.resolveRoute(demoId);
    return DemoPreviewData.forDemo(
      demoId: entry?.id ?? demoId,
      title: entry?.title ?? title,
      subtitle: subtitle ?? entry?.subtitle,
      color: color ?? (entry == null ? null : Color(entry.accent)),
    );
  }
}
