import 'package:flutter/material.dart';

/// Calm, accessible dark theme colors for EmoLens.
/// Soft blue/purple accents on dark backgrounds with high contrast text.
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color cardBackground = Color(0xFF1C2128);
  static const Color inputBackground = Color(0xFF21262D);

  // Accent colors
  static const Color primary = Color(0xFF7C8DFF); // Soft blue-purple
  static const Color secondary = Color(0xFF9B6DFF); // Softer purple
  static const Color accent = Color(0xFF58A6FF); // Sky blue

  // Status / emotion colors
  static const Color happy = Color(0xFF56D364); // Soft green
  static const Color neutral = Color(0xFFF0C75E); // Warm amber
  static const Color sad = Color(0xFFF47067); // Soft coral red
  static const Color error = Color(0xFFF85149);

  // Connection status
  static const Color connected = Color(0xFF56D364);
  static const Color connecting = Color(0xFFF0C75E);
  static const Color offline = Color(0xFFF85149);
  static const Color disconnected = Color(0xFFF85149);

  // Text
  static const Color textPrimary = Color(0xFFF0F6FC);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textTertiary = Color(0xFF6E7681);

  // Borders
  static const Color border = Color(0xFF30363D);

  /// Returns the color for a given emotion label.
  static Color emotionColor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return happy;
      case 'sad':
        return sad;
      case 'neutral':
      default:
        return neutral;
    }
  }

  /// Returns the emoji for a given emotion label.
  static String emotionEmoji(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'neutral':
      default:
        return '😐';
    }
  }
}
