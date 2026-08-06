/// Dépôt : écrit les événements et met à jour les projections.
///
/// Toute écriture suit le même chemin : un événement est ajouté au journal,
/// puis les projections sont mises à jour, le tout dans une transaction. Le
/// journal reste la source de vérité — [reconstruireProjections] le prouve en
/// rejouant tout depuis le début.
library;

import 'package:drift/drift.dart';

import '../domaine/evenements.dart';
import '../domaine/montant.dart';
import '../domaine/references.dart';
import '../domaine/telephone.dart';
import '../domaine/texte.dart';
import 'base.dart';
import 'journal.dart';

/// Une ligne de vente à enregistrer.
class LigneAEnregistrer {
  /// Code de l'article. Nul lorsque le commerçant a saisi un montant libre :
  /// l'article sera alors créé ou retrouvé automatiquement.
  final String? codeArticle;

  final String? designation;
  final Montant prixUnitaire;
  final Quantite quantite;

  /// Prix du catalogue, s'il diffère du prix pratiqué.
  ///
  /// Sur un marché le prix se négocie. On garde les deux pour pouvoir montrer
  /// au commerçant ce que ses remises lui coûtent.
  final Montant? prixCatalogue;

  final GroupeTaxation groupeTaxation;

  const LigneAEnregistrer({
    required this.prixUnitaire,
    required this.quantite,
    this.codeArticle,
    this.designation,
    this.prixCatalogue,
    this.groupeTaxation = GroupeTaxation.a,
  });
}

/// Un règlement à enregistrer.
class PaiementAEnregistrer {
  final ModePaiement mode;
  final Montant montant;
  final String? reference;
  final String? expediteur;

  const PaiementAEnregistrer({
    required this.mode,
    required this.montant,
    this.reference,
    this.expediteur,
  });
}

/// Le résumé du jour, celui qui part le soir au patron.
class RapportDuJour {
  final Montant encaisse;
  final Montant aCredit;
  final int nombreVentes;
  final int articlesEnRupture;
  final Montant remisesAccordees;

  const RapportDuJour({
    required this.encaisse,
    required this.aCredit,
    required this.nombreVentes,
    required this.articlesEnRupture,
    required this.remisesAccordees,
  });
}

class Depot {
  final BaseLocale base;
  final Journal journal;

  /// Nombre de ventes au-delà duquel on propose de nommer un article.
  static const seuilDeNommage = 3;

  Depot(this.base, this.journal);

  // ---------------------------------------------------------------- ventes

  /// Enregistre une vente.
  ///
  /// La vente est écrite localement, immédiatement, sans attendre le réseau.
  /// Sa certification viendra plus tard : c'est un événement distinct.
  Future<String> enregistrerVente({
    required List<LigneAEnregistrer> lignes,
    required List<PaiementAEnregistrer> paiements,
    String? clientId,
    String? operateur,
    DateTime? horodatage,
  }) async {
    if (lignes.isEmpty) {
      throw ArgumentError('Une vente doit comporter au moins une ligne.');
    }

    final quand = horodatage ?? DateTime.now();

    return base.transaction(() async {
      final resolues = await _resoudreLignes(lignes);
      final total = resolues.total;
      final remise = resolues.remise;

      final evenement = await journal.ajouter(
        TypeEvenement.venteEnregistree,
        {
          'lignes': resolues.lignes,
          'paiements': [
            for (final p in paiements)
              {
                'mode': p.mode.name,
                'montant': p.montant.centimes,
                'reference': p.reference,
                'expediteur': p.expediteur,
              }
          ],
          'clientId': clientId,
          'operateur': operateur,
          'total': total.centimes,
          'remise': remise.centimes,
        },
        horodatage: quand,
      );

      await _appliquerVente(evenement);
      return evenement.id;
    });
  }

  /// Applique une vente aux projections. Utilisé à l'écriture et au rejeu.
  Future<void> _appliquerVente(Evenement evenement) async {
    final charge = evenement.charge;
    final venteId = evenement.id;

    await base.into(base.ventes).insert(
          VentesCompanion.insert(
            id: venteId,
            horodatage: evenement.horodatage,
            totalCentimes: charge['total']! as int,
            remiseCentimes: Value(charge['remise'] as int? ?? 0),
            clientId: Value(charge['clientId'] as String?),
            operateur: Value(charge['operateur'] as String?),
          ),
        );

    await _poserLignes(
      venteId: venteId,
      lignes: (charge['lignes']! as List).cast<Map<String, Object?>>(),
      quand: evenement.horodatage,
    );

    await _poserPaiements(
      venteId: venteId,
      paiements:
          (charge['paiements'] as List? ?? const []).cast<Map<String, Object?>>(),
      clientId: charge['clientId'] as String?,
      quand: evenement.horodatage,
    );
  }

