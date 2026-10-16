import 'package:flutter/material.dart';

import '../theme/vr_home_theme.dart';

@immutable
class VrHomeCatalogItem {
  VrHomeCatalogItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.accent,
    List<String> tags = const [],
    this.featured = false,
  }) : tags = List<String>.unmodifiable(tags);

  final String id;
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final Color accent;
  final List<String> tags;
  final bool featured;
}

/// Data-driven library UI. The host supplies every item and launches it; no
/// renderers, hardware services or built-in experience lists live here.
class VrHomeCatalog extends StatefulWidget {
  const VrHomeCatalog({
    super.key,
    required this.items,
    required this.onLaunch,
    this.theme = VrHomeThemeData.aurora,
    this.onThemeChanged,
    this.onBack,
    this.backLabel = 'Inicio',
    this.onPairController,
    this.title = 'Explorar',
    this.actions = const [],
  });

  final List<VrHomeCatalogItem> items;
  final Future<void> Function(VrHomeCatalogItem) onLaunch;
  final VrHomeThemeData theme;
  final ValueChanged<VrHomeThemeData>? onThemeChanged;
  final VoidCallback? onBack;
  final String backLabel;
  final VoidCallback? onPairController;
  final String title;
  final List<Widget> actions;

  @override
  State<VrHomeCatalog> createState() => _VrHomeCatalogState();
}

class _VrHomeCatalogState extends State<VrHomeCatalog> {
  final _search = TextEditingController();
  String? _category;
  String? _launchingId;
  VrHomeCatalogItem? _failedItem;

