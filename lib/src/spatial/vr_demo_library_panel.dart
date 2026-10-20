import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../theme/vr_home_theme.dart';
import 'vr_demo_library_model.dart';
import 'home_spatial_metrics.dart';

/// Injectable geometry/texture creation; CPU tests explicitly use meshless nodes.
typedef VrLibraryBoxBuilder =
    Node Function(double w, double h, double d, Color color);
typedef VrLibrarySurfaceBuilder =
    Future<Node> Function(VrLibraryArtwork artwork, double w, double h);

/// A small immutable description of a UI surface, not a screenshot of a game.
class VrLibraryArtwork {
  const VrLibraryArtwork({
    required this.title,
    this.subtitle = '',
    this.badge = '',
    this.accent = const Color(0xFF77DDD1),
    this.icon,
    this.cover = false,
    this.disabled = false,
    this.theme = VrHomeThemeData.aurora,
  });
  final String title, subtitle, badge;
  final Color accent;
  final IconData? icon;
  final bool cover;
  final bool disabled;
  final VrHomeThemeData theme;

  /// Rasterize only the UI surface. Geometry, depth and interaction remain 3D.
  Future<VrTextBitmap> rasterize({double? aspectRatio}) async {
    const width = 640;
    // Match the physical plane, so short tabs are not horizontally compressed
    // and the wide title is not stretched. Keep uploads bounded.
    final height = cover
        ? 424
        : aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0
        ? (width / aspectRatio).round().clamp(80, 320)
        : (subtitle.isEmpty ? 112 : 160);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(24)),
      Paint()..color = theme.surface,
    );
    if (cover) {
      final art = const Rect.fromLTWH(0, 0, 640, 232);
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(24)),
      );
      canvas.drawRect(
        art,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .7),
              theme.secondary.withValues(alpha: .24),
            ],
          ).createShader(art),
      );
      // Abstract cover artwork, deliberately not presented as an in-game capture.
      for (var i = 0; i < 5; i++) {
        canvas.drawCircle(
          Offset(550 + i * 22.0, 30),
          120 + i * 48.0,
          Paint()
            ..color = Colors.white.withValues(alpha: .06)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      _text(
        canvas,
        String.fromCharCode((icon ?? Icons.view_in_ar_rounded).codePoint),
        const Offset(36, 54),
        94,
        fontFamily: (icon ?? Icons.view_in_ar_rounded).fontFamily,
        width: 170,
      );
      _text(
        canvas,
        badge.toUpperCase(),
        const Offset(38, 187),
        20,
        color: Colors.white.withValues(alpha: .9),
        width: 560,
      );
      _text(
        canvas,
        title,
        const Offset(30, 251),
        43,
        width: 580,
        color: theme.foreground,
        weight: FontWeight.w700,
      );
      _text(
        canvas,
        subtitle,
        const Offset(30, 315),
        29,
        width: 580,
        color: theme.muted,
        lines: 2,
      );
    } else {
      final leading = icon == null ? 24.0 : height * .82;
      if (icon != null) {
        _text(
          canvas,
          String.fromCharCode(icon!.codePoint),
          Offset(24, height * .24),
          height * .45,
          fontFamily: icon!.fontFamily,
          width: height * .6,
          color: accent,
        );
      }
      _text(
        canvas,
        title,
        Offset(leading, height * (subtitle.isEmpty ? .25 : .08)),
        height * .4,
        width: 615 - leading,
        weight: FontWeight.w600,
        color: disabled ? theme.muted.withValues(alpha: .6) : theme.foreground,
      );
      if (subtitle.isNotEmpty) {
        _text(
          canvas,
          subtitle,
          Offset(leading, height * .62),
          height * .25,
          width: 615 - leading,
          color: theme.muted,
        );
      }
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) {
          throw StateError('Library surface could not be rasterized.');
        }
        return VrTextBitmap(data.buffer.asUint8List(), width, height);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  static void _text(
    Canvas canvas,
    String text,
    Offset at,
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w500,
    String? fontFamily,
    required double width,
    int lines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          height: 1.15,
          color: color,
          fontWeight: weight,
          fontFamily: fontFamily ?? 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, at);
    painter.dispose();
  }
}

