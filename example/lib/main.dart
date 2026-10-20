import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vrlizate/vrlizate.dart'
    show VrSessionHost, VrWidgetSessionAdapter;
import 'package:vrlizate_apps/vrlizate_apps.dart';
import 'package:vrlizate_apps/vrlizate_apps_io.dart';
import 'package:vrlizate_apps/vrlizate_apps_library.dart';
import 'package:vrlizate_apps/vrlizate_apps_viewer.dart';
import 'package:vrlizate_home/vrlizate_home.dart';
import 'package:vrlizate_home/vrlizate_home_spatial.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HomeExample());
}

Future<VrlzPackage> _gardensPackage() async {
  final data = await rootBundle.load('assets/connected_gardens.vrlz');
  return VrlzPackage.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

Future<void> _openGardens(
  BuildContext context, {
  Widget Function(VrlzWorldBundle)? worldBuilder,
}) async {
  final package = await _gardensPackage();
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/experience/connected-gardens'),
      builder: (_) => _WorldSession(
        bundle: package.worldBundle!,
        worldBuilder: worldBuilder,
      ),
    ),
  );
}

Future<VrlzPackage> _galleryPackage() async {
  final data = await rootBundle.load('assets/stereo_gallery.vrlz');
  return VrlzPackage.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

Future<void> _openGallery(
  BuildContext context, {
  Widget Function(VrzBundle bundle)? sceneBuilder,
}) async {
  final package = await _galleryPackage();
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/experience/gallery'),
      builder: (_) => _SceneSession(
        bundle: package.sceneBundle!,
        sceneBuilder: sceneBuilder,
      ),
    ),
  );
}

/// The host composes Home presentation with Apps data and runtime APIs.
class HomeExample extends StatefulWidget {
  const HomeExample({super.key, this.sceneBuilder, this.worldBuilder});
  final Widget Function(VrlzWorldBundle bundle)? worldBuilder;
  final Widget Function(VrzBundle bundle)? sceneBuilder;
  @override
  State<HomeExample> createState() => _HomeExampleState();
}

class _HomeExampleState extends State<HomeExample> {
  final _navigator = GlobalKey<NavigatorState>();
  final _theme = ValueNotifier(VrHomeThemeData.aurora);
  final _remote = VrRemoteControllerService();
  final _catalog = VrDemoCatalog(const [
    VrDemoLibraryEntry(
      id: 'connected-gardens',
      title: 'Jardines conectados',
      subtitle: 'Dos mundos propios conectados por portales',
      category: VrDemoLibraryCategory.lab,
      accent: 0xFF72D2AB,
      icon: 'view3d',
      featured: true,
    ),
    VrDemoLibraryEntry(
      id: 'gallery',
      title: 'Galería portátil',
      subtitle: 'Una escena .vrlz que también funciona sin conexión',
      category: VrDemoLibraryCategory.lab,
      accent: 0xFF8AE4CC,
      icon: 'view3d',
      featured: true,
    ),
  ]);

