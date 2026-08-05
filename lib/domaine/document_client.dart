/// Les documents destinés au client.
///
/// Le client n'installe rien. Ce qu'on lui envoie est un **message** — par
/// WhatsApp ou par SMS — qu'il lit sur n'importe quel téléphone. Personne
/// n'installe une application pour un achat de 500 F au comptoir.
///
/// Chaque parcours de vente a son document : un reçu au comptoir, la note en
/// cours au restaurant, l'ardoise pour une dette, une confirmation pour une
/// réservation. Voir `docs/11-cote-client.md`.
///
/// Ces documents servent d'abord le commerçant : une note que le client voit
/// évite les disputes à table, et une ardoise que les deux consultent évite
/// le « je t'ai déjà payé », qui est la première source de conflit sur le
/// crédit.
library;

import 'montant.dart';
import 'references.dart';

/// Une ligne d'un document.
class LigneDocument {
  final String designation;
  final Quantite quantite;
  final Montant prixUnitaire;
  final Montant montant;

  const LigneDocument({
    required this.designation,
    required this.quantite,
    required this.prixUnitaire,
    required this.montant,
  });
}

/// Nature du document, qui décide de son titre et de son pied.
enum NatureDocument {
  recu('Reçu'),
  note('Note en cours'),
  ardoise('Ardoise'),
  historique('Tes achats'),
  confirmation('Confirmation'),
  devis('Devis');

  final String libelle;
  const NatureDocument(this.libelle);
}

/// Un document prêt à être envoyé.
class DocumentClient {
  final NatureDocument nature;
  final String nomCommerce;
  final DateTime date;

  /// Ce qui identifie la vente pour le client : « Table 4 », « Ticket 12 ».
  final String? contenant;

  final List<LigneDocument> lignes;
  final Montant total;

  /// Ce qui a déjà été réglé. Égal au total pour un reçu.
  final Montant regle;

  final List<ModePaiement> modes;

  /// Message libre ajouté en pied, avant la formule de politesse.
  final String? complement;

  /// Code de vérification de la facture certifiée, quand elle l'est.
  final String? codeVerification;

  const DocumentClient({
    required this.nature,
    required this.nomCommerce,
    required this.date,
    required this.lignes,
    required this.total,
    required this.regle,
    this.contenant,
    this.modes = const [],
    this.complement,
    this.codeVerification,
  });

  Montant get reste => total - regle;
  bool get estSolde => reste.centimes <= 0;

  /// Le message tel qu'il part sur WhatsApp ou par SMS.
  ///
  /// Volontairement étroit — une quarantaine de colonnes — pour rester
  /// lisible sur un petit écran sans que les lignes ne se cassent.
  String get texte {
    final lignesTexte = <String>[
      nomCommerce.toUpperCase(),
      _titre,
      _quand,
      '',
    ];

    for (final ligne in lignes) {
      lignesTexte.add(_ligneArticle(ligne));
    }

    if (lignes.isNotEmpty) lignesTexte.add(_separateur);

    // Trois cas seulement, pour ne jamais répéter deux fois le même montant :
    // tout est payé, une partie l'est, ou rien.
    if (estSolde) {
      lignesTexte.add(_totalise('Total', total));
      if (modes.isNotEmpty) lignesTexte.add('Payé en ${_modes()}');
    } else if (regle.centimes > 0) {
      lignesTexte
        ..add(_totalise('Total', total))
        ..add(_totalise('Déjà payé', regle))
        ..add(_totalise('Reste à payer', reste));
    } else {
      lignesTexte.add(_totalise('À payer', total));
    }

    if (complement != null && complement!.isNotEmpty) {
      lignesTexte
        ..add('')
        ..add(complement!);
    }

    if (codeVerification != null) {
      lignesTexte
        ..add('')
        ..add('Facture certifiée')
        ..add(codeVerification!);
    }

    lignesTexte
      ..add('')
      ..add(_pied);

    return lignesTexte.join('\n');
  }

  /// Titre court. Le contenant y figure quand il y en a un — c'est ce que le
  /// client reconnaît en premier : sa table, son numéro de ticket.
  String get _titre =>
      contenant == null ? nature.libelle : '${nature.libelle} · $contenant';

  /// La date sur sa propre ligne : mise à la suite du titre, l'ensemble
  /// dépassait la largeur d'un petit écran.
  String get _quand =>
      '${_deuxChiffres(date.day)}/${_deuxChiffres(date.month)}/${date.year} '
      'à ${_deuxChiffres(date.hour)}h${_deuxChiffres(date.minute)}';

