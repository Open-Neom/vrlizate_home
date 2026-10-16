import 'package:flutter/material.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';
import '../theme/vr_home_theme.dart';

/// Monoscopic, touch-operated preparation controls, used before wearing VR.
///
/// These are not spatial controls and must be hidden in headset mode. The
/// world-locked library and Home bar remain responsible for in-VR interaction.
class VirtualHomeHudCoordinator {
  static Widget buildTopQuickControls({
    bool hidden = false,
    VrHomeThemeData theme = VrHomeThemeData.aurora,
    VoidCallback? onToggleHidden,
    VoidCallback? onItzliTap,
    String assistantLabel = 'Abrir asistente',
    VoidCallback? onExit,
    required VoidCallback onLookTap,
    required VoidCallback onResolutionTap,
    VoidCallback? onCatalogTap,
    VoidCallback? onRemotePairTap,
    VoidCallback? onRecenterTap,
    VoidCallback? onSpatialSettingsTap,
    VoidCallback? onCastTap,
    required String lookName,
    required VrQualityPreset qualityPreset,
  }) {
    // Even the reveal button belongs to the caller's pre-use flow, not to a
    // head-locked overlay duplicated inside the two optical viewports.
    if (hidden) return const SizedBox.shrink();

    final tierLabel = switch (qualityPreset.tier) {
      VrQualityTier.low => 'LITE',
      VrQualityTier.medium => 'MEDIA',
      VrQualityTier.high => 'ESTÁNDAR',
      VrQualityTier.ultra => 'ALTA',
    };
    final scaleLabel = qualityPreset.pixelRatioScale.toStringAsFixed(2);

    return SafeArea(
      bottom: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Material(
            key: const ValueKey('home_preuse_controls'),
            color: theme.surface.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Preparación · Ocultar para usar el visor',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  // Wrap instead of scaling down the row: narrow phones keep
                  // the same minimum touch target, without per-eye copies.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      if (onExit != null)
                        _quickControl(
                          icon: Icons.home_outlined,
                          label: 'Volver al inicio',
                          onTap: onExit,
                          theme: theme,
                        ),
                      if (onToggleHidden != null)
                        _quickControl(
                          theme: theme,
                          icon: Icons.visibility_off_rounded,
                          label: 'Ocultar controles',
                          onTap: onToggleHidden,
                        ),
                      if (onRecenterTap != null)
                        _quickControl(
                          theme: theme,
                          icon: Icons.filter_center_focus_rounded,
                          label: 'Recentrar vista',
                          onTap: onRecenterTap,
                        ),
                      if (onCastTap != null)
                        _quickControl(
                          theme: theme,
                          icon: Icons.cast,
                          label: 'Compartir vista por Wi-Fi',
                          onTap: onCastTap,
                        ),
                      if (onSpatialSettingsTap != null)
                        _quickControl(
                          theme: theme,
                          icon: Icons.view_in_ar_outlined,
                          label: 'Movimiento físico del visor',
                          onTap: onSpatialSettingsTap,
                        ),
                      if (onItzliTap != null)
                        _quickControl(
                          theme: theme,
                          icon: Icons.auto_awesome_rounded,
                          label: assistantLabel,
                          onTap: onItzliTap,
                        ),
                      _quickControl(
                        theme: theme,
                        icon: Icons.palette_rounded,
                        label: 'Apariencia: $lookName',
                        onTap: onLookTap,
                      ),
                      _quickControl(
                        theme: theme,
                        icon: Icons.speed_rounded,
                        label: 'Calidad: $tierLabel · ${scaleLabel}x',
                        onTap: onResolutionTap,
                      ),
                      if (onRemotePairTap != null)
                        _quickControl(
                          theme: theme,
                          icon: Icons.qr_code_rounded,
                          label: 'Emparejar mando remoto',
                          onTap: onRemotePairTap,
                        ),
                      if (onCatalogTap != null)
                        _quickControl(
                          theme: theme,
                          icon: Icons.grid_view_rounded,
                          label: 'Abrir catálogo 2D',
                          onTap: onCatalogTap,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Legacy method name retained for callers; this is now a single compact
  /// pre-use status strip, not a stereo HUD in the optical sweet spot.
  ///
  /// Camera/voice arguments remain source-compatible but deliberately produce
  /// no capability badges: simulated or inactive features are not advertised.
  static Widget buildCenterSweetSpotHud({
    bool hidden = false,
    VrHomeThemeData theme = VrHomeThemeData.aurora,
    required String zoneName,
    required String statusMessage,
    required bool isRealHandInCamera,
    required bool isVoiceListening,
    required bool isRemoteConnected,
  }) {
    if (hidden) return const SizedBox.shrink();
    final remoteStatus = isRemoteConnected ? 'Mando conectado' : 'Sin mando';
    return IgnorePointer(
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              key: const ValueKey('home_preuse_status'),
              color: theme.surface.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$zoneName · $remoteStatus',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.muted, fontSize: 11),
                      ),
                      if (statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          statusMessage,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.foreground,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _quickControl({
    required VrHomeThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: Icon(icon, size: 22),
    color: theme.foreground,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    padding: const EdgeInsets.all(12),
  );
}
