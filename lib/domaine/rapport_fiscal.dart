/// Les rapports X, Z et A.
///
/// Le §5 de la note de service n° 2025-0889 en impose trois, et leur contenu
/// est énuméré ligne par ligne. Ils ne dépendent d'aucun module de contrôle :
/// ce sont des totaux sur ce que la caisse a déjà enregistré, et je peux donc
/// les produire aujourd'hui.
///
/// Ils ne servent pas que l'administration, et c'est ce qui m'a décidé à les
/// faire tôt. **Le Z est la clôture de caisse** : le geste du soir, celui qui
/// arrête la journée et dit combien il doit y avoir dans le tiroir. Un
/// commerçant qui compte son argent le fait déjà ; il le fait de tête, et il
/// se trompe. Le X est le même chiffre sans arrêter la journée — pour jeter un
/// œil à midi sans rien clôturer.
///
/// | Rapport | Période | Effet |
/// |---|---|---|
/// | X | depuis le dernier Z, ou une période choisie | aucun, il se relit |
/// | Z | depuis le dernier Z | il clôture : le suivant repart d'ici |
/// | A | depuis le dernier A, par article | il clôture aussi |
library;

import 'document_client.dart';
import 'fiche_entreprise.dart';
import 'montant.dart';
import 'references.dart';

/// Ce qu'un rapport arrête.
enum NatureRapport {
  /// Lecture sans clôture. Se retire autant de fois qu'on veut.
  x('X', 'X-rapport'),

  /// Clôture de la période. Le rapport suivant repart d'ici.
  z('Z', 'Z-rapport'),

  /// Clôture par article.
  a('A', 'A-rapport');

  final String code;
  final String libelle;
  const NatureRapport(this.code, this.libelle);

  /// Vrai quand le rapport arrête une période. Le X ne le fait pas : c'est
  /// toute la différence entre regarder et clôturer.
  bool get cloture => this != x;

  static NatureRapport parCode(String code) => values.firstWhere(
        (n) => n.code == code,
        orElse: () => x,
      );
}

/// Les totaux d'un ensemble de factures, par type puis par groupe.
class TotauxParType {
  final TypeFacture type;
  final int nombre;
  final Montant total;
  final Montant taxable;
  final Montant taxe;

  const TotauxParType({
    required this.type,
    required this.nombre,
    required this.total,
    required this.taxable,
    required this.taxe,
  });
}

/// Les totaux d'un groupe de taxation sur la période.
class TotauxParGroupe {
  final GroupeTaxation groupe;
  final Montant total;
  final Montant taxable;
  final Montant taxe;

  const TotauxParGroupe({
    required this.groupe,
    required this.total,
    required this.taxable,
    required this.taxe,
  });
}

/// Un article, tel que le A-rapport le compte.
class LigneArticleRapport {
  final String code;
  final String nom;
  final Montant prixUnitaire;

  /// Taux d'impôt en millièmes, tel que le groupe de taxation le porte.
  final int? tauxMillieme;

  final Quantite venduee;

  /// Ce qui est revenu : annulations et reprises.
  final Quantite retournee;

  /// Ce qui reste sur l'étagère. Nulle quand l'article n'est pas suivi — et
  /// c'est le cas de la plupart, ce qui est un choix, pas un oubli.
  final Quantite? enStock;

  const LigneArticleRapport({
    required this.code,
    required this.nom,
    required this.prixUnitaire,
    required this.venduee,
    required this.retournee,
    this.tauxMillieme,
    this.enStock,
  });
}

/// Un rapport X, Z ou A composé.
///
/// Le même objet porte les trois : leur contenu commun est le même, et ce qui
/// les distingue tient à la période et à l'effet de clôture. Trois classes
/// auraient triplé le même code.
class RapportFiscal {
  final NatureRapport nature;
  final FicheEntreprise emetteur;

  /// Le numéro d'ordre du rapport dans sa série. Un contrôleur demande « le Z
  /// du 12 » : sans numéro il faudrait chercher par date, et deux Z du même
  /// jour seraient indiscernables.
  final int numero;

  final DateTime debut;
  final DateTime fin;

  /// Quand le rapport a été tiré. Distinct de [fin] pour un X périodique, où
  /// l'on regarde une période passée.
  final DateTime tireLe;

  final List<TotauxParType> parType;
  final List<TotauxParGroupe> parGroupe;
  final Map<ModePaiement, Montant> parMode;

  /// Les remises accordées sur la période (§5, « réductions commerciales »).
  final Montant reductions;

  /// Ce qui a réduit les ventes autrement : annulations, avoirs, pertes.
  final Montant autresReductions;

  /// Les ventes restées ouvertes en fin de période — une note de restaurant
  /// jamais soldée, un panier abandonné. La note les appelle « ventes
  /// incomplètes » et veut leur nombre.
  final int ventesIncompletes;

  /// Les articles, pour un A-rapport. Vide pour les autres.
  final List<LigneArticleRapport> articles;

  const RapportFiscal({
    required this.nature,
    required this.emetteur,
    required this.numero,
    required this.debut,
    required this.fin,
    required this.tireLe,
    this.parType = const [],
    this.parGroupe = const [],
    this.parMode = const {},
    this.reductions = const Montant.zero(),
    this.autresReductions = const Montant.zero(),
    this.ventesIncompletes = 0,
    this.articles = const [],
  });

  Montant get total => _cumul((t) => t.total);
  Montant get taxable => _cumul((t) => t.taxable);
  Montant get taxe => _cumul((t) => t.taxe);
  int get nombreFactures =>
      parType.fold(0, (somme, t) => somme + t.nombre);

