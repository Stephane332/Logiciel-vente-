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
import '../domaine/numerotation.dart';
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

/// Ce qui a fait monter ou descendre l'ardoise d'un client.
enum SensDeCompte { achat, remboursement }

/// Une ligne d'un achat à crédit, telle qu'on la montre au client.
class DetailDAchat {
  final String designation;
  final Quantite quantite;
  final Montant total;

  const DetailDAchat({
    required this.designation,
    required this.quantite,
    required this.total,
  });
}

/// Un mouvement du compte d'un client.
class MouvementDeCompte {
  final DateTime quand;
  final Montant montant;
  final SensDeCompte sens;

  /// Ce qui composait l'achat. Vide pour un remboursement, et vide aussi
  /// pour un achat au montant libre — dans ce cas il n'y a rien à détailler,
  /// et prétendre le contraire serait pire que de se taire.
  final List<DetailDAchat> detail;

  /// Une vente annulée reste affichée, barrée. La faire disparaître ferait
  /// croire au client qu'on lui a effacé une ligne dans le dos.
  final bool annule;

  const MouvementDeCompte({
    required this.quand,
    required this.montant,
    required this.sens,
    this.detail = const [],
    this.annule = false,
  });

  bool get estAchat => sens == SensDeCompte.achat;
}

/// Ce qu'un vendeur a encaissé sur une période.
class PartDeVendeur {
  /// Nom du vendeur. Vide quand la vente n'a été attribuée à personne — ce
  /// qui est le cas normal d'un commerçant seul.
  final String vendeur;

  final int nombreVentes;
  final Montant total;
  final Montant remises;

  const PartDeVendeur({
    required this.vendeur,
    required this.nombreVentes,
    required this.total,
    required this.remises,
  });

  bool get estAnonyme => vendeur.isEmpty;
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

  /// Annule une vente.
  ///
  /// Dans un cahier, on rature. Sans ce geste, une erreur de saisie fausse la
  /// journée du commerçant pour toujours — et lui fait refermer l'application
  /// pour de bon.
  ///
  /// Le passé ne se réécrit pas : la vente reste dans le journal, et un
  /// événement d'annulation vient s'ajouter par-dessus. C'est aussi ce
  /// qu'impose la DGI, qui traite les annulations par facture d'avoir
  /// (§2.28). Les projections, elles, sont remises comme avant : le stock
  /// revient, la dette du client redescend, les compteurs reculent.
  Future<void> annulerVente(String venteId, {String? motif}) async {
    final vente = await (base.select(base.ventes)
          ..where((v) => v.id.equals(venteId)))
        .getSingleOrNull();

    // Annuler deux fois ne doit pas rendre le stock deux fois.
    if (vente == null || vente.annulee) return;

    await base.transaction(() async {
      final evenement = await journal.ajouter(
        TypeEvenement.venteAnnulee,
        {'venteId': venteId, 'motif': motif},
      );
      await _appliquerAnnulation(evenement);
    });
  }

  // -------------------------------------------------------------- factures

  /// Émet une facture pour une vente et lui attribue son numéro.
  ///
  /// Le numéro est attribué **ici et une seule fois**, dans la transaction qui
  /// l'écrit au journal. Deux caisses qui factureraient au même instant ne
  /// peuvent donc pas se voir donner le même rang : la transaction sérialise.
  ///
  /// Une vente déjà facturée rend sa référence d'origine sans en consommer une
  /// nouvelle — c'est le duplicata du §2.18, qui garde le numéro d'origine.
  /// Sans cette règle, rééditer une facture perdue trouerait la série.
  ///
  /// Une vente annulée ne se facture pas : la note traite les annulations par
  /// facture d'avoir (§2.28), pas en émettant la facture d'une vente qui n'a
  /// plus lieu d'être.
  Future<ReferenceFacture> emettreFacture(
    String venteId, {
    TypeFacture type = TypeFacture.vente,
    DateTime? horodatage,
  }) async {
    final vente = await (base.select(base.ventes)
          ..where((v) => v.id.equals(venteId)))
        .getSingleOrNull();
    if (vente == null) {
      throw ArgumentError('Vente inconnue : $venteId');
    }
    if (vente.annulee) {
      throw StateError(
          "Une vente annulée ne se facture pas : elle se solde par un avoir "
          "(§2.28).");
    }

    final deja = await referenceFacture(venteId);
    if (deja != null) return deja;

    final quand = horodatage ?? vente.horodatage;
    final annee = Numerotation.anneeDe(quand);

    return base.transaction(() async {
      final rang = const Numerotation()
          .rangSuivant(await _rangsAttribues(type: type, annee: annee));

      final evenement = await journal.ajouter(
        TypeEvenement.factureEmise,
        {
          'venteId': venteId,
          'type': type.etiquette,
          'annee': annee,
          'rang': rang,
        },
        horodatage: quand,
      );
      await _appliquerEmissionFacture(evenement);

      return ReferenceFacture(type: type.etiquette, annee: annee, rang: rang);
    });
  }