  @override
  void didUpdateWidget(VrHomeCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_category != null &&
        !widget.items.any((item) => item.category == _category)) {
      _category = null;
    }
    if (_failedItem != null &&
        !widget.items.any((item) => item.id == _failedItem!.id)) {
      _failedItem = null;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _launch(VrHomeCatalogItem item) async {
    if (_launchingId != null) return;
    setState(() {
      _launchingId = item.id;
      _failedItem = null;
    });
    try {
      await widget.onLaunch(item);
    } catch (error, stack) {
      debugPrint('VrHomeCatalog: could not launch ${item.id}: $error\n$stack');
      if (mounted) setState(() => _failedItem = item);
    } finally {
      if (mounted) setState(() => _launchingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final categories =
        widget.items
            .map((item) => item.category)
            .where((c) => c.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final words = _normalize(
      _search.text,
    ).trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    final items = widget.items.where((item) {
      if (_category != null && item.category != _category) return false;
      final content = _normalize(
        '${item.title} ${item.subtitle} ${item.category} ${item.tags.join(' ')}',
      );
      return words.every(content.contains);
    }).toList();

    return Theme(
      data: theme.materialTheme,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: theme.gradient,
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, outer) => SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: outer.maxWidth < 500 ? 20 : 32,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.onBack != null ||
                            widget.onPairController != null ||
                            widget.actions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                if (widget.onBack != null)
                                  TextButton.icon(
                                    key: const ValueKey('catalog_back'),
                                    onPressed: widget.onBack,
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    label: Text(widget.backLabel),
                                  ),
                                if (widget.onPairController != null)
                                  OutlinedButton.icon(
                                    key: const ValueKey(
                                      'catalog_pair_controller',
                                    ),
                                    onPressed: _launchingId == null
                                        ? widget.onPairController
                                        : null,
                                    icon: const Icon(
                                      Icons.sports_esports_rounded,
                                    ),
                                    label: const Text('QR Mando'),
                                  ),
                                ...widget.actions,
                              ],
                            ),
                          ),
                        Text(
                          'TU BIBLIOTECA',
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: theme.foreground,
                            fontSize: 38,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Elige un espacio y hazlo tuyo.',
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        if (widget.onThemeChanged != null) ...[
                          const SizedBox(height: 20),
                          VrHomeThemeSelector(
                            theme: theme,
                            onChanged: widget.onThemeChanged!,
                          ),
                        ],
                        const SizedBox(height: 26),
                        TextField(
                          key: const ValueKey('catalog_search'),
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Buscar experiencias',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    key: const ValueKey('catalog_clear_search'),
                                    tooltip: 'Borrar búsqueda',
                                    onPressed: () => setState(_search.clear),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _categoryChip(null, 'Todas'),
                            for (final category in categories)
                              _categoryChip(category, category),
                          ],
                        ),
                        if (_failedItem != null) ...[
                          const SizedBox(height: 20),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const ValueKey('catalog_launch_error'),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: theme.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: theme.secondary),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No pudimos abrir esta experiencia. Inténtalo de nuevo.',
                                    style: TextStyle(
                                      color: theme.foreground,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    key: const ValueKey('catalog_retry_launch'),
                                    onPressed: _launchingId == null
                                        ? () => _launch(_failedItem!)
                                        : null,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Reintentar'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          '${items.length} ${items.length == 1 ? 'experiencia' : 'experiencias'}',
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (items.isEmpty)
                          _emptyState()
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final minimum =
                                  MediaQuery.textScalerOf(context).scale(1) >
                                      1.4
                                  ? 420.0
                                  : 285.0;
                              final columns =
                                  ((constraints.maxWidth + 16) / (minimum + 16))
                                      .floor()
                                      .clamp(1, 3);
                              final width =
                                  (constraints.maxWidth - (columns - 1) * 16) /
                                  columns;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  for (final item in items)
                                    SizedBox(
                                      width: width,
                                      child: _itemCard(item),
                                    ),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(String? category, String label) {
    final theme = widget.theme;
    final selected = _category == category;
    return ChoiceChip(
      key: ValueKey(
        category == null
            ? 'catalog_category_all'
            : 'catalog_category_$category',
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      backgroundColor: theme.surface,
      selectedColor: theme.accent.withValues(alpha: 0.16),
      labelStyle: TextStyle(color: theme.foreground),
      side: BorderSide(color: selected ? theme.accent : theme.border),
      onSelected: (_) => setState(() => _category = category),
    );
  }

  Widget _emptyState() => Container(
    key: const ValueKey('catalog_empty'),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    decoration: BoxDecoration(
      color: widget.theme.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: widget.theme.border),
    ),
    child: Column(
      children: [
        Icon(Icons.explore_off_outlined, color: widget.theme.muted, size: 36),
        const SizedBox(height: 16),
        Text(
          'No hay experiencias aquí todavía',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.theme.foreground,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _search.text.isNotEmpty || _category != null
              ? 'Prueba otra búsqueda o elige otra categoría.'
              : 'Vuelve cuando haya nuevos espacios para explorar.',
          textAlign: TextAlign.center,
          style: TextStyle(color: widget.theme.muted, height: 1.5),
        ),
        if (_search.text.isNotEmpty || _category != null) ...[
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => setState(() {
              _search.clear();
              _category = null;
            }),
            child: const Text('Ver todas'),
          ),
        ],
      ],
    ),
  );

  Widget _itemCard(VrHomeCatalogItem item) {
    final theme = widget.theme;
    final busy = _launchingId == item.id;
    return Semantics(
      button: true,
      enabled: _launchingId == null,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: theme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('catalog_item_${item.id}'),
          onTap: _launchingId == null ? () => _launch(item) : null,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: item.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(item.icon, color: item.accent, size: 32),
                    ),
                    if (item.featured)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Destacado',
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  item.category,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  item.title,
                  style: TextStyle(
                    color: theme.foreground,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in item.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: theme.border),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(color: theme.muted, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        busy ? 'Abriendo…' : 'Entrar',
                        style: TextStyle(
                          color: theme.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (busy)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.accent,
                        ),
                      )
                    else
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 21,
                        color: theme.accent,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _normalize(String value) {
  var normalized = value.toLowerCase();
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  for (final entry in accents.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}
