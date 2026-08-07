/// Les fenêtres de temps que le rapport sait regarder.
///
/// Un commerçant ne consulte pas toujours son rapport le soir même. Il ouvre
/// l'application le lendemain matin en ouvrant sa boutique, et à ce
/// moment-là sa journée d'hier a disparu — c'est le genre de détail qui fait
/// croire que l'application a perdu les chiffres.
///
/// Les bornes vivent ici plutôt que dans l'écran : le rapport affiché et le
/// résumé envoyé au patron doivent couvrir exactement la même tranche de
/// temps, sinon les deux se contredisent.
library;

enum Periode {
  jour("Aujourd'hui", 'Journée du {debut}'),
  hier('Hier', 'Journée du {debut}'),
  semaine('7 jours', 'Du {debut} au {fin}'),
  mois('30 jours', 'Du {debut} au {fin}');

  /// Ce qu'affiche la pastille de sélection. Court : elles tiennent sur une
  /// ligne, côte à côte, sur un écran de téléphone d'entrée de gamme.
  final String libelle;

  /// Le gabarit de l'intitulé qui coiffe le résumé envoyé au patron.
  final String _intitule;

  const Periode(this.libelle, this._intitule);

  /// Début inclus, fin exclue, en journées entières.
  ///
  /// La fenêtre se ferme au prochain minuit et non à l'instant présent : la
  /// vente qu'on vient d'encaisser est justement celle que le commerçant
  /// cherche des yeux en ouvrant son rapport.
  (DateTime, DateTime) bornes([DateTime? maintenant]) {
    final reference = maintenant ?? DateTime.now();
    final minuit = DateTime(reference.year, reference.month, reference.day);
    final demain = minuit.add(const Duration(days: 1));

    return switch (this) {
      Periode.jour => (minuit, demain),
      Periode.hier => (minuit.subtract(const Duration(days: 1)), minuit),
      Periode.semaine => (minuit.subtract(const Duration(days: 6)), demain),
      Periode.mois => (minuit.subtract(const Duration(days: 29)), demain),
    };
  }

  /// La date qui date le résumé : le jour concerné, pas le jour d'envoi.
  DateTime dateDeReference([DateTime? maintenant]) => bornes(maintenant).$1;

  /// L'intitulé du résumé, dates comprises.
  String intitule([DateTime? maintenant]) {
    final (debut, fin) = bornes(maintenant);
    return _intitule
        .replaceAll('{debut}', _jour(debut))
        // La borne de fin est exclue : le dernier jour couvert est la veille.
        .replaceAll('{fin}', _jour(fin.subtract(const Duration(days: 1))));
  }

  static String _jour(DateTime date) =>
      '${_deuxChiffres(date.day)}/${_deuxChiffres(date.month)}/${date.year}';

  static String _deuxChiffres(int valeur) =>
      valeur < 10 ? '0$valeur' : '$valeur';
}
