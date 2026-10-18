// Widget tests for Finbuk Jellyfin Client
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:finbuk/main.dart';
import 'package:finbuk/providers/auth_provider.dart';
import 'package:finbuk/providers/theme_provider.dart';
import 'package:finbuk/providers/music_player_provider.dart';
import 'package:finbuk/providers/homepage_provider.dart';

void main() {
  group('FinbukApp Smoke Tests', () {
    testWidgets('App starts without crashing', (WidgetTester tester) async {
      // Build our app with the same provider setup as main.dart
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => MusicPlayerProvider()),
            ChangeNotifierProvider(create: (_) => HomepageProvider()),
          ],
          child: const FinbukApp(),
        ),
      );

      // Allow any async initialization to complete
      await tester.pumpAndSettle();

      // Verify that the app renders with MaterialApp
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('App has correct title', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => MusicPlayerProvider()),
            ChangeNotifierProvider(create: (_) => HomepageProvider()),
          ],
          child: const FinbukApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Check that MaterialApp has the correct title
      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.title, equals('Finbuk Jellyfin Client'));
    });

    testWidgets('App has theme configured', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => MusicPlayerProvider()),
            ChangeNotifierProvider(create: (_) => HomepageProvider()),
          ],
          child: const FinbukApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that MaterialApp is present with theme
      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.theme, isNotNull);
      expect(app.darkTheme, isNotNull);
    });
  });
}