  /// Résout des lignes brutes en lignes prêtes à écrire : code d'article
  /// déduit si besoin, désignation retrouvée, montants calculés.
  Future<_LignesResolues> _resoudreLignes(List<LigneAEnregistrer> lignes) async {
    final resolues = <Map<String, Object?>>[];
    var total = const Montant.zero();
    var remise = const Montant.zero();

    for (final ligne in lignes) {
      final code =
          ligne.codeArticle ?? _codeAutomatiquePour(ligne.prixUnitaire);
      final designation = ligne.designation ??
          await _designationConnue(code) ??
          'Article à ${ligne.prixUnitaire.enFrancs}';

      final montant = ligne.prixUnitaire.multiplieParQuantite(ligne.quantite);
      total = total + montant;

      if (ligne.prixCatalogue != null) {
        final ecart =
            ligne.prixCatalogue!.multiplieParQuantite(ligne.quantite) - montant;
        if (ecart.estPositif) remise = remise + ecart;
      }

      resolues.add({
        'code': code,
        'designation': designation,
        'quantite': ligne.quantite.milliemes,
        'prix': ligne.prixUnitaire.centimes,
        'prixCatalogue': ligne.prixCatalogue?.centimes,
        'groupe': ligne.groupeTaxation.etiquette,
        'montant': montant.centimes,
      });
    }

    return _LignesResolues(resolues, total, remise);
  }

  /// Écrit les lignes d'une vente et met à jour le catalogue.
  ///
  /// Le décalage sert quand on ajoute à une vente qui a déjà des lignes :
  /// les identifiants doivent rester uniques.
  Future<void> _poserLignes({
    required String venteId,
    required List<Map<String, Object?>> lignes,
    required DateTime quand,
    int decalage = 0,
  }) async {
    for (var i = 0; i < lignes.length; i++) {
      final ligne = lignes[i];
      final code = ligne['code']! as String;

      await base.into(base.lignesVente).insert(
            LignesVenteCompanion.insert(
              id: '$venteId-${decalage + i}',
              venteId: venteId,
              codeArticle: code,
              designation: ligne['designation']! as String,
              quantiteMilliemes: ligne['quantite']! as int,
              prixUnitaireCentimes: ligne['prix']! as int,
              prixCatalogueCentimes: Value(ligne['prixCatalogue'] as int?),
              groupeTaxation: ligne['groupe']! as String,
              montantCentimes: ligne['montant']! as int,
            ),
          );

      await _incrementerArticle(
        code: code,
        designation: ligne['designation']! as String,
        prixCentimes: ligne['prix']! as int,
        groupe: ligne['groupe']! as String,
        quantiteMilliemes: ligne['quantite']! as int,
        quand: quand,
      );
    }
  }

  /// Écrit les règlements d'une vente et alimente le cahier de dettes.
  Future<void> _poserPaiements({
    required String venteId,
    required List<Map<String, Object?>> paiements,
    required DateTime quand,
    String? clientId,
    int decalage = 0,
  }) async {
    for (var i = 0; i < paiements.length; i++) {
      final paiement = paiements[i];
      await base.into(base.paiements).insert(
            PaiementsCompanion.insert(
              id: '$venteId-p${decalage + i}',
              venteId: venteId,
              mode: paiement['mode']! as String,
              montantCentimes: paiement['montant']! as int,
              reference: Value(paiement['reference'] as String?),
              expediteur: Value(paiement['expediteur'] as String?),
            ),
          );

      // Une vente à crédit alimente le cahier de dettes.
      if (paiement['mode'] == ModePaiement.credit.name && clientId != null) {
        await _ajusterEncours(clientId, paiement['montant']! as int, quand);
      }
    }
  }

  /// Crée l'article s'il n'existe pas, sinon incrémente son compteur.
  ///
  /// C'est le mécanisme du catalogue auto-construit : on ne demande jamais au
  /// commerçant de saisir un inventaire, le catalogue naît de ses ventes.
  Future<void> _incrementerArticle({
    required String code,
    required String designation,
    required int prixCentimes,
    required String groupe,
    required int quantiteMilliemes,
    required DateTime quand,
  }) async {
    final existant = await (base.select(base.articles)
          ..where((a) => a.code.equals(code)))
        .getSingleOrNull();

    if (existant == null) {
      await base.into(base.articles).insert(
            ArticlesCompanion.insert(
              code: code,
              designation: designation,
              prixCentimes: prixCentimes,
              groupeTaxation: Value(groupe),
              nombreVentes: const Value(1),
              nomme: Value(!code.startsWith('AUTO-')),
              derniereVente: Value(quand),
            ),
          );
      return;
    }

    final stock = existant.stockMilliemes;
    // Le stock ne se décrémente qu'en suivi direct — quand l'article est
    // vendu tel qu'il est acheté. Un plat de restaurant consomme des
    // ingrédients, pas lui-même : son suivi passe par une recette, traitée
    // par le module métier. Un service ne consomme rien du tout.
    final suitLeStock =
        existant.suiviStock == SuiviStock.direct.cle && stock != null;

    await (base.update(base.articles)..where((a) => a.code.equals(code))).write(
      ArticlesCompanion(
        nombreVentes: Value(existant.nombreVentes + 1),
        derniereVente: Value(quand),
        stockMilliemes:
            suitLeStock ? Value(stock - quantiteMilliemes) : const Value.absent(),
      ),
    );
  }

