import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

void main() {
  for (final size in [const Size(360, 740), const Size(740, 360)]) {
    testWidgets('all rooms remain accessible at $size with large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: VrHomeEcosystemLobby(
            onOpenRoom: (room) async => opened.add(room.id),
          ),
        ),
      );
      for (final room in VrHomeEcosystemRoom.defaults) {
        final button = find.byKey(ValueKey('ecosystem_room_${room.id}'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(opened, VrHomeEcosystemRoom.defaults.map((r) => r.id));
    });
  }

  testWidgets('awaits the host route and retains Home after returning', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return VrHomeEcosystemLobby(
              onOpenRoom: (room) async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        Scaffold(appBar: AppBar(title: Text(room.title))),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    final room = find.byKey(const ValueKey('ecosystem_room_profile'));
    await tester.ensureVisible(room);
    await tester.tap(room);
    await tester.pumpAndSettle();
    expect(find.byType(VrHomeEcosystemLobby), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(VrHomeEcosystemLobby), findsOneWidget);
    expect(tester.widget<FilledButton>(room).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy, unavailable and failed rooms never duplicate requests', (
    tester,
  ) async {
    var requests = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: VrHomeEcosystemLobby(
          onOpenRoom: (_) {
            requests++;
            return pending.future;
          },
          unavailableReasons: const {
            'social': 'Disponible al conectar tu cuenta',
          },
        ),
      ),
    );
    final profile = find.byKey(const ValueKey('ecosystem_room_profile'));
    final social = find.byKey(const ValueKey('ecosystem_room_social'));
    expect(tester.widget<FilledButton>(social).onPressed, isNull);
    await tester.ensureVisible(profile);
    await tester.tap(profile);
    await tester.tap(profile);
    await tester.pump();
    expect(requests, 1);
    expect(tester.widget<FilledButton>(profile).onPressed, isNull);
    pending.completeError(StateError('Private backend details'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ecosystem_open_error')), findsOneWidget);
    expect(find.textContaining('Private backend details'), findsNothing);
    expect(tester.widget<FilledButton>(profile).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host owns back and existing experiences callbacks', (
    tester,
  ) async {
    var back = 0, experiences = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VrHomeEcosystemLobby(
          onOpenRoom: (_) async {},
          onBack: () => back++,
          onExperiences: () => experiences++,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ecosystem_back')));
    await tester.tap(find.byKey(const ValueKey('ecosystem_experiences')));
    expect(back, 1);
    expect(experiences, 1);
  });

  testWidgets(
    'ecosystem entrance is optional and respects landing busy state',
    (tester) async {
      var calls = 0;
      Widget app({VoidCallback? action, bool busy = false}) => MaterialApp(
        home: VrHomeLanding(
          onExplore: null,
          onViewer: null,
          onController: null,
          onEcosystem: action,
          busy: busy,
        ),
      );
      await tester.pumpWidget(app());
      expect(find.byKey(const ValueKey('start_ecosystem')), findsNothing);
      await tester.pumpWidget(app(action: () => calls++));
      final button = find.byKey(const ValueKey('start_ecosystem'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      expect(calls, 1);
      await tester.pumpWidget(app(action: () => calls++, busy: true));
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    },
  );
}
