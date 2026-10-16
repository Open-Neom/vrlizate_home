/// Render-independent inventory and navigation for the spatial app library.
/// Lists are created only on catalog/filter/page changes, never on frame reads.
enum VrDemoLibraryCategory { featured, games, productivity, learn, lab, all }

extension VrDemoLibraryCategoryLabel on VrDemoLibraryCategory {
  String get label => switch (this) {
    VrDemoLibraryCategory.featured => 'Destacados',
    VrDemoLibraryCategory.games => 'Juegos',
    VrDemoLibraryCategory.productivity => 'Productividad',
    VrDemoLibraryCategory.learn => 'Aprender',
    VrDemoLibraryCategory.lab => 'Laboratorio',
    VrDemoLibraryCategory.all => 'Todo',
  };
}

enum VrDemoLibraryStatus { playable, prototype, simulated }

extension VrDemoLibraryStatusLabel on VrDemoLibraryStatus {
  String get label => switch (this) {
    VrDemoLibraryStatus.playable => 'Demo interactiva',
    VrDemoLibraryStatus.prototype => 'Prototipo',
    VrDemoLibraryStatus.simulated => 'Simulado',
  };
}

class VrDemoLibraryEntry {
  const VrDemoLibraryEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.accent,
    required this.icon,
    this.status = VrDemoLibraryStatus.playable,
    this.featured = false,
    this.aliases = const [],
    this.tags = const [],
  });

  /// Canonical launch route. Aliases resolve here without duplicate cards.
  final String id;
  final String title;
  final String subtitle;

  /// Primary category; featured is a collection, not a duplicate entry.
  final VrDemoLibraryCategory category;

  /// ARGB color and renderer-neutral icon name (not a Flutter/GPU dependency).
  final int accent;
  final String icon;
  final VrDemoLibraryStatus status;
  final bool featured;
  final List<String> aliases;
  final List<String> tags;
}

class VrDemoCatalog {
  static const columns = 3;
  static const rows = 2;
  static const pageSize = columns * rows;

  /// Stable curated order. Changing category/search never re-sorts by locale,
  /// recent activity, launch count or frame timing.
  final List<VrDemoLibraryEntry> entries;

  VrDemoCatalog(Iterable<VrDemoLibraryEntry> entries)
    : entries = List<VrDemoLibraryEntry>.unmodifiable(entries) {
    _byRoute = _indexRoutes();
    routeIds = Set<String>.unmodifiable(_byRoute.keys);
    _searchText = Map<String, String>.unmodifiable({
      for (final entry in this.entries)
        entry.id: _normalize(
          '${entry.id} ${entry.title} ${entry.subtitle} '
          '${entry.category.label} ${entry.status.label} '
          '${entry.aliases.join(' ')} ${entry.tags.join(' ')}',
        ),
    });
  }

  late final Map<String, VrDemoLibraryEntry> _byRoute;
  late final Set<String> routeIds;
  late final Map<String, String> _searchText;

  Map<String, VrDemoLibraryEntry> _indexRoutes() {
    final result = <String, VrDemoLibraryEntry>{};
    for (final entry in entries) {
      for (final route in [entry.id, ...entry.aliases]) {
        if (result.containsKey(route)) {
          throw StateError('Duplicate library route: $route');
        }
        result[route] = entry;
      }
    }
    return Map.unmodifiable(result);
  }

  VrDemoLibraryEntry? resolveRoute(String routeId) => _byRoute[routeId];

  List<VrDemoLibraryEntry> _filter(
    VrDemoLibraryCategory category,
    String query,
  ) {
    final normalized = _normalize(query);
    final terms = normalized.isEmpty ? const <String>[] : normalized.split(' ');
    return List.unmodifiable(
      entries.where((entry) {
        final matchesCategory =
            category == VrDemoLibraryCategory.all ||
            (category == VrDemoLibraryCategory.featured
                ? entry.featured
                : entry.category == category);
        return matchesCategory && terms.every(_searchText[entry.id]!.contains);
      }),
    );
  }

  static String _normalize(String value) {
    var result = value.toLowerCase();
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
    };
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}

enum VrLibraryDirection { left, right, up, down }

/// Immutable view snapshot. Keep this object between frames and replace it
/// only in response to search, tab, page or focus input.
class VrDemoLibraryState {
  final VrDemoCatalog catalog;
  final VrDemoLibraryCategory category;
  final String query;
  final int pageIndex;
  final String? focusedId;
  final List<VrDemoLibraryEntry> filteredEntries;
  final List<VrDemoLibraryEntry> pageEntries;

  factory VrDemoLibraryState({
    required VrDemoCatalog catalog,
    VrDemoLibraryCategory category = VrDemoLibraryCategory.featured,
    String query = '',
    int pageIndex = 0,
    String? focusedId,
  }) {
    final text = query.trim();
    return VrDemoLibraryState._page(
      catalog,
      category,
      text,
      catalog._filter(category, text),
      pageIndex,
      focusedId,
    );
  }

  const VrDemoLibraryState._(
    this.catalog,
    this.category,
    this.query,
    this.pageIndex,
    this.focusedId,
    this.filteredEntries,
    this.pageEntries,
  );

