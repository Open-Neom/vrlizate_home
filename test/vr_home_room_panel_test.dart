import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/ecosystem/vr_home_room_presentation.dart';
import 'package:vrlizate_home/src/spatial/vr_home_room_panel.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

final _room = VrHomeEcosystemRoom.defaults.first;

VrWorldPose _pose() => VrWorldPose.facingEye(
  center: vm.Vector3(1.5, 1.6, -3),
  eye: vm.Vector3(0, 1.6, 0),
);

Node _actionNode(VrWorldActionPanel3D panel, String id) => panel.nodes
    .firstWhere((node) => node.name == 'home_room_${_room.id}_action_$id');

Future<VrWorldActionPanel3D> _panel({
  VrHomeRoomPresentation? presentation,
  bool busy = false,
  String? error,
  int page = 0,
  void Function(String)? onAction,
  void Function()? onClose,
  void Function()? onRetry,
  void Function(int)? onPage,
  List<VrWorldTextSpec>? text,
}) => createVrHomeRoomPanel(
  room: _room,
  pose: _pose(),
  presentation: presentation,
  busy: busy,
  error: error,
  pageIndex: page,
  onAction: onAction ?? (_) {},
  onRetry: onRetry ?? () {},
  onClose: onClose ?? () {},
  onPage: onPage ?? (_) {},
  meshBuilder: () => Mesh.primitives(primitives: const []),
  textNodeBuilder: (spec) async {
    text?.add(spec);
    return Node(name: spec.nodeName);
  },
);

VrHomeRoomPresentation _catalog(int count) => VrHomeRoomPresentation(
  title: 'Catálogo',
  subtitle: 'Contenido autorizado',
  actions: [
    for (var index = 0; index < count; index++)
      VrHomeRoomAction(id: 'item-$index', label: 'Elemento $index'),
  ],
);

