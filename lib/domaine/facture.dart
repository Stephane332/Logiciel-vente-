/// La facture, telle qu'elle se compose et telle qu'elle s'imprime.
///
/// C'est le document du §3 de la note de service n° 2025-0889 : ses mentions
/// obligatoires vont de *a* à *z*, et je peux en produire toutes sauf trois.
///
/// **Les trois qui manquent viennent du module de contrôle**, pas de moi : le
/// numéro de série du SECeF, l'identifiant de SFE que l'Administration attribue
/// à l'homologation, et les éléments de sécurité — code SECeF/DGI, compteurs,
/// horodatage du module, code QR. Tant qu'ils manquent, la facture porte en
/// toutes lettres qu'elle **n'est pas certifiée**. C'est la seule chose que je
/// refuse de laisser ambiguë : une facture non certifiée qui aurait l'air
/// certifiée exposerait mon client à une sanction, et moi à pire.
///
/// Ce que ce fichier produit reste utile aujourd'hui. Un commerçant à qui une
/// entreprise réclame une facture en écrit une à la main ; celle-ci porte les
/// mentions, les totaux par groupe de taxation, le montant en lettres et une
/// référence qui ne se répète jamais. Le jour où le module arrive, il n'y aura
/// qu'à y coller les éléments de sécurité.
library;

import 'calcul_facture.dart';
import 'document_client.dart';
import 'fiche_entreprise.dart';
import 'montant.dart';
import 'montant_en_lettres.dart';
import 'numerotation.dart';
import 'references.dart';

/// Le client, tel que la facture doit le nommer (§2.14).
class ClientFacture {
  final TypeClient type;

  /// Nul pour un client comptant, qui n'a rien à décliner.
  final String? nom;

  final String? ifu;

  const ClientFacture({required this.type, this.nom, this.ifu});

  /// Le client anonyme du comptoir. Le cas ordinaire.
  static const comptant = ClientFacture(type: TypeClient.comptant);

  /// Ce qui manque pour que ce client soit facturable, en une phrase.
  /// Nul quand tout y est.
  String? get defaut {
    if (type.nomRequis && (nom == null || nom!.trim().isEmpty)) {
      return 'Un client « ${type.libelle} » doit être nommé.';
    }
    if (type.ifuRequis && (Ifu.normaliser(ifu) == null)) {
      return "Un client « ${type.libelle} » doit porter un IFU valable.";
    }
    return null;
  }

  /// Les lignes qui identifient le client sur la facture (§3, e et f).
  List<String> get lignes => [
        'Client : ${type.libelle}',
        if (nom != null && nom!.trim().isNotEmpty) nom!.trim(),
        if (ifu != null && ifu!.trim().isNotEmpty) 'IFU client : ${ifu!.trim()}',
      ];
}

/// Une ligne de commentaire libre (§2.27). Huit au minimum, dont deux dont
/// l'objet est fixé par la note.
class Commentaire {
  final LigneCommentaire ligne;
  final String texte;

  const Commentaire(this.ligne, this.texte);
}

/// Une facture composée, prête à imprimer ou à envoyer.
///
/// Elle est **immuable** : une fois composée, elle porte son numéro, et ce
/// numéro ne changera plus. Un duplicata se compose à partir de la même
/// référence (§2.18).
class Facture {
  final ReferenceFacture reference;
  final TypeFacture type;
  final FicheEntreprise emetteur;
  final ClientFacture client;
  final FactureCalculee calcul;
  final DateTime date;

  /// Qui a établi la facture (§3, mention 25).
  final String? operateur;

  /// Les règlements, par mode. Leur somme doit égaler le total (§2.22).
  final Map<ModePaiement, Montant> reglements;

  /// Le droit de timbre sur quittance, quand un règlement se fait en espèces.
  ///
  /// La note impose la **mention** et son montant (§3), pas le tarif — que je
  /// n'invente pas. Il vaut zéro tant que le commerçant ne l'a pas renseigné,
  /// et la mention le dit alors franchement plutôt que de mentir sur un chiffre.
  final Montant timbreQuittance;

  final List<Commentaire> commentaires;

  /// Vrai pour un duplicata : la mention est obligatoire, et le numéro reste
  /// celui de l'original (§2.18).
  final bool duplicata;

  /// La référence de la facture d'origine, pour un avoir (§2.28).
  final String? factureOrigine;

  /// La nature de l'avoir. Une remise passe obligatoirement par un avoir dont
  /// la nature vaut « RRR » (§2.29).
  final NatureAvoir? natureAvoir;