  String get _pied => switch (nature) {
        NatureDocument.recu => 'Merci !',
        NatureDocument.note => 'Bon appétit.',
        NatureDocument.ardoise =>
          'Une question sur ce montant ? Réponds à ce message.',
        NatureDocument.historique => 'Merci de ta fidélité.',
        NatureDocument.confirmation => 'À bientôt.',
        NatureDocument.devis => 'Ce devis reste valable 30 jours.',
      };

  static const _largeur = 38;
  static String get _separateur => '─' * _largeur;

  String _ligneArticle(LigneDocument ligne) {
    final montant = ligne.montant.enFrancs;
    final quantite = ligne.quantite == const Quantite.unites(1)
        ? ''
        : '${ligne.quantite} × ${ligne.prixUnitaire.enFrancs}';

    // Désignation à gauche, montant collé à droite. Si tout ne tient pas,
    // la désignation est tronquée plutôt que de casser l'alignement.
    final gauche = quantite.isEmpty
        ? ligne.designation
        : '${ligne.designation}  $quantite';
    final place = _largeur - montant.length - 1;
    final ajustee =
        gauche.length > place ? '${gauche.substring(0, place - 1)}…' : gauche;

    return '$ajustee${' ' * (_largeur - ajustee.length - montant.length)}$montant';
  }

  String _totalise(String libelle, Montant montant) =>
      aligne(libelle, montant.enFrancs);

  /// Libellé à gauche, valeur collée à droite, sur la largeur du ticket.
  ///
  /// C'est ce qui rend les documents lisibles en chasse fixe : les montants
  /// tombent tous sur la même colonne, comme sur un ticket de caisse.
  static String aligne(String libelle, String valeur) {
    final espaces = _largeur - libelle.length - valeur.length;
    return '$libelle${' ' * (espaces < 1 ? 1 : espaces)}$valeur';
  }

  String _modes() {
    final noms = modes.map((m) => m.libelle.toLowerCase()).toList();
    if (noms.length == 1) return noms.single;
    return '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}';
  }

  static String _deuxChiffres(int valeur) => valeur.toString().padLeft(2, '0');
}

/// L'ardoise d'un client : ce qu'il doit, et depuis quand.
///
/// C'est le document le plus utile des six. Aujourd'hui la dette est dans le
/// cahier du commerçant, et la mémoire du client dit autre chose. Un relevé
/// que les deux consultent met fin à la discussion.
class Ardoise {
  final String nomCommerce;
  final String nomClient;
  final Montant encours;
  final DateTime date;
  final int nombreAchats;
  final int nombreRemboursements;
  final DateTime? depuis;

  const Ardoise({
    required this.nomCommerce,
    required this.nomClient,
    required this.encours,
    required this.date,
    this.nombreAchats = 0,
    this.nombreRemboursements = 0,
    this.depuis,
  });

  bool get estSoldee => encours.centimes <= 0;

  String get texte {
    final lignes = <String>[
      nomCommerce.toUpperCase(),
      'Ardoise de $nomClient',
      '',
    ];

    if (estSoldee) {
      lignes
        ..add('Tu ne dois plus rien. Merci !')
        ..add('');
      lignes.add('Au ${_date(date)}');
      return lignes.join('\n');
    }

    lignes
      ..add('Tu dois : ${encours.enFrancs}')
      ..add('');

    if (depuis != null) lignes.add('Depuis le ${_date(depuis!)}');

    final resume = <String>[];
    if (nombreAchats > 0) {
      resume.add('$nombreAchats achat${nombreAchats > 1 ? 's' : ''} à crédit');
    }
    if (nombreRemboursements > 0) {
      resume.add('$nombreRemboursements remboursement'
          '${nombreRemboursements > 1 ? 's' : ''}');
    }
    if (resume.isNotEmpty) lignes.add(resume.join(' · '));

    lignes
      ..add('')
      ..add('Arrêté au ${_date(date)}')
      ..add('Une question ? Réponds à ce message.');

    return lignes.join('\n');
  }

  static String _date(DateTime date) =>
      '${DocumentClient._deuxChiffres(date.day)}/'
      '${DocumentClient._deuxChiffres(date.month)}/${date.year}';
}


/// L'historique des achats d'un client dans une boutique.
///
/// C'est le premier pas vers un historique qui suivrait le client d'une
/// boutique à l'autre. Le reste attend le serveur — et le consentement du
/// client, qui est un accord distinct de celui de recevoir un reçu.
class HistoriqueClient {
  final String nomCommerce;
  final String nomClient;
  final DateTime depuis;
  final DateTime jusqua;