void main() {
  test('host action IDs remain separate from panel controls', () async {
    final activated = <String>[];
    var closed = 0;
    final panel = await _panel(
      presentation: VrHomeRoomPresentation(
        title: 'Room',
        actions: const [VrHomeRoomAction(id: 'close', label: 'Host close')],
      ),
      onAction: activated.add,
      onClose: () => closed++,
    );
    expect(panel.handleSelect(_actionNode(panel, 'content:close')), isTrue);
    expect(activated, ['close']);
    expect(closed, 0);
    expect(panel.handleSelect(_actionNode(panel, 'close')), isTrue);
    expect(activated, ['close']);
    expect(closed, 1);
    expect(
      panel.handleSelect(Node(name: _actionNode(panel, 'content:close').name)),
      isFalse,
    );
    expect(activated, ['close']);
  });

  test('disabled host actions cannot be selected by ray or joystick', () async {
    final activated = <String>[];
    final panel = await _panel(
      presentation: VrHomeRoomPresentation(
        title: 'Room',
        actions: const [
          VrHomeRoomAction(id: 'paid', label: 'Unavailable', enabled: false),
        ],
      ),
      onAction: activated.add,
    );
    final disabled = _actionNode(panel, 'content:paid');
    expect(panel.ownsInteractiveNode(disabled), isFalse);
    expect(panel.handleSelect(disabled), isFalse);
    expect(panel.focusedAction.id, 'close');
    panel.setFocus(0);
    expect(panel.activateFocused(), isFalse);
    expect(activated, isEmpty);
    panel.moveGridFocus(horizontal: 1);
    expect(panel.focusedAction.id, 'close');
  });

  test(
    'loading removes stale host actions and keeps close available',
    () async {
      var closed = 0;
      final activated = <String>[];
      final text = <VrWorldTextSpec>[];
      final panel = await _panel(
        presentation: _catalog(9),
        text: text,
        busy: true,
        onAction: activated.add,
        onClose: () => closed++,
      );
      expect(panel.actions.map((action) => action.id), ['close']);
      expect(
        text.singleWhere((spec) => spec.nodeName.endsWith('_title')).text,
        _room.title.toUpperCase(),
      );
      expect(panel.columns, 1);
      expect(panel.handleSelect(_actionNode(panel, 'close')), isTrue);
      expect(closed, 1);
      expect(activated, isEmpty);
    },
  );

  test(
    'failed content shows only retry and close, with the safe error',
    () async {
      var retried = 0;
      var closed = 0;
      final text = <VrWorldTextSpec>[];
      final panel = await _panel(
        presentation: _catalog(9),
        error: 'No se pudo cargar la sala.',
        onRetry: () => retried++,
        onClose: () => closed++,
        text: text,
      );
      expect(panel.actions.map((action) => action.id), ['retry', 'close']);
      expect(
        text.singleWhere((spec) => spec.nodeName.endsWith('_description')).text,
        'No se pudo cargar la sala.',
      );
      expect(panel.handleSelect(_actionNode(panel, 'retry')), isTrue);
      expect(panel.handleSelect(_actionNode(panel, 'close')), isTrue);
      expect(retried, 1);
      expect(closed, 1);
    },
  );

  test(
    'public room without a provider remains a usable spatial panel',
    () async {
      final text = <VrWorldTextSpec>[];
      var closed = 0;
      final panel = await _panel(text: text, onClose: () => closed++);
      expect(panel.actions.map((action) => action.id), ['close']);
      expect(panel.columns, 1);
      expect(
        text.singleWhere((spec) => spec.nodeName.endsWith('_title')).text,
        _room.title.toUpperCase(),
      );
      expect(
        text.singleWhere((spec) => spec.nodeName.endsWith('_description')).text,
        _room.description,
      );
      expect(panel.activateFocused(), isTrue);
      expect(closed, 1);
    },
  );

  test(
    'catalog pages expose four host actions and bounded navigation',
    () async {
      final requestedPages = <int>[];
      final activated = <String>[];
      final content = _catalog(9);
      final first = await _panel(
        presentation: content,
        page: -5,
        onPage: requestedPages.add,
      );
      expect(first.actions.map((action) => action.id), [
        'content:item-0',
        'content:item-1',
        'content:item-2',
        'content:item-3',
        'previous',
        'next',
        'close',
      ]);
      expect(first.handleSelect(_actionNode(first, 'previous')), isFalse);
      expect(first.handleSelect(_actionNode(first, 'next')), isTrue);
      expect(requestedPages, [1]);

      final middle = await _panel(presentation: content, page: 1);
      expect(
        middle.actions
            .where((action) => action.id.startsWith('content:'))
            .map((action) => action.id),
        [
          'content:item-4',
          'content:item-5',
          'content:item-6',
          'content:item-7',
        ],
      );

      final last = await _panel(
        presentation: content,
        page: 999,
        onPage: requestedPages.add,
        onAction: activated.add,
      );
      expect(last.actions.map((action) => action.id), [
        'content:item-8',
        'previous',
        'next',
        'close',
      ]);
      expect(last.handleSelect(_actionNode(last, 'next')), isFalse);
      expect(last.handleSelect(_actionNode(last, 'previous')), isTrue);
      expect(requestedPages, [1, 1]);
      expect(last.handleSelect(_actionNode(last, 'content:item-8')), isTrue);
      expect(activated, ['item-8']);
    },
  );

  test(
    'joystick navigation and frame updates keep the room panel anchored',
    () async {
      final activated = <String>[];
      final panel = await _panel(
        presentation: _catalog(4),
        onAction: activated.add,
      );
      final initialTransform = panel.rootNode.localTransform.clone();
      final pointerTarget = _actionNode(panel, 'content:item-0');
      panel.handleHover(pointerTarget);
      panel.moveGridFocus(horizontal: 1);
      expect(panel.focusedAction.id, 'content:item-1');
      for (var frame = 0; frame < 120; frame++) {
        panel.handleHover(pointerTarget);
        panel.update(1 / 60);
      }
      expect(panel.focusedAction.id, 'content:item-1');
      expect(panel.activateFocused(), isTrue);
      expect(activated, ['item-1']);
      expect(
        panel.rootNode.localTransform.storage,
        orderedEquals(initialTransform.storage),
      );
      expect(panel.pose.center.distanceTo(_pose().center), lessThan(1e-9));
    },
  );
}
