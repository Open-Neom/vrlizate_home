import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants/vr_home_constants.dart';
import '../../utils/constants/vr_home_translation_constants.dart';
import '../theme/vr_home_theme.dart';

/// A presentation-only entry page. Navigation, pairing and device ownership
/// remain in the application callbacks; this widget starts no services.
class VrHomeLanding extends StatelessWidget {
  const VrHomeLanding({
    super.key,
    this.theme = VrHomeThemeData.aurora,
    this.notice,
    this.busy = false,
    required this.onExplore,
    required this.onViewer,
    required this.onController,
    this.onResumeController,
    this.onForgetController,
    this.settings,
    this.footerAction,
    this.onThemeChanged,
    this.onEcosystem,
    this.controllerInstructions =
        VrHomeTranslationConstants.defaultControllerInstructions,
  });

  final VrHomeThemeData theme;
  final String? notice;
  final bool busy;
  final VoidCallback? onExplore;
  final VoidCallback? onViewer;
  final VoidCallback? onController;
  final VoidCallback? onEcosystem;
  final VoidCallback? onResumeController;
  final VoidCallback? onForgetController;
  final Widget? settings;
  final Widget? footerAction;
  final ValueChanged<VrHomeThemeData>? onThemeChanged;

  /// Host-specific transport instructions; Home never starts a connection.
  final String controllerInstructions;