/// Library window + dock. Its transform changes only on explicit repositioning.
/// Six cards per page; no orbiting game objects and no head-following UI.
class VrDemoLibraryPanel {
  VrDemoLibraryPanel._(
    this._boxBuilder,
    this._surfaceBuilder,
    this.onOpen,
    this.onAction,
    VrDemoCatalog catalog,
    this.theme,
    this.dockActions,
    VrDemoLibraryState? initialState,
  ) : state = initialState ?? VrDemoLibraryState(catalog: catalog) {
    root.localTransform = vm.Matrix4.translationValues(
      0,
      1.67,
      -HomeSpatialMetrics.libraryDistance,
    )..scaleByVector3(vm.Vector3.all(worldScale));
    _addBox(root, 3.94, 2.42, .065, theme.background, 0, 0, -.05);
    _addBox(root, 3.50, .28, .055, theme.background, 0, -1.49, -.03);
  }

  static const width = 3.94, height = 2.42;
  // Leave optical-inset margin in both eyes at a 19.5:9 landscape viewport,
  // default 60° vertical FOV. Custom lens calibration may change visibility.
  static const worldScale = .88;
  final VrHomeThemeData theme;
  final List<(String, String)> dockActions;
  final Node root = Node(name: 'vr_library_root')..raycastable = false;
  final VrLibraryBoxBuilder _boxBuilder;
  final VrLibrarySurfaceBuilder _surfaceBuilder;
  final void Function(VrDemoLibraryEntry entry) onOpen;
  final void Function(String action) onAction;
  VrDemoLibraryState state;
  final Map<Node, VoidCallback> _actions = Map.identity();
  final Map<Node, String> _routes = Map.identity();
  final Map<String, Node> _highlights = {};
  final List<Node> _content = [];
  VoidCallback? _clearSurfaceCache;
  int _revision = 0;
  bool _disposed = false, _busy = false;
  String? _hoveredRoute;
  VoidCallback? _hoveredAction;

  bool get busy => _busy;
  String? get hoveredRoute => _hoveredRoute;
  vm.Vector3 get worldPosition => root.localTransform.getTranslation();
  bool owns(Node node) =>
      !_disposed && !busy && root.visible && _actions.containsKey(node);
  String? routeFor(Node node) => _routes[node];

  static Future<VrDemoLibraryPanel> create({
    required VrDemoCatalog catalog,
    VrHomeThemeData theme = VrHomeThemeData.aurora,
    VrDemoLibraryState? initialState,
    List<(String, String)> dockActions = const [
      ('library', 'Biblioteca'),
      ('place', 'Colocar'),
    ],
    required void Function(VrDemoLibraryEntry) onOpen,
    required void Function(String) onAction,
    VrLibraryBoxBuilder? boxBuilder,
    VrLibrarySurfaceBuilder? surfaceBuilder,
  }) async {
    if (initialState != null && !identical(initialState.catalog, catalog)) {
      throw ArgumentError('Library state belongs to a different catalog.');
    }
    // Cache GPU surfaces per window, bounded across pagination; a cache hit
    // creates a lightweight node sharing geometry/material, not another upload.
    final cache = <Object, Mesh>{};
    var cacheActive = true;
    Future<Node> cachedSurface(VrLibraryArtwork art, double w, double h) async {
      final key = (
        art.title,
        art.subtitle,
        art.badge,
        art.accent,
        art.icon,
        art.cover,
        art.disabled,
        art.theme,
        w,
        h,
      );
      final cached = cache.remove(key);
      if (cached != null) {
        cache[key] = cached;
        return Node(mesh: cached);
      }
      final node = await _surface(art, w, h);
      if (cacheActive) {
        if (cache.length >= 32) cache.remove(cache.keys.first);
        cache[key] = node.mesh!;
      }
      return node;
    }

    final panel = VrDemoLibraryPanel._(
      boxBuilder ?? _box,
      surfaceBuilder ?? cachedSurface,
      onOpen,
      onAction,
      catalog,
      theme,
      List.unmodifiable(dockActions),
      initialState,
    );
    panel._clearSurfaceCache = () {
      cacheActive = false;
      cache.clear();
    };
    await panel.refresh();
    return panel;
  }

  static Node _box(double w, double h, double d, Color color) {
    double linear(double channel) => channel <= .04045
        ? channel / 12.92
        : math.pow((channel + .055) / 1.055, 2.4).toDouble();
    final material = UnlitMaterial()
      ..vertexColorWeight = 0
      ..baseColorFactor = vm.Vector4(
        linear(color.r),
        linear(color.g),
        linear(color.b),
        1,
      );
    return Node(mesh: Mesh(CuboidGeometry(vm.Vector3(w, h, d)), material));
  }