  Montant _cumul(Montant Function(TotauxParType) quoi) {
    var somme = const Montant.zero();
    for (final entree in parType) {
      somme = somme + quoi(entree);
    }
    return somme;
  }

  /// Ce que le tiroir devrait contenir : les espèces encaissées, rien d'autre.
  ///
  /// C'est le chiffre que le commerçant vient chercher, avant toute
  /// considération fiscale. Le mobile money est sur son téléphone, le crédit
  /// n'est nulle part encore.
  Montant get especes => parMode[ModePaiement.especes] ?? const Montant.zero();

  /// Le rapport, ligne par ligne, tel qu'il s'imprime et tel qu'il s'envoie.
  List<String> get lignes {
    final sortie = <String>[
      ...emetteur.enTete,
      _separateur,
      '${nature.libelle} n° $numero',
      'Du ${_horodatage(debut)}',
      'Au ${_horodatage(fin)}',
      'Tiré le ${_horodatage(tireLe)}',
      _separateur,
    ];

    if (nature == NatureRapport.a) {
      sortie.addAll(_lignesArticles);
      sortie.add(_separateur);
      return sortie;
    }

    sortie.add('Par type de facture :');
    if (parType.isEmpty) {
      sortie.add('  Aucune facture sur la période.');
    }
    for (final entree in parType) {
      sortie
        ..add('${entree.type.etiquette} · ${entree.type.libelle}'
            ' (${entree.nombre})')
        ..add(DocumentClient.aligne('  Total', entree.total.enFrancs))
        ..add(DocumentClient.aligne('  Taxable', entree.taxable.enFrancs))
        ..add(DocumentClient.aligne('  Taxe', entree.taxe.enFrancs));
    }

    sortie
      ..add(_separateur)
      ..add('Par groupe de taxation :');
    if (parGroupe.isEmpty) {
      sortie.add('  Aucun.');
    }
    for (final entree in parGroupe) {
      final taux = entree.groupe.tauxMillieme;
      final tauxLisible =
          taux == null || taux == 0 ? '—' : '${(taux / 10).toStringAsFixed(0)} %';
      sortie
        ..add('${entree.groupe.etiquette} · $tauxLisible')
        ..add(DocumentClient.aligne('  Taxable', entree.taxable.enFrancs))
        ..add(DocumentClient.aligne('  Taxe', entree.taxe.enFrancs));
    }

    sortie
      ..add(_separateur)
      ..add('Par mode de règlement :');
    if (parMode.isEmpty) {
      sortie.add('  Aucun.');
    }
    for (final entree in parMode.entries) {
      sortie.add(DocumentClient.aligne(
          '  ${entree.key.libelle}', entree.value.enFrancs));
    }

    sortie
      ..add(_separateur)
      ..add(DocumentClient.aligne(
          'Réductions commerciales', reductions.enFrancs))
      ..add(DocumentClient.aligne(
          'Autres réductions', autresReductions.enFrancs))
      ..add(DocumentClient.aligne(
          'Ventes incomplètes', '$ventesIncompletes'))
      ..add(_separateur)
      ..add(DocumentClient.aligne('Nombre de factures', '$nombreFactures'))
      ..add(DocumentClient.aligne('Total taxable', taxable.enFrancs))
      ..add(DocumentClient.aligne('Total taxe', taxe.enFrancs))
      ..add(DocumentClient.aligne('TOTAL', total.enFrancs))
      ..add('')
      // Le chiffre que le commerçant vient chercher, mis en évidence.
      ..add(DocumentClient.aligne(
          'À avoir en caisse (espèces)', especes.enFrancs));

    if (!certifie) {
      sortie
        ..add(_separateur)
        ..addAll(_avertissement);
    }

    return sortie;
  }

  List<String> get _lignesArticles {
    if (articles.isEmpty) return const ['Aucun article vendu sur la période.'];

    final sortie = <String>[];
    for (final article in articles) {
      final taux = article.tauxMillieme;
      sortie
        ..add(article.nom)
        ..add('  ${article.code} · ${article.prixUnitaire.enFrancs}'
            '${taux == null || taux == 0 ? '' : ' · ${(taux / 10).toStringAsFixed(0)} %'}')
        ..add(DocumentClient.aligne('  Vendu', '${article.venduee}'));
      if (article.retournee.milliemes != 0) {
        sortie.add(
            DocumentClient.aligne('  Retourné', '${article.retournee}'));
      }
      if (article.enStock case final stock?) {
        sortie.add(DocumentClient.aligne('  En stock', '$stock'));
      }
    }
    return sortie;
  }

  String get texte => lignes.join('\n');

  /// Toujours faux tant que le module de contrôle manque. Le rapport le dit,
  /// pour la même raison que la facture : un document qui aurait l'air en
  /// règle sans l'être est pire qu'un document absent.
  bool get certifie => false;

  static const _avertissement = [
    'RAPPORT NON CERTIFIÉ',
    "Ce rapport ne porte ni identifiant de SFE ni éléments de sécurité. Il "
        "vaut arrêté de caisse interne, pas rapport normalisé.",
  ];

  static const _largeur = 38;
  static String get _separateur => '─' * _largeur;

  static String _horodatage(DateTime quand) {
    String d(int v) => v.toString().padLeft(2, '0');
    return '${d(quand.day)}/${d(quand.month)}/${quand.year} '
        'à ${d(quand.hour)}h${d(quand.minute)}';
  }
}
