/// Compose les rapports X, Z et A depuis la base.
///
/// Le calcul est ici, la mise en forme dans `domaine/rapport_fiscal.dart`, et
/// la clôture dans le journal. Cette séparation n'est pas de la coquetterie :
/// c'est le calcul que je devrai montrer au comité d'homologation, et il doit
/// se vérifier sans lancer d'écran.
///
/// Une précision qui décide de tout le fichier : **la caisse enregistre des
/// ventes, pas des factures.** Sur mille ventes du jour, deux seulement
/// donneront lieu à une facture. Les rapports comptent donc les ventes, et
/// les rangent sous le type FV — c'est ce qu'elles sont du point de vue de la
/// note : des ventes au comptant. Le jour où d'autres types apparaîtront
/// (avoirs, acomptes), ils se rangeront à côté sans que rien ne change ici.
library;

import 'package:drift/drift.dart';

import '../domaine/fiche_entreprise.dart';
import '../domaine/montant.dart';
import '../domaine/rapport_fiscal.dart';
import '../domaine/references.dart';
import '../domaine/evenements.dart';
import 'base.dart';
import 'journal.dart';

class Rapports {
  final BaseLocale base;
  final Journal journal;

  /// La fiche qui coiffe le rapport. Le nom suffit chez un commerçant sans
  /// mentions fiscales, et c'est le cas ordinaire.
  final FicheEntreprise fiche;

  const Rapports(this.base, this.journal, {required this.fiche});

  /// Le X-rapport : on regarde sans clôturer.
  ///
  /// Sans bornes, il couvre la période depuis la dernière clôture Z — c'est
  /// « le X quotidien » de la note. Avec des bornes, il couvre la période
  /// choisie : c'est « le X périodique ».
  ///
  /// Il **n'avance pas** la borne des rapports suivants : c'est toute la
  /// différence entre regarder et clôturer. Il est tout de même écrit au
  /// journal, parce que le §2.23 y veut « tous les rapports » — et parce
  /// qu'un X tiré à midi puis un Z qui ne recoupe pas, ça se vérifie.
  Future<RapportFiscal> x({DateTime? debut, DateTime? fin}) async {
    final maintenant = DateTime.now();
    final depuis = debut ?? await derniereCloture(NatureRapport.z) ?? await _origine();
    final borne = fin ?? maintenant;
    final numero = await _prochainNumero(NatureRapport.x);

    final rapport = await _composer(
      nature: NatureRapport.x,
      debut: depuis,
      fin: borne,
      tireLe: maintenant,
      numero: numero,
    );

    await journal.ajouter(
      TypeEvenement.clotureTiree,
      {
        'nature': NatureRapport.x.code,
        'numero': numero,
        'debut': depuis.toIso8601String(),
        'fin': borne.toIso8601String(),
        'totalCentimes': rapport.total.centimes,
        'taxeCentimes': rapport.taxe.centimes,
        'especesCentimes': rapport.especes.centimes,
        'nombreFactures': rapport.nombreFactures,
      },
      horodatage: maintenant,
    );

    return rapport;
  }

  /// Le Z-rapport : la clôture.
  ///
  /// Il arrête la période et l'écrit au journal. Le Z suivant repartira d'ici,
  /// et c'est ce qui rend la série vérifiable : un rapport qu'on peut retirer
  /// deux fois avec deux résultats différents ne clôture rien.
  Future<RapportFiscal> z({DateTime? quand}) async {
    final maintenant = quand ?? DateTime.now();
    final depuis = await derniereCloture(NatureRapport.z) ?? await _origine();
    final numero = await _prochainNumero(NatureRapport.z);

    final rapport = await _composer(
      nature: NatureRapport.z,
      debut: depuis,
      fin: maintenant,
      tireLe: maintenant,
      numero: numero,
    );

    await journal.ajouter(
      TypeEvenement.clotureTiree,
      {
        'nature': NatureRapport.z.code,
        'numero': numero,
        'debut': depuis.toIso8601String(),
        'fin': maintenant.toIso8601String(),
        // Les totaux sont figés dans l'événement, pas seulement recalculables.
        // Une correction ultérieure — un article renommé, une projection
        // reconstruite — ne doit pas changer un Z déjà remis.
        'totalCentimes': rapport.total.centimes,
        'taxeCentimes': rapport.taxe.centimes,
        'especesCentimes': rapport.especes.centimes,
        'nombreFactures': rapport.nombreFactures,
      },
      horodatage: maintenant,
    );

    return rapport;
  }