  /// La référence de la facture d'une vente, si elle en a une.
  Future<ReferenceFacture?> referenceFacture(String venteId) async {
    for (final evenement
        in await journal.parType(TypeEvenement.factureEmise)) {
      if (evenement.charge['venteId'] != venteId) continue;
      return ReferenceFacture(
        type: evenement.charge['type']! as String,
        annee: evenement.charge['annee']! as int,
        rang: evenement.charge['rang']! as int,
      );
    }
    return null;
  }

  /// Les rangs déjà attribués dans une série. Lus au journal, pas à la
  /// projection : c'est le journal qui fait foi, et une projection vidée ne
  /// doit pas faire repartir la numérotation à un.
  Future<List<int>> _rangsAttribues({
    required TypeFacture type,
    required int annee,
  }) async {
    final rangs = <int>[];
    for (final evenement
        in await journal.parType(TypeEvenement.factureEmise)) {
      if (evenement.charge['type'] != type.etiquette) continue;
      if (evenement.charge['annee'] != annee) continue;
      rangs.add(evenement.charge['rang']! as int);
    }
    return rangs;
  }

  /// Les trous d'une série, s'il y en a. Vide quand tout va bien.
  ///
  /// Ce n'est pas censé arriver. C'est vérifié quand même : une série trouée
  /// est le premier reproche d'un contrôle, et je préfère l'apprendre d'un
  /// écran que d'un redressement.
  Future<List<int>> trousDeSerie({
    TypeFacture type = TypeFacture.vente,
    required int annee,
  }) async =>
      const Numerotation()
          .trous(await _rangsAttribues(type: type, annee: annee));

  Future<void> _appliquerEmissionFacture(Evenement evenement) async {
    final venteId = evenement.charge['venteId']! as String;

    await (base.update(base.ventes)..where((v) => v.id.equals(venteId))).write(
      VentesCompanion(
        numero: Value(evenement.charge['rang']! as int),
        anneeGestion: Value(evenement.charge['annee']! as int),
      ),
    );
  }

  Future<void> _appliquerAnnulation(Evenement evenement) async {
    final venteId = evenement.charge['venteId']! as String;

    final vente = await (base.select(base.ventes)
          ..where((v) => v.id.equals(venteId)))
        .getSingleOrNull();
    if (vente == null || vente.annulee) return;

    await (base.update(base.ventes)..where((v) => v.id.equals(venteId)))
        .write(const VentesCompanion(annulee: Value(true)));

    // Le stock revient et le compteur de ventes recule : sinon un article
    // annulé continuerait de peser dans « ce qui rapporte » et de manquer à
    // l'étagère.
    final lignes = await (base.select(base.lignesVente)
          ..where((l) => l.venteId.equals(venteId)))
        .get();
    for (final ligne in lignes) {
      await _decrementerArticle(ligne.codeArticle, ligne.quantiteMilliemes);
    }

    // Une dette effacée doit disparaître du cahier, sinon le commerçant
    // réclamerait de l'argent qu'on ne lui doit pas.
    if (vente.clientId case final clientId?) {
      final reglements = await (base.select(base.paiements)
            ..where((p) => p.venteId.equals(venteId)))
          .get();
      final aCredit = reglements
          .where((p) => p.mode == ModePaiement.credit.name)
          .fold(0, (somme, p) => somme + p.montantCentimes);

      if (aCredit > 0) {
        await _ajusterEncours(clientId, -aCredit, evenement.horodatage);
      }
    }
  }

  Future<void> _decrementerArticle(String code, int quantiteMilliemes) async {
    final article = await (base.select(base.articles)
          ..where((a) => a.code.equals(code)))
        .getSingleOrNull();
    if (article == null) return;

    final stock = article.stockMilliemes;
    final suitLeStock =
        article.suiviStock == SuiviStock.direct.cle && stock != null;

    await (base.update(base.articles)..where((a) => a.code.equals(code)))
        .write(ArticlesCompanion(
      nombreVentes: Value(
          article.nombreVentes > 0 ? article.nombreVentes - 1 : 0),
      stockMilliemes:
          suitLeStock ? Value(stock + quantiteMilliemes) : const Value.absent(),
    ));
  }

