/// Le montant en toutes lettres.
///
/// Le §3 de la note de service n° 2025-0889 range le **montant total en
/// lettres** parmi les mentions obligatoires de la facture. Ce n'est pas une
/// coquetterie administrative : c'est ce qui empêche d'ajouter un zéro sur un
/// papier signé, et c'est pour ça que les chèques le portent aussi.
///
/// L'orthographe retenue est la traditionnelle — « vingt et un », « soixante
/// et onze » — et non celle de 1990. C'est celle qu'on lit sur les documents
/// administratifs d'ici, et une facture n'est pas l'endroit où défendre une
/// réforme.
library;

import 'montant.dart';

const _unites = [
  'zéro',
  'un',
  'deux',
  'trois',
  'quatre',
  'cinq',
  'six',
  'sept',
  'huit',
  'neuf',
  'dix',
  'onze',
  'douze',
  'treize',
  'quatorze',
  'quinze',
  'seize',
  'dix-sept',
  'dix-huit',
  'dix-neuf',
];

const _dizaines = {
  2: 'vingt',
  3: 'trente',
  4: 'quarante',
  5: 'cinquante',
  6: 'soixante',
};

/// Un montant en toutes lettres, suivi de sa devise.
///
/// Le franc CFA n'a pas de subdivision en circulation, mais les sommes sont
/// tenues en centimes dans toute l'application. Les centimes n'apparaissent
/// donc que s'il y en a — et s'il y en a sur une facture, c'est en soi une
/// information utile.
String montantEnLettres(Montant montant, {String devise = 'francs CFA'}) {
  final negatif = montant.centimes < 0;
  final absolu = negatif ? -montant.centimes : montant.centimes;

  final francs = absolu ~/ 100;
  final centimes = absolu % 100;

  final mots = StringBuffer();
  if (negatif) mots.write('moins ');
  mots
    ..write(entierEnLettres(francs))
    ..write(' ')
    ..write(devise);

  if (centimes > 0) {
    mots
      ..write(' et ')
      ..write(entierEnLettres(centimes))
      ..write(centimes > 1 ? ' centimes' : ' centime');
  }

  return mots.toString();
}

/// Un entier en toutes lettres.
///
/// Séparé de [montantEnLettres] parce qu'il se vérifie seul : c'est là que
/// sont les règles pénibles du français, et c'est là que se trouvent les
/// fautes.
String entierEnLettres(int nombre) {
  if (nombre < 0) return 'moins ${entierEnLettres(-nombre)}';
  return _composer(nombre);
}

String _composer(int nombre) {
  if (nombre < 20) return _unites[nombre];
  if (nombre < 100) return _sousCent(nombre);
  if (nombre < 1000) return _sousMille(nombre);

  for (final palier in _paliers) {
    if (nombre >= palier.valeur * 1000) continue;

    final combien = nombre ~/ palier.valeur;
    final reste = nombre % palier.valeur;
    final tete = palier.tete(combien);
    return reste == 0 ? tete : '$tete ${_composer(reste)}';
  }

  // Au-delà du billion, aucune facture ne va. Le rendre en chiffres vaut
  // mieux qu'un mot inventé.
  return nombre.toString();
}

String _sousMille(int nombre) {
  final centaines = nombre ~/ 100;
  final reste = nombre % 100;

  // « cent » sans « un » devant.
  if (centaines == 1) {
    return reste == 0 ? 'cent' : 'cent ${_sousCent(reste)}';
  }

  final tete = '${_unites[centaines]} cent';
  // « cents » au pluriel seulement quand rien ne le suit : deux cents, mais
  // deux cent un.
  return reste == 0 ? '${tete}s' : '$tete ${_sousCent(reste)}';
}

String _sousCent(int nombre) {
  if (nombre < 20) return _unites[nombre];

  final dizaine = nombre ~/ 10;
  final unite = nombre % 10;

  // 70 à 79 et 90 à 99 se construisent sur soixante et quatre-vingt, avec le
  // reste compté à partir de dix : soixante-quinze, quatre-vingt-dix-sept.
  if (dizaine == 7 || dizaine == 9) {
    final base = dizaine == 7 ? 'soixante' : 'quatre-vingt';
    final reste = nombre - (dizaine == 7 ? 60 : 80);
    // Seul soixante et onze prend le « et » ; quatre-vingt-onze ne le prend
    // pas, parce que quatre-vingt n'est pas une dizaine simple.
    if (reste == 11 && dizaine == 7) return 'soixante et onze';
    return '$base-${_unites[reste]}';
  }

  if (dizaine == 8) {
    // « quatre-vingts » au pluriel quand rien ne suit, singulier sinon.
    return unite == 0 ? 'quatre-vingts' : 'quatre-vingt-${_unites[unite]}';
  }

  final base = _dizaines[dizaine]!;
  if (unite == 0) return base;
  // « et un » : vingt et un, trente et un… jusqu'à soixante et un.
  if (unite == 1) return '$base et un';
  return '$base-${_unites[unite]}';
}

/// Retire la marque du pluriel de « cents » et « quatre-vingts » en fin de
/// nombre.
///
/// C'est la règle qui piège tout le monde : **cent** et **vingt** ne prennent
/// le *s* que si rien ne les suit. « mille » est un adjectif numéral, il
/// compte comme quelque chose qui suit — d'où « deux cent mille » et
/// « quatre-vingt mille ». « million » et « milliard » sont des noms, ils ne
/// comptent pas — d'où « deux cents millions ».
String _sansPluriel(String mots) {
  if (mots.endsWith('cents')) {
    return mots.substring(0, mots.length - 1);
  }
  if (mots.endsWith('quatre-vingts')) {
    return mots.substring(0, mots.length - 1);
  }
  return mots;
}

/// Un palier de grands nombres, avec sa règle d'accord.
class _Palier {
  final int valeur;
  final String singulier;

  /// « mille » est invariable et ne prend jamais de *s* ; million et milliard
  /// en prennent un au pluriel.
  final bool invariable;

  const _Palier(this.valeur, this.singulier, {this.invariable = false});

  String tete(int combien) {
    if (invariable) {
      // « mille », pas « un mille ».
      if (combien == 1) return singulier;
      return '${_sansPluriel(_composer(combien))} $singulier';
    }
    final mot = combien > 1 ? '${singulier}s' : singulier;
    return '${_composer(combien)} $mot';
  }
}

const _paliers = [
  _Palier(1000, 'mille', invariable: true),
  _Palier(1000000, 'million'),
  _Palier(1000000000, 'milliard'),
];