  /// Le A-rapport : par article, depuis le dernier A.
  Future<RapportFiscal> a({DateTime? quand}) async {
    final maintenant = quand ?? DateTime.now();
    final depuis = await derniereCloture(NatureRapport.a) ?? await _origine();
    final numero = await _prochainNumero(NatureRapport.a);

    final rapport = RapportFiscal(
      nature: NatureRapport.a,
      emetteur: fiche,
      numero: numero,
      debut: depuis,
      fin: maintenant,
      tireLe: maintenant,
      articles: await _articles(depuis, maintenant),
    );

    await journal.ajouter(
      TypeEvenement.clotureTiree,
      {
        'nature': NatureRapport.a.code,
        'numero': numero,
        'debut': depuis.toIso8601String(),
        'fin': maintenant.toIso8601String(),
        'nombreArticles': rapport.articles.length,
      },
      horodatage: maintenant,
    );

    return rapport;
  }

  /// Quand la dernière clôture de cette nature a été tirée. Nulle quand il n'y
  /// en a jamais eu — le premier Z couvre alors tout depuis l'installation.
  Future<DateTime?> derniereCloture(NatureRapport nature) async {
    DateTime? derniere;
    for (final evenement in await journal.tous()) {
      if (evenement.type != TypeEvenement.clotureTiree) continue;
      if (evenement.charge['nature'] != nature.code) continue;
      final fin = DateTime.tryParse(evenement.charge['fin'] as String? ?? '');
      if (fin == null) continue;
      if (derniere == null || fin.isAfter(derniere)) derniere = fin;
    }
    return derniere;
  }

  /// Les clôtures déjà tirées, de la plus récente à la plus ancienne.
  ///
  /// C'est l'historique qu'un contrôleur demande : « montre-moi les Z du
  /// mois ». Il se lit au journal, qui ne se réécrit pas.
  Future<List<ClotureTiree>> clotures({NatureRapport? nature}) async {
    final sortie = <ClotureTiree>[];
    for (final evenement in await journal.tous()) {
      if (evenement.type != TypeEvenement.clotureTiree) continue;
      final quelle = NatureRapport.parCode(
          evenement.charge['nature'] as String? ?? 'Z');
      if (nature != null && quelle != nature) continue;

      sortie.add(ClotureTiree(
        nature: quelle,
        numero: evenement.charge['numero'] as int? ?? 0,
        debut: DateTime.parse(evenement.charge['debut']! as String),
        fin: DateTime.parse(evenement.charge['fin']! as String),
        total: Montant(evenement.charge['totalCentimes'] as int? ?? 0),
        especes: Montant(evenement.charge['especesCentimes'] as int? ?? 0),
        nombreFactures: evenement.charge['nombreFactures'] as int? ?? 0,
      ));
    }
    return sortie.reversed.toList();
  }

  Future<int> _prochainNumero(NatureRapport nature) async {
    var maximum = 0;
    for (final evenement in await journal.tous()) {
      if (evenement.type != TypeEvenement.clotureTiree) continue;
      if (evenement.charge['nature'] != nature.code) continue;
      final numero = evenement.charge['numero'] as int? ?? 0;
      if (numero > maximum) maximum = numero;
    }
    return maximum + 1;
  }

