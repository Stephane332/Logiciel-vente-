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
      final lignesResolues = <Map<String, Object?>>[];
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
          final ecart = ligne.prixCatalogue!.multiplieParQuantite(ligne.quantite) -
              montant;
          if (ecart.estPositif) remise = remise + ecart;
        }

        lignesResolues.add({
          'code': code,
          'designation': designation,
          'quantite': ligne.quantite.milliemes,
          'prix': ligne.prixUnitaire.centimes,
          'prixCatalogue': ligne.prixCatalogue?.centimes,
          'groupe': ligne.groupeTaxation.etiquette,
          'montant': montant.centimes,
        });
      }

      final evenement = await journal.ajouter(
        TypeEvenement.venteEnregistree,
        {
          'lignes': lignesResolues,
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

    final lignes = (charge['lignes']! as List).cast<Map<String, Object?>>();
    for (var i = 0; i < lignes.length; i++) {
      final ligne = lignes[i];
      final code = ligne['code']! as String;

      await base.into(base.lignesVente).insert(
            LignesVenteCompanion.insert(
              id: '$venteId-$i',
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
        quand: evenement.horodatage,
      );
    }

    final paiements = (charge['paiements'] as List? ?? const [])
        .cast<Map<String, Object?>>();
    for (var i = 0; i < paiements.length; i++) {
      final paiement = paiements[i];
      await base.into(base.paiements).insert(
            PaiementsCompanion.insert(
              id: '$venteId-p$i',
              venteId: venteId,
              mode: paiement['mode']! as String,
              montantCentimes: paiement['montant']! as int,
              reference: Value(paiement['reference'] as String?),
              expediteur: Value(paiement['expediteur'] as String?),
            ),
          );

      // Une vente à crédit alimente le cahier de dettes.
      final clientId = charge['clientId'] as String?;
      if (paiement['mode'] == ModePaiement.credit.name && clientId != null) {
        await _ajusterEncours(
          clientId,
          paiement['montant']! as int,
          evenement.horodatage,
        );
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
  Future<void> ajusterStock(String code, Quantite quantite) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.stockAjuste, {
        'code': code,
        'quantite': quantite.milliemes,
      });
      await _appliquerAjustementStock(evenement);
    });
  }

  Future<void> _appliquerAjustementStock(Evenement evenement) async {
    await (base.update(base.articles)
          ..where((a) => a.code.equals(evenement.charge['code']! as String)))
        .write(ArticlesCompanion(
      stockMilliemes: Value(evenement.charge['quantite']! as int),
      suiviStock: Value(SuiviStock.direct.cle),
    ));
  }

  /// Change le mode de suivi du stock d'un article.
  ///
  /// Repasser en `aucun` oublie le stock connu : mieux vaut ne rien afficher
  /// qu'un chiffre qu'on a cessé de tenir à jour.
  Future<void> definirSuiviStock(String code, SuiviStock suivi) async {
    await base.transaction(() async {
      final evenement = await journal.ajouter(TypeEvenement.stockAjuste, {
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

  /// Les articles vendus assez souvent pour mériter un nom.
  Future<List<LigneArticle>> articlesANommer() {
    final requete = base.select(base.articles)
      ..where((a) =>
          a.nomme.equals(false) & a.nombreVentes.isBiggerOrEqualValue(seuilDeNommage))
      ..orderBy([(a) => OrderingTerm.desc(a.nombreVentes)]);
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

      for (final evenement in await journal.tous()) {
        switch (evenement.type) {
          case TypeEvenement.venteEnregistree:
            await _appliquerVente(evenement);
          case TypeEvenement.clientCree:
            await _appliquerCreationClient(evenement);
          case TypeEvenement.articleNomme:
            await _appliquerNommage(evenement);
          case TypeEvenement.stockAjuste:
            if (evenement.charge.containsKey('suivi')) {
              await _appliquerModeSuivi(evenement);
            } else {
              await _appliquerAjustementStock(evenement);
            }
          case TypeEvenement.creditRembourse:
            await _appliquerRemboursement(evenement);
          case TypeEvenement.caisseMouvement:
            await _appliquerMouvementCaisse(evenement);
          case TypeEvenement.venteAnnulee:
          case TypeEvenement.articleCree:
          case TypeEvenement.articlePrixModifie:
          case TypeEvenement.creditAccorde:
          case TypeEvenement.ventecertifiee:
            break;
        }
      }
    });
  }
}
