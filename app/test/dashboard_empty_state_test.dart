import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emolens/features/dashboard/dashboard_screen.dart';

void main() {
  group('Dashboard Empty State Widget Test', () {
    testWidgets('shows setup card when no camera IP configured', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      // Wait for settings to load
      await tester.pumpAndSettle();

      // Should show the no-camera setup card
      expect(find.text('Camera Not Configured'), findsOneWidget);
      expect(find.text('Go to Settings'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);
    });

    testWidgets('shows settings button in AppBar', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(find.text('EmoLens'), findsOneWidget);
    });
  });
}

