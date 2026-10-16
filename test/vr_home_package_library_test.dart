import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

const _scene = VrHomePackageItem(
  id: 'org.example.gallery',
  title: 'Galería portátil',
  description: 'Una sala de esculturas que puedes explorar.',
  typeLabel: 'Escena portátil',
);
const _game = VrHomePackageItem(
  id: 'org.example.race',
  title: 'Carrera integrada',
  description: 'Usa el juego que ya incluye la aplicación.',
  typeLabel: 'Demo integrada',
);

void main() {
  for (final size in [const Size(360, 740), const Size(740, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('library fits $size at text scale $scale', (tester) async {
        _viewport(tester, size);
        await tester.pumpWidget(
          _app(
            VrHomePackageLibrary(
              items: const [_scene, _game],
              location:
                  '/Users/example/Library/Application Support/VRLizate/paquetes/mis_paquetes_de_prueba',
              onLaunch: (_) async {},
              onRefresh: () {},
              onImport: () {},
              onInstallExamples: () {},
              onCopyLocation: () {},
              issues: const [
                'archivo-incompatible.vrlz: Este archivo no se pudo validar; el resto sigue disponible.',
              ],
              error:
                  'Un aviso extenso que debe seguir visible y permitir revisar los paquetes disponibles.',
            ),
            scale: scale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Escena portátil'), findsOneWidget);
        expect(find.text('Demo integrada'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('home_package_open_org.example.race')),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('mounting and resuming do not invoke host actions', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      _app(
        VrHomePackageLibrary(
          items: const [],
          location: '/packages',
          onLaunch: (_) async {
            actions++;
          },
          onRefresh: () {
            actions++;
          },
          onImport: () {
            actions++;
          },
          onInstallExamples: () {
            actions++;
          },
          onCopyLocation: () {
            actions++;
          },
        ),
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(actions, 0);
    expect(find.byKey(const ValueKey('home_package_empty')), findsOneWidget);
    expect(find.text('/packages'), findsOneWidget);
  });

  testWidgets('library controls delegate only explicit user actions', (
    tester,
  ) async {
    final actions = <String>[];
    await tester.pumpWidget(
      _app(
        VrHomePackageLibrary(
          items: const [],
          location: '/packages',
          onLaunch: (_) async {},
          onRefresh: () => actions.add('refresh'),
          onImport: () => actions.add('import'),
          onInstallExamples: () => actions.add('examples'),
          onCopyLocation: () => actions.add('copy'),
        ),
      ),
    );
    for (final action in ['copy', 'refresh', 'import', 'examples']) {
      final control = find.byKey(ValueKey('home_package_$action'));
      await tester.ensureVisible(control);
      await tester.tap(control);
      await tester.pump();
    }
    expect(actions, ['copy', 'refresh', 'import', 'examples']);
  });

  testWidgets('unavailable entries keep their reason and cannot launch', (
    tester,
  ) async {
    var launches = 0;
    const unavailable = VrHomePackageItem(
      id: 'org.example.doom',
      title: 'DOOM',
      description: 'Juego integrado',
      typeLabel: 'Demo integrada',
      unavailableReason: 'Disponible solo en Android.',
    );
    await tester.pumpWidget(
      _app(
        VrHomePackageLibrary(
          items: const [unavailable],
          location: '/packages',
          onLaunch: (_) async {
            launches++;
          },
        ),
      ),
    );
    expect(find.text('Disponible solo en Android.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('home_package_open_org.example.doom')),
    );
    expect(button.onPressed, isNull);
    expect(launches, 0);
    expect(find.byKey(const ValueKey('home_package_import')), findsNothing);
  });

  testWidgets('a per-file issue leaves supported entries usable', (
    tester,
  ) async {
    final launches = <String>[];
    await tester.pumpWidget(
      _app(
        VrHomePackageLibrary(
          items: const [_scene],
          location: '/packages',
          issues: const ['roto.vrlz no es un paquete válido.'],
          onLaunch: (id) async {
            launches.add(id);
          },
        ),
      ),
    );
    final button = find.byKey(
      const ValueKey('home_package_open_org.example.gallery'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(launches, ['org.example.gallery']);
    expect(find.text('roto.vrlz no es un paquete válido.'), findsOneWidget);
  });

  testWidgets('pending launch prevents duplicate and parallel entry taps', (
    tester,
  ) async {
    final pending = Completer<void>();
    final launches = <String>[];
    await tester.pumpWidget(
      _app(
        VrHomePackageLibrary(
          items: const [_scene, _game],
          location: '/packages',
          onRefresh: () {},
          onLaunch: (id) {
            launches.add(id);
            return pending.future;
          },
        ),
      ),
    );
    final first = tester.widget<FilledButton>(
      find.byKey(const ValueKey('home_package_open_org.example.gallery')),
    );
    final second = tester.widget<FilledButton>(
      find.byKey(const ValueKey('home_package_open_org.example.race')),
    );
    first.onPressed!();
    first.onPressed!();
    second.onPressed!();
    await tester.pump();
    expect(launches, ['org.example.gallery']);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('home_package_refresh')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('home_package_open_org.example.race')),
          )
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('home_package_open_org.example.race')),
          )
          .onPressed,
      isNotNull,
    );
  });

  for (final loading in [true, false]) {
    testWidgets('host ${loading ? 'loading' : 'busy'} disables actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          VrHomePackageLibrary(
            items: const [_scene],
            location: '/packages',
            onLaunch: (_) async {},
            loading: loading,
            busy: !loading,
            onRefresh: () {},
            onImport: () {},
            onInstallExamples: () {},
            onCopyLocation: () {},
          ),
        ),
      );
      for (final button in tester.widgetList<ButtonStyleButton>(
        find.byWidgetPredicate((w) => w is ButtonStyleButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  }

  testWidgets('a callback failure releases the guard and offers retry', (
    tester,
  ) async {
    var launches = 0;
    await tester.pumpWidget(
      _app(
        VrHomePackageLibrary(
          items: const [_scene],
          location: '/packages',
          onLaunch: (_) async {
            if (launches++ == 0) throw StateError('Host failed');
          },
        ),
      ),
    );
    final button = find.byKey(
      const ValueKey('home_package_open_org.example.gallery'),
    );
    tester.widget<FilledButton>(button).onPressed!();
    await tester.pump();
    expect(
      find.textContaining('No se pudo abrir Galería portátil'),
      findsOneWidget,
    );
    tester.widget<FilledButton>(button).onPressed!();
    await tester.pump();
    expect(launches, 2);
    expect(find.byKey(const ValueKey('home_package_error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch completion after disposal has no UI side effects', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      _app(
        VrHomePackageLibrary(
          items: const [_scene],
          location: '/packages',
          onLaunch: (_) => pending.future,
        ),
      ),
    );
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('home_package_open_org.example.gallery')),
        )
        .onPressed!();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
