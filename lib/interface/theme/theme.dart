/// Thème de l'application.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'palette.dart';

/// Échelle typographique.
///
/// Les montants sont en chiffres tabulaires et en graisse lourde : ils
/// doivent se lire de loin, et ne pas sautiller quand ils changent.
TextTheme _typographie(Color encre, Color encreDouce) => TextTheme(
      displayLarge: TextStyle(
        fontSize: 56,
        height: 1.0,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.8,
        color: encre,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displayMedium: TextStyle(
        fontSize: 40,
        height: 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: encre,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: encre,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: encre,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: encre,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: encre),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: encreDouce),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: encre,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: encreDouce,
      ),
    );

ThemeData themeClair() {
  final base = ColorScheme.fromSeed(
    seedColor: Couleurs.primaire,
    brightness: Brightness.light,
  ).copyWith(
    primary: Couleurs.primaire,
    onPrimary: Colors.white,
    secondary: Couleurs.accent,
    error: Couleurs.alerte,
    surface: Couleurs.surface,
    onSurface: Couleurs.encre,
    outlineVariant: Couleurs.bordure,
  );

  return _assembler(
    schema: base,
    fond: Couleurs.fond,
    bordure: Couleurs.bordure,
    encre: Couleurs.encre,
    encreDouce: Couleurs.encreDouce,
  );
}

ThemeData themeSombre() {
  final base = ColorScheme.fromSeed(
    seedColor: Couleurs.primaire,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Couleurs.primaireVif,
    onPrimary: Colors.black,
    secondary: Couleurs.accent,
    error: Couleurs.alerte,
    surface: Couleurs.nuitSurface,
    onSurface: Couleurs.nuitEncre,
    outlineVariant: Couleurs.nuitBordure,
  );

  return _assembler(
    schema: base,
    fond: Couleurs.nuitFond,
    bordure: Couleurs.nuitBordure,
    encre: Couleurs.nuitEncre,
    encreDouce: const Color(0xFFA8A399),
  );
}

ThemeData _assembler({
  required ColorScheme schema,
  required Color fond,
  required Color bordure,
  required Color encre,
  required Color encreDouce,
}) {
  final typo = _typographie(encre, encreDouce);

  return ThemeData(
    useMaterial3: true,
    colorScheme: schema,
    scaffoldBackgroundColor: fond,
    // La police est embarquée, jamais chargée depuis le réseau : le rendu
    // doit être identique sur Android et sur iPhone, et fonctionner hors
    // ligne comme le reste de l'application.
    fontFamily: 'Outfit',
    textTheme: typo,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: fond,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: typo.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: schema.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rayon.m),
        side: BorderSide(color: bordure),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(cibleTactile),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rayon.m),
        ),
        textStyle: typo.labelLarge?.copyWith(fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(cibleTactile),
        side: BorderSide(color: bordure, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rayon.m),
        ),
        textStyle: typo.labelLarge,
      ),
    ),
    dividerTheme: DividerThemeData(color: bordure, space: 1, thickness: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: schema.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Rayon.xl)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
