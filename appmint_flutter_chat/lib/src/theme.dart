import 'package:flutter/material.dart';

/// Colours and shapes the chat draws with. Each app passes its own so the
/// screen looks native there; the defaults are a quiet neutral set.
class AppmintChatTheme {
  final Color accent; // my bubbles, send button
  final Color onAccent;
  final Color background;
  final Color surface; // their bubbles, composer
  final Color text;
  final Color muted;
  final Color line;
  final Color success;
  final Color danger;
  final double radius;
  final String? fontFamily;

  const AppmintChatTheme({
    this.accent = const Color(0xFF2F5D50),
    this.onAccent = Colors.white,
    this.background = const Color(0xFFF7F6F2),
    this.surface = Colors.white,
    this.text = const Color(0xFF1E1E1C),
    this.muted = const Color(0xFF6F6F6A),
    this.line = const Color(0xFFE3E1DA),
    this.success = const Color(0xFF3A7D5C),
    this.danger = const Color(0xFFB4413A),
    this.radius = 18,
    this.fontFamily,
  });

  /// Derive one from the app's Material theme when nothing custom is wanted.
  factory AppmintChatTheme.fromMaterial(ThemeData t) => AppmintChatTheme(
        accent: t.colorScheme.primary,
        onAccent: t.colorScheme.onPrimary,
        background: t.scaffoldBackgroundColor,
        surface: t.colorScheme.surface,
        text: t.colorScheme.onSurface,
        muted: t.colorScheme.onSurface.withValues(alpha: .6),
        line: t.dividerColor,
        fontFamily: t.textTheme.bodyMedium?.fontFamily,
      );

  AppmintChatTheme copyWith({
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? surface,
    Color? text,
    Color? muted,
    Color? line,
    Color? success,
    Color? danger,
    double? radius,
    String? fontFamily,
  }) =>
      AppmintChatTheme(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        success: success ?? this.success,
        danger: danger ?? this.danger,
        radius: radius ?? this.radius,
        fontFamily: fontFamily ?? this.fontFamily,
      );
}