  static VrDemoLibraryState _page(
    VrDemoCatalog catalog,
    VrDemoLibraryCategory category,
    String query,
    List<VrDemoLibraryEntry> filtered,
    int page,
    String? focus,
  ) {
    final count =
        (filtered.length + VrDemoCatalog.pageSize - 1) ~/
        VrDemoCatalog.pageSize;
    final index = count == 0 ? 0 : page.clamp(0, count - 1);
    final start = index * VrDemoCatalog.pageSize;
    final end = (start + VrDemoCatalog.pageSize).clamp(0, filtered.length);
    final visible = List<VrDemoLibraryEntry>.unmodifiable(
      filtered.getRange(start, end),
    );
    final canonicalFocus = focus == null
        ? null
        : catalog.resolveRoute(focus)?.id;
    final focused = visible.any((entry) => entry.id == canonicalFocus)
        ? canonicalFocus
        : visible.firstOrNull?.id;
    return VrDemoLibraryState._(
      catalog,
      category,
      query,
      index,
      focused,
      filtered,
      visible,
    );
  }

  int get pageCount =>
      (filteredEntries.length + VrDemoCatalog.pageSize - 1) ~/
      VrDemoCatalog.pageSize;
  int get resultCount => filteredEntries.length;
  bool get hasPreviousPage => pageIndex > 0;
  bool get hasNextPage => pageIndex + 1 < pageCount;
  VrDemoLibraryEntry? get focusedEntry =>
      focusedId == null ? null : catalog.resolveRoute(focusedId!);

  VrDemoLibraryState setCategory(VrDemoLibraryCategory value) =>
      value == category
      ? this
      : VrDemoLibraryState(catalog: catalog, category: value, query: query);

  VrDemoLibraryState search(String value) => value.trim() == query
      ? this
      : VrDemoLibraryState(catalog: catalog, category: category, query: value);

  VrDemoLibraryState goToPage(int value) {
    final index = pageCount == 0 ? 0 : value.clamp(0, pageCount - 1);
    if (index == pageIndex) return this;
    return VrDemoLibraryState._page(
      catalog,
      category,
      query,
      filteredEntries,
      index,
      null,
    );
  }

  /// Canonical route identity survives aliases, search result indices and pages.
  /// A route excluded by the current filter does not silently change the filter.
  VrDemoLibraryState focusRoute(String routeId) {
    final entry = catalog.resolveRoute(routeId);
    if (entry == null || entry.id == focusedId) return this;
    final index = filteredEntries.indexOf(entry);
    if (index < 0) return this;
    if (index ~/ VrDemoCatalog.pageSize == pageIndex) {
      return VrDemoLibraryState._(
        catalog,
        category,
        query,
        pageIndex,
        entry.id,
        filteredEntries,
        pageEntries,
      );
    }
    return VrDemoLibraryState._page(
      catalog,
      category,
      query,
      filteredEntries,
      index ~/ VrDemoCatalog.pageSize,
      entry.id,
    );
  }

  /// Left/right follow reading order; up/down preserve the three-column grid.
  /// Crossing a six-card boundary changes page. Ends do not wrap to the start.
  VrDemoLibraryState moveFocus(VrLibraryDirection direction) {
    if (filteredEntries.isEmpty) return this;
    final current = filteredEntries.indexOf(focusedEntry!);
    final delta = switch (direction) {
      VrLibraryDirection.left => -1,
      VrLibraryDirection.right => 1,
      VrLibraryDirection.up => -VrDemoCatalog.columns,
      VrLibraryDirection.down => VrDemoCatalog.columns,
    };
    final target = current + delta;
    if (target < 0 || target >= filteredEntries.length) return this;
    return focusRoute(filteredEntries[target].id);
  }
}

/// One D-pad/analog step per neutral-to-deflected gesture; no frame repeats.
/// Input Y is positive upwards. Exact diagonals prefer the horizontal axis.
class VrDpadLatch {
  final double activationThreshold;
  final double neutralThreshold;
  bool _latched = false;

  VrDpadLatch({this.activationThreshold = 0.6, this.neutralThreshold = 0.25}) {
    if (!activationThreshold.isFinite ||
        !neutralThreshold.isFinite ||
        activationThreshold <= 0 ||
        activationThreshold > 1 ||
        neutralThreshold < 0 ||
        neutralThreshold >= activationThreshold) {
      throw ArgumentError('D-pad requires 0 <= neutral < activation <= 1.');
    }
  }

  bool get isLatched => _latched;
  void reset() => _latched = false;

  VrLibraryDirection? update(double x, double y) {
    if (!x.isFinite || !y.isFinite) return null;
    if (x.abs() <= neutralThreshold && y.abs() <= neutralThreshold) {
      reset();
      return null;
    }
    if (_latched ||
        (x.abs() < activationThreshold && y.abs() < activationThreshold)) {
      return null;
    }
    _latched = true;
    if (x.abs() >= y.abs()) {
      return x < 0 ? VrLibraryDirection.left : VrLibraryDirection.right;
    }
    return y < 0 ? VrLibraryDirection.down : VrLibraryDirection.up;
  }
}
