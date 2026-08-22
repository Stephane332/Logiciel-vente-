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

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domaine/fiche_entreprise.dart';
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
  static const _temoin = 'stockage.temoin';
  static const _derniereSauvegarde = 'sauvegarde.derniere';
  static const _codePatron = 'patron.code';

  /// Les mentions de la fiche entreprise. Une clé par mention plutôt qu'un
  /// bloc JSON : ça s'ajoute et ça se retire sans migration, et une valeur
  /// abîmée n'emporte pas les autres.
  static const _raisonSociale = 'entreprise.raison';
  static const _ifu = 'entreprise.ifu';
  static const _cadastre = 'entreprise.cadastre';
  static const _adresse = 'entreprise.adresse';
  static const _telephone = 'entreprise.telephone';
  static const _courriel = 'entreprise.courriel';
  static const _regime = 'entreprise.regime';
  static const _serviceImpots = 'entreprise.service';
  static const _banque = 'entreprise.banque';

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

    final nomCommerce = valeurs[_nomCommerce] ?? nomCommerceParDefaut;

    return Reglage(
      nomCommerce: nomCommerce,
      comptes: ComptesMarchands(comptes),
      vendeurs: vendeurs,
      // Un vendeur retiré de la liste ne tient plus la caisse : sans ce
      // filtre, son nom continuerait de s'écrire sur les ventes après son
      // départ, et le rapport accuserait quelqu'un qui n'était plus là.
      vendeurActif: vendeurs.contains(actif) ? actif : null,
      mentions: FicheEntreprise(
        nomCommercial: nomCommerce,
        raisonSociale: valeurs[_raisonSociale],
        // L'IFU est renormalisé à la lecture, pas seulement à l'écriture :
        // une sauvegarde restaurée peut venir d'une version qui validait
        // autrement, et une facture ne doit pas porter une forme fausse.
        ifu: Ifu.normaliser(valeurs[_ifu]),
        cadastre: ReferenceCadastrale.analyser(valeurs[_cadastre]),
        adresse: valeurs[_adresse],
        telephone: valeurs[_telephone],
        courriel: valeurs[_courriel],
        regime: RegimeImposition.parEtiquette(valeurs[_regime]),
        serviceImpots: valeurs[_serviceImpots],
        referencesBancaires: valeurs[_banque],
      ),
    );
  }

  /// Enregistre la fiche entreprise.
  ///
  /// Chaque mention vide **efface** sa clé plutôt que d'écrire une chaîne
  /// vide : une facture doit pouvoir dire « cette mention manque », et une
  /// chaîne vide se lirait comme une mention remplie avec rien.
  ///
  /// L'IFU et les références cadastrales ne sont enregistrés que s'ils ont la
  /// bonne forme. Une saisie fausse n'est pas rangée à moitié : elle est
  /// refusée, et l'écran la garde sous les yeux du commerçant avec ce qui
  /// cloche.
  Future<void> definirFiche(FicheEntreprise fiche) async {
    await definirNomCommerce(fiche.nomCommercial);
    await _ecrireOuEffacer(_raisonSociale, fiche.raisonSociale);
    await _ecrireOuEffacer(_ifu, Ifu.normaliser(fiche.ifu));
    await _ecrireOuEffacer(_cadastre, fiche.cadastre?.compact);
    await _ecrireOuEffacer(_adresse, fiche.adresse);
    await _ecrireOuEffacer(_telephone, fiche.telephone);
    await _ecrireOuEffacer(_courriel, fiche.courriel);
    await _ecrireOuEffacer(_regime, fiche.regime?.etiquette);
    await _ecrireOuEffacer(_serviceImpots, fiche.serviceImpots);
    await _ecrireOuEffacer(_banque, fiche.referencesBancaires);
  }

  Future<void> _ecrireOuEffacer(String cle, String? valeur) {
    final propre = valeur?.trim() ?? '';
    return propre.isEmpty ? _effacer(cle) : _ecrire(cle, propre);
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

  /// Le témoin de stockage : la preuve qu'une session précédente a survécu.
  ///
  /// Il ne sert que dans un navigateur, où l'on ne peut pas savoir d'avance
  /// si ce qu'on écrit sera relu. On dépose une marque au premier lancement ;
  /// si on la retrouve au suivant, c'est que le stockage tient. Une promesse
  /// du navigateur ne vaut rien — celle de drift disait « persistant » alors
  /// que rien n'était écrit.
  Future<bool> temoinRetrouve() async {
    final ligne = await (base.select(base.reglages)
          ..where((r) => r.cle.equals(_temoin)))
        .getSingleOrNull();
    if (ligne == null) {
      await _ecrire(_temoin, DateTime.now().toIso8601String());
      return false;
    }
    return true;
  }

  /// Quand le carnet est sorti du téléphone pour la dernière fois.
  ///
  /// Nul tant que ça n'est jamais arrivé — et c'est le cas le plus inquiétant,
  /// pas une absence de donnée sans importance.
  Future<DateTime?> derniereSauvegarde() async {
    final ligne = await (base.select(base.reglages)
          ..where((r) => r.cle.equals(_derniereSauvegarde)))
        .getSingleOrNull();
    if (ligne == null) return null;
    return DateTime.tryParse(ligne.valeur);
  }

  /// À appeler quand le fichier est **sorti** du téléphone, pas quand il est
  /// composé : une sauvegarde qui reste sur l'appareil disparaît avec lui, et
  /// noter celle-là éteindrait le rappel sans rien protéger.
  Future<void> noterSauvegarde([DateTime? quand]) =>
      _ecrire(_derniereSauvegarde, (quand ?? DateTime.now()).toIso8601String());

  /// Vrai quand un code patron a été posé.
  ///
  /// Il ne protège qu'une chose : **les numéros marchands**. C'est le seul
  /// réglage qui déplace de l'argent — un caissier qui y met le sien détourne
  /// tous les paiements mobile money, et personne ne le voit avant que les SMS
  /// cessent d'arriver. Le reste des réglages n'a pas besoin d'être verrouillé,
  /// et verrouiller l'écran entier ferait appeler le patron pour corriger le
  /// nom de la boutique.
  Future<bool> codePatronPose() async => (await _lire(_codePatron)) != null;

  /// Pose ou remplace le code. Quatre chiffres : ça se retient, ça se tape
  /// d'une main, et ça n'a pas à résister à une attaque — ça a à résister à
  /// un employé pressé.
  Future<void> definirCodePatron(String code) async {
    final propre = code.trim();
    if (propre.length < 4) {
      throw ArgumentError('Le code fait au moins quatre chiffres.');
    }
    await _ecrire(_codePatron, _empreinte(propre));
  }

  /// Vrai si le code proposé est le bon. Faux quand aucun code n'est posé :
  /// il n'y a alors rien à ouvrir, et l'appelant ne doit pas croire l'avoir
  /// ouvert.
  Future<bool> codePatronJuste(String code) async {
    final pose = await _lire(_codePatron);
    if (pose == null) return false;
    return pose == _empreinte(code.trim());
  }

  Future<void> retirerCodePatron() => _effacer(_codePatron);

  /// L'empreinte, pas le code. Une sauvegarde emporte les réglages : si le
  /// code y voyageait en clair, il suffirait d'ouvrir le fichier pour le lire.
  static String _empreinte(String code) =>
      sha256.convert(utf8.encode('carnet.patron.$code')).toString();

  Future<String?> _lire(String cle) async {
    final ligne = await (base.select(base.reglages)
          ..where((r) => r.cle.equals(cle)))
        .getSingleOrNull();
    return ligne?.valeur;
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

  /// Les mentions fiscales saisies. Nulle tant que le commerçant n'est pas
  /// passé par la fiche entreprise — c'est-à-dire presque toujours.
  final FicheEntreprise? mentions;

  /// La fiche entreprise, jamais nulle : un appelant qui compose l'en-tête
  /// d'un document doit l'obtenir même quand rien n'est rempli, réduite au
  /// seul nom de la boutique.
  FicheEntreprise get fiche =>
      mentions ?? FicheEntreprise(nomCommercial: nomCommerce);

  const Reglage({
    required this.nomCommerce,
    required this.comptes,
    this.vendeurs = const [],
    this.vendeurActif,
    this.mentions,
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