  const Facture({
    required this.reference,
    required this.type,
    required this.emetteur,
    required this.client,
    required this.calcul,
    required this.date,
    this.operateur,
    this.reglements = const {},
    this.timbreQuittance = const Montant.zero(),
    this.commentaires = const [],
    this.duplicata = false,
    this.factureOrigine,
    this.natureAvoir,
  });

  /// Vrai quand la facture porte les éléments de sécurité du module.
  ///
  /// Toujours faux aujourd'hui : le protocole de dialogue avec le module ne
  /// m'a pas encore été communiqué. Voir `docs/07-protocole-mcf.md`.
  bool get certifiee => false;

  /// Ce qui empêche d'émettre cette facture, en une phrase. Nul quand rien
  /// n'empêche.
  String? get defaut {
    final duClient = client.defaut;
    if (duClient != null) return duClient;

    if (!calcul.estCoherente) {
      return 'Les totaux ne se recoupent pas (§6.7).';
    }
    if (!calcul.totalTtc.estPositif) {
      return 'Une facture ne peut pas avoir un montant nul ou négatif (§2.24).';
    }
    if (type.estAvoir && natureAvoir == null) {
      return "Une facture d'avoir doit porter sa nature (§2.28).";
    }
    if (reglements.isNotEmpty) {
      var somme = const Montant.zero();
      for (final part in reglements.values) {
        somme = somme + part;
      }
      if (somme != calcul.totalTtc) {
        return 'La somme des règlements doit égaler le total (§2.22).';
      }
    }
    return null;
  }

  /// Vrai quand au moins un règlement se fait en espèces : c'est ce qui
  /// déclenche la mention du timbre de quittance.
  bool get regleeEnEspeces =>
      reglements.containsKey(ModePaiement.especes) &&
      reglements[ModePaiement.especes]!.estPositif;

  /// La facture, ligne par ligne, telle qu'elle s'imprime.
  ///
  /// Un seul rendu pour le papier et pour le message : deux mises en page
  /// d'un même document finiraient par diverger, et c'est le client qui
  /// aurait raison de s'en apercevoir.
  List<String> get lignes {
    final sortie = <String>[
      ...emetteur.enTete,
      _separateur,
      _titre,
      'Référence : ${reference.texte}',
      _quand,
      if (operateur != null && operateur!.trim().isNotEmpty)
        'Établie par ${operateur!.trim()}',
      if (factureOrigine != null) 'Facture d\'origine : $factureOrigine',
      if (natureAvoir != null) 'Motif : ${natureAvoir!.mention}',
      _separateur,
      ...client.lignes,
      _separateur,
      'Prix exprimés en ${calcul.modePrix.etiquette}',
      '',
    ];

    for (final ligne in calcul.lignes) {
      sortie.addAll(_ligneArticle(ligne));
    }

    sortie.add(_separateur);
    sortie.addAll(_totauxParGroupe);
    sortie.add(_separateur);

    if (calcul.totalTaxeSpecifique.estPositif) {
      sortie.add(DocumentClient.aligne(
          'Taxe spécifique', calcul.totalTaxeSpecifique.enFrancs));
    }
    sortie
      ..add(DocumentClient.aligne(
          'Total imposable', calcul.totalImposable.enFrancs))
      ..add(DocumentClient.aligne('Total taxe', calcul.totalTaxe.enFrancs))
      ..add(DocumentClient.aligne('TOTAL TTC', calcul.totalTtc.enFrancs));

    if (calcul.psvb.estPositif) {
      sortie.add(DocumentClient.aligne('Dont PSVB', calcul.psvb.enFrancs));
    }

    sortie
      ..add('')
      ..add('Arrêtée à la somme de :')
      ..add(montantEnLettres(calcul.totalTtc));

    if (reglements.isNotEmpty) {
      sortie
        ..add('')
        ..add('Règlement :');
      for (final entree in reglements.entries) {
        sortie.add(
            DocumentClient.aligne(entree.key.libelle, entree.value.enFrancs));
      }
    }

    // §3 : la mention est obligatoire dès qu'un règlement se fait en espèces,
    // suivie de son montant.
    if (regleeEnEspeces) {
      sortie
        ..add('')
        ..add(DocumentClient.aligne(
          'Montant timbre quittance en cas de règlement en espèce',
          timbreQuittance.enFrancs,
        ));
    }

    final remplis = commentaires.where((c) => c.texte.trim().isNotEmpty);
    if (remplis.isNotEmpty) {
      sortie.add('');
      for (final commentaire in remplis) {
        sortie.add('${commentaire.ligne.etiquette} : ${commentaire.texte}');
      }
    }

    sortie
      ..add(_separateur)
      ..addAll(_pied);

    return sortie;
  }

