import 'package:buspilot_vehicle/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('buildTheme uses the brand colours, font and token extension', () {
    for (final b in Brightness.values) {
      final t = buildTheme(b);
      final bp = b == Brightness.dark ? BuspilotColors.dark : BuspilotColors.light;
      expect(t.extension<BuspilotColors>(), bp);
      expect(t.colorScheme.primary, bp.primary);
      expect(t.scaffoldBackgroundColor, bp.background);
      expect(t.textTheme.bodyLarge?.fontFamily, brandFontFamily);
    }
  });

  test('colour pairs from the theme meet WCAG AA', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    for (final b in Brightness.values) {
      final s = buildTheme(b).colorScheme;
      final bp = buildTheme(b).extension<BuspilotColors>()!;
      expect(contrast(s.primary, s.onPrimary), greaterThanOrEqualTo(4.5));
      expect(contrast(s.secondary, s.onSecondary), greaterThanOrEqualTo(4.5));
      expect(contrast(s.tertiary, s.onTertiary), greaterThanOrEqualTo(4.5));
      expect(contrast(s.primaryContainer, s.onPrimaryContainer), greaterThanOrEqualTo(4.5));
      expect(contrast(s.surface, s.onSurfaceVariant), greaterThanOrEqualTo(4.5));
      expect(contrast(s.errorContainer, s.onErrorContainer), greaterThanOrEqualTo(4.5));
      // Status icons on cards.
      expect(contrast(s.surface, bp.onTime), greaterThanOrEqualTo(3));
    }
  });
}
