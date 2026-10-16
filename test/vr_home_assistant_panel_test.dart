import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/spatial/virtual_home_view.dart';
import 'package:vrlizate_home/src/spatial/vr_demo_library_model.dart';
import 'package:vrlizate_home/src/spatial/vr_home_spatial_bindings.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

VrWorldPose _pose() => VrWorldPose.facingEye(
  center: vm.Vector3(1, 1.6, -2.3),
  eye: vm.Vector3(0, 1.6, 0),
);

Node _action(VrWorldActionPanel3D panel, String id) =>
    panel.nodes.firstWhere((node) => node.name == 'itzli_action_$id');

Future<VrWorldActionPanel3D> _panel({
  bool assistant = true,
  bool busy = false,
  bool listening = false,
  bool showPrompts = false,
  String text = '',
  List<VrHomePrompt> prompts = const [],
  void Function(String)? onAction,
  void Function(VrHomePrompt)? onPrompt,
  VoidCallback? onClose,
  VoidCallback? onTogglePrompts,
  VrWorldPose? pose,
  List<VrWorldTextSpec>? labels,
}) => createVrHomeAssistantPanel(
  bindings: VrHomeSpatialBindings(
    catalog: VrDemoCatalog(const []),
    remoteController: VrRemoteControllerService(),
    onLaunch: (_, _) async {},
    onAssistantAction: assistant ? (_, _) async {} : null,
    prompts: prompts,
  ),
  pose: pose ?? _pose(),
  text: text,
  busy: busy,
  listening: listening,
  showPrompts: showPrompts,
  onAction: onAction ?? (_) {},
  onPrompt: onPrompt ?? (_) {},
  onClose: onClose ?? () {},
  onTogglePrompts: onTogglePrompts ?? () {},
  meshBuilder: () => Mesh.primitives(primitives: const []),
  textNodeBuilder: (spec) async {
    labels?.add(spec);
    return Node(name: spec.nodeName);
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live actions work without prompts and never implicitly close', () async {
    final dispatched = <String>[];
    var closed = 0;
    final panel = await _panel(
      onAction: dispatched.add,
      onClose: () => closed++,
    );
    expect(panel.actions.map((action) => action.id), [
      'assistant:listen',
      'assistant:vision',
      'assistant:help',
      'assistant:cancel',
      'close',
    ]);
    // A activates the initially focused action; laser selects exact node identity.
    expect(panel.activateFocused(), isTrue);
    expect(panel.handleSelect(_action(panel, 'assistant:vision')), isTrue);
    expect(panel.handleSelect(_action(panel, 'assistant:help')), isTrue);
    expect(panel.handleSelect(_action(panel, 'assistant:cancel')), isTrue);
    expect(dispatched, ['listen', 'vision', 'help', 'cancel']);
    expect(closed, 0);
    expect(
      panel.handleSelect(Node(name: 'itzli_action_assistant:help')),
      isFalse,
    );
    expect(panel.handleSelect(_action(panel, 'close')), isTrue);
    expect(closed, 1);
  });

  test(
    'busy actions cannot restart work; listening retains finish voice',
    () async {
      final dispatched = <String>[];
      final labels = <VrWorldTextSpec>[];
      final busy = await _panel(
        busy: true,
        onAction: dispatched.add,
        labels: labels,
      );
      expect(busy.focusedAction.id, 'assistant:cancel');
      for (final action in ['listen', 'vision', 'help']) {
        expect(busy.handleSelect(_action(busy, 'assistant:$action')), isFalse);
      }
      expect(busy.activateFocused(), isTrue);
      expect(dispatched, ['cancel']);
      expect(
        labels.singleWhere((spec) => spec.nodeName.endsWith('_subtitle')).text,
        contains('PENSANDO'),
      );
      final listening = await _panel(
        busy: true,
        listening: true,
        onAction: dispatched.add,
      );
      expect(listening.focusedAction.label, 'Terminar voz');
      expect(listening.activateFocused(), isTrue);
      expect(dispatched, ['cancel', 'listen']);
      expect(
        listening.handleSelect(_action(listening, 'assistant:vision')),
        isFalse,
      );
    },
  );

  test('existing prompts remain on a compact shortcuts page', () async {
    const prompts = [
      VrHomePrompt(
        id: 'listen',
        displayLabel: 'Ajedrez',
        guidance: VrHomeGuidance(
          actionType: VrHomeActionType.launchExperience,
          speechResponse: 'Ajedrez',
          targetDemoId: 'chess',
        ),
      ),
      VrHomePrompt(id: 'close', displayLabel: 'Cerrar'),
    ];
    var toggled = 0;
    final chosen = <VrHomePrompt>[];
    final main = await _panel(
      prompts: prompts,
      onTogglePrompts: () => toggled++,
    );
    expect(main.actions, hasLength(6));
    expect(main.handleSelect(_action(main, 'assistant:shortcuts')), isTrue);
    expect(toggled, 1);
    final shortcuts = await _panel(
      prompts: prompts,
      showPrompts: true,
      onPrompt: chosen.add,
      onTogglePrompts: () => toggled++,
    );
    expect(shortcuts.actions.map((action) => action.id), [
      'prompt:listen',
      'prompt:close',
      'assistant:shortcuts',
    ]);
    expect(shortcuts.handleSelect(_action(shortcuts, 'prompt:listen')), isTrue);
    expect(chosen.single.guidance?.targetDemoId, 'chess');
    expect(
      shortcuts.handleSelect(_action(shortcuts, 'assistant:shortcuts')),
      isTrue,
    );
    expect(toggled, 2);
  });

  test('hosts with legacy prompts need no assistant provider', () async {
    var selected = 0;
    final panel = await _panel(
      assistant: false,
      prompts: const [VrHomePrompt(id: 'close', displayLabel: 'Cerrar')],
      onPrompt: (_) => selected++,
    );
    expect(panel.actions.map((action) => action.id), ['prompt:close']);
    expect(panel.activateFocused(), isTrue);
    expect(selected, 1);
    expect(panel.rootNode.getChildByName('itzli_response'), isNull);
  });

  testWidgets('response is readable inside a bounded spatial surface', (
    tester,
  ) async {
    final panel = await _panel(
      text: List.filled(90, 'Mundo virtual').join(' '),
    );
    final response = panel.rootNode.getChildByName('itzli_response')!;
    final surface = response.getComponent<WidgetComponent>()!;
    expect(surface.size, const Size(1120, 450));
    expect(surface.worldHeight, lessThanOrEqualTo(.74));
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: surface.size.width,
            height: surface.size.height,
            child: surface.child,
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text).last);
    expect(text.data!.runes.length, 700);
    expect(text.data, endsWith('…'));
    expect(text.maxLines, 11);
    expect(
      tester
          .widget<Align>(
            find
                .ancestor(
                  of: find.byType(Text).last,
                  matching: find.byType(Align),
                )
                .first,
          )
          .alignment,
      Alignment.centerLeft,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'spatial controls and answer replacement preserve a supplied pose',
    () async {
      final pose = _pose();
      final panel = await _panel(pose: pose, text: 'Primera respuesta');
      final before = panel.rootNode.localTransform.clone();
      panel.moveGridFocus(horizontal: 1);
      for (var frame = 0; frame < 120; frame++) {
        panel.update(1 / 60);
      }
      final updated = await _panel(
        pose: panel.pose,
        text: 'Respuesta completa',
      );
      expect(
        panel.rootNode.localTransform.storage,
        orderedEquals(before.storage),
      );
      expect(
        updated.rootNode.localTransform.storage,
        orderedEquals(before.storage),
      );
    },
  );

  test(
    'context is JSON-only, snapshots target and names orientation units',
    () {
      final target = {'kind': 'room', 'id': 'youtube', 'label': 'Cine'};
      final context = vrHomeAssistantContext(
        zone: 'Plaza',
        eye: vm.Vector3(2, 1.6, -8),
        forward: vm.Vector3(0, 0, -1),
        yaw: .8,
        pitch: .2,
        target: target,
        buttonId: 'vision',
        buttonLabel: 'Qué estoy viendo',
      );
      target['id'] = 'changed';
      final decoded = jsonDecode(jsonEncode(context)) as Map<String, dynamic>;
      expect(decoded['experience'], 'home');
      expect(decoded['zone'], 'Plaza');
      expect(decoded['camera']['position'], {
        'x': closeTo(2, 1e-6),
        'y': closeTo(1.6, 1e-6),
        'z': closeTo(-8, 1e-6),
      });
      expect(decoded['camera']['orientation']['unit'], 'radians');
      expect(decoded['target']['id'], 'youtube');
      expect(decoded['button']['id'], 'vision');
      final invalid = vrHomeAssistantContext(
        zone: 'Plaza',
        eye: vm.Vector3(double.nan, 0, double.infinity),
        forward: vm.Vector3(0, 0, -1),
        yaw: double.nan,
        pitch: double.infinity,
      );
      expect(() => jsonEncode(invalid), returnsNormally);
    },
  );

  test('description keeps Unicode intact and collapses excess whitespace', () {
    expect(
      vrHomeAssistantDescription('  Un\n mundo\t virtual  '),
      'Un mundo virtual',
    );
    final text = vrHomeAssistantDescription(List.filled(800, '🌎').join());
    expect(text.runes.length, 700);
    expect(text, endsWith('…'));
    expect(text.contains('\uFFFD'), isFalse);
  });
}
