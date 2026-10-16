import 'package:flutter/material.dart';

import 'virtual_home_models.dart';

/// Immutable content shown before entering an immersive demo.
class DemoPreviewData {
  const DemoPreviewData({
    required this.demoId,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.category,
    required this.controls,
    required this.color,
    required this.icon,
  });

  final String demoId;
  final String title;
  final String subtitle;
  final String description;
  final String category;
  final String controls;
  final Color color;
  final IconData icon;

  factory DemoPreviewData.fromPedestal(PortalPedestal pedestal) =>
      DemoPreviewData.forDemo(
        demoId: pedestal.demoId,
        title: pedestal.title,
        subtitle: pedestal.subtitle,
        color: pedestal.color,
      );

  factory DemoPreviewData.forDemo({
    required String demoId,
    required String title,
    String? subtitle,
    Color? color,
  }) {
    const details = _fallbackDetails;
    return DemoPreviewData(
      demoId: demoId,
      title: title,
      subtitle: subtitle ?? details.subtitle,
      description: details.description,
      category: details.category,
      controls: details.controls,
      color: color ?? details.color,
      icon: details.icon,
    );
  }
}

class _DemoDetails {
  const _DemoDetails({
    required this.subtitle,
    required this.description,
    required this.category,
    required this.controls,
    required this.color,
    required this.icon,
  });

  final String subtitle;
  final String description;
  final String category;
  final String controls;
  final Color color;
  final IconData icon;
}

const _fallbackDetails = _DemoDetails(
  subtitle: 'Experiencia inmersiva VRlizate',
  description: 'Explora una experiencia espacial diseñada para VR móvil.',
  category: 'EXPERIENCIA VR',
  controls: 'MIRADA + MANDO',
  color: Color(0xFF00E5FF),
  icon: Icons.view_in_ar_rounded,
);