  @override
  Widget build(BuildContext context) => Theme(
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
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final hasNotice = notice?.trim().isNotEmpty ?? false;
              final hasSavedActions =
                  onResumeController != null || onForgetController != null;
              final isTallPhone =
                  constraints.maxHeight >= 660 &&
                  constraints.maxWidth < 600 &&
                  textScale <= 1.25;
              final verticalPad = isTallPhone ? 12.0 : 8.0;
              final reservedHeight =
                  126.0 +
                  (hasNotice ? 56.0 : 0.0) +
                  (hasSavedActions ? 42.0 : 0.0) +
                  (onEcosystem != null ? 40.0 : 0.0) +
                  ((onController != null || footerAction != null)
                      ? (isTallPhone ? 164.0 : 126.0)
                      : 0.0);
              final cardMinHeight = isTallPhone
                  ? ((constraints.maxHeight -
                                verticalPad * 2 -
                                reservedHeight) /
                            2)
                        .clamp(176.0, 276.0)
                  : 0.0;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth < 500 ? 14 : 28,
                  vertical: verticalPad,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 1040,
                      minHeight: isTallPhone
                          ? math.max(
                              0.0,
                              constraints.maxHeight - verticalPad * 2,
                            )
                          : 0.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: isTallPhone
                          ? MainAxisAlignment.spaceBetween
                          : MainAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: theme.accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.accent.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.all_inclusive_rounded,
                                    color: theme.accent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    VrHomeTranslationConstants.brandTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.foreground,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                ),
                                if (onThemeChanged != null) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: VrHomeThemeSelector(
                                      theme: theme,
                                      onChanged: onThemeChanged!,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: isTallPhone ? 10 : 6),
                            Text(
                              VrHomeTranslationConstants.heroHeadline,
                              style: TextStyle(
                                color: theme.foreground,
                                fontSize: constraints.maxWidth < 500 ? 23 : 28,
                                height: 1.08,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              onExplore == null
                                  ? VrHomeTranslationConstants
                                        .heroSubtitleVisorOnly
                                  : onController == null
                                  ? VrHomeTranslationConstants
                                        .heroSubtitleExploreAndVisor
                                  : VrHomeTranslationConstants
                                        .heroSubtitleAllModes,
                              style: TextStyle(
                                color: theme.muted,
                                fontSize: isTallPhone ? 13 : 11.5,
                                height: 1.26,
                              ),
                            ),
                            if (hasNotice) ...[
                              const SizedBox(height: 8),
                              Semantics(
                                liveRegion: true,
                                child: Container(
                                  key: const ValueKey(
                                    VrHomeConstants.startNoticeKey,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.secondary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.secondary.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: theme.secondary,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          notice!.trim(),
                                          style: TextStyle(
                                            color: theme.foreground,
                                            fontSize: 12,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (busy) ...[
                              const SizedBox(height: 6),
                              const LinearProgressIndicator(minHeight: 2),
                              const SizedBox(height: 3),
                              Text(
                                VrHomeTranslationConstants.openingSpaceLabel,
                                style: TextStyle(
                                  color: theme.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: isTallPhone ? 12 : 8),
                        LayoutBuilder(
                          builder: (context, inner) {
                            final twoColumns =
                                inner.maxWidth >= 320 && textScale <= 1.35;
                            final visorCard = _modeCard(
                              key: const ValueKey(
                                VrHomeConstants.startVisorKey,
                              ),
                              icon: Icons.view_in_ar_rounded,
                              badge: VrHomeTranslationConstants.visorBadge,
                              title: VrHomeTranslationConstants.visorTitle,
                              description:
                                  VrHomeTranslationConstants.visorDescription,
                              action: VrHomeTranslationConstants.visorAction,
                              accent: theme.accent,
                              callback: onViewer,
                              minHeight: cardMinHeight,
                              spacious: isTallPhone,
                            );
                            final controllerCard = onController == null
                                ? null
                                : _modeCard(
                                    key: const ValueKey(
                                      VrHomeConstants.startControllerKey,
                                    ),
                                    icon: Icons.sports_esports_rounded,
                                    badge: VrHomeTranslationConstants
                                        .controllerBadge,
                                    title: VrHomeTranslationConstants
                                        .controllerTitle,
                                    description: VrHomeTranslationConstants
                                        .controllerDescription,
                                    action: VrHomeTranslationConstants
                                        .controllerAction,
                                    accent: theme.secondary,
                                    callback: onController,
                                    minHeight: cardMinHeight,
                                    spacious: isTallPhone,
                                  );
                            final settingsCard = settings == null
                                ? null
                                : _settingsCard(
                                    settings!,
                                    minHeight: cardMinHeight,
                                    spacious: isTallPhone,
                                  );

                            if (!twoColumns) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (onExplore != null) ...[
                                    _exploreCard(
                                      minHeight: cardMinHeight,
                                      spacious: isTallPhone,
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  visorCard,
                                  if (controllerCard != null) ...[
                                    const SizedBox(height: 10),
                                    controllerCard,
                                  ],
                                  if (settingsCard != null) ...[
                                    const SizedBox(height: 10),
                                    settingsCard,
                                  ],
                                ],
                              );
                            }

                            final gap = isTallPhone ? 12.0 : 8.0;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (onExplore != null) ...[
                                        Expanded(
                                          child: _exploreCard(
                                            minHeight: cardMinHeight,
                                            spacious: isTallPhone,
                                          ),
                                        ),
                                        SizedBox(width: gap),
                                      ],
                                      Expanded(child: visorCard),
                                    ],
                                  ),
                                ),
                                if (controllerCard != null ||
                                    settingsCard != null) ...[
                                  SizedBox(height: gap),
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (controllerCard != null)
                                          Expanded(child: controllerCard),
                                        if (controllerCard != null &&
                                            settingsCard != null)
                                          SizedBox(width: gap),
                                        if (settingsCard != null)
                                          Expanded(child: settingsCard),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        if (onEcosystem != null) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              VrHomeConstants.startEcosystemKey,
                            ),
                            onPressed: busy ? null : onEcosystem,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(
                              Icons.meeting_room_outlined,
                              size: 16,
                            ),
                            label: const Text(
                              VrHomeTranslationConstants
                                  .enterEcosystemHomeAction,
                            ),
                          ),
                        ],
                        if (hasSavedActions) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (onResumeController != null)
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    VrHomeConstants.resumeControllerKey,
                                  ),
                                  onPressed: busy ? null : onResumeController,
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(
                                    Icons.history_rounded,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    VrHomeTranslationConstants
                                        .resumeLastControllerAction,
                                  ),
                                ),
                              if (onForgetController != null)
                                TextButton(
                                  key: const ValueKey(
                                    VrHomeConstants.forgetControllerKey,
                                  ),
                                  onPressed: busy ? null : onForgetController,
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    VrHomeTranslationConstants
                                        .forgetPairingAction,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (onController != null || footerAction != null) ...[
                          SizedBox(height: isTallPhone ? 12 : 8),
                          Container(
                            key: const ValueKey(
                              VrHomeConstants.startBottomInfoCardKey,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isTallPhone ? 14 : 10,
                              vertical: isTallPhone ? 12 : 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.surface.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: theme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (footerAction != null) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: footerAction!,
                                  ),
                                  if (onController != null)
                                    SizedBox(height: isTallPhone ? 10 : 6),
                                ],
                                if (onController != null) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.devices_rounded,
                                        color: theme.accent,
                                        size: isTallPhone ? 17 : 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          VrHomeTranslationConstants
                                              .twoPhonesSectionTitle,
                                          style: TextStyle(
                                            color: theme.foreground,
                                            fontSize: isTallPhone ? 13.5 : 11.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    controllerInstructions,
                                    style: TextStyle(
                                      color: theme.muted,
                                      fontSize: isTallPhone ? 12 : 10.5,
                                      height: 1.32,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _exploreCard({double minHeight = 0, bool spacious = false}) =>
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Container(
          padding: EdgeInsets.all(spacious ? 15 : 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  theme.accent.withValues(alpha: 0.20),
                  theme.surface,
                ),
                theme.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(spacious ? 18 : 14),
            border: Border.all(color: theme.accent.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(spacious ? 7 : 4),
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.videogame_asset_rounded,
                          color: theme.accent,
                          size: spacious ? 21 : 18,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          VrHomeTranslationConstants.handheldBadge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: spacious ? 10 : 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacious ? 10 : 4),
                  Text(
                    VrHomeTranslationConstants.handheldTitle,
                    style: TextStyle(
                      color: theme.foreground,
                      fontSize: spacious ? 17.5 : 14.5,
                      height: 1.14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: spacious ? 6 : 3),
                  Text(
                    VrHomeTranslationConstants.handheldDescription,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: spacious ? 12.5 : 10.5,
                      height: 1.28,
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacious ? 12 : 7),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey(VrHomeConstants.startPhoneDemosKey),
                  onPressed: busy ? null : onExplore,
                  style: FilledButton.styleFrom(
                    visualDensity: spacious
                        ? VisualDensity.standard
                        : VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size(0, spacious ? 40 : 32),
                    padding: EdgeInsets.symmetric(
                      horizontal: spacious ? 12 : 10,
                      vertical: spacious ? 10 : 6,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          VrHomeTranslationConstants.handheldAction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: VrHomeConstants.robotoFontFamily,
                            fontSize: spacious ? 13 : 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: spacious ? 17 : 15,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _settingsCard(
    Widget child, {
    double minHeight = 0,
    bool spacious = false,
  }) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: minHeight),
    child: Container(
      key: const ValueKey(VrHomeConstants.startSettingsCardKey),
      padding: EdgeInsets.all(spacious ? 15 : 10),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(spacious ? 18 : 14),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(spacious ? 7 : 4),
                    decoration: BoxDecoration(
                      color: theme.secondary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      size: spacious ? 21 : 18,
                      color: theme.secondary,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      VrHomeTranslationConstants.settingsBadge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.secondary,
                        fontSize: spacious ? 10 : 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacious ? 10 : 4),
              Text(
                VrHomeTranslationConstants.settingsTitle,
                style: TextStyle(
                  color: theme.foreground,
                  fontSize: spacious ? 17.5 : 14.5,
                  fontWeight: FontWeight.w800,
                  height: 1.14,
                ),
              ),
              SizedBox(height: spacious ? 5 : 2),
              Text(
                VrHomeTranslationConstants.settingsDescription,
                style: TextStyle(
                  color: theme.muted,
                  fontSize: spacious ? 12.2 : 10.5,
                  height: 1.26,
                ),
              ),
            ],
          ),
          SizedBox(height: spacious ? 10 : 6),
          child,
        ],
      ),
    ),
  );

  Widget _modeCard({
    required Key key,
    required IconData icon,
    required String badge,
    required String title,
    required String description,
    required String action,
    required Color accent,
    required VoidCallback? callback,
    double minHeight = 0,
    bool spacious = false,
  }) {
    final enabled = !busy && callback != null;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Material(
          color: theme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(spacious ? 18 : 14),
            side: BorderSide(color: theme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: key,
            onTap: enabled ? callback : null,
            child: Padding(
              padding: EdgeInsets.all(spacious ? 15 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(spacious ? 7 : 4),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              icon,
                              size: spacious ? 21 : 18,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              badge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: accent,
                                fontSize: spacious ? 10 : 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacious ? 10 : 4),
                      Text(
                        title,
                        style: TextStyle(
                          color: theme.foreground,
                          fontSize: spacious ? 17.5 : 14.5,
                          fontWeight: FontWeight.w800,
                          height: 1.14,
                        ),
                      ),
                      SizedBox(height: spacious ? 6 : 3),
                      Text(
                        description,
                        style: TextStyle(
                          color: theme.muted,
                          fontSize: spacious ? 12.5 : 10.5,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacious ? 12 : 7),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacious ? 10 : 0,
                      vertical: spacious ? 8 : 0,
                    ),
                    decoration: spacious
                        ? BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.32),
                            ),
                          )
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            action,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: enabled ? accent : theme.muted,
                              fontSize: spacious ? 12.5 : 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: enabled ? accent : theme.muted,
                          size: spacious ? 16 : 15,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