  String get texte => lignes.join('\n');

  /// Le titre, avec les mentions que la note impose selon le cas (§3, g).
  String get _titre {
    final mentions = <String>[
      if (duplicata) 'DUPLICATA',
      switch (type) {
        TypeFacture.avoir || TypeFacture.avoirExport => "FACTURE D'AVOIR",
        TypeFacture.acompte || TypeFacture.acompteExport => "FACTURE D'ACOMPTE",
        _ => 'FACTURE',
      },
      if (type.estExport) 'EXPORTATION',
    ];
    return mentions.join(' · ');
  }

  String get _quand {
    String d(int v) => v.toString().padLeft(2, '0');
    return 'Le ${d(date.day)}/${d(date.month)}/${date.year} '
        'à ${d(date.hour)}h${d(date.minute)}';
  }

  List<String> _ligneArticle(LigneCalculee ligne) {
    final source = ligne.source;

    // La désignation est **repliée, jamais tronquée**. Le §2.19 impose de
    // porter au moins soixante-quatre caractères ; sur un reçu de comptoir on
    // coupe pour garder l'alignement, mais couper ici reviendrait à ne pas
    // tenir la règle — et une désignation coupée est précisément ce qu'un
    // client professionnel conteste.
    final replie = _replier(source.designation, _largeur);

    final sortie = <String>[
      DocumentClient.aligne(replie.first, ligne.montantNet.enFrancs),
      ...replie.skip(1),
      '  ${source.quantite} × ${source.prixUnitaire.enFrancs} '
          '· groupe ${source.groupeTaxation.etiquette}',
    ];
    if (source.remise.estPositif) {
      // §3, q : les remises figurent au détail des lignes.
      sortie.add('  Remise : ${source.remise.enFrancs}');
    }
    return sortie;
  }

  /// Un total par groupe de taxation, avec son taux et son impôt (§3, o à q).
  List<String> get _totauxParGroupe {
    final sortie = <String>['Par groupe de taxation :'];
    for (final total in calcul.totauxParGroupe) {
      final taux = total.groupe.tauxMillieme;
      final tauxLisible =
          taux == null || taux == 0 ? '—' : '${(taux / 10).toStringAsFixed(0)} %';
      sortie
        ..add('${total.groupe.etiquette} · ${total.groupe.description}')
        ..add(DocumentClient.aligne(
            '  Base $tauxLisible', total.montantImposable.enFrancs))
        ..add(DocumentClient.aligne('  Impôt', total.taxe.enFrancs));
    }
    return sortie;
  }

  /// Ce que la facture dit d'elle-même.
  ///
  /// La phrase du bas est la plus importante du fichier. Une facture non
  /// certifiée qui n'annoncerait pas qu'elle ne l'est pas serait pire
  /// qu'inutile : elle donnerait à mon client la certitude d'être en règle.
  List<String> get _pied => certifiee
      ? const []
      : const [
          'FACTURE NON CERTIFIÉE',
          "Ce document ne porte pas les éléments de sécurité du Système "
              "Électronique Certifié de Facturation. Il ne vaut pas facture "
              "normalisée au sens de l'article 564 du Code général des impôts.",
        ];

  static const _largeur = 38;
  static String get _separateur => '─' * _largeur;

  /// Replie un texte sur plusieurs lignes, en coupant aux espaces.
  ///
  /// La première ligne laisse la place au montant collé à droite ; les
  /// suivantes sont décalées de deux espaces, comme le détail.
  static List<String> _replier(String texte, int largeur) {
    final premiere = largeur - 12;
    final suivantes = largeur - 2;

    final lignes = <String>[];
    var courante = StringBuffer();
    var place = premiere;

    void pousser() {
      if (courante.isEmpty) return;
      lignes.add(lignes.isEmpty ? '$courante' : '  $courante');
      courante = StringBuffer();
      place = suivantes;
    }

    for (final mot in texte.trim().split(RegExp(r'\s+'))) {
      final ajout = courante.isEmpty ? mot.length : courante.length + 1 + mot.length;
      if (ajout > place && courante.isNotEmpty) pousser();
      if (courante.isNotEmpty) courante.write(' ');
      courante.write(mot);
    }
    pousser();

    return lignes.isEmpty ? [''] : lignes;
  }
}
