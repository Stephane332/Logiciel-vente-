/// Analyses de vente.
///
/// L'intention n'est pas de dresser un palmarès : un commerçant sait déjà ce
/// qu'il vend le plus. Ce qu'il ne sait pas, c'est **ce qui a changé** —
/// quel article s'est mis à baisser, lequel dort sur l'étagère depuis des
/// semaines, et combien d'argent y est immobilisé.
///
/// Toutes ces analyses se lisent dans les projections. Aucune donnée nouvelle
/// n'est nécessaire : le journal les contenait déjà.
library;

import 'package:drift/drift.dart';

import '../domaine/montant.dart';
import '../domaine/references.dart';
import 'base.dart';

/// Ce qu'un article a rapporté sur une période.
class PerformanceArticle {
  final String code;
  final String designation;
  final Quantite quantiteVendue;
  final Montant chiffre;

  /// Nombre de ventes distinctes où l'article apparaît.
  final int nombreVentes;

  const PerformanceArticle({
    required this.code,
    required this.designation,
    required this.quantiteVendue,
    required this.chiffre,
    required this.nombreVentes,
  });
}

/// Un article qui ne bouge plus.
class ArticleEndormi {
  final String code;
  final String designation;
  final DateTime? derniereVente;
  final int joursSansVente;

  /// Ce que le stock restant représente au prix de vente, quand le stock est
  /// connu. C'est l'argent immobilisé sur l'étagère.
  final Montant? valeurImmobilisee;

  const ArticleEndormi({
    required this.code,
    required this.designation,
    required this.joursSansVente,
    this.derniereVente,
    this.valeurImmobilisee,
  });
}

/// Comparaison d'un article entre deux périodes de même durée.
class EvolutionArticle {
  final String code;
  final String designation;
  final Montant chiffreActuel;
  final Montant chiffrePrecedent;

  const EvolutionArticle({
    required this.code,
    required this.designation,
    required this.chiffreActuel,
    required this.chiffrePrecedent,
  });

  Montant get ecart => chiffreActuel - chiffrePrecedent;

  /// Variation en pourcentage. Nulle quand la période précédente est vide :
  /// on ne compare pas à zéro.
  double? get variation => chiffrePrecedent.estNul
      ? null
      : (chiffreActuel.centimes - chiffrePrecedent.centimes) *
          100 /
          chiffrePrecedent.centimes;

  bool get enBaisse => ecart.estNegatif;
}

/// Habitudes d'achat d'un client.
///
/// Sert au commerçant, pas au client : savoir qu'Awa achète du riz tous les
/// vendredis et qu'elle n'est pas venue depuis trois semaines, c'est ce qui
/// permet de la rappeler — ou de comprendre pourquoi sa dette ne bouge plus.
class HabitudesClient {
  final String clientId;
  final String nom;
  final List<PerformanceArticle> articlesHabituels;
  final Montant totalDepense;
  final int nombreVisites;
  final DateTime? dernierePresence;

  const HabitudesClient({
    required this.clientId,
    required this.nom,
    required this.articlesHabituels,
    required this.totalDepense,
    required this.nombreVisites,
    this.dernierePresence,
  });

  int? get joursDAbsence => dernierePresence == null
      ? null
      : DateTime.now().difference(dernierePresence!).inDays;
}

/// Alerte de réapprovisionnement.
///
/// Le seuil n'est pas un nombre fixe. « Alerte à 5 unités » est faux partout :
/// cinq sacs de riz, c'est beaucoup ; cinq sachets d'eau, c'est rien. Le
/// seuil se déduit de la **vitesse de vente**, ce qui le règle tout seul et
/// tient compte du fait que se réapprovisionner prend du temps.
class AlerteStock {
  final String code;
  final String designation;
  final Quantite stockRestant;

  /// Quantité vendue par jour sur la période observée.
  final double parJour;

  /// Jours de stock restants au rythme actuel. Nul si l'article ne se vend
  /// plus du tout — dans ce cas ce n'est pas un problème de stock.
  final int? joursRestants;

  const AlerteStock({
    required this.code,
    required this.designation,
    required this.stockRestant,
    required this.parJour,
    this.joursRestants,
  });

  bool get enRupture => stockRestant.milliemes <= 0;

