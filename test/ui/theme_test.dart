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
}
