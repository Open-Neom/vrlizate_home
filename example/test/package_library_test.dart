import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart'
    show VrSessionController, VrSessionHost, VrSessionStatus;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart';
import 'package:vrlizate_apps/vrlizate_apps_viewer.dart';
import 'package:vrlizate_home/vrlizate_home.dart';
import 'package:vrlizate_home_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  late PathProviderPlatform originalPathProvider;
  late _ExamplePathProvider pathProvider;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('home-example-library-');
    originalPathProvider = PathProviderPlatform.instance;
    pathProvider = _ExamplePathProvider(documents.path);
    PathProviderPlatform.instance = pathProvider;
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    documents.deleteSync(recursive: true);
  });

  testWidgets(
    'independent worlds package launches from Home through the SDK session',
    (tester) async {
      VrlzWorldBundle? opened;
      VrSessionController? session;
      await tester.pumpWidget(
        HomeExample(
          worldBuilder: (bundle) {
            opened = bundle;
            return Builder(
              builder: (context) {
                session = VrSessionHost.of(context);
                return const Scaffold(body: Text('Portable worlds renderer'));
              },
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Probar sin visor'));
      await tester.pumpAndSettle();
      final gardens = find.byKey(
        const ValueKey('catalog_item_connected-gardens'),
      );
      await tester.ensureVisible(gardens);
      await tester.tap(gardens);
      for (var i = 0; i < 200 && opened == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(opened?.manifest.id, 'community.connected_gardens');
      expect(opened?.manifest.worlds, hasLength(2));
      expect(opened?.manifest.portals, hasLength(2));
      expect(session?.status.value, VrSessionStatus.running);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(session?.status.value, VrSessionStatus.closed);
      expect(find.byType(VrHomeCatalog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('retro package stays unavailable when its runtime is absent', (
    tester,
  ) async {
    final directory = Directory.fromUri(
      documents.uri.resolve('VRlizate-example/experiencias/'),
    )..createSync(recursive: true);
    final level = VrlzRetroLevel.fromJson({
      'name': 'Original course',
      'theme': 'garden',
      'mode': 'platformer',
      'rows': [
        '................',
        '................',
        '................',
        '................',
        '................',
        '................',
        '..S..........G..',
        '################',
      ],
    });
    File.fromUri(directory.uri.resolve('retro.vrlz')).writeAsBytesSync(
      VrlzPackage.encodeRetro(
        level: level,
        id: 'org.example.retro',
        title: 'Juego original',
        license:
            'Original test fixture. Permission to use, copy, modify and redistribute is granted without restriction.',
      ),
    );
    await tester.pumpWidget(const HomeExample());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Biblioteca .vrlz'));
    await tester.tap(find.text('Biblioteca .vrlz'));
    await tester.pump();
    await _waitForDirectory(tester);
    final page = tester.widget<VrHomePackageLibrary>(
      find.byType(VrHomePackageLibrary),
    );
    final item = page.items.single;
    expect(item.typeLabel, 'Juego retro 2.5D');
    expect(
      item.unavailableReason,
      'El runtime retro 2.5D no está instalado en este ejemplo.',
    );
    expect(find.byType(VrlzSceneViewer), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'NES package is listed but cannot launch without its installed runtime',
    (tester) async {
      final directory = Directory.fromUri(
        documents.uri.resolve('VRlizate-example/experiencias/'),
      )..createSync(recursive: true);
      final rom = Uint8List(16 + 16384 + 8192)
        ..setRange(0, 8, [0x4e, 0x45, 0x53, 0x1a, 1, 1, 0, 0]);
      File.fromUri(directory.uri.resolve('cartridge.vrlz')).writeAsBytesSync(
        VrlzPackage.encodeNes(
          romBytes: rom,
          id: 'org.example.nes',
          title: 'Cartucho de prueba',
          license:
              'Synthetic test fixture. Permission to use, copy, modify and redistribute is granted without restriction.',
          sourceUrl: 'https://example.org/source',
        ),
      );
      await tester.pumpWidget(const HomeExample());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Biblioteca .vrlz'));
      await tester.tap(find.text('Biblioteca .vrlz'));
      await tester.pump();
      await _waitForDirectory(tester);
      final page = tester.widget<VrHomePackageLibrary>(
        find.byType(VrHomePackageLibrary),
      );
      final item = page.items.single;
      expect(item.typeLabel, 'Cartucho NES');
      expect(
        item.unavailableReason,
        'El runtime NES no está instalado en este ejemplo.',
      );
      expect(find.byType(VrlzSceneViewer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'SDK player opens a package, pauses its engine session and returns Home',
    (tester) async {
      VrSessionController? session;
      await tester.pumpWidget(
        HomeExample(
          sceneBuilder: (bundle) => Builder(
            builder: (context) {
              session = VrSessionHost.of(context);
              return Scaffold(
                appBar: AppBar(title: Text(bundle.manifest.title)),
                body: const Text('Portable renderer boundary'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Biblioteca .vrlz'));
      await tester.tap(find.text('Biblioteca .vrlz'));
      await tester.pump();
      await _waitForDirectory(tester);
      final install = find.byKey(const ValueKey('home_package_examples'));
      await tester.ensureVisible(install);
      // Asset reads and imports start in the real async zone; starting the
      // sequential asset chain in FakeAsync can strand its second I/O future.
      await tester.runAsync(() => tester.tap(install));
      await tester.pump();
      await _waitForDirectory(tester);
      final page = tester.widget<VrHomePackageLibrary>(
        find.byType(VrHomePackageLibrary),
      );
      final scene = page.items.firstWhere(
        (item) => item.typeLabel == 'Escena portátil',
      );
      final launch = find.byKey(ValueKey('home_package_open_${scene.id}'));
      await tester.ensureVisible(launch);
      await tester.tap(launch);
      // Package reading uses the real filesystem; let the launch complete.
      for (var i = 0; i < 200 && session == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final controller = session!;
      expect(controller.status.value, VrSessionStatus.running);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.status.value, VrSessionStatus.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.status.value, VrSessionStatus.running);
      await tester.pageBack();
      await tester.pump();
      await _waitForDirectory(tester);
      expect(controller.status.value, VrSessionStatus.closed);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Probar sin visor'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inactive visible library reads a missing folder without creating it',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpWidget(const HomeExample());
      await tester.pumpAndSettle();
      expect(pathProvider.directoryRequests, 0);
      final launch = find.text('Biblioteca .vrlz');
      await tester.ensureVisible(launch);
      await tester.tap(launch);
      await tester.pump();
      await _waitForDirectory(tester);

      expect(pathProvider.directoryRequests, 1);
      final directory = Directory.fromUri(
        documents.uri.resolve('VRlizate-example/experiencias/'),
      );
      expect(directory.existsSync(), isFalse);
      final page = tester.widget<VrHomePackageLibrary>(
        find.byType(VrHomePackageLibrary),
      );
      expect(page.location, directory.path);
      expect(page.issues, isNotEmpty);
      expect(find.byKey(const ValueKey('home_package_empty')), findsOneWidget);
      expect(find.byType(VrlzSceneViewer), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Probar sin visor'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'explicit example installation adds scene, worlds and the gallery builtin without launching',
    (tester) async {
      await tester.pumpWidget(const HomeExample());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Biblioteca .vrlz'));
      await tester.tap(find.text('Biblioteca .vrlz'));
      await tester.pump();
      await _waitForDirectory(tester);

      final install = find.byKey(const ValueKey('home_package_examples'));
      await tester.ensureVisible(install);
      // Asset reads and imports start in the real async zone; starting the
      // sequential asset chain in FakeAsync can strand its second I/O future.
      await tester.runAsync(() => tester.tap(install));
      await tester.pump();
      await _waitForDirectory(tester);

      final directory = Directory.fromUri(
        documents.uri.resolve('VRlizate-example/experiencias/'),
      );
      List<VrlzPackage> packages() => directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.vrlz'))
          .map((file) => VrlzPackage.decode(file.readAsBytesSync()))
          .toList();
      final installed = packages();
      expect(installed, hasLength(3));
      expect(
        installed.where((p) => p.kind == VrlzPackageKind.scene),
        hasLength(1),
      );
      expect(
        installed
            .singleWhere((p) => p.kind == VrlzPackageKind.worlds)
            .worldBundle!
            .manifest
            .worlds,
        hasLength(2),
      );
      final builtin = installed.singleWhere(
        (p) => p.kind == VrlzPackageKind.builtin,
      );
      expect(builtin.id, 'org.vrlizate.example.gallery');
      expect(builtin.demoId, 'gallery');
      expect(builtin.title, 'Galería integrada');
      expect(find.byType(VrlzSceneViewer), findsNothing);

      await tester.ensureVisible(install);
      // Asset reads and imports start in the real async zone; starting the
      // sequential asset chain in FakeAsync can strand its second I/O future.
      await tester.runAsync(() => tester.tap(install));
      await tester.pump();
      await _waitForDirectory(tester);
      expect(packages(), hasLength(3));
      expect(
        tester
            .widget<VrHomePackageLibrary>(find.byType(VrHomePackageLibrary))
            .error,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

/// Works for both MethodChannel and FFI platform implementations.
class _ExamplePathProvider extends PathProviderPlatform {
  _ExamplePathProvider(this.documentsPath);

  final String documentsPath;
  int directoryRequests = 0;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    directoryRequests++;
    return documentsPath;
  }
}

/// Native filesystem futures need real event-loop time in a widget test.
/// Wait for observable controller completion rather than a fixed startup delay.
Future<void> _waitForDirectory(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final page = tester.widget<VrHomePackageLibrary>(
      find.byType(VrHomePackageLibrary),
    );
    if (!page.busy && !page.loading) {
      await tester.pumpAndSettle();
      expect(page.error, isNull);
      return;
    }
  }
  fail('The example directory controller did not finish.');
}