  Future<void> _ajusterEncours(String clientId, int delta, DateTime quand) async {
    final client = await (base.select(base.clients)
          ..where((c) => c.id.equals(clientId)))
        .getSingleOrNull();
    if (client == null) return;

    await (base.update(base.clients)..where((c) => c.id.equals(clientId))).write(
      ClientsCompanion(
        encoursCentimes: Value(client.encoursCentimes + delta),
        derniereActivite: Value(quand),
      ),
    );
  }

  /// Un article non nommé est identifié par son prix : le commerçant qui tape
  /// trois fois « 500 F » vend très probablement trois fois la même chose.
  String _codeAutomatiquePour(Montant prix) => 'AUTO-${prix.centimes}';

  Future<String?> _designationConnue(String code) async {
    final article = await (base.select(base.articles)
          ..where((a) => a.code.equals(code)))
        .getSingleOrNull();
    return article?.designation;
  }

  // ---------------------------------------------------- parcours en plusieurs temps

  /// Ouvre une vente qui restera modifiable : note de restaurant, commande en
  /// préparation, devis.
  ///
  /// Le contenant est ce qui la regroupe — une table, un numéro de ticket, un
  /// nom. Au comptoir il ne sert pas, et [enregistrerVente] reste la voie
  /// courte.
  Future<String> ouvrirVente({
    String? contenant,
    TypeContenant? typeContenant,
    String? clientId,
    String? operateur,
    DateTime? horodatage,
  }) async {
    return base.transaction(() async {
      final evenement = await journal.ajouter(
        TypeEvenement.venteOuverte,
        {
          'contenant': contenant,
          'typeContenant': typeContenant?.cle,
          'clientId': clientId,
          'operateur': operateur,
        },
        horodatage: horodatage,
      );
      await _appliquerOuverture(evenement);
      return evenement.id;
    });
  }

  Future<void> _appliquerOuverture(Evenement evenement) async {
    await base.into(base.ventes).insert(
          VentesCompanion.insert(
            id: evenement.id,
            horodatage: evenement.horodatage,
            totalCentimes: 0,
            etat: Value(EtatVente.ouverte.cle),
            contenant: Value(evenement.charge['contenant'] as String?),
            typeContenant: Value(evenement.charge['typeContenant'] as String?),
            clientId: Value(evenement.charge['clientId'] as String?),
            operateur: Value(evenement.charge['operateur'] as String?),
          ),
        );
  }

  /// Ajoute des lignes à une vente ouverte.
  ///
  /// C'est le geste du serveur qui rapporte une commande supplémentaire à une
  /// table déjà servie.
  Future<void> ajouterAVente(String venteId, List<LigneAEnregistrer> lignes) async {
    if (lignes.isEmpty) return;

    await base.transaction(() async {
      final vente = await (base.select(base.ventes)
            ..where((v) => v.id.equals(venteId)))
          .getSingleOrNull();
      if (vente == null) {
        throw ArgumentError('Vente inconnue : $venteId');
      }
      if (vente.etat != EtatVente.ouverte.cle) {
        throw StateError(
            "On ne peut ajouter qu'à une vente ouverte (état : ${vente.etat}).");
      }

      final resolues = await _resoudreLignes(lignes);
      final evenement = await journal.ajouter(TypeEvenement.lignesAjoutees, {
        'venteId': venteId,
        'lignes': resolues.lignes,
        'total': resolues.total.centimes,
        'remise': resolues.remise.centimes,
      });
      await _appliquerAjoutLignes(evenement);
    });
  }

  Future<void> _appliquerAjoutLignes(Evenement evenement) async {
    final venteId = evenement.charge['venteId']! as String;
    final vente = await (base.select(base.ventes)
          ..where((v) => v.id.equals(venteId)))
        .getSingle();

    final depart = await (base.select(base.lignesVente)
          ..where((l) => l.venteId.equals(venteId)))
        .get();

    await _poserLignes(
      venteId: venteId,
      lignes: (evenement.charge['lignes']! as List).cast<Map<String, Object?>>(),
      quand: evenement.horodatage,
      decalage: depart.length,
    );

    await (base.update(base.ventes)..where((v) => v.id.equals(venteId))).write(
      VentesCompanion(
        totalCentimes:
            Value(vente.totalCentimes + (evenement.charge['total']! as int)),
        remiseCentimes:
            Value(vente.remiseCentimes + (evenement.charge['remise'] as int? ?? 0)),
      ),
    );
  }

