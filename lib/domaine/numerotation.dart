/// La numérotation des factures.
///
/// Le §2.18 de la note de service n° 2025-0889 tient en une phrase et
/// contraint tout : « référence unique par facture, série ascendante
/// ininterrompue par année de gestion » — et un duplicata garde le numéro
/// d'origine.
///
/// **Ininterrompue** est le mot qui décide de l'architecture. Une série sans
/// trou interdit d'attribuer un numéro à quelque chose qui pourrait ne jamais
/// devenir une facture. C'est pourquoi une vente au comptoir n'en reçoit
/// aucun : sur mille ventes de la journée, deux donneront lieu à une facture,
/// et numéroter les mille laisserait neuf cent quatre-vingt-dix-huit trous que
/// je ne saurais justifier devant un contrôleur.
///
/// Le numéro est donc attribué **au moment où la facture est émise**, et une
/// fois attribué il ne bouge plus.
library;

/// Une référence de facture, telle qu'elle s'imprime.
///
/// Trois éléments : le type de facture, l'année de gestion, et le rang dans
/// la série de cette année. `FV-2026-000042`.
class ReferenceFacture {
  /// L'étiquette du type de facture : `FV`, `FA`, `EV`…
  final String type;

  /// L'année de gestion. Ce n'est pas forcément l'année civile — un exercice
  /// peut être décalé — mais c'est le cas de tout le monde ici, et la note ne
  /// prévoit rien d'autre.
  final int annee;

  /// Le rang dans la série, à partir de 1.
  final int rang;

  const ReferenceFacture({
    required this.type,
    required this.annee,
    required this.rang,
  });

  /// Rangs sur six chiffres : une entreprise qui émet trois cents factures par
  /// jour tient l'année sans changer de format, et les références se trient
  /// alors dans l'ordre en tant que texte.
  String get texte =>
      '$type-$annee-${rang.toString().padLeft(6, '0')}';

  @override
  String toString() => texte;

  @override
  bool operator ==(Object other) =>
      other is ReferenceFacture &&
      other.type == type &&
      other.annee == annee &&
      other.rang == rang;

  @override
  int get hashCode => Object.hash(type, annee, rang);
}

/// Ce qui cloche dans une série de numéros.
///
/// Ces défauts ne devraient jamais arriver. Ils sont détectés quand même :
/// une série trouée est le premier reproche d'un contrôle, et je préfère
/// l'apprendre par un test que par une amende.
class SerieRompue implements Exception {
  final String message;
  const SerieRompue(this.message);

  @override
  String toString() => 'SerieRompue : $message';
}

/// Attribue les numéros de facture et vérifie la série.
///
/// Sans état propre : elle reçoit les rangs déjà attribués et rend le suivant.
/// C'est ce qui permet de la vérifier sans base, et de la rejouer depuis le
/// journal après une reconstruction.
class Numerotation {
  const Numerotation();

  /// L'année de gestion d'une date. L'année civile, faute d'exercice décalé
  /// à gérer — et le jour où il en faudra un, c'est ici qu'il se posera.
  static int anneeDe(DateTime quand) => quand.year;

  /// Le rang suivant dans la série d'une année.
  ///
  /// Un rang par facture, sans trou, à partir de 1. La série repart à 1 à
  /// chaque année de gestion : c'est ce que veut dire « par année de gestion ».
  int rangSuivant(Iterable<int> rangsAttribues) {
    var maximum = 0;
    for (final rang in rangsAttribues) {
      if (rang > maximum) maximum = rang;
    }
    return maximum + 1;
  }

  /// Vérifie qu'une série est complète et sans doublon.
  ///
  /// Rend la liste des rangs manquants, vide quand tout va bien. Sert au
  /// contrôle interne et à la démonstration d'homologation : montrer que la
  /// règle est tenue vaut mieux que l'affirmer.
  List<int> trous(Iterable<int> rangsAttribues) {
    final vus = <int>{};
    for (final rang in rangsAttribues) {
      if (rang < 1) {
        throw SerieRompue('Rang $rang : la série commence à 1.');
      }
      if (!vus.add(rang)) {
        throw SerieRompue('Rang $rang attribué deux fois.');
      }
    }
    if (vus.isEmpty) return const [];

    final dernier = vus.reduce((a, b) => a > b ? a : b);
    return [
      for (var rang = 1; rang <= dernier; rang++)
        if (!vus.contains(rang)) rang,
    ];
  }
}
