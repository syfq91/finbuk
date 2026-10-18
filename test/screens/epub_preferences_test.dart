import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_readium/flutter_readium.dart';

void main() {
  group('EPUBPreferences Sanitization Tests', () {
    test('sanitizes legacy fontWeight 400.0 to null', () {
      const rawJson = '''
      {
        "fontFamily": "Georgia",
        "fontSize": 1.0,
        "fontWeight": 400.0,
        "scroll": false,
        "backgroundColor": 4294967295,
        "textColor": 4278190080
      }
      ''';

      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final rawFontSize = (map['fontSize'] as num?)?.toDouble() ?? 1.0;
      final fontSize = rawFontSize > 10.0 ? rawFontSize / 100.0 : rawFontSize;
      final rawFontWeight = (map['fontWeight'] as num?)?.toDouble();
      final fontWeight =
          (rawFontWeight != null &&
              rawFontWeight >= 0.0 &&
              rawFontWeight <= 2.5)
          ? rawFontWeight
          : null;

      expect(fontWeight, isNull);
      expect(fontSize, equals(1.0));

      final prefs = EPUBPreferences(
        fontFamily: map['fontFamily'] as String? ?? 'Georgia',
        fontSize: fontSize,
        fontWeight: fontWeight,
        scroll: map['scroll'] as bool? ?? false,
        backgroundColor: Color(map['backgroundColor'] as int),
        textColor: Color(map['textColor'] as int),
      );

      expect(prefs.fontWeight, isNull);
      expect(prefs.fontSize, equals(1.0));
      expect(prefs.fontFamily, equals('Georgia'));
    });

    test('preserves valid fontWeight within 0.0..2.5 range', () {
      const rawJson = '''
      {
        "fontFamily": "Helvetica",
        "fontSize": 1.2,
        "fontWeight": 1.5,
        "scroll": true,
        "backgroundColor": 4294967295,
        "textColor": 4278190080
      }
      ''';

      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final rawFontWeight = (map['fontWeight'] as num?)?.toDouble();
      final fontWeight =
          (rawFontWeight != null &&
              rawFontWeight >= 0.0 &&
              rawFontWeight <= 2.5)
          ? rawFontWeight
          : null;

      expect(fontWeight, equals(1.5));
    });

    test('sanitizes negative fontWeight to null', () {
      const rawJson = '''
      {
        "fontWeight": -0.5
      }
      ''';

      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final rawFontWeight = (map['fontWeight'] as num?)?.toDouble();
      final fontWeight =
          (rawFontWeight != null &&
              rawFontWeight >= 0.0 &&
              rawFontWeight <= 2.5)
          ? rawFontWeight
          : null;

      expect(fontWeight, isNull);
    });

    test('sanitizes legacy fontSize 120.0 to 1.2', () {
      const rawJson = '''
      {
        "fontSize": 120.0
      }
      ''';

      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final rawFontSize = (map['fontSize'] as num?)?.toDouble() ?? 1.0;
      final fontSize = rawFontSize > 10.0 ? rawFontSize / 100.0 : rawFontSize;

      expect(fontSize, equals(1.2));
    });
  });
}
