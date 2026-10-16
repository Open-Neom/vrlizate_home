import 'package:flutter/material.dart';

/// Palette shared by the landing page and catalog, without platform state.
@immutable
class VrHomeThemeData {
  VrHomeThemeData({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.secondary,
    required this.border,
    required List<Color> gradient,
  }) : gradient = List<Color>.unmodifiable(gradient) {
    if (gradient.length < 2) {
      throw ArgumentError.value(
        gradient,
        'gradient',
        'Needs at least two colors',
      );
    }
  }

  const VrHomeThemeData._({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.secondary,
    required this.border,
    required this.gradient,
  });

  final String id;
  final String name;
  final Color background;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color secondary;
  final Color border;
  final List<Color> gradient;

  static const aurora = VrHomeThemeData._(
    id: 'aurora',
    name: 'Aurora',
    background: Color(0xFF0B1721),
    surface: Color(0xFF142733),
    foreground: Color(0xFFF2F8FA),
    muted: Color(0xFFB0C5D0),
    accent: Color(0xFF8AE4CC),
    secondary: Color(0xFFAACDFF),
    border: Color(0xFF2D4554),
    gradient: [Color(0xFF13363C), Color(0xFF0B1721), Color(0xFF17283F)],
  );

  static const daylight = VrHomeThemeData._(
    id: 'daylight',
    name: 'Día',
    background: Color(0xFFF2F6F4),
    surface: Color(0xFFFFFFFF),
    foreground: Color(0xFF163136),
    muted: Color(0xFF4E676C),
    accent: Color(0xFF006A59),
    secondary: Color(0xFF265FA2),
    border: Color(0xFFCCDCD8),
    gradient: [Color(0xFFE4F3EB), Color(0xFFF4F7F4), Color(0xFFE8EFF8)],
  );

  static const midnight = VrHomeThemeData._(
    id: 'midnight',
    name: 'Medianoche',
    background: Color(0xFF10101C),
    surface: Color(0xFF1D1C30),
    foreground: Color(0xFFF5F1FC),
    muted: Color(0xFFC0B9D5),
    accent: Color(0xFFC5AFFA),
    secondary: Color(0xFF82D2EE),
    border: Color(0xFF39334F),
    gradient: [Color(0xFF29213E), Color(0xFF10101C), Color(0xFF152B37)],
  );

  static const presets = <VrHomeThemeData>[aurora, daylight, midnight];

  ThemeData get materialTheme {
    final brightness = background.computeLuminance() > 0.5
        ? Brightness.light
        : Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: accent.computeLuminance() > 0.45
              ? const Color(0xFF102728)
              : Colors.white,
          secondary: secondary,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: muted,
          outline: border,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      dividerColor: border,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
    );
  }
}

/// Controlled palette selection; the host owns persistence and theme changes.
class VrHomeThemeSelector extends StatelessWidget {
  const VrHomeThemeSelector({
    super.key,
    required this.theme,
    required this.onChanged,
  });

  final VrHomeThemeData theme;
  final ValueChanged<VrHomeThemeData> onChanged;

  void _cycleNext() {
    final presets = VrHomeThemeData.presets;
    final currentIndex = presets.indexWhere((item) => item.id == theme.id);
    final nextIndex = (currentIndex + 1) % presets.length;
    onChanged(presets[nextIndex]);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: theme.surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: theme.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cycleNext,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Icon(Icons.palette_outlined, size: 13, color: theme.accent),
          ),
        ),
        for (final preset in VrHomeThemeData.presets)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              button: true,
              selected: theme.id == preset.id,
              label: preset.name,
              child: InkResponse(
                key: ValueKey('home_theme_${preset.id}'),
                onTap: () => onChanged(preset),
                radius: 13,
                child: Tooltip(
                  message: preset.name,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: theme.id == preset.id ? 18 : 14,
                    height: theme.id == preset.id ? 18 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [preset.accent, preset.secondary],
                      ),
                      border: Border.all(
                        color: theme.id == preset.id
                            ? theme.foreground
                            : theme.foreground.withValues(alpha: 0.28),
                        width: theme.id == preset.id ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
