import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart'
    show VrSessionController, VrSessionHost, VrSessionStatus;
import 'package:vrlizate_home/vrlizate_home.dart';
import 'package:vrlizate_home_example/main.dart';

void main() {
  testWidgets('the independent host starts in the lightweight Home', (
    tester,
  ) async {
    await tester.pumpWidget(const HomeExample());
    await tester.pumpAndSettle();
    expect(find.text('VRlizate'), findsOneWidget);
    expect(find.text('Probar sin visor'), findsOneWidget);
    expect(find.text('Usar como visor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme updates preserve catalog navigation and system Back', (
    tester,
  ) async {
    VrSessionController? session;
    await tester.pumpWidget(
      HomeExample(
        sceneBuilder: (_) => Builder(
          builder: (context) {
            session = VrSessionHost.of(context);
            return Scaffold(
              appBar: AppBar(title: const Text('Gallery session')),
              body: const Text('Portable renderer boundary'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Probar sin visor'));
    await tester.pumpAndSettle();
    expect(find.byType(VrHomeCatalog), findsOneWidget);

    final daylight = find.byKey(const ValueKey('home_theme_daylight'));
    await tester.ensureVisible(daylight);
    await tester.tap(daylight);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
      Brightness.light,
    );
    expect(find.byType(VrHomeCatalog), findsOneWidget);

    final gallery = find.byKey(const ValueKey('catalog_item_gallery'));
    await tester.ensureVisible(gallery);
    await tester.tap(gallery);
    for (var attempt = 0; attempt < 200 && session == null; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(session, isNotNull);
    final controller = session!;
    expect(controller.status.value, VrSessionStatus.running);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.status.value, VrSessionStatus.closed);
    expect(find.byType(VrHomeCatalog), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('catalog_back')));
    await tester.tap(find.byKey(const ValueKey('catalog_back')));
    await tester.pumpAndSettle();
    expect(find.text('Probar sin visor'), findsOneWidget);
    expect(
      tester.widget<VrHomeLanding>(find.byType(VrHomeLanding)).theme.id,
      VrHomeThemeData.daylight.id,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
