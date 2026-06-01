// lib/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class QueueTheme {
  // Cores principais
  static const Color bg = Color(0xFF080C14);
  static const Color bgCard = Color(0xFF0D1420);
  static const Color bgElevated = Color(0xFF111927);
  static const Color border = Color(0xFF1E2D42);
  static const Color borderBright = Color(0xFF2A3F5E);

  // Accent — Amber elétrico
  static const Color amber = Color(0xFFF5A623);
  static const Color amberDim = Color(0x33F5A623);
  static const Color amberGlow = Color(0x15F5A623);

  // Accent secundário — Azul elétrico
  static const Color blue = Color(0xFF1A8FFF);
  static const Color blueDim = Color(0x331A8FFF);

  // Status
  static const Color calling = Color(0xFFF5A623);  // Amber — a chamar
  static const Color serving = Color(0xFF1A8FFF);   // Azul — a atender
  static const Color waiting = Color(0xFF4A6580);   // Cinza — a aguardar

  // Texto
  static const Color textPrimary = Color(0xFFF0F4F8);
  static const Color textSecondary = Color(0xFF8EA8C3);
  static const Color textMuted = Color(0xFF4A6580);

  // Success / error
  static const Color green = Color(0xFF22C55E);
  static const Color red = Color(0xFFEF4444);

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          background: bg,
          surface: bgCard,
          primary: amber,
          secondary: blue,
        ),
        textTheme: GoogleFonts.spaceGroteskTextTheme(
          const TextTheme(
            displayLarge: TextStyle(color: textPrimary),
            bodyLarge: TextStyle(color: textPrimary),
          ),
        ),
      );

  // Tipografia
  static TextStyle get ticketHero => GoogleFonts.spaceMono(
        fontSize: 96,
        fontWeight: FontWeight.w700,
        color: amber,
        letterSpacing: 8,
        height: 1.0,
      );

  static TextStyle get ticketLarge => GoogleFonts.spaceMono(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: 4,
      );

  static TextStyle get ticketMedium => GoogleFonts.spaceMono(
        fontSize: 32,
        fontWeight: FontWeight.w500,
        color: textSecondary,
        letterSpacing: 2,
      );

  static TextStyle get label => GoogleFonts.spaceGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textMuted,
        letterSpacing: 2,
      );

  static TextStyle get labelBright => GoogleFonts.spaceGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: amber,
        letterSpacing: 2,
      );

  static TextStyle get heading => GoogleFonts.spaceGrotesk(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: 0.5,
      );

  static TextStyle get body => GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextStyle get counterName => GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: blue,
        letterSpacing: 1,
      );
}
