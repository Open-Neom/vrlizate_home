import 'package:flutter/material.dart';

import '../../utils/constants/vr_home_translation_constants.dart';

/// Non-interactive spatial loading splash overlay displayed while the 3D
/// Virtual Home Mall scene and controller synchronization finish warming up.
class VrHomeLoadingSplashOverlay extends StatelessWidget {
  const VrHomeLoadingSplashOverlay({
    super.key,
    required this.visible,
    this.isSyncingController = false,
  });

  final bool visible;
  final bool isSyncingController;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: ColoredBox(
          color: const Color(0xFF060B18),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              decoration: BoxDecoration(
                color: const Color(0xFF0D162E),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.16),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x2200E5FF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x6600E5FF)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.view_in_ar_rounded,
                          color: Colors.cyanAccent,
                          size: 15,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            VrHomeTranslationConstants.splashBadge,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                      strokeWidth: 3.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isSyncingController
                        ? VrHomeTranslationConstants.splashSyncingTitle
                        : VrHomeTranslationConstants.splashLoadingTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    VrHomeTranslationConstants.splashSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.32,
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