  /// La borne de départ du tout premier rapport, faute de clôture précédente.
  ///
  /// Le premier événement du journal, c'est-à-dire le jour où le carnet a
  /// commencé. Une date fixe conviendrait au calcul — tout est postérieur —
  /// mais elle s'imprime sur le rapport, et « Du 01/01/1970 » ne veut rien
  /// dire pour un commerçant qui ouvre sa caisse. Vu sur une capture, pas
  /// dans un test : aucun test ne lisait la ligne de période.
  /// Une seconde **avant** le premier événement : les bornes de période sont
  /// strictes à gauche, pour qu'une vente tombant pile à l'instant d'un Z ne
  /// compte pas deux fois. Rendre l'horodatage exact exclurait donc la toute
  /// première vente de son propre premier rapport.
  Future<DateTime> _origine() async {
    final tous = await journal.tous();
    if (tous.isEmpty) return DateTime.now();
    return tous.first.horodatage.subtract(const Duration(seconds: 1));
  }

  Future<RapportFiscal> _composer({
    required NatureRapport nature,
    required DateTime debut,
    required DateTime fin,
    required DateTime tireLe,
    required int numero,
  }) async {
    final ventes = await (base.select(base.ventes)
          ..where((v) =>
              v.horodatage.isBiggerThanValue(debut) &
              v.horodatage.isSmallerOrEqualValue(fin)))
        .get();

    final retenues = ventes.where((v) => !v.annulee).toList();
    final annulees = ventes.where((v) => v.annulee).toList();

    // Une vente encore ouverte n'est pas une vente : le §5 veut leur nombre
    // à part, et les compter dans le total gonflerait la journée d'une note
    // de restaurant que personne n'a payée.
    final incompletes =
        retenues.where((v) => EtatVente.parCle(v.etat) == EtatVente.ouverte);
    final abouties =
        retenues.where((v) => EtatVente.parCle(v.etat) != EtatVente.ouverte)
            .toList();

    final identifiants = abouties.map((v) => v.id).toList();

    final parGroupe = await _parGroupe(identifiants);
    final parMode = await _parMode(identifiants);

    var total = const Montant.zero();
    var taxable = const Montant.zero();
    var taxe = const Montant.zero();
    for (final entree in parGroupe) {
      total = total + entree.total;
      taxable = taxable + entree.taxable;
      taxe = taxe + entree.taxe;
    }

    var remises = const Montant.zero();
    for (final vente in abouties) {
      remises = remises + Montant(vente.remiseCentimes);
    }

    var annule = const Montant.zero();
    for (final vente in annulees) {
      annule = annule + Montant(vente.totalCentimes);
    }

    return RapportFiscal(
      nature: nature,
      emetteur: fiche,
      numero: numero,
      debut: debut,
      fin: fin,
      tireLe: tireLe,
      parType: [
        if (abouties.isNotEmpty)
          TotauxParType(
            type: TypeFacture.vente,
            nombre: abouties.length,
            total: total,
            taxable: taxable,
            taxe: taxe,
          ),
      ],
      parGroupe: parGroupe,
      parMode: parMode,
      reductions: remises,
      autresReductions: annule,
      ventesIncompletes: incompletes.length,
    );
  }

  /// Les totaux par groupe de taxation.
  ///
  /// Les prix pratiqués sont toutes taxes comprises : la taxe s'en extrait,
  /// arrondie à la valeur supérieure comme l'impose le §6.7, et le montant
  /// imposable s'obtient par différence. C'est la même règle que dans le
  /// calcul de facture, et elle doit le rester : deux façons d'arrondir
  /// donneraient un Z qui ne recoupe pas les factures du jour.
  Future<List<TotauxParGroupe>> _parGroupe(List<String> ventes) async {
    if (ventes.isEmpty) return const [];

    final lignes = await (base.select(base.lignesVente)
          ..where((l) => l.venteId.isIn(ventes)))
        .get();

    final cumuls = <String, int>{};
    for (final ligne in lignes) {
      cumuls[ligne.groupeTaxation] =
          (cumuls[ligne.groupeTaxation] ?? 0) + ligne.montantCentimes;
    }

    return [
      for (final groupe in GroupeTaxation.tous)
        if (cumuls.containsKey(groupe.etiquette))
          _totaliser(groupe, Montant(cumuls[groupe.etiquette]!)),
    ];
  }

