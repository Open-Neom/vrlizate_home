import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Build-time inspection only. The dependency's generated FlatBuffer schema is
// the same schema used by its shader trimming hook; no Flutter/GPU is started.
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;

const baseDataKey =
    'packages/flutter_scene/flutter_gpu_shaders/shaderbundles/base.shaderbundle';
const physicalDataKey =
    'packages/flutter_scene/flutter_scene/fmat/physical/physical.shaderbundle';
const generatedManifestKey = 'flutter_scene_generated/manifest.json';

/// Checks the bundles selected by flutter_scene's Android asset lookup order.
///
/// This is a packaging check, not shader compilation on the device, a complete
/// FlatBuffer security verifier, or a performance/graphics compatibility test.
/// Extra bundles for other targets are harmless unless selected at runtime.
List<String> verifyAndroidShaderAssets(Map<String, Uint8List> assets) {
  final reports = <String>[];
  for (final entry in const [
    (baseDataKey, 'shaderBundle', 'base'),
    (physicalDataKey, 'material', 'physical#shaderbundle'),
  ]) {
    final (dataKey, family, id) = entry;
    final key = assets.containsKey(dataKey)
        ? dataKey
        : _generatedKey(assets, family, id);
    if (key == null || !assets.containsKey(key)) {
      throw FormatException('Missing Android shader bundle: $id.');
    }
    final count = verifyAndroidShaderBundle(
      assets[key]!,
      label: key,
      requireUnskinnedVertex: id == 'base',
    );
    reports.add('$key: $count shaders with OpenGL ES + Vulkan.');
  }
  return reports;
}

String? _generatedKey(Map<String, Uint8List> assets, String family, String id) {
  // Runtime prefers an app-owned generated tree over the package's tree.
  for (final manifestKey in const [
    generatedManifestKey,
    'packages/flutter_scene/$generatedManifestKey',
  ]) {
    final bytes = assets[manifestKey];
    if (bytes == null) continue;
    final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final entries = manifest['entries'] as List<dynamic>;
    for (final raw in entries) {
      final entry = raw as Map<String, dynamic>;
      if (entry['family'] == family &&
          entry['id'] == id &&
          (entry['owner'] ?? manifest['package']) == 'flutter_scene' &&
          (entry['target'] == null || entry['target'] == 'openglEs,vulkan')) {
        final prefix = manifestKey.substring(
          0,
          manifestKey.length - 'manifest.json'.length,
        );
        return '$prefix${entry['file']}';
      }
    }
  }
  return null;
}

int verifyAndroidShaderBundle(
  Uint8List bytes, {
  required String label,
  bool requireUnskinnedVertex = false,
}) {
  if (bytes.length < 8 || ascii.decode(bytes.sublist(4, 8)) != 'IPSB') {
    throw FormatException('$label: missing shader-bundle header.');
  }
  final bundle = fb.ShaderBundle(bytes);
  if (bundle.formatVersion != fb.ShaderBundleFormatVersion.kVersion.value) {
    throw FormatException('$label: incompatible shader-bundle version.');
  }
  final shaders = bundle.shaders;
  if (shaders == null || shaders.isEmpty) {
    throw FormatException('$label: empty shader bundle.');
  }
  var hasUnskinnedVertex = false;
  for (final shader in shaders) {
    if (shader.name == 'UnskinnedVertex') hasUnskinnedVertex = true;
    final gles = shader.openglEs?.shader;
    final vulkan = shader.vulkan?.shader;
    if (gles == null || gles.isEmpty || vulkan == null || vulkan.isEmpty) {
      throw FormatException(
        '$label: shader ${shader.name} is missing OpenGL ES or Vulkan. '
        'A desktop build/test may have overwritten shared generated assets. '
        'Stop concurrent Flutter tasks and rebuild with '
        'FLUTTER_DART_DATA_ASSETS=false flutter build apk --release.',
      );
    }
  }
  if (requireUnskinnedVertex && !hasUnskinnedVertex) {
    throw FormatException('$label: missing UnskinnedVertex.');
  }
  return shaders.length;
}

Map<String, Uint8List> _readApkShaderAssets(String apk) {
  final list = Process.runSync('unzip', ['-Z1', apk]);
  if (list.exitCode != 0) {
    throw FileSystemException('Unable to list APK: ${list.stderr}', apk);
  }
  const prefix = 'assets/flutter_assets/';
  final assets = <String, Uint8List>{};
  for (final path in (list.stdout as String).split('\n')) {
    if (!path.startsWith(prefix) ||
        !(path.endsWith('.shaderbundle') ||
            path.endsWith(generatedManifestKey))) {
      continue;
    }
    final extracted = Process.runSync('unzip', [
      '-p',
      apk,
      path,
    ], stdoutEncoding: null);
    if (extracted.exitCode != 0) {
      throw FileSystemException('Unable to read APK asset: $path', apk);
    }
    assets[path.substring(prefix.length)] = Uint8List.fromList(
      extracted.stdout as List<int>,
    );
  }
  return assets;
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart tool/verify_android_shaders.dart APP.apk');
    exitCode = 64;
    return;
  }
  try {
    for (final report in verifyAndroidShaderAssets(
      _readApkShaderAssets(args.single),
    )) {
      stdout.writeln(report);
    }
    stdout.writeln(
      'Android shader packaging OK. Device rendering still requires testing.',
    );
  } catch (error) {
    stderr.writeln('Android shader packaging FAILED: $error');
    exitCode = 1;
  }
}
