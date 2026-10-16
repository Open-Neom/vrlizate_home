import 'package:flutter/material.dart';

import '../theme/vr_home_theme.dart';

/// Presentation metadata supplied by the host, independent of package formats.
@immutable
class VrHomePackageItem {
  const VrHomePackageItem({
    required this.id,
    required this.title,
    required this.description,
    required this.typeLabel,
    this.unavailableReason,
  });

  final String id;
  final String title;
  final String description;
  final String typeLabel;
  final String? unavailableReason;
}

/// Package-library UI only: the host owns discovery, network, validation,
/// platform availability, clipboard access and experience navigation.
///
/// Supply unavailable reasons for entries that cannot be opened, including an
/// incomplete or ambiguous directory scan. Mounting this widget has no I/O or
/// lifecycle side effects. Its local launch guard only prevents duplicate taps
/// while the host's asynchronous callback is running.
class VrHomePackageLibrary extends StatefulWidget {
  const VrHomePackageLibrary({
    super.key,
    required this.items,
    required this.location,
    required this.onLaunch,
    this.issues = const [],
    this.loading = false,
    this.busy = false,
    this.error,
    this.theme = VrHomeThemeData.aurora,
    this.onRefresh,
    this.onImport,
    this.onInstallExamples,
    this.onCopyLocation,
    this.onUseLocal,
  });

  final List<VrHomePackageItem> items;
  final String location;
  final List<String> issues;
  final bool loading;
  final bool busy;
  final String? error;
  final VrHomeThemeData theme;
  final Future<void> Function(String id) onLaunch;
  final VoidCallback? onRefresh;
  final VoidCallback? onImport;
  final VoidCallback? onInstallExamples;
  final VoidCallback? onCopyLocation;
  final VoidCallback? onUseLocal;

  @override
  State<VrHomePackageLibrary> createState() => _VrHomePackageLibraryState();
}

class _VrHomePackageLibraryState extends State<VrHomePackageLibrary> {
  String? _launchingId;
  String? _launchError;

  bool get _blocked => widget.loading || widget.busy || _launchingId != null;

  @override
  void didUpdateWidget(VrHomePackageLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !oldWidget.loading) _launchError = null;
  }

  Future<void> _launch(VrHomePackageItem item) async {
    if (_blocked || item.unavailableReason != null) return;
    setState(() {
      _launchingId = item.id;
      _launchError = null;
    });
    try {
      await widget.onLaunch(item.id);
    } catch (error, stack) {
      // Hosts normally report operation errors through widget.error. Preserve
      // a retryable UI even if a callback unexpectedly propagates a failure.
      debugPrint(
        'VrHomePackageLibrary: could not open ${item.id}: $error\n$stack',
      );
      if (mounted) {
        setState(
          () => _launchError =
              'No se pudo abrir ${item.title}. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _launchingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final error = widget.error ?? _launchError;
    return Theme(
      data: theme.materialTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Biblioteca .vrlz',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            key: const ValueKey('home_package_scroll'),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tus paquetes',
                      style: TextStyle(
                        color: theme.foreground,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Las escenas portátiles incluyen su contenido 3D. '
                      'Las demos integradas usan una experiencia de la aplicación instalada.',
                      style: TextStyle(color: theme.muted, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Ubicación',
                              style: TextStyle(color: theme.muted),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.location.isEmpty
                                  ? 'Sin ubicación disponible'
                                  : widget.location,
                              key: const ValueKey('home_package_location'),
                              style: TextStyle(
                                color: theme.foreground,
                                fontSize: 13,
                              ),
                            ),
                            if (widget.onCopyLocation != null) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: const ValueKey('home_package_copy'),
                                  onPressed: _blocked || widget.location.isEmpty
                                      ? null
                                      : widget.onCopyLocation,
                                  icon: const Icon(Icons.copy_outlined),
                                  label: const Text('Copiar ubicación'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (widget.onUseLocal != null)
                          OutlinedButton.icon(
                            key: const ValueKey('home_package_local'),
                            onPressed: _blocked ? null : widget.onUseLocal,
                            icon: const Icon(Icons.folder_outlined),
                            label: const Text('Usar carpeta local'),
                          ),
                        if (widget.onRefresh != null)
                          OutlinedButton.icon(
                            key: const ValueKey('home_package_refresh'),
                            onPressed: _blocked ? null : widget.onRefresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Actualizar'),
                          ),
                        if (widget.onImport != null)
                          FilledButton.icon(
                            key: const ValueKey('home_package_import'),
                            onPressed: _blocked ? null : widget.onImport,
                            icon: const Icon(Icons.add_link),
                            label: const Text('Añadir desde HTTPS'),
                          ),
                        if (widget.onInstallExamples != null)
                          OutlinedButton.icon(
                            key: const ValueKey('home_package_examples'),
                            onPressed: _blocked
                                ? null
                                : widget.onInstallExamples,
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Añadir ejemplos'),
                          ),
                      ],
                    ),
                    if (widget.loading || widget.busy) ...[
                      const SizedBox(height: 20),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          widget.loading
                              ? 'Actualizando biblioteca…'
                              : 'Procesando…',
                          style: TextStyle(color: theme.muted),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 20),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          key: const ValueKey('home_package_error'),
                          style: TextStyle(
                            color: theme.materialTheme.colorScheme.error,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    if (widget.issues.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Avisos de la biblioteca',
                        style: TextStyle(
                          color: theme.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      for (final issue in widget.issues)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            issue,
                            style: TextStyle(color: theme.muted, height: 1.5),
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    if (widget.items.isEmpty && !widget.loading)
                      Text(
                        'No hay paquetes para mostrar. Añade un paquete o actualiza la biblioteca.',
                        key: const ValueKey('home_package_empty'),
                        style: TextStyle(color: theme.muted, height: 1.5),
                      ),
                    for (final item in widget.items) _itemCard(item),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(VrHomePackageItem item) {
    final theme = widget.theme;
    final opening = _launchingId == item.id;
    final reason = item.unavailableReason;
    return Padding(
      key: ValueKey('home_package_item_${item.id}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    child: Text(
                      item.typeLabel,
                      style: TextStyle(color: theme.accent, fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                style: TextStyle(
                  color: theme.foreground,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.description,
                  style: TextStyle(color: theme.muted, height: 1.5),
                ),
              ],
              const SizedBox(height: 8),
              Text(item.id, style: TextStyle(color: theme.muted, fontSize: 12)),
              if (reason != null) ...[
                const SizedBox(height: 12),
                Text(
                  reason.isEmpty ? 'No disponible en esta aplicación.' : reason,
                  key: ValueKey('home_package_unavailable_${item.id}'),
                  style: TextStyle(color: theme.muted, height: 1.5),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: ValueKey('home_package_open_${item.id}'),
                  onPressed: _blocked || reason != null
                      ? null
                      : () => _launch(item),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(opening ? 'Abriendo…' : 'Abrir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
