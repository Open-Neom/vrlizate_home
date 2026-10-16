import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/vrlizate_home_catalog.dart';

VrDemoLibraryEntry _entry(
  String id, {
  String? title,
  List<String> aliases = const [],
  List<String> tags = const [],
}) => VrDemoLibraryEntry(
  id: id,
  title: title ?? id,
  subtitle: 'Contenido del anfitrión',
  category: VrDemoLibraryCategory.learn,
  accent: 0xFF2299AA,
  icon: 'museum',
  featured: true,
  aliases: aliases,
  tags: tags,
);

void main() {
  test(
    'two hosts can use the same route without sharing inventory or focus',
    () {
      final first = VrDemoCatalog([
        _entry('museum', title: 'Museo de Oaxaca', aliases: ['legacy']),
        _entry('garden'),
      ]);
      final second = VrDemoCatalog([
        _entry('museum', title: 'Museo de Monterrey'),
      ]);
      final firstState = VrDemoLibraryState(
        catalog: first,
      ).focusRoute('legacy').moveFocus(VrLibraryDirection.right);
      final secondState = VrDemoLibraryState(catalog: second);

      expect(first.resolveRoute('legacy'), same(first.resolveRoute('museum')));
      expect(second.resolveRoute('legacy'), isNull);
      expect(firstState.focusedId, 'garden');
      expect(secondState.focusedEntry!.title, 'Museo de Monterrey');
      expect(first.entries.first.title, 'Museo de Oaxaca');
      expect(
        () => first.entries.add(_entry('injected')),
        throwsUnsupportedError,
      );
      expect(() => second.routeIds.add('injected'), throwsUnsupportedError);
    },
  );

  test('search, aliases and page navigation use only the injected catalog', () {
    final catalog = VrDemoCatalog([
      for (var i = 0; i < 14; i++)
        _entry(
          'room_$i',
          title: 'Colección $i',
          aliases: ['old_$i'],
          tags: ['arte'],
        ),
    ]);
    final state = VrDemoLibraryState(
      catalog: catalog,
    ).setCategory(VrDemoLibraryCategory.all).goToPage(2);
    expect(state.pageEntries.map((entry) => entry.id), ['room_12', 'room_13']);
    expect(state.focusRoute('old_3').focusedId, 'room_3');
    expect(state.search('coleccion arte 13').focusedId, 'room_13');
    expect(state.search('VRlizate ajedrez').resultCount, 0);
    expect(state.pageIndex, 2, reason: 'Snapshots remain immutable.');
  });

  test('ambiguous host aliases fail at catalog construction', () {
    expect(
      () => VrDemoCatalog([
        _entry('one', aliases: ['shared']),
        _entry('two', aliases: ['shared']),
      ]),
      throwsStateError,
    );
    expect(
      () => VrDemoCatalog([
        _entry('one'),
        _entry('two', aliases: ['one']),
      ]),
      throwsStateError,
    );
  });

  test(
    'an empty host catalog is navigable without inventing an experience',
    () {
      final state = VrDemoLibraryState(catalog: VrDemoCatalog(const []));
      expect(state.pageCount, 0);
      expect(state.focusedEntry, isNull);
      expect(state.moveFocus(VrLibraryDirection.right).focusedId, isNull);
      expect(state.goToPage(500).pageEntries, isEmpty);
      expect(state.search('anything').pageEntries, isEmpty);
    },
  );
}