  /// Ce que chacun a encaissé sur une période.
  ///
  /// Le patron qui emploie quelqu'un ne demande pas un tableau de bord : il
  /// demande qui a vendu combien, et si quelqu'un accorde plus de remises que
  /// les autres. C'est tout, et c'est déjà ce que le cahier ne dira jamais.
  Future<List<PartDeVendeur>> parVendeur(DateTime debut, DateTime fin) async {
    final lignes = await base.customSelect(
      '''
      SELECT COALESCE(v.operateur, '')     AS vendeur,
             COUNT(*)                      AS ventes,
             SUM(v.total_centimes)         AS total,
             SUM(v.remise_centimes)        AS remises
      FROM ventes v
      WHERE v.annulee = 0
        AND v.horodatage >= ?
        AND v.horodatage <  ?
      GROUP BY COALESCE(v.operateur, '')
      ORDER BY total DESC
      ''',
      variables: [Variable<DateTime>(debut), Variable<DateTime>(fin)],
      readsFrom: {base.ventes},
    ).get();

    return [
      for (final ligne in lignes)
        PartDeVendeur(
          vendeur: ligne.read<String>('vendeur'),
          nombreVentes: ligne.read<int>('ventes'),
          total: Montant(ligne.read<int>('total')),
          remises: Montant(ligne.read<int>('remises')),
        )
    ];
  }

  /// Les dernières ventes, pour pouvoir en annuler une.
  ///
  /// Les annulées restent dans la liste, barrées : le commerçant doit voir
  /// que son geste a été pris en compte, pas voir la ligne disparaître.
  Future<List<LigneVente>> dernieresVentes({int limite = 20}) {
    final requete = base.select(base.ventes)
      ..orderBy([(v) => OrderingTerm.desc(v.horodatage)])
      ..limit(limite);
    return requete.get();
  }

  /// Le montant au-delà duquel une vente mérite qu'on redemande.
  ///
  /// Pas un plafond fixe : ce qui est énorme pour une vendeuse de rue est
  /// ordinaire pour un grossiste. On se cale sur ce que ce commerce encaisse
  /// réellement — dix fois sa plus grosse vente du mois.
  ///
  /// Tant qu'on ne connaît pas encore la boutique, seul un plancher protège :
  /// il vise le doigt resté appuyé sur le zéro, pas le commerçant qui vend
  /// cher.
  Future<Montant> seuilDeVigilance({DateTime? maintenant}) async {
    final reference = maintenant ?? DateTime.now();
    final depuis = reference.subtract(const Duration(days: 30));

    final ventes = await (base.select(base.ventes)
          ..where((v) =>
              v.horodatage.isBiggerOrEqualValue(depuis) &
              v.annulee.equals(false)))
        .get();

    if (ventes.length < ventesAvantDeJuger) return plancherDeVigilance;

    final plusGrosse =
        ventes.map((v) => v.totalCentimes).reduce((a, b) => a > b ? a : b);
    final relatif = Montant(plusGrosse * 10);

    return relatif.centimes > plancherDeVigilance.centimes
        ? relatif
        : plancherDeVigilance;
  }

  /// Vrai quand le montant mérite une confirmation avant d'être encaissé.
  Future<bool> montantInhabituel(Montant montant,
      {DateTime? maintenant}) async {
    final seuil = await seuilDeVigilance(maintenant: maintenant);
    return montant.centimes > seuil.centimes;
  }

  /// Nombre de ventes en deçà duquel on ne prétend pas connaître la boutique.
  static const ventesAvantDeJuger = 5;

