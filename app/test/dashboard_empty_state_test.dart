import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emolens/features/dashboard/dashboard_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Dashboard Empty State Widget Test', () {
    testWidgets('shows setup card when no camera IP configured', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      // Wait for settings to load with a finite pump
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // Should show the no-camera setup card
      expect(find.text('Camera Not Configured'), findsOneWidget);
      expect(find.text('Go to Settings'), findsOneWidget);
      expect(find.text('EmoLens'), findsOneWidget);
    });

    testWidgets('shows settings button in AppBar', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byIcon(Icons.settings_rounded), findsWidgets);
    });

    testWidgets('shows EmoLens in app bar title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('EmoLens'), findsOneWidget);
    });
  });
}

