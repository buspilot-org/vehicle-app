import 'package:material_ui/material_ui.dart';

import 'brand/buspilot_tokens.dart';

export 'brand/buspilot_tokens.dart' show BuspilotColors;

/// The brand font, bundled in assets/fonts/ (SIL OFL 1.1). Never loaded from
/// the network.
const brandFontFamily = 'M PLUS Rounded 1c';
const _fontFallback = ['Hiragino Maru Gothic ProN', 'BIZ UDPGothic', 'sans-serif'];

/// Buspilot app chrome from the brand tokens (asagi), so the app looks the
/// same as the rider app and the admin console.
ThemeData buildTheme(Brightness brightness) {
  final bp = brightness == Brightness.dark ? BuspilotColors.dark : BuspilotColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: bp.primary, brightness: brightness).copyWith(
    primary: bp.primary,
    onPrimary: bp.onPrimary,
    primaryContainer: bp.primaryTint,
    onPrimaryContainer: bp.onPrimaryTint,
    secondary: bp.primaryStrong,
    onSecondary: bp.onPrimary,
    secondaryContainer: bp.primaryTint,
    onSecondaryContainer: bp.onPrimaryTint,
    tertiary: bp.accent,
    onTertiary: bp.onAccent,
    surface: bp.surface,
    onSurface: bp.text,
    onSurfaceVariant: bp.textMuted,
    outlineVariant: bp.border,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: brandFontFamily, fontFamilyFallback: _fontFallback);
  return base.copyWith(
    scaffoldBackgroundColor: bp.background,
    textTheme: _brandText(base.textTheme),
    cardTheme: CardThemeData(color: bp.surface, margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
    extensions: [bp],
  );
}

/// The brand type scale (brand tokens/typography.json, app sizes in sp).
/// Never smaller than 12.
TextTheme _brandText(TextTheme t) {
  TextStyle? s(TextStyle? x, double size, FontWeight w, double height) =>
      x?.copyWith(fontSize: size, fontWeight: w, height: height, letterSpacing: 0);
  return t.copyWith(
    displaySmall: s(t.displaySmall, 32, FontWeight.w800, 1.3),
    headlineSmall: s(t.headlineSmall, 24, FontWeight.w800, 1.35),
    titleLarge: s(t.titleLarge, 22, FontWeight.w800, 1.4),
    titleMedium: s(t.titleMedium, 18, FontWeight.w700, 1.5),
    titleSmall: s(t.titleSmall, 14, FontWeight.w700, 1.4),
    bodyLarge: s(t.bodyLarge, 16, FontWeight.w500, 1.7),
    bodyMedium: s(t.bodyMedium, 14, FontWeight.w500, 1.6),
    bodySmall: s(t.bodySmall, 12, FontWeight.w500, 1.5),
    labelLarge: s(t.labelLarge, 14, FontWeight.w700, 1.4),
    labelMedium: s(t.labelMedium, 12, FontWeight.w700, 1.4),
    labelSmall: s(t.labelSmall, 12, FontWeight.w500, 1.5),
  );
}

/// The brand colours of the current theme.
extension BuspilotTheme on BuildContext {
  BuspilotColors get brand => Theme.of(this).extension<BuspilotColors>() ?? BuspilotColors.light;
}
