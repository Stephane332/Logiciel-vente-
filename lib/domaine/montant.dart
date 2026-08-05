/// Arithmétique monétaire exacte.
///
/// Aucun calcul d'argent ne passe par un flottant : les erreurs de
/// représentation binaire y sont inévitables et la DGI exige une égalité
/// stricte entre montant imposable, taxe et montant total (§6.7).
///
/// Les montants sont portés par des entiers en centimes — deux décimales,
/// comme l'impose le §6.1 — et les quantités par des entiers en millièmes,
/// soit trois décimales.
library;

/// Un montant, stocké en centimes.
class Montant implements Comparable<Montant> {
  final int centimes;

  const Montant(this.centimes);
  const Montant.zero() : centimes = 0;

  /// Construit un montant depuis une valeur décimale exprimée en unités.
  ///
  /// Réservé à la saisie et aux tests : arrondit à la valeur la plus
  /// proche, deux décimales au maximum (§6.2).
  factory Montant.depuisDecimal(num valeur) =>
      Montant(_arrondiProche(valeur * 100));

  static int _arrondiProche(num valeur) {
    // Arrondi à la valeur la plus proche, en s'éloignant de zéro à
    // mi-chemin. `round()` de Dart applique déjà cette règle.
    return valeur.round();
  }

  Montant operator +(Montant autre) => Montant(centimes + autre.centimes);
  Montant operator -(Montant autre) => Montant(centimes - autre.centimes);
  Montant operator -() => Montant(-centimes);

  bool get estNul => centimes == 0;
  bool get estNegatif => centimes < 0;
  bool get estPositif => centimes > 0;

  /// Multiplie par une quantité et arrondit à la valeur la plus proche (§6.2).
  Montant multiplieParQuantite(Quantite quantite) =>
      Montant(_diviseArrondi(centimes * quantite.milliemes, 1000));

  /// Applique un taux exprimé en millièmes (18 % vaut 180).
  ///
  /// L'arrondi se fait **à la valeur supérieure**, conformément au §6.7 qui
  /// impose que montant imposable + taxe égale exactement le montant total.
  Montant appliqueTauxArrondiSuperieur(int tauxMillieme) =>
      Montant(_diviseArrondiSuperieur(centimes * tauxMillieme, 1000));

  /// Applique un taux exprimé en dix-millièmes, pour le PSVB (§2.16).
  Montant appliqueTauxDixMillieme(int taux) =>
      Montant(_diviseArrondi(centimes * taux, 10000));

  /// Extrait la part de taxe contenue dans un montant toutes taxes comprises.
  ///
  /// En mode TTC, le montant imposable se déduit du montant total du groupe
  /// (§6.6). La taxe est arrondie à la valeur supérieure (§6.7), et le
  /// montant imposable s'obtient ensuite par différence, ce qui garantit
  /// l'égalité exacte.
  Montant taxeIncluseArrondiSuperieur(int tauxMillieme) =>
      Montant(_diviseArrondiSuperieur(
          centimes * tauxMillieme, 1000 + tauxMillieme));

  /// Division entière avec arrondi à la valeur la plus proche.
  static int _diviseArrondi(int numerateur, int denominateur) {
    if (numerateur == 0) return 0;
    final negatif = (numerateur < 0) != (denominateur < 0);
    final n = numerateur.abs();
    final d = denominateur.abs();
    final resultat = (n + d ~/ 2) ~/ d;
    return negatif ? -resultat : resultat;
  }

  /// Division entière avec arrondi à la valeur supérieure en valeur absolue.
  ///
  /// Le signe est préservé : un avoir doit s'arrondir dans le même sens
  /// qu'une facture de vente, sans quoi une correction ne compenserait pas
  /// exactement la facture d'origine.
  static int _diviseArrondiSuperieur(int numerateur, int denominateur) {
    if (numerateur == 0) return 0;
    final negatif = (numerateur < 0) != (denominateur < 0);
    final n = numerateur.abs();
    final d = denominateur.abs();
    final resultat = (n + d - 1) ~/ d;
    return negatif ? -resultat : resultat;
  }

  @override
  int compareTo(Montant autre) => centimes.compareTo(autre.centimes);

  @override
  bool operator ==(Object other) =>
      other is Montant && other.centimes == centimes;

  @override
  int get hashCode => centimes.hashCode;

  /// Représentation en francs CFA, sans décimales.
  ///
  /// Le franc CFA n'a pas de subdivision en circulation : les décimales
  /// servent au calcul, jamais à l'affichage.
  String get enFrancs {
    final francs = _diviseArrondi(centimes, 100);
    final texte = francs.abs().toString();
    final groupes = <String>[];
    for (var i = texte.length; i > 0; i -= 3) {
      groupes.insert(0, texte.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${francs < 0 ? '-' : ''}${groupes.join(' ')} F';
  }

  @override
  String toString() {
    final signe = centimes < 0 ? '-' : '';
    final abs = centimes.abs();
    return '$signe${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }
}

/// Une quantité, stockée en millièmes — trois décimales (§6.1).
class Quantite implements Comparable<Quantite> {
  final int milliemes;

  const Quantite(this.milliemes);
  const Quantite.zero() : milliemes = 0;

  /// Une quantité entière d'unités.
  const Quantite.unites(int unites) : milliemes = unites * 1000;

  factory Quantite.depuisDecimal(num valeur) =>
      Quantite((valeur * 1000).round());

  Quantite operator +(Quantite autre) => Quantite(milliemes + autre.milliemes);
  Quantite operator -(Quantite autre) => Quantite(milliemes - autre.milliemes);

  bool get estNulle => milliemes == 0;
  bool get estNegative => milliemes < 0;

  @override
  int compareTo(Quantite autre) => milliemes.compareTo(autre.milliemes);

  @override
  bool operator ==(Object other) =>
      other is Quantite && other.milliemes == milliemes;

  @override
  int get hashCode => milliemes.hashCode;

  @override
  String toString() {
    if (milliemes % 1000 == 0) return (milliemes ~/ 1000).toString();
    final signe = milliemes < 0 ? '-' : '';
    final abs = milliemes.abs();
    final decimales =
        (abs % 1000).toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '');
    return '$signe${abs ~/ 1000},$decimales';
  }
}