  /// Marque une vente comme servie sans être soldée : c'est l'état d'une
  /// vente à crédit, ou d'une table qui a mangé mais pas encore payé.
  Future<void> marquerServie(String venteId) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.venteServie, {
        'venteId': venteId,
      });
      await _appliquerEtat(evenement, EtatVente.servie);
    });
  }

  /// Solde une vente ouverte par un ou plusieurs règlements.
  Future<void> solder(String venteId, List<PaiementAEnregistrer> paiements) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.venteSoldee, {
        'venteId': venteId,
        'paiements': [
          for (final p in paiements)
            {
              'mode': p.mode.name,
              'montant': p.montant.centimes,
              'reference': p.reference,
              'expediteur': p.expediteur,
            }
        ],
      });
      await _appliquerSolde(evenement);
    });
  }

  Future<void> _appliquerSolde(Evenement evenement) async {
    final venteId = evenement.charge['venteId']! as String;
    final vente = await (base.select(base.ventes)
          ..where((v) => v.id.equals(venteId)))
        .getSingle();

    final existants = await (base.select(base.paiements)
          ..where((p) => p.venteId.equals(venteId)))
        .get();

    await _poserPaiements(
      venteId: venteId,
      paiements:
          (evenement.charge['paiements']! as List).cast<Map<String, Object?>>(),
      clientId: vente.clientId,
      quand: evenement.horodatage,
      decalage: existants.length,
    );

    await _appliquerEtat(evenement, EtatVente.soldee);
  }

  Future<void> _appliquerEtat(Evenement evenement, EtatVente etat) async {
    await (base.update(base.ventes)
          ..where((v) => v.id.equals(evenement.charge['venteId']! as String)))
        .write(VentesCompanion(etat: Value(etat.cle)));
  }

  /// Les ventes encore ouvertes : les tables en cours, les commandes en
  /// préparation.
  Future<List<LigneVente>> ventesOuvertes() {
    final requete = base.select(base.ventes)
      ..where((v) =>
          v.etat.equals(EtatVente.ouverte.cle) & v.annulee.equals(false))
      ..orderBy([(v) => OrderingTerm.asc(v.horodatage)]);
    return requete.get();
  }

  /// Les ventes servies mais pas encore payées.
  Future<List<LigneVente>> ventesAEncaisser() {
    final requete = base.select(base.ventes)
      ..where((v) =>
          v.etat.equals(EtatVente.servie.cle) & v.annulee.equals(false))
      ..orderBy([(v) => OrderingTerm.asc(v.horodatage)]);
    return requete.get();
  }

  // -------------------------------------------------------------- catalogue

  /// Donne un nom à un article que le commerçant vend souvent.
  Future<void> nommerArticle(String code, String designation) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.articleNomme, {
        'code': code,
        'designation': designation,
      });
      await _appliquerNommage(evenement);
    });
  }

  Future<void> _appliquerNommage(Evenement evenement) async {
    final code = evenement.charge['code']! as String;
    final designation = evenement.charge['designation']! as String;

    await (base.update(base.articles)..where((a) => a.code.equals(code)))
        .write(ArticlesCompanion(
      designation: Value(designation),
      nomme: const Value(true),
    ));

    // Les ventes déjà enregistrées gardent leur libellé d'origine : le
    // journal ne se réécrit pas. Seul le catalogue est mis à jour.
  }

  /// Déclare le stock restant d'un article.
  ///
  /// Déclarer un stock, c'est demander à ce qu'il soit suivi : l'article
  /// passe automatiquement en suivi direct.
  Future<void> ajusterStock(
    String code,
    Quantite quantite, {
    String? motif,
    DateTime? horodatage,
  }) =>
      _bougerStock(
        code: code,
        nature: NatureMouvementStock.inventaire,
        quantite: quantite,
        motif: motif,
        horodatage: horodatage,
      );

  /// Enregistre une réception de marchandise.
  ///
  /// S'ajoute au stock connu, contrairement à l'inventaire qui le remplace.
  /// C'est le geste courant : « j'ai reçu vingt sacs » se dit sans avoir à
  /// recompter l'étagère.
  Future<void> entrerStock(
    String code,
    Quantite quantite, {
    String? motif,
    DateTime? horodatage,
  }) =>
      _bougerStock(
        code: code,
        nature: NatureMouvementStock.entree,
        quantite: quantite,
        motif: motif,
        horodatage: horodatage,
      );

  /// Enregistre une perte : casse, vol, péremption, cadeau.
  ///
  /// Sans cette ligne, une perte devient un écart inexpliqué — et c'est
  /// exactement là que l'argent d'un commerce disparaît sans qu'on sache
  /// jamais par où.
  Future<void> declarerPerte(
    String code,
    Quantite quantite, {
    String? motif,
    DateTime? horodatage,
  }) =>
      _bougerStock(
        code: code,
        nature: NatureMouvementStock.perte,
        quantite: quantite,
        motif: motif,
        horodatage: horodatage,
      );

  Future<void> _bougerStock({
    required String code,
    required NatureMouvementStock nature,
    required Quantite quantite,
    String? motif,
    DateTime? horodatage,
  }) async {
    if (quantite.milliemes < 0) {
      throw ArgumentError('Un mouvement de stock se déclare en positif.');
    }

    await base.transaction(() async {
      final evenement = await journal.ajouter(
        TypeEvenement.stockAjuste,
        {
          'code': code,
          'nature': nature.cle,
          'quantite': quantite.milliemes,
          'motif': motif,
        },
        horodatage: horodatage,
      );
      await _appliquerAjustementStock(evenement);
    });
  }

  Future<void> _appliquerAjustementStock(Evenement evenement) async {
    final charge = evenement.charge;
    final code = charge['code']! as String;
    final quantite = charge['quantite']! as int;

    // Les événements écrits avant l'introduction des natures sont des
    // inventaires : c'est tout ce que le dépôt savait faire à l'époque.
    final nature = NatureMouvementStock.parCle(
        charge['nature'] as String? ?? NatureMouvementStock.inventaire.cle);

    final article = await (base.select(base.articles)
          ..where((a) => a.code.equals(code)))
        .getSingleOrNull();
    if (article == null) return;

    final avant = article.stockMilliemes ?? 0;
    final apres = switch (nature) {
      NatureMouvementStock.inventaire => quantite,
      NatureMouvementStock.entree => avant + quantite,
      NatureMouvementStock.perte => avant - quantite,
    };

    await (base.update(base.articles)..where((a) => a.code.equals(code)))
        .write(ArticlesCompanion(
      stockMilliemes: Value(apres),
      // Déclarer un stock, c'est décider de le suivre.
      suiviStock: Value(SuiviStock.direct.cle),
    ));

    await base.into(base.mouvementsStock).insert(
          MouvementsStockCompanion.insert(
            id: evenement.id,
            codeArticle: code,
            horodatage: evenement.horodatage,
            nature: nature.cle,
            variationMilliemes: apres - avant,
            stockApresMilliemes: apres,
            motif: Value(charge['motif'] as String?),
          ),
        );
  }

  /// L'historique des mouvements d'un article, du plus récent au plus ancien.
  Future<List<LigneMouvementStock>> mouvementsDe(String code,
      {int limite = 20}) {
    final requete = base.select(base.mouvementsStock)
      ..where((m) => m.codeArticle.equals(code))
      ..orderBy([(m) => OrderingTerm.desc(m.horodatage)])
      ..limit(limite);
    return requete.get();
  }

  /// Change le mode de suivi du stock d'un article.
  ///
  /// Repasser en `aucun` oublie le stock connu : mieux vaut ne rien afficher
  /// qu'un chiffre qu'on a cessé de tenir à jour.
  Future<void> definirSuiviStock(String code, SuiviStock suivi) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.suiviStockDefini, {
        'code': code,
        'suivi': suivi.cle,
      });
      await _appliquerModeSuivi(evenement);
    });
  }

  Future<void> _appliquerModeSuivi(Evenement evenement) async {
    final suivi = evenement.charge['suivi']! as String;
    await (base.update(base.articles)
          ..where((a) => a.code.equals(evenement.charge['code']! as String)))
        .write(ArticlesCompanion(
      suiviStock: Value(suivi),
      stockMilliemes: suivi == SuiviStock.aucun.cle
          ? const Value(null)
          : const Value.absent(),
    ));
  }

  /// Le commerçant dit qu'un même prix recouvre plusieurs produits.
  ///
  /// Un article né d'un montant libre est identifié par son prix seul : c'est
  /// ce qui permet de démarrer sans rien saisir, mais c'est un pari. Deux
  /// produits vendus au même prix tombent dans le même article, et si un
  /// stock y était déclaré il mentirait à chaque vente de l'autre produit.
  ///
  /// Refuser le pari arrête la proposition de nom. L'article reste un
  /// fourre-tout assumé — ce qui est honnête — et le commerçant crée ses
  /// vrais articles depuis l'écran de stock quand il le souhaite.
  Future<void> refuserNommage(String code) async {
    await base.transaction(() async {
      final evenement =
          await journal.ajouter(TypeEvenement.nommageRefuse, {'code': code});
      await _appliquerRefusNommage(evenement);
    });
  }

  Future<void> _appliquerRefusNommage(Evenement evenement) async {
    await (base.update(base.articles)
          ..where((a) => a.code.equals(evenement.charge['code']! as String)))
        .write(ArticlesCompanion(
      nommageRefuseLe: Value(evenement.horodatage),
    ));
  }

  /// Les articles vendus assez souvent pour mériter un nom.
  Future<List<LigneArticle>> articlesANommer() {
    final requete = base.select(base.articles)
      ..where((a) =>
          a.nomme.equals(false) &
          a.nommageRefuseLe.isNull() &
          a.nombreVentes.isBiggerOrEqualValue(seuilDeNommage))
      ..orderBy([(a) => OrderingTerm.desc(a.nombreVentes)]);
    return requete.get();
  }

  /// Crée un article à la main, avec son nom et son prix.
  ///
  /// Le catalogue se construit tout seul à l'usage — c'est le chemin normal,
  /// et celui qui ne demande aucun travail. Mais un commerçant qui *veut*
  /// saisir ses articles à l'avance doit pouvoir le faire : c'est son
  /// commerce, pas le mien. Certains préfèrent une soirée de saisie à des
  /// semaines de construction progressive, et ils ont le droit.
  ///
  /// Renvoie le code de l'article. Un article déjà connu est mis à jour
  /// plutôt que dupliqué.
  Future<String> creerArticle({
    required String designation,
    required Montant prix,
    String? code,
    Quantite? stock,
  }) async {
    final nom = designation.trim();
    if (nom.isEmpty) {
      throw ArgumentError('Un article a besoin d\'un nom.');
    }
    if (!prix.estPositif) {
      throw ArgumentError('Un article a besoin d\'un prix positif.');
    }

    final identifiant = code ?? _codeDepuisNom(nom);

    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.articleCree, {
        'code': identifiant,
        'designation': nom,
        'prix': prix.centimes,
      });
      await _appliquerCreationArticle(evenement);
    });

    if (stock != null) {
      await ajusterStock(identifiant, stock);
    }
    return identifiant;
  }

  Future<void> _appliquerCreationArticle(Evenement evenement) async {
    final charge = evenement.charge;

    await base.into(base.articles).insertOnConflictUpdate(
          ArticlesCompanion.insert(
            code: charge['code']! as String,
            designation: charge['designation']! as String,
            prixCentimes: charge['prix']! as int,
            nomme: const Value(true),
          ),
        );
  }

  /// Change le prix de vente d'un article.
  ///
  /// Les ventes déjà enregistrées gardent le prix pratiqué ce jour-là : le
  /// journal ne se réécrit pas.
  Future<void> modifierPrix(String code, Montant prix) async {
    if (!prix.estPositif) {
      throw ArgumentError('Un prix de vente est positif.');
    }

    await base.transaction(() async {
      final evenement =
          await journal.ajouter(TypeEvenement.articlePrixModifie, {
        'code': code,
        'prix': prix.centimes,
      });
      await _appliquerPrix(evenement);
    });
  }

  Future<void> _appliquerPrix(Evenement evenement) async {
    await (base.update(base.articles)
          ..where((a) => a.code.equals(evenement.charge['code']! as String)))
        .write(ArticlesCompanion(
      prixCentimes: Value(evenement.charge['prix']! as int),
    ));
  }

  /// Un code lisible dérivé du nom, pour un article saisi à la main.
  ///
  /// Les accents et la ponctuation sautent : le code voyagera un jour dans
  /// des échanges où ils poseraient problème.
  static String _codeDepuisNom(String nom) {
    final base = sansAccents(nom.toLowerCase())
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    final racine = base.isEmpty ? 'article' : base;
    // Le suffixe évite qu'un même nom écrase un article existant portant un
    // prix différent.
    return '${racine.toUpperCase()}-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  /// Le commerçant préfère ne pas suivre ce stock pour l'instant.
  ///
  /// La proposition disparaît, l'article reste. Il figure toujours dans
  /// l'écran de stock, où le suivi peut démarrer d'un bouton — un refus par
  /// erreur ne coûte donc rien, et un changement d'avis non plus.
  Future<void> reporterPropositionSuivi(String code) async {
    await base.transaction(() async {
      final evenement = await journal
          .ajouter(TypeEvenement.propositionSuiviReportee, {'code': code});
      await _appliquerReport(evenement);
    });
  }

  Future<void> _appliquerReport(Evenement evenement) async {
    await (base.update(base.articles)
          ..where((a) => a.code.equals(evenement.charge['code']! as String)))
        .write(ArticlesCompanion(
      propositionSuiviReporteeLe: Value(evenement.horodatage),
    ));
  }

  /// Nombre de ventes au-delà duquel on propose de compter le stock.
  ///
  /// Plus haut que le seuil de nommage : on ne demande à un commerçant de
  /// compter son étagère qu'une fois qu'il est clair que l'article compte
  /// pour lui. Poser la question trop tôt, c'est se faire refuser.
  static const seuilDeSuiviStock = 8;

  /// Les articles nommés, vendus souvent, dont le stock n'est pas encore suivi.
  ///
  /// C'est la deuxième marche de la construction progressive : d'abord le
  /// nom, ensuite la quantité. Jamais un inventaire à saisir d'un coup.
  Future<List<LigneArticle>> articlesASuivre() {
    final requete = base.select(base.articles)
      ..where((a) =>
          a.nomme.equals(true) &
          a.suiviStock.equals(SuiviStock.aucun.cle) &
          a.propositionSuiviReporteeLe.isNull() &
          a.nombreVentes.isBiggerOrEqualValue(seuilDeSuiviStock))
      ..orderBy([(a) => OrderingTerm.desc(a.nombreVentes)]);
    return requete.get();
  }

  /// Tous les articles dont le stock n'est pas suivi, proposés ou non.
  ///
  /// C'est le filet de sécurité : quoi qu'il ait répondu aux propositions, le
  /// commerçant retrouve ici n'importe quel article et peut en démarrer le
  /// suivi. Rien n'est jamais définitif.
  Future<List<LigneArticle>> articlesSansSuivi({int limite = 60}) {
    final requete = base.select(base.articles)
      ..where((a) => a.suiviStock.equals(SuiviStock.aucun.cle))
      ..orderBy([
        (a) => OrderingTerm.desc(a.nombreVentes),
        (a) => OrderingTerm.desc(a.derniereVente),
      ])
      ..limit(limite);
    return requete.get();
  }

  /// Les articles dont le stock est réellement suivi, les plus bas d'abord.
  Future<List<LigneArticle>> articlesEnStock() {
    final requete = base.select(base.articles)
      ..where((a) => a.suiviStock.equals(SuiviStock.direct.cle))
      ..orderBy([(a) => OrderingTerm.asc(a.stockMilliemes)]);
    return requete.get();
  }

  /// Le catalogue tel qu'il s'affiche à la caisse : les plus vendus d'abord.
  Future<List<LigneArticle>> catalogue({int limite = 60}) {
    final requete = base.select(base.articles)
      ..orderBy([
        (a) => OrderingTerm.desc(a.nombreVentes),
        (a) => OrderingTerm.desc(a.derniereVente),
      ])
      ..limit(limite);
    return requete.get();
  }

  // ----------------------------------------------------------------- crédit

  /// Crée un client. Le fichier se construit à l'usage, comme le catalogue.
  Future<String> creerClient({
    required String nom,
    String? telephone,
    TypeClient type = TypeClient.comptant,
    String? ifu,
  }) async {
    return base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.clientCree, {
        'nom': nom,
        'telephone': telephone,
        'telephoneNormalise': normaliserTelephone(telephone),
        'type': type.etiquette,
        'ifu': ifu,
      });
      await _appliquerCreationClient(evenement);
      return evenement.id;
    });
  }

  Future<void> _appliquerCreationClient(Evenement evenement) async {
    await base.into(base.clients).insert(
          ClientsCompanion.insert(
            id: evenement.id,
            nom: evenement.charge['nom']! as String,
            telephone: Value(evenement.charge['telephone'] as String?),
            telephoneNormalise:
                Value(evenement.charge['telephoneNormalise'] as String?),
            typeClient: Value(evenement.charge['type'] as String? ?? 'CC'),
            ifu: Value(evenement.charge['ifu'] as String?),
            derniereActivite: Value(evenement.horodatage),
          ),
        );
  }

  /// Enregistre un remboursement de dette.
  Future<void> rembourserCredit(String clientId, Montant montant) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.creditRembourse, {
        'clientId': clientId,
        'montant': montant.centimes,
      });
      await _appliquerRemboursement(evenement);
    });
  }

  Future<void> _appliquerRemboursement(Evenement evenement) async {
    await _ajusterEncours(
      evenement.charge['clientId']! as String,
      -(evenement.charge['montant']! as int),
      evenement.horodatage,
    );
  }

  /// Retrouve un client par son numéro, quelle que soit la façon de l'écrire.
  ///
  /// Sert à reconnaître le payeur d'un SMS mobile money sans rien saisir, et
  /// à ne pas créer deux fiches pour la même personne.
  Future<LigneClient?> clientParTelephone(String telephone) async {
    final normalise = normaliserTelephone(telephone);
    if (normalise == null) return null;
    return (base.select(base.clients)
          ..where((c) => c.telephoneNormalise.equals(normalise)))
        .getSingleOrNull();
  }

  /// Enregistre le consentement du client à ce que son historique le suive
  /// d'une boutique à l'autre.
  ///
  /// Donner son numéro pour recevoir un reçu n'est pas consentir à cela :
  /// c'est un accord distinct, et il est daté.
  Future<void> enregistrerConsentement(String clientId) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.consentementDonne, {
        'clientId': clientId,
      });
      await _appliquerConsentement(evenement);
    });
  }

  Future<void> _appliquerConsentement(Evenement evenement) async {
    await (base.update(base.clients)
          ..where((c) => c.id.equals(evenement.charge['clientId']! as String)))
        .write(ClientsCompanion(consentementLe: Value(evenement.horodatage)));
  }

  /// Au-delà de ce délai sans mouvement, une dette change de nature : ce
  /// n'est plus une facilité accordée à un habitué, c'est une créance qu'on
  /// risque de ne plus revoir. Le cahier la signale à partir de là.
  static const joursDetteAncienne = 30;

  /// Les clients connus, les plus récemment actifs d'abord.
  ///
  /// Sert à retrouver quelqu'un au moment de lui faire crédit : au comptoir,
  /// c'est presque toujours un habitué, et il est en haut de la liste.
  Future<List<LigneClient>> clients({int limite = 50}) {
    final requete = base.select(base.clients)
      ..orderBy([(c) => OrderingTerm.desc(c.derniereActivite)])
      ..limit(limite);
    return requete.get();
  }

  /// Qui me doit combien, du plus ancien au plus récent.
  Future<List<LigneClient>> clientsDebiteurs() {
    final requete = base.select(base.clients)
      ..where((c) => c.encoursCentimes.isBiggerThanValue(0))
      ..orderBy([(c) => OrderingTerm.asc(c.derniereActivite)]);
    return requete.get();
  }

  // ----------------------------------------------------------------- caisse

  Future<void> mouvementCaisse({
    required String nature,
    required Montant montant,
    String? motif,
    String? operateur,
  }) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.caisseMouvement, {
        'nature': nature,
        'montant': montant.centimes,
        'motif': motif,
        'operateur': operateur,
      });
      await _appliquerMouvementCaisse(evenement);
    });
  }

  Future<void> _appliquerMouvementCaisse(Evenement evenement) async {
    await base.into(base.mouvementsCaisse).insert(
          MouvementsCaisseCompanion.insert(
            id: evenement.id,
            horodatage: evenement.horodatage,
            nature: evenement.charge['nature']! as String,
            montantCentimes: evenement.charge['montant']! as int,
            motif: Value(evenement.charge['motif'] as String?),
            operateur: Value(evenement.charge['operateur'] as String?),
          ),
        );
  }

  // ---------------------------------------------------------------- rapport

  /// Le résumé du jour, celui qui part le soir au patron.
  Future<RapportDuJour> rapportDuJour([DateTime? jour]) async {
    final reference = jour ?? DateTime.now();
    final debut = DateTime(reference.year, reference.month, reference.day);
    final fin = debut.add(const Duration(days: 1));

    final ventes = await (base.select(base.ventes)
          ..where((v) =>
              v.horodatage.isBiggerOrEqualValue(debut) &
              v.horodatage.isSmallerThanValue(fin) &
              v.annulee.equals(false)))
        .get();

    final identifiants = ventes.map((v) => v.id).toList();
    final reglements = identifiants.isEmpty
        ? <LignePaiement>[]
        : await (base.select(base.paiements)
              ..where((p) => p.venteId.isIn(identifiants)))
            .get();

    var encaisse = 0;
    var credit = 0;
    for (final reglement in reglements) {
      if (reglement.mode == ModePaiement.credit.name) {
        credit += reglement.montantCentimes;
      } else {
        encaisse += reglement.montantCentimes;
      }
    }

    final ruptures = await (base.select(base.articles)
          ..where((a) =>
              a.suiviStock.equals(SuiviStock.direct.cle) &
              a.stockMilliemes.isSmallerOrEqualValue(0)))
        .get();

    return RapportDuJour(
      encaisse: Montant(encaisse),
      aCredit: Montant(credit),
      nombreVentes: ventes.length,
      articlesEnRupture: ruptures.length,
      remisesAccordees:
          Montant(ventes.fold(0, (s, v) => s + v.remiseCentimes)),
    );
  }

  // ------------------------------------------------------------------ rejeu

  /// Vide les projections et les reconstruit à partir du journal.
  ///
  /// C'est la preuve que le journal est bien la source de vérité, et le
  /// recours si une projection est corrompue.
  Future<void> reconstruireProjections() async {
    await base.transaction(() async {
      await base.delete(base.paiements).go();
      await base.delete(base.lignesVente).go();
      await base.delete(base.ventes).go();
      await base.delete(base.articles).go();
      await base.delete(base.clients).go();
      await base.delete(base.mouvementsCaisse).go();
      await base.delete(base.mouvementsStock).go();

      for (final evenement in await journal.tous()) {
        switch (evenement.type) {
          case TypeEvenement.venteEnregistree:
            await _appliquerVente(evenement);
          case TypeEvenement.clientCree:
            await _appliquerCreationClient(evenement);
          case TypeEvenement.consentementDonne:
            await _appliquerConsentement(evenement);
          case TypeEvenement.articleNomme:
            await _appliquerNommage(evenement);
          case TypeEvenement.stockAjuste:
            // Les journaux écrits avant la séparation des deux événements
            // portent parfois un changement de suivi sous ce type-là.
            if (evenement.charge.containsKey('suivi')) {
              await _appliquerModeSuivi(evenement);
            } else {
              await _appliquerAjustementStock(evenement);
            }
          case TypeEvenement.suiviStockDefini:
            await _appliquerModeSuivi(evenement);
          case TypeEvenement.propositionSuiviReportee:
            await _appliquerReport(evenement);
          case TypeEvenement.nommageRefuse:
            await _appliquerRefusNommage(evenement);
          case TypeEvenement.articleCree:
            await _appliquerCreationArticle(evenement);
          case TypeEvenement.articlePrixModifie:
            await _appliquerPrix(evenement);
          case TypeEvenement.creditRembourse:
            await _appliquerRemboursement(evenement);
          case TypeEvenement.caisseMouvement:
            await _appliquerMouvementCaisse(evenement);
          case TypeEvenement.venteOuverte:
            await _appliquerOuverture(evenement);
          case TypeEvenement.lignesAjoutees:
            await _appliquerAjoutLignes(evenement);
          case TypeEvenement.venteServie:
            await _appliquerEtat(evenement, EtatVente.servie);
          case TypeEvenement.venteSoldee:
            await _appliquerSolde(evenement);
          case TypeEvenement.venteAnnulee:
          case TypeEvenement.creditAccorde:
          case TypeEvenement.ventecertifiee:
            break;
        }
      }
    });
  }
}


/// Lignes résolues, prêtes à être écrites.
class _LignesResolues {
  final List<Map<String, Object?>> lignes;
  final Montant total;
  final Montant remise;

  const _LignesResolues(this.lignes, this.total, this.remise);
}

/// L'ancienneté d'une dette, telle que le cahier la lit.
///
/// Ces deux règles vivent ici et pas dans l'écran : ce sont des décisions de
/// crédit, pas des choix d'affichage, et une relance automatique devra un
/// jour s'appuyer sur exactement la même définition.
extension AncienneteDette on LigneClient {
  /// Nombre de jours depuis le dernier mouvement. Nul si le client n'a
  /// jamais rien fait bouger.
  int? ageEnJours(DateTime maintenant) => derniereActivite == null
      ? null
      : maintenant.difference(derniereActivite!).inDays;

  bool detteAncienne(DateTime maintenant) {
    final jours = ageEnJours(maintenant);
    return jours != null && jours >= Depot.joursDetteAncienne;
  }
}