  /// Les achats, du plus récent au plus ancien.
  final List<AchatResume> achats;

  final Montant total;

  /// Ce qui reste dû, s'il reste quelque chose.
  final Montant encours;

  const HistoriqueClient({
    required this.nomCommerce,
    required this.nomClient,
    required this.depuis,
    required this.jusqua,
    required this.achats,
    required this.total,
    required this.encours,
  });

  String get texte {
    final lignes = <String>[
      nomCommerce.toUpperCase(),
      'Tes achats · $nomClient',
      'Du ${Ardoise._date(depuis)} au ${Ardoise._date(jusqua)}',
      '',
    ];

    if (achats.isEmpty) {
      lignes
        ..add('Aucun achat sur cette période.')
        ..add('');
      return lignes.join('\n');
    }

    for (final achat in achats) {
      lignes.add(achat.ligne);
    }

    lignes
      ..add(DocumentClient._separateur)
      ..add(_totalise('Total dépensé', total));

    if (encours.centimes > 0) {
      lignes.add(_totalise('Reste à payer', encours));
    }

    lignes
      ..add('')
      ..add('${achats.length} achat${achats.length > 1 ? 's' : ''}')
      ..add('')
      ..add('Merci de ta fidélité.');

    return lignes.join('\n');
  }

  static String _totalise(String libelle, Montant montant) {
    final valeur = montant.enFrancs;
    final espaces = DocumentClient._largeur - libelle.length - valeur.length;
    return '$libelle${' ' * (espaces < 1 ? 1 : espaces)}$valeur';
  }
}

/// Un achat, résumé en une ligne.
class AchatResume {
  final DateTime date;
  final Montant montant;

  /// Ce qui a été acheté, en abrégé : le premier article, et le nombre des
  /// autres. La liste complète tiendrait rarement sur une ligne.
  final String resume;

  const AchatResume({
    required this.date,
    required this.montant,
    required this.resume,
  });

  String get ligne {
    final quand = '${DocumentClient._deuxChiffres(date.day)}/'
        '${DocumentClient._deuxChiffres(date.month)}';
    final valeur = montant.enFrancs;
    final gauche = '$quand  $resume';
    final place = DocumentClient._largeur - valeur.length - 1;
    final ajustee =
        gauche.length > place ? '${gauche.substring(0, place - 1)}…' : gauche;
    return '$ajustee${' ' * (DocumentClient._largeur - ajustee.length - valeur.length)}$valeur';
  }
}

/// Le rapport du soir, tel qu'il part au patron.
///
/// Le seul document des sept qui ne s'adresse pas au client mais au
/// propriétaire. Il tient dans un message : ce qui est rentré, ce qui a été
/// promis, et ce qu'il faut racheter demain. Le patron qui n'est pas au
/// magasin voit son commerce sans y être.
class RapportDuSoir {
  final String nomCommerce;
  final DateTime date;
  final Montant encaisse;
  final Montant aCredit;
  final Montant remises;
  final int nombreVentes;

  /// Ce qu'il faut racheter, déjà formulé par les analyses. On ne reformule
  /// pas ici : l'écran et le message doivent dire exactement la même chose.
  final List<String> aRacheter;

  const RapportDuSoir({
    required this.nomCommerce,
    required this.date,
    required this.encaisse,
    required this.aCredit,
    required this.remises,
    required this.nombreVentes,
    this.aRacheter = const [],
  });

  String get texte {
    final lignes = <String>[
      nomCommerce.toUpperCase(),
      'Journée du ${_date(date)}',
      DocumentClient._separateur,
      DocumentClient.aligne('Encaissé', encaisse.enFrancs),
    ];

    if (aCredit.estPositif) {
      lignes.add(DocumentClient.aligne('À crédit', aCredit.enFrancs));
    }
    if (remises.estPositif) {
      lignes.add(DocumentClient.aligne('Remises accordées', remises.enFrancs));
    }

    lignes
      ..add(DocumentClient.aligne(
          'Ventes', '$nombreVentes'))
      ..add(DocumentClient._separateur);

    if (aRacheter.isEmpty) {
      lignes.add('Rien à racheter.');
    } else {
      lignes.add('À racheter :');
      for (final article in aRacheter) {
        lignes.add('· $article');
      }
    }

    return lignes.join('\n');
  }

  static String _date(DateTime date) =>
      '${DocumentClient._deuxChiffres(date.day)}/'
      '${DocumentClient._deuxChiffres(date.month)}/${date.year}';
}