  static Future<Node> _surface(VrLibraryArtwork art, double w, double h) async {
    final bitmap = await art.rasterize(aspectRatio: w / h);
    final texture = Texture2D.fromPixels(
      bitmap.pixels,
      bitmap.width,
      bitmap.height,
      sampling: const TextureSampling(mipmaps: true),
    );
    final material = UnlitMaterial(colorTexture: texture)
      ..alphaMode = AlphaMode.blend
      ..vertexColorWeight = 0;
    return Node(
      mesh: Mesh(PlaneGeometry(width: w, depth: h), material),
    );
  }

  Node _addBox(
    Node parent,
    double w,
    double h,
    double d,
    Color color,
    double x,
    double y,
    double z,
  ) {
    final node = _boxBuilder(w, h, d, color)
      ..raycastable = false
      ..localTransform = vm.Matrix4.translationValues(-x, y, z);
    parent.add(node);
    return node;
  }

  /// Screen-right is -X in this renderer. Do not mirror the camera or eye order.
  static vm.Matrix4 surfaceTransform(double screenX, double y, double z) =>
      vm.Matrix4.translationValues(-screenX, y, z)
        ..rotateX(math.pi / 2)
        ..scaleByVector3(vm.Vector3(-1, 1, 1));

  Future<void> refresh() async {
    if (_disposed) return;
    final revision = ++_revision;
    _busy = true;
    _hoveredAction = null;
    _hoveredRoute = null;
    final content = <Node>[];
    final actions = <Node, VoidCallback>{};
    final routes = <Node, String>{};
    final highlights = <String, Node>{};
    Future<void> tile(
      String id,
      VrLibraryArtwork art,
      double x,
      double y,
      double w,
      double h,
      VoidCallback? action, {
      String? route,
      bool selected = false,
    }) async {
      final group = Node(name: 'library_$id')..raycastable = false;
      final border = _addBox(
        group,
        w + .025,
        h + .025,
        .02,
        theme.accent,
        x,
        y,
        -.005,
      )..visible = selected;
      if (route != null) highlights[route] = border;
      final surface = await _surfaceBuilder(art, w, h);
      surface.name = 'library_$id';
      surface.localTransform = surfaceTransform(x, y, .018);
      surface.raycastable = action != null;
      group.add(surface);
      if (action != null) actions[surface] = action;
      if (route != null) routes[surface] = route;
      content.add(group);
    }

    // One sequential upload queue, not dozens of competing toImage operations.
    try {
      await tile(
        'title',
        VrLibraryArtwork(
          theme: theme,
          title: 'VRlizate  /  Biblioteca',
          subtitle:
              '${state.filteredEntries.length} experiencias · ${state.category.label}',
        ),
        -.72,
        .97,
        2.22,
        .29,
        null,
      );
      await tile(
        'hint',
        VrLibraryArtwork(theme: theme, title: 'Mira · Selecciona · Explora'),
        1.18,
        .97,
        1.20,
        .22,
        null,
      );
      for (var i = 0; i < VrDemoLibraryCategory.values.length; i++) {
        final category = VrDemoLibraryCategory.values[i];
        await tile(
          'category_${category.name}',
          VrLibraryArtwork(theme: theme, title: category.label),
          -1.50,
          .55 - i * .255,
          .65,
          .19,
          () => setCategory(category),
          selected: state.category == category,
        );
      }
      for (var i = 0; i < state.pageEntries.length; i++) {
        final entry = state.pageEntries[i];
        await tile(
          'demo_${entry.id}',
          VrLibraryArtwork(
            theme: theme,
            title: entry.title,
            subtitle: entry.subtitle,
            badge: entry.status.label,
            accent: Color(entry.accent),
            icon: _icon(entry.icon),
            cover: true,
          ),
          -.57 + (i % 3) * .98,
          .37 - (i ~/ 3) * .78,
          .91,
          .63,
          () => onOpen(entry),
          route: entry.id,
          selected: entry.id == state.focusedId,
        );
      }
      await tile(
        'previous',
        VrLibraryArtwork(
          theme: theme,
          title: '‹  Anterior',
          disabled: !state.hasPreviousPage,
        ),
        -.44,
        -.99,
        .83,
        .17,
        state.hasPreviousPage ? () => goToPage(state.pageIndex - 1) : null,
      );
      await tile(
        'page',
        VrLibraryArtwork(
          theme: theme,
          title:
              '${state.pageCount == 0 ? 0 : state.pageIndex + 1} / ${state.pageCount}',
        ),
        .54,
        -.99,
        .52,
        .17,
        null,
      );
      await tile(
        'next',
        VrLibraryArtwork(
          theme: theme,
          title: 'Siguiente  ›',
          disabled: !state.hasNextPage,
        ),
        1.39,
        -.99,
        .83,
        .17,
        state.hasNextPage ? () => goToPage(state.pageIndex + 1) : null,
      );
      final dock = dockActions;
      for (var i = 0; i < dock.length; i++) {
        final (id, label) = dock[i];
        await tile(
          'dock_$id',
          VrLibraryArtwork(theme: theme, title: label),
          -(dock.length - 1) * .345 + i * .69,
          -1.49,
          .63,
          .20,
          () => id == 'library'
              ? setCategory(VrDemoLibraryCategory.featured)
              : onAction(id),
        );
      }
      if (_disposed || revision != _revision) return;
      for (final node in _content) {
        root.remove(node);
      }
      _content
        ..clear()
        ..addAll(content);
      _actions
        ..clear()
        ..addAll(actions);
      _routes
        ..clear()
        ..addAll(routes);
      _highlights
        ..clear()
        ..addAll(highlights);
      for (final node in content) {
        root.add(node);
      }
    } finally {
      if (revision == _revision) _busy = false;
    }
  }

