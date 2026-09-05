/// Encaissement par mobile money, sans aucune API payante.
///
/// Le principe tient en une phrase : c'est l'opérateur qui fait le travail.
/// Mon logiciel se contente de composer le code marchand déjà rempli, et de
/// le présenter sous deux formes — un code QR que le client scanne avec son
/// appareil photo, et le code écrit en grand pour ceux qui le tapent.
///
/// Le client n'installe rien. Le commerçant ne paie aucun abonnement. Le jour
/// où j'aurai du volume, je négocierai un contrat direct avec l'opérateur ;
/// d'ici là, cette voie coûte zéro franc et marche sur tous les téléphones.
///
/// Les codes viennent du terrain, pas d'une documentation : je les ai relevés
/// sur des comptes réels. Ils sont donc à revérifier périodiquement — un
/// opérateur peut changer sa syntaxe sans prévenir personne.
library;

import 'montant.dart';
import 'telephone.dart';

/// Un opérateur de mobile money burkinabè.
enum OperateurMobile {
  /// Orange Money — de loin le plus répandu ici.
  ///
  /// `*144*10*<numéro>*<montant>#` est le code de paiement marchand. Il exige
  /// que le commerçant ait ouvert un **compte marchand** : sur un compte
  /// ordinaire, il subit les frais de transfert entre particuliers.
  orange('Orange Money', 'Orange', '*144*10*{numero}*{montant}#'),

  moov('Moov Money', 'Moov', '*555*{numero}*{montant}#'),

  telecel('Telecel Money', 'Telecel', '*800*{numero}*{montant}#');

  final String nom;

  /// Nom court, pour les boutons étroits.
  final String abrege;

  /// Modèle du code marchand. `{numero}` et `{montant}` sont substitués.
  final String modele;

  const OperateurMobile(this.nom, this.abrege, this.modele);

  /// Le code USSD complet, prêt à être composé.
  ///
  /// Le montant part en francs entiers : aucun opérateur d'ici n'accepte de
  /// centimes, et un code refusé au comptoir fait perdre la vente.
  String code({required String numero, required Montant montant}) {
    final national = normaliserTelephone(numero);
    if (national == null) {
      throw ArgumentError('Numéro marchand invalide : $numero');
    }
    if (!montant.estPositif) {
      throw ArgumentError('Un encaissement porte sur un montant positif.');
    }

    return modele
        .replaceAll('{numero}', national)
        .replaceAll('{montant}', '${montant.centimes ~/ 100}');
  }

  /// Le lien que comprend le composeur du téléphone.
  ///
  /// Le `#` doit impérativement être encodé en `%23`, sans quoi le composeur
  /// tronque le code à cet endroit et le client compose un code incomplet.
  ///
  /// Testé sur Android et sur iPhone : dans les deux cas le composeur s'ouvre
  /// déjà rempli. Ce qui n'existe pas sur iPhone, c'est la lecture
  /// automatique de la réponse — mais ça, c'est le problème du commerçant,
  /// pas celui du client qui paie.
  String lienComposeur({required String numero, required Montant montant}) =>
      'tel:${Uri.encodeComponent(code(numero: numero, montant: montant))}';
}

/// Ce que le commerçant a configuré pour se faire payer.
///
/// Un numéro par opérateur : beaucoup de commerçants ont un compte Orange et
/// un compte Moov, et pas forcément sur la même puce.
class ComptesMarchands {
  final Map<OperateurMobile, String> numeros;

  const ComptesMarchands(this.numeros);

  const ComptesMarchands.aucun() : numeros = const {};

  String? numeroDe(OperateurMobile operateur) => numeros[operateur];

  bool aUnCompte(OperateurMobile operateur) =>
      normaliserTelephone(numeros[operateur]) != null;

  /// Les opérateurs réellement utilisables, dans l'ordre habituel.
  ///
  /// Inutile de proposer Telecel à un commerçant qui n'y a pas de compte :
  /// il afficherait un code qui ne le paierait pas.
  List<OperateurMobile> get disponibles =>
      OperateurMobile.values.where(aUnCompte).toList();

  bool get estVide => disponibles.isEmpty;
}