  String get message {
    if (enRupture) return '$designation — rupture';
    if (joursRestants == null) return '$designation — stock dormant';
    if (joursRestants == 0) return '$designation — il ne reste presque rien';
    return '$designation — il te reste $joursRestants jour'
        '${joursRestants! > 1 ? 's' : ''}';
  }
}

class Analyses {
  final BaseLocale base;

  const Analyses(this.base);

  /// Ce qui s'est le mieux vendu sur une période.
  ///
  /// Classé par chiffre d'affaires : dix sachets d'eau à 100 F pèsent moins
  /// qu'un sac de riz à 20 000 F, et c'est le second qui décide du
  /// réapprovisionnement.
  Future<List<PerformanceArticle>> meilleuresVentes({
    required DateTime debut,
    required DateTime fin,
    int limite = 10,
  }) async {
    final lignes = await base.customSelect(
      '''
      SELECT l.code_article               AS code,
             MAX(l.designation)           AS designation,
             SUM(l.quantite_milliemes)    AS quantite,
             SUM(l.montant_centimes)      AS chiffre,
             COUNT(DISTINCT l.vente_id)   AS ventes
      FROM lignes_vente l
      JOIN ventes v ON v.id = l.vente_id
      WHERE v.annulee = 0
        AND v.horodatage >= ?
        AND v.horodatage <  ?
      GROUP BY l.code_article
      ORDER BY chiffre DESC
      LIMIT ?
      ''',
      variables: [
        Variable<DateTime>(debut),
        Variable<DateTime>(fin),
        Variable<int>(limite),
      ],
      readsFrom: {base.lignesVente, base.ventes},
    ).get();

    return lignes.map(_versPerformance).toList();
  }

  /// Les articles qui ne se vendent plus.
  ///
  /// Un commerçant remarque tout de suite ce qui se vend bien. Il ne remarque
  /// presque jamais ce qui a cessé de se vendre — c'est pourtant là que son
  /// argent dort.
  Future<List<ArticleEndormi>> articlesQuiDorment({
    int joursSansVente = 21,
    int ventesMinimum = 3,
    DateTime? maintenant,
  }) async {
    final reference = maintenant ?? DateTime.now();
    final limite = reference.subtract(Duration(days: joursSansVente));

    final requete = base.select(base.articles)
      ..where((a) =>
          a.nombreVentes.isBiggerOrEqualValue(ventesMinimum) &
          a.derniereVente.isSmallerThanValue(limite))
      ..orderBy([(a) => OrderingTerm.asc(a.derniereVente)]);

    final articles = await requete.get();

    return articles.map((a) {
      final stock = a.stockMilliemes;
      return ArticleEndormi(
        code: a.code,
        designation: a.designation,
        derniereVente: a.derniereVente,
        joursSansVente: a.derniereVente == null
            ? joursSansVente
            : reference.difference(a.derniereVente!).inDays,
        valeurImmobilisee: stock == null || stock <= 0
            ? null
            : Montant(a.prixCentimes)
                .multiplieParQuantite(Quantite(stock)),
      );
    }).toList();
  }

  /// Compare une période à la précédente, de même durée.
  ///
  /// C'est la seule façon honnête de dire « ça baisse » : au Burkina les
  /// ventes suivent les saisons, les fêtes et la rentrée. Un chiffre isolé
  /// ne veut rien dire.
  Future<List<EvolutionArticle>> evolution({
    required DateTime debut,
    required DateTime fin,
    int limite = 10,
  }) async {
    final duree = fin.difference(debut);
    final actuelles = await meilleuresVentes(
        debut: debut, fin: fin, limite: 1000);
    final precedentes = await meilleuresVentes(
        debut: debut.subtract(duree), fin: debut, limite: 1000);

    final avant = {for (final p in precedentes) p.code: p.chiffre};
    final codes = {...actuelles.map((a) => a.code), ...avant.keys};

    final designations = {
      for (final p in [...actuelles, ...precedentes]) p.code: p.designation
    };
    final apres = {for (final a in actuelles) a.code: a.chiffre};

    final evolutions = codes
        .map((code) => EvolutionArticle(
              code: code,
              designation: designations[code] ?? code,
              chiffreActuel: apres[code] ?? const Montant.zero(),
              chiffrePrecedent: avant[code] ?? const Montant.zero(),
            ))
        .toList()
      ..sort((a, b) => a.ecart.centimes.compareTo(b.ecart.centimes));

    return evolutions.take(limite).toList();
  }