  Future<void> setCategory(VrDemoLibraryCategory category) async {
    if (_disposed) return;
    final next = state.setCategory(category);
    if (identical(next, state)) return;
    state = next;
    await refresh();
  }

  Future<void> goToPage(int page) async {
    if (_disposed) return;
    final next = state.goToPage(page);
    if (identical(next, state)) return;
    state = next;
    await refresh();
  }

  Future<void> moveFocus(VrLibraryDirection direction) async {
    if (_disposed || !root.visible || busy) return;
    final before = state.pageIndex;
    state = state.moveFocus(direction);
    _hoveredAction = null;
    _hoveredRoute = null;
    if (before != state.pageIndex) {
      await refresh();
    } else {
      _updateHighlight();
    }
  }

  void hover(Node? node) {
    if (_disposed || !root.visible || busy) return;
    _hoveredAction = _actions[node];
    _hoveredRoute = _routes[node];
    if (_hoveredRoute != null) state = state.focusRoute(_hoveredRoute!);
    _updateHighlight();
  }

  void _updateHighlight() {
    for (final entry in _highlights.entries) {
      entry.value.visible = entry.key == state.focusedId;
    }
  }

  void select(Node node) {
    if (owns(node)) _actions[node]?.call();
  }

  void activateFocused() {
    if (_disposed || busy || !root.visible) return;
    if (_hoveredAction != null) {
      _hoveredAction!();
      return;
    }
    final entry = state.catalog.resolveRoute(state.focusedId ?? '');
    if (entry != null) onOpen(entry);
  }

  /// Explicit one-shot placement only, never called from a frame tick.
  void place(VrWorldPose pose) {
    root.localTransform = pose.transformAt(vm.Vector3.zero())
      ..scaleByVector3(vm.Vector3.all(worldScale));
  }

  void dispose() {
    _disposed = true;
    root.visible = false;
    _hoveredAction = null;
    _hoveredRoute = null;
    _revision++;
    _actions.clear();
    _routes.clear();
    _highlights.clear();
    root.children.toList().forEach(root.remove);
    _content.clear();
    _clearSurfaceCache?.call();
  }

  static IconData _icon(String id) => switch (id) {
    'motorsport' => Icons.sports_motorsports_rounded,
    'flame' => Icons.local_fire_department_rounded,
    'shield' => Icons.shield_rounded,
    'kanban' => Icons.view_kanban_rounded,
    'note' => Icons.note_alt_rounded,
    'keyboard' => Icons.gesture_rounded,
    'chart' => Icons.bar_chart_rounded,
    'tune' => Icons.tune_rounded,
    'cinema' => Icons.movie_rounded,
    'museum' => Icons.museum_rounded,
    'landscape' => Icons.landscape_rounded,
    'chess' => Icons.extension_rounded,
    'rocket' => Icons.rocket_launch_rounded,
    'castle' => Icons.castle_rounded,
    'diamond' => Icons.diamond_rounded,
    _ => Icons.view_in_ar_rounded,
  };
}
