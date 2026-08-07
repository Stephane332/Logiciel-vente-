/// Les réglages de la boutique.
///
/// Tout est réglable, rien n'est obligatoire : l'application doit encaisser
/// dès la première seconde, sans qu'on ait rempli quoi que ce soit. Un
/// commerçant qui doit configurer avant de vendre est un commerçant qui
/// n'ouvrira pas l'application une deuxième fois.
///
/// Les valeurs sont donc toutes facultatives, et chacune a un repli qui tient
/// debout tout seul.
library;

import '../domaine/mobile_money.dart';
import '../domaine/telephone.dart';
import 'base.dart';

class Parametres {
  final BaseLocale base;

  Parametres(this.base);

  static const _nomCommerce = 'commerce.nom';
  static const _prefixeMarchand = 'marchand.';
  static const _vendeurs = 'vendeurs';
  static const _vendeurActif = 'vendeur.actif';

  /// Nom affiché en tête des documents, faute de fiche entreprise.
  static const nomCommerceParDefaut = 'Ma boutique';

  /// Ce qui sépare deux noms de vendeurs dans la valeur enregistrée. Un nom
  /// qui en contiendrait un couperait la liste en deux : il est retiré à
  /// l'écriture.
  static const _separateur = '\n';

  /// Tous les réglages d'un coup.
  ///
  /// Lus en une seule requête au démarrage, puis gardés en mémoire : ce sont
  /// quelques lignes qui ne changent presque jamais.
  Future<Reglage> tout() async {
    final lignes = await base.select(base.reglages).get();
    final valeurs = {for (final l in lignes) l.cle: l.valeur};

    final comptes = <OperateurMobile, String>{};
    for (final operateur in OperateurMobile.values) {
      final numero = valeurs['$_prefixeMarchand${operateur.name}'];
      if (numero != null) comptes[operateur] = numero;
    }

    final vendeurs = _decouper(valeurs[_vendeurs]);
    final actif = valeurs[_vendeurActif];

    return Reglage(
      nomCommerce: valeurs[_nomCommerce] ?? nomCommerceParDefaut,
      comptes: ComptesMarchands(comptes),
      vendeurs: vendeurs,
      // Un vendeur retiré de la liste ne tient plus la caisse : sans ce
      // filtre, son nom continuerait de s'écrire sur les ventes après son
      // départ, et le rapport accuserait quelqu'un qui n'était plus là.
      vendeurActif: vendeurs.contains(actif) ? actif : null,
    );
  }

  Future<void> definirNomCommerce(String nom) =>
      _ecrire(_nomCommerce, nom.trim());

  /// Qui peut tenir la caisse.
  ///
  /// Vide tant que le commerçant est seul, et c'est le cas le plus fréquent :
  /// rien ne s'affiche alors, et les ventes ne sont attribuées à personne.
  /// Mieux vaut pas de nom du tout qu'un nom faux dans le rapport.
  Future<void> definirVendeurs(List<String> noms) async {
    final propres = <String>[];
    for (final nom in noms) {
      final propre = nom.replaceAll(_separateur, ' ').trim();
      if (propre.isNotEmpty && !propres.contains(propre)) propres.add(propre);
    }

    if (propres.isEmpty) {
      await _effacer(_vendeurs);
      // Plus personne dans la liste : plus personne à la caisse non plus.
      await _effacer(_vendeurActif);
      return;
    }
    await _ecrire(_vendeurs, propres.join(_separateur));
  }

  /// Qui la tient en ce moment. Nul quand la vente n'est attribuée à personne.
  Future<void> definirVendeurActif(String? nom) async {
    final propre = nom?.trim() ?? '';
    if (propre.isEmpty) {
      await _effacer(_vendeurActif);
      return;
    }
    await _ecrire(_vendeurActif, propre);
  }

  static List<String> _decouper(String? valeur) {
    if (valeur == null) return const [];
    return [
      for (final nom in valeur.split(_separateur))
        if (nom.trim().isNotEmpty) nom.trim()
    ];
  }

  /// Enregistre — ou efface — le numéro marchand d'un opérateur.
  ///
  /// Un numéro invalide est refusé plutôt que rangé : mieux vaut un opérateur
  /// absent de la liste qu'un code QR qui ne paie personne.
  Future<void> definirNumeroMarchand(
    OperateurMobile operateur,
    String? numero,
  ) async {
    final cle = '$_prefixeMarchand${operateur.name}';
    final normalise = normaliserTelephone(numero);

    if (normalise == null) {
      await _effacer(cle);
      return;
    }
    await _ecrire(cle, normalise);
  }

  Future<void> _effacer(String cle) =>
      (base.delete(base.reglages)..where((r) => r.cle.equals(cle))).go();

  Future<void> _ecrire(String cle, String valeur) =>
      base.into(base.reglages).insertOnConflictUpdate(
            ReglagesCompanion.insert(
              cle: cle,
              valeur: valeur,
              modifieLe: DateTime.now(),
            ),
          );
}

/// L'état courant des réglages.
class Reglage {
  final String nomCommerce;
  final ComptesMarchands comptes;

  /// Les noms qui peuvent tenir la caisse. Vide quand le commerçant est seul.
  final List<String> vendeurs;

  /// Qui la tient en ce moment, s'il y a quelqu'un.
  final String? vendeurActif;

  const Reglage({
    required this.nomCommerce,
    required this.comptes,
    this.vendeurs = const [],
    this.vendeurActif,
  });

  /// Vrai tant que le commerçant ne peut pas encore encaisser par téléphone.
  bool get mobileMoneyAConfigurer => comptes.estVide;

  /// Vrai dès qu'il y a quelqu'un d'autre que le patron derrière le comptoir,
  /// donc dès qu'il faut savoir qui a encaissé.
  bool get equipe => vendeurs.isNotEmpty;

  /// Une équipe déclarée, mais personne de choisi : les ventes partiraient
  /// sans nom alors que le patron attend un compte par vendeur.
  bool get vendeurAChoisir => equipe && vendeurActif == null;
}
