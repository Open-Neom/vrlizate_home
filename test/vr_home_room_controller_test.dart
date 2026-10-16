import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/ecosystem/vr_home_room_controller.dart';
import 'package:vrlizate_home/src/ecosystem/vr_home_room_presentation.dart';

final _room = VrHomeEcosystemRoom.defaults.first;
final _otherRoom = VrHomeEcosystemRoom.defaults.last;

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _RoomChanges extends ChangeNotifier {
  void change() => notifyListeners();

  bool get hasSubscriptions => hasListeners;
}

VrHomeRoomPresentation _content(String title) => VrHomeRoomPresentation(
  title: title,
  actions: const [
    VrHomeRoomAction(id: 'open', label: 'Abrir'),
    VrHomeRoomAction(id: 'locked', label: 'Bloqueado', enabled: false),
  ],
);

void main() {
  test('presentation copies its actions and rejects ambiguous IDs', () {
    final actions = [const VrHomeRoomAction(id: 'a', label: 'A')];
    final presentation = VrHomeRoomPresentation(
      title: 'Sala',
      actions: actions,
    );
    actions.clear();
    expect(presentation.actions.single.id, 'a');
    expect(presentation.actions.clear, throwsUnsupportedError);
    for (final invalid in [
      [const VrHomeRoomAction(id: '  ', label: 'Empty')],
      [
        const VrHomeRoomAction(id: 'a', label: 'A'),
        const VrHomeRoomAction(id: 'a', label: 'Another A'),
      ],
    ]) {
      expect(
        () => VrHomeRoomPresentation(title: 'Sala', actions: invalid),
        throwsArgumentError,
      );
    }
  });

  test('unconnected room exposes only its public metadata', () {
    final controller = VrHomeRoomController();
    addTearDown(controller.dispose);
    controller.openRoom(_room);
    expect(controller.isOpen, isTrue);
    expect(controller.room, same(_room));
    expect(controller.presentation?.title, _room.title);
    expect(controller.presentation?.description, _room.description);
    expect(controller.presentation?.actions, isEmpty);
    expect(controller.busy, isFalse);
    expect(controller.error, isNull);
  });

  test('opening another room discards the previous pending result', () async {
    final first = Completer<VrHomeRoomPresentation>();
    final second = Completer<VrHomeRoomPresentation>();
    final calls = <String>[];
    final controller = VrHomeRoomController(
      callback: (room, action) {
        expect(action, isNull);
        calls.add(room.id);
        return room.id == _room.id ? first.future : second.future;
      },
    );
    addTearDown(controller.dispose);
    controller.openRoom(_room);
    controller.openRoom(_otherRoom);
    second.complete(_content('Current account'));
    await _flush();
    first.complete(_content('Old account'));
    await _flush();
    expect(calls, [_room.id, _otherRoom.id]);
    expect(controller.room, same(_otherRoom));
    expect(controller.presentation?.title, 'Current account');
    expect(controller.busy, isFalse);
  });

  test(
    'room replacement clears and revokes before loading the next room',
    () async {
      final sequence = <String>[];
      late VrHomeRoomController controller;
      controller = VrHomeRoomController(
        onInvalidated: () {
          expect(controller.presentation, isNull);
          expect(controller.room, same(_otherRoom));
          sequence.add('revoke');
        },
        callback: (room, _) async {
          sequence.add('load:${room.id}');
          return _content(room.title);
        },
      );
      addTearDown(controller.dispose);
      controller.openRoom(_room);
      await _flush();
      sequence.clear();
      controller.addListener(() {
        if (controller.presentation == null) sequence.add('clear');
      });
      controller.openRoom(_otherRoom);
      expect(sequence, ['clear', 'revoke', 'load:${_otherRoom.id}']);
      expect(controller.presentation, isNull);
      await _flush();
      expect(controller.presentation?.title, _otherRoom.title);
    },
  );

  test(
    'disabled and unknown actions are ignored; busy prevents duplicates',
    () async {
      final actionResult = Completer<VrHomeRoomPresentation>();
      final calls = <String?>[];
      final controller = VrHomeRoomController(
        callback: (room, action) {
          calls.add(action);
          return action == null
              ? Future.value(_content('Ready'))
              : actionResult.future;
        },
      );
      addTearDown(controller.dispose);
      controller.openRoom(_room);
      await _flush();
      await controller.activate('locked');
      await controller.activate('not-listed');
      expect(calls, [null]);
      final active = controller.activate('open');
      expect(controller.presentation, isNull);
      expect(controller.busy, isTrue);
      await controller.activate('open');
      await controller.retry();
      expect(calls, [null, 'open']);
      actionResult.complete(_content('Opened'));
      await active;
      expect(controller.presentation?.title, 'Opened');
      expect(controller.busy, isFalse);
    },
  );

  test(
    'identity change clears protected content before revocation and reload',
    () async {
      final changes = _RoomChanges();
      final refreshed = Completer<VrHomeRoomPresentation>();
      final sequence = <String>[];
      var requests = 0;
      late VrHomeRoomController controller;
      controller = VrHomeRoomController(
        roomChanges: changes,
        onInvalidated: () {
          expect(controller.presentation, isNull);
          sequence.add('revoke');
        },
        callback: (room, action) {
          expect(action, isNull);
          requests++;
          if (requests == 1) return Future.value(_content('Private title'));
          sequence.add('reload');
          return refreshed.future;
        },
      );
      addTearDown(changes.dispose);
      addTearDown(controller.dispose);
      controller.openRoom(_room);
      await _flush();
      controller.addListener(() {
        if (controller.presentation == null) sequence.add('clear');
      });
      changes.change();
      expect(controller.presentation, isNull);
      expect(controller.busy, isTrue);
      expect(sequence, ['clear', 'revoke', 'reload']);
      refreshed.complete(_content('Public title'));
      await _flush();
      expect(controller.presentation?.title, 'Public title');
    },
  );

  test(
    'identity change invalidates an in-flight action and its failure',
    () async {
      final changes = _RoomChanges();
      final actionResult = Completer<VrHomeRoomPresentation>();
      final refreshed = Completer<VrHomeRoomPresentation>();
      var loads = 0;
      final controller = VrHomeRoomController(
        roomChanges: changes,
        callback: (room, action) {
          if (action != null) return actionResult.future;
          return ++loads == 1
              ? Future.value(_content('Account A'))
              : refreshed.future;
        },
      );
      addTearDown(changes.dispose);
      addTearDown(controller.dispose);
      controller.openRoom(_room);
      await _flush();
      final action = controller.activate('open');
      changes.change();
      refreshed.complete(_content('Account B'));
      await _flush();
      actionResult.completeError(StateError('Private action error'));
      await action;
      expect(controller.presentation?.title, 'Account B');
      expect(controller.error, isNull);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'close notifies and prevents a pending load from reopening the room',
    () async {
      final pending = Completer<VrHomeRoomPresentation>();
      final controller = VrHomeRoomController(
        callback: (_, _) => pending.future,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.openRoom(_room);
      controller.close();
      final afterClose = notifications;
      expect(afterClose, 2);
      pending.complete(_content('Too late'));
      await _flush();
      expect(notifications, afterClose);
      expect(controller.isOpen, isFalse);
      expect(controller.room, isNull);
      expect(controller.presentation, isNull);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'dispose removes the identity listener and ignores late failures',
    () async {
      final changes = _RoomChanges();
      final pending = Completer<VrHomeRoomPresentation>();
      var calls = 0;
      final controller = VrHomeRoomController(
        roomChanges: changes,
        callback: (_, _) {
          calls++;
          return pending.future;
        },
      );
      addTearDown(changes.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.openRoom(_room);
      controller.dispose();
      changes.change();
      pending.completeError(StateError('Late private failure'));
      await _flush();
      expect(calls, 1);
      expect(notifications, 1);
      expect(changes.hasSubscriptions, isFalse);
      expect(controller.presentation, isNull);
      expect(controller.error, isNull);
    },
  );

  test('errors conceal backend details and allow a fresh retry', () async {
    var calls = 0;
    final controller = VrHomeRoomController(
      callback: (_, _) {
        if (++calls == 1) throw StateError('Secret URL and account');
        return Future.value(_content('Recovered'));
      },
    );
    addTearDown(controller.dispose);
    controller.openRoom(_room);
    await _flush();
    expect(controller.presentation, isNull);
    expect(controller.busy, isFalse);
    expect(controller.error, isNotNull);
    expect(controller.error, isNot(contains('Secret')));
    await controller.retry();
    expect(calls, 2);
    expect(controller.error, isNull);
    expect(controller.presentation?.title, 'Recovered');
  });

  test(
    'failed host invalidation never reloads or restores protected content',
    () async {
      final changes = _RoomChanges();
      var calls = 0;
      final controller = VrHomeRoomController(
        roomChanges: changes,
        onInvalidated: () => throw StateError('Private revocation details'),
        callback: (_, _) async {
          calls++;
          return _content('Protected');
        },
      );
      addTearDown(changes.dispose);
      addTearDown(controller.dispose);
      controller.openRoom(_room);
      await _flush();
      changes.change();
      expect(calls, 1);
      expect(controller.presentation, isNull);
      expect(controller.error, isNotNull);
      expect(controller.error, isNot(contains('Private')));
      expect(controller.busy, isFalse);
      await controller.retry();
      expect(calls, 1);
      expect(controller.presentation, isNull);
      expect(controller.error, isNotNull);
    },
  );

  test('closing from a notification prevents the callback from starting', () {
    var calls = 0;
    final controller = VrHomeRoomController(
      callback: (_, _) async {
        calls++;
        return _content('Never requested');
      },
    );
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.busy) controller.close();
    });
    controller.openRoom(_room);
    expect(calls, 0);
    expect(controller.isOpen, isFalse);
    expect(controller.busy, isFalse);
  });

  test(
    'closed rooms do not reload and do not call the session invalidation hook',
    () async {
      final changes = _RoomChanges();
      var invalidations = 0;
      var calls = 0;
      final controller = VrHomeRoomController(
        roomChanges: changes,
        onInvalidated: () => invalidations++,
        callback: (_, _) async {
          calls++;
          return _content('Ready');
        },
      );
      addTearDown(changes.dispose);
      controller.openRoom(_room);
      await _flush();
      controller.close();
      changes.change();
      await controller.retry();
      await controller.activate('open');
      controller.dispose();
      expect(calls, 1);
      expect(invalidations, 0);
    },
  );
}
