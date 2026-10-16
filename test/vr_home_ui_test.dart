import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/src/theme/vr_home_theme.dart';
import 'package:vrlizate_home/src/ui/vr_home_catalog.dart';
import 'package:vrlizate_home/src/ui/vr_home_landing.dart';

void main() {
  test('palettes and catalog metadata keep caller collections immutable', () {
    final colors = <Color>[Colors.black, Colors.blue];
    final custom = VrHomeThemeData(
      id: 'custom',
      name: 'Personalizado',
      background: Colors.black,
      surface: Colors.black,
      foreground: Colors.white,
      muted: Colors.grey,
      accent: Colors.cyan,
      secondary: Colors.blue,
      border: Colors.grey,
      gradient: colors,
    );
    colors[0] = Colors.red;
    expect(custom.gradient.first, Colors.black);
    expect(() => custom.gradient.add(Colors.red), throwsUnsupportedError);
    expect(
      VrHomeThemeData.presets.map((theme) => theme.id).toSet(),
      hasLength(3),
    );
    expect(VrHomeThemeData.daylight.materialTheme.brightness, Brightness.light);
    expect(VrHomeThemeData.midnight.materialTheme.brightness, Brightness.dark);
    expect(
      VrHomeThemeData.aurora.materialTheme.colorScheme.primary,
      VrHomeThemeData.aurora.accent,
    );
    final tags = <String>['táctil'];
    final item = VrHomeCatalogItem(
      id: 'test',
      title: 'Prueba',
      subtitle: '',
      category: 'Espacios',
      icon: Icons.room,
      accent: Colors.cyan,
      tags: tags,
    );
    tags.add('added');
    expect(item.tags, ['táctil']);
    expect(() => item.tags.clear(), throwsUnsupportedError);
  });

  for (final size in [const Size(360, 740), const Size(740, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('landing and catalog fit $size with text scale $scale', (
        tester,
      ) async {
        _viewport(tester, size);
        await tester.pumpWidget(
          _app(
            VrHomeLanding(
              notice: 'Tu invitación está lista. Elige cómo quieres entrar.',
              onExplore: () {},
              onViewer: () {},
              onController: () {},
              onResumeController: () {},
              onForgetController: () {},
              onThemeChanged: (_) {},
              settings: TextButton(
                onPressed: () {},
                child: const Text('Ajustes de la experiencia'),
              ),
            ),
            textScale: scale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Tu espacio, a tu manera'), findsOneWidget);
        expect(find.textContaining('misma red Wi-Fi'), findsOneWidget);
        await tester.ensureVisible(find.textContaining('misma red Wi-Fi'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          _app(
            VrHomeCatalog(
              items: _items(),
              onLaunch: (_) async {},
              onBack: () {},
              onPairController: () {},
              onThemeChanged: (_) {},
              actions: [
                OutlinedButton(onPressed: () {}, child: const Text('Mando 3D')),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Abrir .vrz'),
                ),
              ],
            ),
            textScale: scale,
          ),
        );
        await tester.pump();
        expect(find.byType(Card), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('catalog_item_orbit')),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in [const Size(360, 740), const Size(800, 600)]) {
    testWidgets('primary phone action starts visible at $size', (tester) async {
      _viewport(tester, size);
      await tester.pumpWidget(
        _app(
          VrHomeLanding(
            onExplore: () {},
            onViewer: () {},
            onController: () {},
            onThemeChanged: (_) {},
          ),
        ),
      );
      final action = find.byKey(const ValueKey('start_phone_demos'));
      expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(size.height));
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a host without pairing hides controller setup', (tester) async {
    _viewport(tester, const Size(360, 740));
    var explored = 0;
    var viewed = 0;
    await tester.pumpWidget(
      _app(
        VrHomeLanding(
          onExplore: () => explored++,
          onViewer: () => viewed++,
          onController: null,
        ),
      ),
    );
    expect(find.text('Usar como mando'), findsNothing);
    expect(find.byKey(const ValueKey('start_controller')), findsNothing);
    expect(find.text('Para usar dos teléfonos'), findsNothing);
    expect(find.textContaining('misma red Wi-Fi'), findsNothing);
    expect(find.textContaining('conecta un mando'), findsNothing);
    for (final id in ['start_phone_demos', 'start_visor']) {
      final action = find.byKey(ValueKey(id));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
    }
    expect(explored, 1);
    expect(viewed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landing delegates each action and palette selection', (
    tester,
  ) async {
    _viewport(tester, const Size(360, 740));
    final actions = <String>[];
    VrHomeThemeData? selected;
    await tester.pumpWidget(
      _app(
        VrHomeLanding(
          onExplore: () => actions.add('explore'),
          onViewer: () => actions.add('viewer'),
          onController: () => actions.add('controller'),
          onResumeController: () => actions.add('resume'),
          onForgetController: () => actions.add('forget'),
          onThemeChanged: (value) => selected = value,
          notice: 'Aviso de prueba',
        ),
      ),
    );
    expect(find.byKey(const ValueKey('start_notice')), findsOneWidget);
    expect(find.text('Usar como visor'), findsOneWidget);
    expect(find.text('Usar como mando'), findsOneWidget);
    expect(find.textContaining('Flutter Scene'), findsNothing);
    for (final key in [
      'start_phone_demos',
      'start_visor',
      'start_controller',
      'resume_controller',
      'forget_controller',
    ]) {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
    }
    expect(actions, ['explore', 'viewer', 'controller', 'resume', 'forget']);
    final theme = find.byKey(const ValueKey('home_theme_daylight'));
    await tester.ensureVisible(theme);
    await tester.tap(theme);
    await tester.pump();
    expect(selected, same(VrHomeThemeData.daylight));
  });

  testWidgets('busy landing disables launch and pairing callbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        VrHomeLanding(
          busy: true,
          onExplore: () {},
          onViewer: () {},
          onController: () {},
          onResumeController: () {},
          onForgetController: () {},
        ),
      ),
    );
    final explore = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start_phone_demos')),
    );
    expect(explore.onPressed, isNull);
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('start_visor'))).onTap,
      isNull,
    );
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('start_controller')))
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('resume_controller')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('forget_controller')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'search includes normalized accents and tags, combined with category',
    (tester) async {
      _viewport(tester, const Size(740, 900));
      await tester.pumpWidget(
        _app(VrHomeCatalog(items: _items(), onLaunch: (_) async {})),
      );
      final search = find.byKey(const ValueKey('catalog_search'));
      await tester.enterText(search, 'orbita');
      await tester.pump();
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Órbita tranquila'), findsOneWidget);
      await tester.enterText(search, 'tactil');
      await tester.pump();
      expect(find.text('Sala de colores'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('catalog_category_Juegos')));
      await tester.pump();
      expect(find.byKey(const ValueKey('catalog_empty')), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      await tester.tap(find.byKey(const ValueKey('catalog_clear_search')));
      await tester.pump();
      expect(find.text('Ritmo en movimiento'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('catalog_category_all')));
      await tester.pump();
      expect(find.byType(Card), findsNWidgets(3));
    },
  );

  testWidgets('catalog preserves navigation labels and host actions', (
    tester,
  ) async {
    var backs = 0, pairs = 0;
    await tester.pumpWidget(
      _app(
        VrHomeCatalog(
          items: const [],
          onLaunch: (_) async {},
          backLabel: 'Virtual Home 3D',
          onBack: () => backs++,
          onPairController: () => pairs++,
        ),
      ),
    );
    await tester.tap(find.text('Virtual Home 3D'));
    await tester.tap(find.text('QR Mando'));
    expect(backs, 1);
    expect(pairs, 1);
    expect(find.byKey(const ValueKey('catalog_empty')), findsOneWidget);
  });

  testWidgets(
    'launch awaits completion and ignores repeated taps before rebuild',
    (tester) async {
      _viewport(tester, const Size(740, 1000));
      final pending = Completer<void>();
      var launches = 0;
      await tester.pumpWidget(
        _app(
          VrHomeCatalog(
            items: _items(),
            onLaunch: (_) {
              launches++;
              return pending.future;
            },
          ),
        ),
      );
      final target = find.byKey(const ValueKey('catalog_item_room'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.tap(target);
      await tester.pump();
      expect(launches, 1);
      expect(find.text('Abriendo…'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('catalog_item_music')))
            .onTap,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Abriendo…'), findsNothing);
      expect(tester.widget<InkWell>(target).onTap, isNotNull);
    },
  );

  testWidgets(
    'failed launch exposes a friendly retry and releases the busy guard',
    (tester) async {
      _viewport(tester, const Size(740, 1000));
      var attempts = 0;
      await tester.pumpWidget(
        _app(
          VrHomeCatalog(
            items: _items(),
            onLaunch: (_) async {
              attempts++;
              if (attempts == 1) throw StateError('Diagnostic failure');
            },
          ),
        ),
      );
      final target = find.byKey(const ValueKey('catalog_item_room'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('catalog_launch_error')),
        findsOneWidget,
      );
      expect(find.textContaining('Diagnostic failure'), findsNothing);
      expect(tester.takeException(), isNull);
      final retry = find.byKey(const ValueKey('catalog_retry_launch'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byKey(const ValueKey('catalog_launch_error')), findsNothing);
    },
  );

  testWidgets('a pending launch can finish after catalog disposal', (
    tester,
  ) async {
    _viewport(tester, const Size(740, 1000));
    final pending = Completer<void>();
    await tester.pumpWidget(
      _app(VrHomeCatalog(items: _items(), onLaunch: (_) => pending.future)),
    );
    final target = find.byKey(const ValueKey('catalog_item_room'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

List<VrHomeCatalogItem> _items() => [
  VrHomeCatalogItem(
    id: 'room',
    title: 'Sala de colores',
    subtitle: 'Recorre un espacio lleno de luz y descubre cada detalle.',
    category: 'Espacios',
    icon: Icons.view_in_ar_rounded,
    accent: Colors.tealAccent,
    tags: ['táctil', 'Sin visor'],
    featured: true,
  ),
  VrHomeCatalogItem(
    id: 'music',
    title: 'Ritmo en movimiento',
    subtitle: 'Encuentra tu ritmo y sigue la música.',
    category: 'Juegos',
    icon: Icons.music_note_rounded,
    accent: Colors.amber,
  ),
  VrHomeCatalogItem(
    id: 'orbit',
    title: 'Órbita tranquila',
    subtitle: 'Explora los planetas a tu ritmo.',
    category: 'Aprender',
    icon: Icons.public_rounded,
    accent: Colors.lightBlue,
    tags: ['Espacio'],
  ),
];

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  builder: (context, nested) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: nested!,
  ),
  home: child,
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