  /// Ce qu'il faut réapprovisionner, et dans quel ordre d'urgence.
  ///
  /// Ne concerne que les articles en suivi direct : un plat de restaurant
  /// consomme des ingrédients et non lui-même, un service ne consomme rien.
  Future<List<AlerteStock>> aReapprovisionner({
    int joursDAvance = 5,
    int fenetreObservation = 14,
    DateTime? maintenant,
  }) async {
    final reference = maintenant ?? DateTime.now();
    final debut = reference.subtract(Duration(days: fenetreObservation));

    final articles = await (base.select(base.articles)
          ..where((a) => a.suiviStock.equals(SuiviStock.direct.cle)))
        .get();
    if (articles.isEmpty) return [];

    final vitesses = await base.customSelect(
      '''
      SELECT l.code_article            AS code,
             SUM(l.quantite_milliemes) AS quantite
      FROM lignes_vente l
      JOIN ventes v ON v.id = l.vente_id
      WHERE v.annulee = 0 AND v.horodatage >= ? AND v.horodatage < ?
      GROUP BY l.code_article
      ''',
      variables: [
        Variable<DateTime>(debut),
        Variable<DateTime>(reference),
      ],
      readsFrom: {base.lignesVente, base.ventes},
    ).get();

    final vendu = {
      for (final ligne in vitesses)
        ligne.read<String>('code'): ligne.read<int>('quantite')
    };

    final alertes = <AlerteStock>[];
    for (final article in articles) {
      final stock = article.stockMilliemes;
      if (stock == null) continue;

      final parJour = (vendu[article.code] ?? 0) / 1000 / fenetreObservation;
      final restants =
          parJour <= 0 ? null : (stock / 1000 / parJour).floor();

      // On alerte si c'est en rupture, ou s'il reste moins de jours que le
      // délai de réapprovisionnement.
      final urgent = stock <= 0 || (restants != null && restants <= joursDAvance);
      if (!urgent) continue;

      alertes.add(AlerteStock(
        code: article.code,
        designation: article.designation,
        stockRestant: Quantite(stock),
        parJour: parJour,
        joursRestants: restants,
      ));
    }

    alertes.sort((a, b) {
      if (a.enRupture != b.enRupture) return a.enRupture ? -1 : 1;
      return (a.joursRestants ?? 9999).compareTo(b.joursRestants ?? 9999);
    });
    return alertes;
  }

  /// Ce qu'un client achète d'habitude, et depuis quand il n'est pas venu.
  Future<HabitudesClient?> habitudesDe(String clientId) async {
    final client = await (base.select(base.clients)
          ..where((c) => c.id.equals(clientId)))
        .getSingleOrNull();
    if (client == null) return null;

    final lignes = await base.customSelect(
      '''
      SELECT l.code_article             AS code,
             MAX(l.designation)         AS designation,
             SUM(l.quantite_milliemes)  AS quantite,
             SUM(l.montant_centimes)    AS chiffre,
             COUNT(DISTINCT l.vente_id) AS ventes
      FROM lignes_vente l
      JOIN ventes v ON v.id = l.vente_id
      WHERE v.annulee = 0 AND v.client_id = ?
      GROUP BY l.code_article
      ORDER BY chiffre DESC
      ''',
      variables: [Variable<String>(clientId)],
      readsFrom: {base.lignesVente, base.ventes},
    ).get();

    final ventes = await (base.select(base.ventes)
          ..where((v) => v.clientId.equals(clientId) & v.annulee.equals(false))
          ..orderBy([(v) => OrderingTerm.desc(v.horodatage)]))
        .get();

    return HabitudesClient(
      clientId: clientId,
      nom: client.nom,
      articlesHabituels: lignes.map(_versPerformance).toList(),
      totalDepense: Montant(ventes.fold(0, (s, v) => s + v.totalCentimes)),
      nombreVisites: ventes.length,
      dernierePresence: ventes.isEmpty ? null : ventes.first.horodatage,
    );
  }

  static PerformanceArticle _versPerformance(QueryRow ligne) =>
      PerformanceArticle(
        code: ligne.read<String>('code'),
        designation: ligne.read<String>('designation'),
        quantiteVendue: Quantite(ligne.read<int>('quantite')),
        chiffre: Montant(ligne.read<int>('chiffre')),
        nombreVentes: ligne.read<int>('ventes'),
      );
}
