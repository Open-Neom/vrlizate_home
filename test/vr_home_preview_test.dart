import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

const _previewDirectory = String.fromEnvironment('VR_HOME_PREVIEW_DIR');
const _phoneSize = Size(390, 844);

// Opt-in captures of the actual shared 2D widgets with mock launch callbacks.
// No scene, renderer, tracking or pairing service is created by this test.
// flutter test test/vr_home_preview_test.dart \
//   --dart-define=VR_HOME_PREVIEW_DIR=/tmp/vrlizate-home-preview
void main() {
  testWidgets('export Home phone previews', (tester) async {
    final directory = Directory(_previewDirectory);
    if (!directory.isAbsolute) {
      throw ArgumentError('VR_HOME_PREVIEW_DIR must be an absolute path.');
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _phoneSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      await directory.create(recursive: true);
      await _loadPreviewFonts();
    });

    for (final theme in VrHomeThemeData.presets) {
      final previewTheme = _PreviewThemeData(theme);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: previewTheme.materialTheme,
            home: VrHomeLanding(
              theme: previewTheme,
              onThemeChanged: (_) {},
              onExplore: () {},
              onViewer: () {},
              onController: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = tester.renderObject<RenderParagraph>(
        find.text('Probar sin visor'),
      );
      expect(
        label.text.style?.fontFamily,
        'Roboto',
        reason: 'The button must not fall back to the widget-test Ahem font.',
      );
      await _capture(tester, boundaryKey, directory, 'landing_${theme.id}');
      if (theme == VrHomeThemeData.aurora) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('start_controller')),
        );
        await tester.pumpAndSettle();
        await _capture(tester, boundaryKey, directory, 'landing_aurora_modes');
      }
    }

    final catalogTheme = _PreviewThemeData(VrHomeThemeData.aurora);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: catalogTheme.materialTheme,
          home: VrHomeCatalog(
            theme: catalogTheme,
            items: _phoneRooms,
            onLaunch: (_) async {},
            onBack: () {},
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await _capture(tester, boundaryKey, directory, 'catalog_aurora');
    await tester.ensureVisible(
      find.byKey(const ValueKey('catalog_item_thermion_room')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, boundaryKey, directory, 'catalog_aurora_rooms');

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: catalogTheme.materialTheme,
          home: VrHomeLanding(
            theme: catalogTheme,
            onExplore: () {},
            onViewer: () {},
            onController: null,
            onEcosystem: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('start_ecosystem')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, boundaryKey, directory, 'landing_ecosystem');

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: catalogTheme.materialTheme,
          home: VrHomeEcosystemLobby(
            theme: catalogTheme,
            onOpenRoom: (_) async {},
            onBack: () {},
            onExperiences: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(6));
    expect(tester.takeException(), isNull);
    await _capture(tester, boundaryKey, directory, 'ecosystem_entrance');
    for (final id in ['creator', 'emxi', 'gigmeout', 'cyberneom']) {
      await tester.ensureVisible(find.byKey(ValueKey('ecosystem_room_$id')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, directory, 'ecosystem_$id');
    }
  }, skip: _previewDirectory.isEmpty);
}

/// Completes an unspecified platform font only in the screenshot harness.
///
/// FilledButton resolves the theme's custom label style independently of the
/// normal TextTheme. Its unspecified family uses the engine's default Ahem in
/// widget tests; loading another font called Ahem does not replace that default.
/// Keep the production palette, geometry and typography values, but select the
/// loaded Android font for this one test-only style resolution.
class _PreviewThemeData extends VrHomeThemeData {
  _PreviewThemeData(VrHomeThemeData source)
    : super(
        id: source.id,
        name: source.name,
        background: source.background,
        surface: source.surface,
        foreground: source.foreground,
        muted: source.muted,
        accent: source.accent,
        secondary: source.secondary,
        border: source.border,
        gradient: source.gradient,
      );

  @override
  ThemeData get materialTheme {
    final base = super.materialTheme;
    final buttonStyle = base.filledButtonTheme.style ?? const ButtonStyle();
    return base.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle.copyWith(
          textStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
            final style =
                buttonStyle.textStyle?.resolve(states) ??
                base.textTheme.labelLarge ??
                const TextStyle();
            return style.copyWith(fontFamily: 'Roboto');
          }),
        ),
      ),
    );
  }
}

final _phoneRooms = <VrHomeCatalogItem>[
  VrHomeCatalogItem(
    id: 'flutter_scene_room',
    title: 'Cuarto · Flutter Scene',
    subtitle:
        'Recorre la sala, acércate a los objetos y descubre sus detalles.',
    category: 'Espacios',
    icon: Icons.view_in_ar_rounded,
    accent: VrHomeThemeData.aurora.accent,
    tags: ['Sin visor', 'Control táctil'],
    featured: true,
  ),
  VrHomeCatalogItem(
    id: 'thermion_room',
    title: 'Cuarto · Thermion',
    subtitle: 'Explora la misma sala con otra forma de dibujar su luz y color.',
    category: 'Espacios',
    icon: Icons.auto_awesome_rounded,
    accent: VrHomeThemeData.aurora.secondary,
    tags: ['Sin visor', 'Control táctil'],
  ),
];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Directory directory,
  String name,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  expect(boundary.size, _phoneSize);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, _phoneSize.width.toInt());
      expect(image.height, _phoneSize.height.toInt());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Could not encode Home preview: $name');
      await File('${directory.path}/$name.png').writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      expect(png.lengthInBytes, greaterThan(1000));
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadPreviewFonts() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final flutter = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'flutter');
  final flutterRoot = Uri.directory(
    Directory.fromUri(
      configFile.uri.resolve(flutter['rootUri'] as String),
    ).path,
  );
  final fonts = flutterRoot.resolve(
    '../../bin/cache/artifacts/material_fonts/',
  );
  // Load Android's real fonts under their own names; Ahem is not replaceable.
  for (final family in ['Roboto', 'MaterialIcons']) {
    final loader = FontLoader(family);
    final files = family == 'MaterialIcons'
        ? ['MaterialIcons-Regular.otf']
        : ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
    for (final file in files) {
      final bytes = await File.fromUri(fonts.resolve(file)).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}
