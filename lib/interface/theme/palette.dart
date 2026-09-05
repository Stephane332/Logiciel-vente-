/// Jetons de design.
///
/// Deux contraintes dictent ces choix, et elles tirent dans le même sens :
/// l'application se lit **en plein soleil**, sur un marché, et tourne sur des
/// téléphones d'entrée de gamme. D'où un contraste élevé, des aplats plutôt
/// que des dégradés, et des ombres rares.
library;

import 'package:flutter/material.dart';

/// Couleurs.
///
/// Le vert profond évoque la croissance et l'argent, et fait un clin d'œil
/// discret au drapeau sans tomber dans la citation littérale. L'ambre sert
/// d'accent, le rouge d'alerte.
abstract final class Couleurs {
  // Vert — couleur principale
  static const primaire = Color(0xFF0E6B4A);
  static const primaireSombre = Color(0xFF08543A);
  static const primaireClair = Color(0xFFE8F3EE);
  static const primaireVif = Color(0xFF14A16E);

  // Ambre — accent, montants, actions positives
  static const accent = Color(0xFFF2A413);
  static const accentClair = Color(0xFFFEF3DC);

  // Rouge — dettes, alertes, suppressions
  static const alerte = Color(0xFFD1453B);
  static const alerteClair = Color(0xFFFDECEB);

  // Neutres, légèrement chauds — un gris froid paraît clinique au soleil
  static const encre = Color(0xFF1A1815);
  static const encreDouce = Color(0xFF6B655C);
  static const encreLegere = Color(0xFF9C968C);
  static const bordure = Color(0xFFE4E0D8);
  static const fond = Color(0xFFF7F5F1);
  static const surface = Color(0xFFFFFFFF);

  // Nuit
  static const nuitFond = Color(0xFF14130F);
  static const nuitSurface = Color(0xFF1F1D18);
  static const nuitBordure = Color(0xFF33302A);
  static const nuitEncre = Color(0xFFF5F3EF);

  /// Teintes des tuiles produit, quand l'article n'a pas de photo.
  ///
  /// La couleur est dérivée du nom : le même article garde toujours la même,
  /// ce qui permet de le reconnaître d'un coup d'œil sans savoir lire.
  static const tuiles = <Color>[
    Color(0xFF2D7D6B),
    Color(0xFFB4762A),
    Color(0xFF7A5AA8),
    Color(0xFFAF4B4B),
    Color(0xFF2E6FA3),
    Color(0xFF6E8B2F),
    Color(0xFFA8557E),
    Color(0xFF3F7A8C),
  ];

  static Color tuilePour(String texte) {
    var somme = 0;
    for (final unite in texte.codeUnits) {
      somme = (somme + unite) % 1000;
    }
    return tuiles[somme % tuiles.length];
  }
}

/// Espacements, sur une trame de 4.
abstract final class Espace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Rayons d'arrondi.
abstract final class Rayon {
  static const s = 10.0;
  static const m = 16.0;
  static const l = 22.0;
  static const xl = 28.0;
  static const rond = 999.0;
}

/// Durées d'animation.
///
/// Volontairement courtes : sur un téléphone lent, une animation longue est
/// perçue comme une lenteur de l'application, pas comme une élégance.
abstract final class Duree {
  static const eclair = Duration(milliseconds: 120);
  static const rapide = Duration(milliseconds: 200);
  static const moyenne = Duration(milliseconds: 320);
  static const lente = Duration(milliseconds: 480);
}

/// Courbes.
abstract final class Courbe {
  /// Départ franc, arrivée douce. C'est la courbe par défaut.
  static const sortie = Curves.easeOutCubic;

  /// Pour ce qui apparaît : léger dépassement, qui donne de la matière.
  static const rebond = Curves.easeOutBack;

  static const entree = Curves.easeInCubic;
}

/// Taille minimale d'une cible tactile.
///
/// 56 plutôt que les 48 habituels : l'application s'utilise debout, vite,
/// parfois les mains encombrées.
const double cibleTactile = 56.0;
