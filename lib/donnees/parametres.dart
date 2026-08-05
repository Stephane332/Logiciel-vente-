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

  /// Nom affiché en tête des documents, faute de fiche entreprise.
  static const nomCommerceParDefaut = 'Ma boutique';

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

    return Reglage(
      nomCommerce: valeurs[_nomCommerce] ?? nomCommerceParDefaut,
      comptes: ComptesMarchands(comptes),
    );
  }

  Future<void> definirNomCommerce(String nom) =>
      _ecrire(_nomCommerce, nom.trim());

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
      await (base.delete(base.reglages)..where((r) => r.cle.equals(cle))).go();
      return;
    }
    await _ecrire(cle, normalise);
  }

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

  const Reglage({required this.nomCommerce, required this.comptes});

  /// Vrai tant que le commerçant ne peut pas encore encaisser par téléphone.
  bool get mobileMoneyAConfigurer => comptes.estVide;
}