  static TotauxParGroupe _totaliser(GroupeTaxation groupe, Montant ttc) {
    if (!groupe.estTaxe) {
      return TotauxParGroupe(
        groupe: groupe,
        total: ttc,
        taxable: ttc,
        taxe: const Montant.zero(),
      );
    }
    final taxe = ttc.taxeIncluseArrondiSuperieur(groupe.tauxMillieme!);
    return TotauxParGroupe(
      groupe: groupe,
      total: ttc,
      taxable: ttc - taxe,
      taxe: taxe,
    );
  }

  Future<Map<ModePaiement, Montant>> _parMode(List<String> ventes) async {
    if (ventes.isEmpty) return const {};

    final paiements = await (base.select(base.paiements)
          ..where((p) => p.venteId.isIn(ventes)))
        .get();

    final parMode = <ModePaiement, Montant>{};
    for (final paiement in paiements) {
      final mode = ModePaiement.values.firstWhere(
        (m) => m.name == paiement.mode,
        orElse: () => ModePaiement.especes,
      );
      parMode[mode] =
          (parMode[mode] ?? const Montant.zero()) + Montant(paiement.montantCentimes);
    }
    return parMode;
  }

  /// Les articles vendus sur la période, avec ce qui est revenu et ce qui
  /// reste.
  Future<List<LigneArticleRapport>> _articles(
      DateTime debut, DateTime fin) async {
    final ventes = await (base.select(base.ventes)
          ..where((v) =>
              v.horodatage.isBiggerThanValue(debut) &
              v.horodatage.isSmallerOrEqualValue(fin)))
        .get();
    if (ventes.isEmpty) return const [];

    final annulees = {for (final v in ventes.where((v) => v.annulee)) v.id};
    final lignes = await (base.select(base.lignesVente)
          ..where((l) => l.venteId.isIn(ventes.map((v) => v.id).toList())))
        .get();

    final vendu = <String, int>{};
    final retourne = <String, int>{};
    final designation = <String, String>{};
    final prix = <String, int>{};

    for (final ligne in lignes) {
      designation[ligne.codeArticle] = ligne.designation;
      prix[ligne.codeArticle] = ligne.prixUnitaireCentimes;
      // Une vente annulée compte en retour, pas en moins de ventes : c'est ce
      // que le A-rapport demande, et c'est aussi plus honnête — la
      // marchandise est bien sortie puis revenue.
      final cible = annulees.contains(ligne.venteId) ? retourne : vendu;
      cible[ligne.codeArticle] =
          (cible[ligne.codeArticle] ?? 0) + ligne.quantiteMilliemes;
    }

    final catalogue = {
      for (final article in await base.select(base.articles).get())
        article.code: article
    };

    final codes = {...vendu.keys, ...retourne.keys}.toList()..sort();

    return [
      for (final code in codes)
        LigneArticleRapport(
          code: code,
          nom: designation[code] ?? catalogue[code]?.designation ?? code,
          prixUnitaire: Montant(prix[code] ?? catalogue[code]?.prixCentimes ?? 0),
          tauxMillieme: catalogue[code] == null
              ? null
              : GroupeTaxation.parEtiquette(catalogue[code]!.groupeTaxation)
                  .tauxMillieme,
          venduee: Quantite(vendu[code] ?? 0),
          retournee: Quantite(retourne[code] ?? 0),
          enStock: catalogue[code]?.stockMilliemes == null
              ? null
              : Quantite(catalogue[code]!.stockMilliemes!),
        ),
    ];
  }
}

/// Une clôture déjà tirée, telle que le journal la garde.
class ClotureTiree {
  final NatureRapport nature;
  final int numero;
  final DateTime debut;
  final DateTime fin;
  final Montant total;
  final Montant especes;
  final int nombreFactures;

  const ClotureTiree({
    required this.nature,
    required this.numero,
    required this.debut,
    required this.fin,
    required this.total,
    required this.especes,
    required this.nombreFactures,
  });
}