  Future<void> _openLibrary() async {
    await _navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/library'),
        builder: (_) => ValueListenableBuilder<VrHomeThemeData>(
          valueListenable: _theme,
          builder: (_, theme, _) => _ExamplePackageLibrary(
            theme: theme,
            sceneBuilder: widget.sceneBuilder,
            worldBuilder: widget.worldBuilder,
          ),
        ),
      ),
    );
  }

  Future<void> _openCatalog() async {
    await _navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/catalog'),
        builder: (context) => ValueListenableBuilder<VrHomeThemeData>(
          valueListenable: _theme,
          builder: (context, theme, _) => VrHomeCatalog(
            theme: theme,
            onThemeChanged: _setTheme,
            onBack: () => Navigator.pop(context),
            items: [
              VrHomeCatalogItem(
                id: 'connected-gardens',
                title: 'Jardines conectados',
                subtitle:
                    'Viaja entre un jardín y un observatorio; vuelve donde te quedaste',
                category: 'Mundos',
                icon: Icons.park_outlined,
                accent: theme.accent,
                featured: true,
                tags: const ['VR', 'sin conexión'],
              ),
              VrHomeCatalogItem(
                id: 'gallery',
                title: 'Galería portátil',
                subtitle:
                    'Modelo, materiales y cámara dentro de un archivo .vrlz',
                category: 'Escenas',
                icon: Icons.view_in_ar_rounded,
                accent: theme.accent,
                featured: true,
                tags: const ['sin visor', 'vrlz'],
              ),
            ],
            onLaunch: (item) => item.id == 'connected-gardens'
                ? _openGardens(context, worldBuilder: widget.worldBuilder)
                : _openGallery(context, sceneBuilder: widget.sceneBuilder),
            actions: [
              TextButton.icon(
                onPressed: _openLibrary,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Biblioteca .vrlz'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSpatial() {
    final bindings = VrHomeSpatialBindings(
      catalog: _catalog,
      remoteController: _remote,
      onExit: (context) => Navigator.of(context).maybePop(),
      onLaunch: (context, item) => item.demoId == 'connected-gardens'
          ? _openGardens(context, worldBuilder: widget.worldBuilder)
          : _openGallery(context, sceneBuilder: widget.sceneBuilder),
      onCatalog: (_) async {
        await _openCatalog();
        return VrHomeCatalogExit.home;
      },
    );
    _navigator.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/viewer'),
        builder: (_) => ValueListenableBuilder<VrHomeThemeData>(
          valueListenable: _theme,
          builder: (_, theme, _) => VrSessionHost(
            adapter: const VrWidgetSessionAdapter(rendererId: 'flutter_scene'),
            builder: (_, _, active) => IgnorePointer(
              ignoring: !active,
              child: VirtualHomeScene(bindings: bindings, theme: theme),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Explicit creator smoke-test entrypoint; normal launches remain Home.
    if (const bool.fromEnvironment('VRLIZATE_EXAMPLE_WORLDS')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _openGardens(
              _navigator.currentState!.overlay!.context,
              worldBuilder: widget.worldBuilder,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _theme.dispose();
    _remote.dispose();
    super.dispose();
  }

  void _setTheme(VrHomeThemeData theme) {
    _theme.value = theme;
  }

  Widget _landing() => ValueListenableBuilder<VrHomeThemeData>(
    valueListenable: _theme,
    builder: (_, theme, _) => VrHomeLanding(
      theme: theme,
      onThemeChanged: _setTheme,
      onExplore: _openCatalog,
      onViewer: _openSpatial,
      onController: null,
      settings: OutlinedButton.icon(
        onPressed: _openLibrary,
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('Biblioteca .vrlz'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VrHomeThemeData>(
    valueListenable: _theme,
    builder: (_, theme, _) => MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme,
      home: _landing(),
    ),
  );
}

/// Discovery, network, lifecycle and dispatch belong to this executable host.
/// Home only receives display values and user-action callbacks.
class _ExamplePackageLibrary extends StatefulWidget {
  const _ExamplePackageLibrary({
    required this.theme,
    this.sceneBuilder,
    this.worldBuilder,
  });
  final Widget Function(VrlzWorldBundle bundle)? worldBuilder;
  final Widget Function(VrzBundle bundle)? sceneBuilder;
  final VrHomeThemeData theme;
  @override
  State<_ExamplePackageLibrary> createState() => _ExamplePackageLibraryState();
}

class _ExamplePackageLibraryState extends State<_ExamplePackageLibrary>
    with WidgetsBindingObserver {
  late final VrlzLibraryController _library;
  bool? _routeCurrent;
  bool _visible = true;
  bool _launching = false, _dialogOpen = false, _sourceChanging = false;
  bool _refreshPending = false, _refreshScheduled = false;
  bool _explicitRefreshPending = false;
  String? _error;

  bool get _blocked =>
      _library.busy || _launching || _dialogOpen || _sourceChanging;
  bool get _canContinue =>
      mounted && _visible && (ModalRoute.of(context)?.isCurrent ?? true);

  // A macOS window may be visible and interactive while its app is inactive.
  static bool _isVisible(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void initState() {
    super.initState();
    _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
    _library = VrlzLibraryController(
      openDirectory: _openDirectory,
      addExamples: _addExamples,
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  static Future<VrlzDirectoryStore> _openDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory.fromUri(
      documents.uri.resolve('VRlizate-example/experiencias/'),
    );
    return VrlzDirectoryStore(directory.path);
  }

  static Future<void> _addExamples(VrlzDirectoryStore store) async {
    final packages = [
      await _galleryPackage(),
      await _gardensPackage(),
      VrlzPackage.decode(
        VrlzPackage.encodeBuiltin(
          id: 'org.vrlizate.example.gallery',
          title: 'Galería integrada',
          description:
              'Abre la galería que ya incluye este ejemplo de aplicación.',
          demoId: 'gallery',
        ),
      ),
    ];
    for (final package in packages) {
      try {
        await store.importBytes(package.encode());
      } on VrlzDiscoveryException catch (error) {
        if (error.kind != VrlzDiscoveryIssueKind.duplicateId) {
          rethrow;
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && _routeCurrent != true) _requestRefresh();
    _routeCurrent = current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasVisible = _visible;
    _visible = _isVisible(state);
    if (_visible && (!wasVisible || state == AppLifecycleState.resumed)) {
      _requestRefresh();
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_refreshPending && !_blocked) _requestRefresh();
  }

  void _requestRefresh({bool explicit = false}) {
    _refreshPending = true;
    _explicitRefreshPending |= explicit;
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted ||
          !(ModalRoute.of(context)?.isCurrent ?? true) ||
          (!_visible && !_explicitRefreshPending) ||
          _blocked ||
          !_refreshPending) {
        return;
      }
      _refreshPending = false;
      _explicitRefreshPending = false;
      unawaited(_library.refresh());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  String? _unavailable(VrlzLibraryItem item) {
    if (!_library.isComplete) {
      return 'Actualiza la biblioteca para completar la validación.';
    }
    if (item.kind == VrlzPackageKind.builtin && item.demoId != 'gallery') {
      return 'Este ejemplo no incluye la experiencia integrada solicitada.';
    }
    if (item.kind == VrlzPackageKind.nes) {
      return 'El runtime NES no está instalado en este ejemplo.';
    }
    if (item.kind == VrlzPackageKind.retro) {
      return 'El runtime retro 2.5D no está instalado en este ejemplo.';
    }
    return null;
  }

  Future<void> _launch(String id) async {
    if (_blocked || !_library.isComplete) return;
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      final item = _library.items.singleWhere((item) => item.id == id);
      final package = await _library.load(item.key);
      if (!mounted || !_canContinue) return;
      if (package.kind == VrlzPackageKind.worlds) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/experience/worlds'),
            builder: (_) => _WorldSession(
              bundle: package.worldBundle!,
              worldBuilder: widget.worldBuilder,
            ),
          ),
        );
        return;
      }
      final VrzBundle bundle;
      if (package.kind == VrlzPackageKind.scene) {
        bundle = package.sceneBundle!;
      } else if (package.kind == VrlzPackageKind.nes) {
        throw StateError('El runtime NES no está instalado en este ejemplo.');
      } else if (package.kind == VrlzPackageKind.retro) {
        throw StateError(
          'El runtime retro 2.5D no está instalado en este ejemplo.',
        );
      } else if (package.kind == VrlzPackageKind.builtin &&
          package.demoId == 'gallery') {
        bundle = (await _galleryPackage()).sceneBundle!;
      } else {
        throw StateError(
          'Este ejemplo solo incluye el runtime integrado gallery.',
        );
      }
      if (!mounted || !_canContinue) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/experience/package'),
          builder: (_) =>
              _SceneSession(bundle: bundle, sceneBuilder: widget.sceneBuilder),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el paquete. $error');
      }
    } finally {
      if (mounted) {
        setState(() => _launching = false);
        _requestRefresh();
      }
    }
  }

  Future<void> _import() async {
    if (_blocked) return;
    setState(() {
      _dialogOpen = true;
      _error = null;
    });
    final request = await showDialog<_SourceRequest>(
      context: context,
      builder: (_) => const _SourceDialog(),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (request == null || !_canContinue) {
      if (_refreshPending) _requestRefresh();
      return;
    }
    setState(() => _sourceChanging = true);
    _refreshPending = false;
    _explicitRefreshPending = false;
    try {
      if (request.catalog) {
        await _library.useWebCatalog(request.uri);
      } else {
        await _library.importFromUrl(request.uri);
      }
    } finally {
      if (mounted) {
        setState(() => _sourceChanging = false);
        if (_refreshPending) _requestRefresh();
      }
    }
  }

  Future<void> _copyLocation() async {
    try {
      await Clipboard.setData(ClipboardData(text: _library.location));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ubicación copiada.')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo copiar la ubicación. $error');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _library.removeListener(_changed);
    _library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VrHomePackageLibrary(
    theme: widget.theme,
    items: [
      for (final item in _library.items)
        VrHomePackageItem(
          id: item.id,
          title: item.title,
          description: item.description,
          typeLabel: switch (item.kind) {
            VrlzPackageKind.scene => 'Escena portátil',
            VrlzPackageKind.builtin => 'Demo integrada',
            VrlzPackageKind.nes => 'Cartucho NES',
            VrlzPackageKind.retro => 'Juego retro 2.5D',
            VrlzPackageKind.webgame => 'Juego web 3D',
            VrlzPackageKind.worlds => 'Mundos conectados',
            null => 'Paquete web por verificar',
          },
          unavailableReason: _unavailable(item),
        ),
    ],
    location: _library.location,
    issues: [
      if (!_library.isComplete && !_library.busy)
        'La lista no está completa. Revisa los avisos y actualiza antes de abrir un paquete.',
      ..._library.issues,
    ],
    loading: _library.busy && _library.items.isEmpty,
    busy: _blocked,
    error: _error ?? _library.error,
    onLaunch: _launch,
    onRefresh: () {
      setState(() => _error = null);
      _requestRefresh(explicit: true);
    },
    onImport: _import,
    onInstallExamples: () {
      setState(() => _error = null);
      unawaited(_library.installExamples());
    },
    onUseLocal: _library.isWeb
        ? () {
            setState(() => _error = null);
            unawaited(_library.useLocalDirectory());
          }
        : null,
    onCopyLocation: _library.location.isEmpty ? null : _copyLocation,
  );
}

class _SourceRequest {
  const _SourceRequest(this.uri, {required this.catalog});
  final Uri uri;
  final bool catalog;
}

class _SourceDialog extends StatefulWidget {
  const _SourceDialog();
  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  final _address = TextEditingController();
  bool _catalog = false;
  String? _error;

  void _submit() {
    final uri = Uri.tryParse(_address.text.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      setState(
        () => _error =
            'Escribe una dirección HTTPS sin credenciales ni fragmentos.',
      );
      return;
    }
    Navigator.of(context).pop(_SourceRequest(uri, catalog: _catalog));
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Añadir desde HTTPS'),
    content: SizedBox(
      width: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Paquete .vrlz'),
                selected: !_catalog,
                onSelected: (_) => setState(() => _catalog = false),
              ),
              ChoiceChip(
                label: const Text('Índice JSON'),
                selected: _catalog,
                onSelected: (_) => setState(() => _catalog = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _catalog
                ? 'Consulta un catálogo web. Los paquetes se validan antes de abrirse.'
                : 'Valida el paquete y guárdalo en la carpeta local. No se abrirá automáticamente.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Dirección HTTPS',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(_catalog ? 'Consultar índice' : 'Importar paquete'),
      ),
    ],
  );
}

/// The engine owns session lifecycle. The viewer owns its GPU data.
class _SceneSession extends StatelessWidget {
  const _SceneSession({required this.bundle, this.sceneBuilder});
  final VrzBundle bundle;
  final Widget Function(VrzBundle bundle)? sceneBuilder;

  @override
  Widget build(BuildContext context) => VrSessionHost(
    adapter: const VrWidgetSessionAdapter(rendererId: 'flutter_scene'),
    builder: (_, _, active) => IgnorePointer(
      ignoring: !active,
      child: sceneBuilder?.call(bundle) ?? VrlzSceneViewer(bundle: bundle),
    ),
  );
}

/// The executable host selects storage; the SDK viewer interprets the worlds.
class _WorldSession extends StatefulWidget {
  const _WorldSession({required this.bundle, this.worldBuilder});
  final VrlzWorldBundle bundle;
  final Widget Function(VrlzWorldBundle bundle)? worldBuilder;
  @override
  State<_WorldSession> createState() => _WorldSessionState();
}

class _WorldSessionState extends State<_WorldSession> {
  late final Future<VrlzWorldSaveStore> _store = _openStore();
  Future<VrlzWorldSaveStore> _openStore() async {
    final documents = await getApplicationDocumentsDirectory();
    return VrlzWorldSaveStore(
      directoryPath: Directory.fromUri(
        documents.uri.resolve('VRlizate-example/saves/'),
      ).path,
    );
  }

  @override
  Widget build(BuildContext context) => VrSessionHost(
    adapter: const VrWidgetSessionAdapter(rendererId: 'flutter_scene'),
    builder: (_, _, active) => IgnorePointer(
      ignoring: !active,
      child:
          widget.worldBuilder?.call(widget.bundle) ??
          FutureBuilder<VrlzWorldSaveStore>(
            future: _store,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return VrlzWorldViewer(
                  bundle: widget.bundle,
                  saveStore: snapshot.data!,
                  onExit: () => Navigator.of(context).pop(),
                );
              }
              return Scaffold(
                appBar: AppBar(title: Text(widget.bundle.manifest.title)),
                body: Center(
                  child: snapshot.hasError
                      ? Text('No se pudo abrir el guardado: ${snapshot.error}')
                      : const CircularProgressIndicator(),
                ),
              );
            },
          ),
    ),
  );
}