  /// Le plancher, quand on n'a pas encore d'historique.
  static const plancherDeVigilance = Montant(10000000);

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
  /// Retire un article du catalogue, ou l'y remet.
  ///
  /// Retiré, pas supprimé. Ses ventes passées restent au journal et dans les
  /// rapports : effacer l'histoire pour effacer une faute de frappe fausserait
  /// la journée, et le §2.23 l'interdit de toute façon. L'article disparaît de
  /// la caisse et du stock, c'est tout — et il revient d'un geste.
  Future<void> retirerArticle(String code, {bool retire = true}) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(
        retire ? TypeEvenement.articleRetire : TypeEvenement.articleRepris,
        {'code': code},
      );
      await _appliquerRetrait(evenement, retire: retire);
    });
  }

  Future<void> _appliquerRetrait(
    Evenement evenement, {
    required bool retire,
  }) async {
    await (base.update(base.articles)
          ..where((a) => a.code.equals(evenement.charge['code']! as String)))
        .write(ArticlesCompanion(
      retireLe: Value(retire ? evenement.horodatage : null),
    ));
  }

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
          a.retireLe.isNull() &
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
          a.retireLe.isNull() &
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
      ..where(
          (a) => a.retireLe.isNull() & a.suiviStock.equals(SuiviStock.aucun.cle))
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
      ..where((a) =>
          a.retireLe.isNull() & a.suiviStock.equals(SuiviStock.direct.cle))
      ..orderBy([(a) => OrderingTerm.asc(a.stockMilliemes)]);
    return requete.get();
  }

  /// Le catalogue tel qu'il s'affiche à la caisse : les plus vendus d'abord.
  Future<List<LigneArticle>> catalogue({int limite = 60, String? recherche}) {
    final requete = base.select(base.articles)
      ..where((a) => a.retireLe.isNull())
      ..orderBy([
        (a) => OrderingTerm.desc(a.nombreVentes),
        (a) => OrderingTerm.desc(a.derniereVente),
      ]);

    final terme = recherche?.trim() ?? '';
    if (terme.isEmpty) {
      // Vue rapide : les plus vendus, ceux qu'on atteint d'un coup d'œil.
      requete.limit(limite);
    } else {
      // Dès qu'on cherche, plus de plafond : au-delà de la limite, un article
      // existait dans la base mais restait invisible au comptoir, et le
      // commerçant le croyait perdu.
      requete.where((a) => a.designation.lower().contains(terme.toLowerCase()));
    }
    return requete.get();
  }

  /// L'article qui porte ce code, s'il existe et s'il est encore au catalogue.
  ///
  /// C'est ce que rend un code-barres scanné : le code lu **est** le code de
  /// l'article. Rien à rapprocher, rien à deviner — un code-barres est déjà un
  /// identifiant unique, c'est même tout ce qu'il est.
  ///
  /// Nul quand l'article n'a jamais été vendu ici, ou qu'il a été retiré : dans
  /// les deux cas la caisse demandera son prix, et le catalogue se garnira tout
  /// seul comme il le fait pour un montant libre.
  Future<LigneArticle?> articleParCode(String code) {
    final propre = code.trim();
    if (propre.isEmpty) return Future.value(null);

    return (base.select(base.articles)
          ..where((a) => a.code.equals(propre) & a.retireLe.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Nombre d'articles au catalogue, pour savoir s'il faut une recherche.
  Future<int> nombreDArticles() async {
    final ligne = await base
        .customSelect('SELECT COUNT(*) AS n FROM articles WHERE retire_le IS NULL',
            readsFrom: {base.articles})
        .getSingle();
    return ligne.read<int>('n');
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

  /// Le détail de ce qu'un client doit : chaque achat, chaque remboursement.
  ///
  /// Le cahier n'affichait qu'un total. Quand le client conteste — et il
  /// conteste toujours — le commerçant n'avait rien à lui montrer, alors que
  /// tout est en base. C'est précisément la dispute que l'ardoise devait
  /// éteindre.
  ///
  /// Les lignes sortent du plus récent au plus ancien : la contestation porte
  /// presque toujours sur le dernier achat.
  Future<List<MouvementDeCompte>> compteDe(String clientId) async {
    final ventes = await (base.select(base.ventes)
          ..where((v) => v.clientId.equals(clientId))
          ..orderBy([(v) => OrderingTerm.desc(v.horodatage)]))
        .get();

    final identifiants = [for (final vente in ventes) vente.id];
    final lignes = identifiants.isEmpty
        ? <LigneDeVente>[]
        : await (base.select(base.lignesVente)
              ..where((l) => l.venteId.isIn(identifiants)))
            .get();
    final aCredit = identifiants.isEmpty
        ? <LignePaiement>[]
        : await (base.select(base.paiements)
              ..where((p) =>
                  p.venteId.isIn(identifiants) &
                  p.mode.equals(ModePaiement.credit.name)))
            .get();

    final mouvements = <MouvementDeCompte>[];

    for (final vente in ventes) {
      final part = aCredit
          .where((p) => p.venteId == vente.id)
          .fold(0, (somme, p) => somme + p.montantCentimes);
      // Une vente payée comptant n'a rien à faire dans une ardoise.
      if (part == 0) continue;

      // Les identifiants de ligne sont séquentiels dans une vente : les
      // trier rend l'ordre de saisie, celui que le client a vu se composer.
      final siennes = lignes.where((l) => l.venteId == vente.id).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      mouvements.add(MouvementDeCompte(
        quand: vente.horodatage,
        montant: Montant(part),
        sens: SensDeCompte.achat,
        annule: vente.annulee,
        detail: [
          for (final ligne in siennes)
            DetailDAchat(
              designation: ligne.designation,
              quantite: Quantite(ligne.quantiteMilliemes),
              total: Montant(ligne.montantCentimes),
            )
        ],
      ));
    }

    // Les remboursements ne sont pas des ventes : ils ne vivent que dans le
    // journal, et c'est là qu'il faut aller les chercher.
    final remboursements = await (base.select(base.evenements)
          ..where((e) => e.type.equals(TypeEvenement.creditRembourse.cle)))
        .get();

    for (final ligne in remboursements) {
      final charge = Evenement.chargeDepuisJson(ligne.charge);
      if (charge['clientId'] != clientId) continue;
      mouvements.add(MouvementDeCompte(
        quand: ligne.horodatage,
        montant: Montant(charge['montant']! as int),
        sens: SensDeCompte.remboursement,
      ));
    }

    // Le journal arrondit à la seconde : un remboursement encaissé juste
    // après un achat porte souvent le même horodatage. À égalité, c'est le
    // remboursement qui vient en dernier — on ne rembourse pas avant
    // d'acheter, et l'ordre affiché doit rester celui des faits.
    mouvements.sort((a, b) {
      final parDate = b.quand.compareTo(a.quand);
      if (parDate != 0) return parDate;
      return a.estAchat == b.estAchat ? 0 : (a.estAchat ? 1 : -1);
    });
    return mouvements;
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
  Future<RapportDuJour> rapportDuJour([DateTime? jour]) {
    final reference = jour ?? DateTime.now();
    final debut = DateTime(reference.year, reference.month, reference.day);
    return rapportSurPeriode(debut, debut.add(const Duration(days: 1)));
  }

  /// Le même rapport, sur n'importe quelle période.
  ///
  /// Le patron absent regarde souvent le lendemain matin : à minuit une, sa
  /// journée d'hier ne doit pas disparaître.
  Future<RapportDuJour> rapportSurPeriode(DateTime debut, DateTime fin) async {
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
              a.retireLe.isNull() &
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

      final tous = await journal.tous();

      // Les clients d'abord, quel que soit leur horodatage.
      //
      // Le rejeu suit l'ordre des faits, et c'est le bon ordre — sauf pour
      // une dépendance : une vente à crédit désigne un client, et si elle est
      // rejouée avant lui, la dette s'applique à quelqu'un qui n'existe pas
      // encore. Elle disparaît alors en silence.
      //
      // Ça ne peut pas arriver sur un seul appareil, dont l'horloge avance :
      // le client est créé au moment de la vente. Ça arrivera le jour où deux
      // caisses se synchroniseront avec des horloges décalées — et ce jour-là,
      // ce sont les dettes des clients qui se perdraient, c'est-à-dire ce que
      // le commerçant a de plus précieux dans ce carnet.
      //
      // Un client n'a besoin de rien d'autre pour exister : les poser tous
      // d'abord retire la dépendance au lieu de parier sur les horloges.
      for (final evenement in tous) {
        if (evenement.type == TypeEvenement.clientCree) {
          await _appliquerCreationClient(evenement);
        }
      }

      for (final evenement in tous) {
        switch (evenement.type) {
          case TypeEvenement.venteEnregistree:
            await _appliquerVente(evenement);
          case TypeEvenement.clientCree:
            // Déjà posé au tour précédent.
            break;
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
          case TypeEvenement.articleRetire:
            await _appliquerRetrait(evenement, retire: true);
          case TypeEvenement.articleRepris:
            await _appliquerRetrait(evenement, retire: false);
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
            await _appliquerAnnulation(evenement);
          case TypeEvenement.factureEmise:
            await _appliquerEmissionFacture(evenement);
          case TypeEvenement.creditAccorde:
          case TypeEvenement.ventecertifiee:
          // Une clôture ne modifie aucune projection : elle borne une période
          // et fige des totaux dans le journal. La rejouer n'a rien à faire.
          case TypeEvenement.clotureTiree:
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
