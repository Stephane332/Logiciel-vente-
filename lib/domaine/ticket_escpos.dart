/// Composer le ticket pour une imprimante thermique 58 mm.
///
/// Ce fichier fabrique le flux d'octets ESC/POS et rien d'autre : il ne parle
/// ni Bluetooth, ni USB. C'est voulu — le transport se vérifie avec une
/// imprimante en main, la mise en page se vérifie ici, et mélanger les deux
/// rendrait la seconde invérifiable.
///
/// **Le jeu de caractères est le vrai piège.** Une imprimante chinoise à
/// 15 000 F ne connaît pas l'UTF-8 : elle attend une page de code sur un
/// octet. Laquelle, ça dépend du modèle, et ça ne se devine pas — ça se lit
/// sur du papier. D'où [PageDeCode] : on choisit, et si on se trompe, le
/// repli sans accents imprime « Recu » au lieu de « Reçu ». C'est laid mais
/// lisible, alors qu'une mauvaise page imprime « Re�u » ou pire.
///
/// 58 mm de papier valent **32 caractères** en police A. Tout est calé
/// là-dessus : au-delà, l'imprimante coupe la ligne où ça tombe, et un total
/// coupé en deux ne se lit plus.
library;

import 'dart:typed_data';

import 'document_client.dart';
import 'texte.dart';

/// Largeur utile d'un ticket 58 mm, en caractères.
const colonnes58 = 32;

/// Comment les accents partent vers l'imprimante.
enum PageDeCode {
  /// Aucun accent : ils sont remplacés par leur lettre nue. Le repli qui
  /// marche sur toutes les imprimantes du monde, et le défaut tant que le
  /// modèle du commerçant n'a pas été essayé.
  sansAccents(null),

  /// Europe de l'Ouest, la plus répandue sur les modèles vendus ici.
  cp858(19),

  /// L'autre page fréquente. Se reconnaît à l'essai : si « é » sort juste
  /// avec l'une et faux avec l'autre, c'est celle-là.
  cp1252(16);

  /// Numéro de page pour `ESC t n`. Nul quand on n'en change pas.
  final int? numero;
  const PageDeCode(this.numero);
}

/// Le flux d'octets d'un ticket.
class TicketEscPos {
  static const _esc = 0x1B;
  static const _gs = 0x1D;

  final int largeur;
  final PageDeCode page;

  const TicketEscPos({
    this.largeur = colonnes58,
    this.page = PageDeCode.sansAccents,
  });

  /// Compose le ticket d'un document client.
  Uint8List composer(DocumentClient document) {
    final octets = <int>[
      ..._initialiser(),
      ..._centre(),
      ..._gras(true),
      ..._doubleHauteur(true),
      ..._ligne(document.nomCommerce.toUpperCase(), large: true),
      ..._doubleHauteur(false),
      ..._gras(false),
      // Les mentions de l'entreprise, quand il y en a. Le papier doit dire
      // exactement ce que dit le message envoyé par WhatsApp : deux versions
      // d'un même reçu qui divergent, c'est une contestation gagnée d'avance
      // par le client.
      for (final mention in document.mentions) ..._ligne(mention),
      ..._ligne(document.nature.libelle),
      ..._ligne(_date(document.date)),
      if (document.operateur != null && document.operateur!.trim().isNotEmpty)
        ..._ligne('Servi par ${document.operateur!.trim()}'),
      ..._gauche(),
      ..._ligne(''),
      ..._separateur(),
    ];

    for (final ligne in document.lignes) {
      octets.addAll(_ligneArticle(ligne));
    }

    octets
      ..addAll(_separateur())
      ..addAll(_gras(true))
      ..addAll(_doubleHauteur(true))
      ..addAll(_colonnes('TOTAL', document.total.enFrancs, large: true))
      ..addAll(_doubleHauteur(false))
      ..addAll(_gras(false));

    if (!document.estSolde) {
      octets
        ..addAll(_colonnes('Deja paye', document.regle.enFrancs))
        ..addAll(_colonnes('Reste', document.reste.enFrancs));
    }

    octets
      ..addAll(_ligne(''))
      ..addAll(_centre())
      ..addAll(_ligne('Merci'))
      ..addAll(_ligne(''))
      ..addAll(_ligne(''))
      ..addAll(_couper());

    return Uint8List.fromList(octets);
  }

  // ------------------------------------------------------------- composition

  /// Une ligne d'article sur deux lignes de papier quand il le faut.
  ///
  /// La désignation d'abord, seule, parce qu'elle peut être longue et que la
  /// couper au milieu rendrait le ticket illisible. Puis la quantité à gauche
  /// et le montant à droite, alignés — c'est ce que le client vérifie.
  List<int> _ligneArticle(LigneDocument ligne) => [
        ..._ligne(_tronquer(ligne.designation, largeur)),
        ..._colonnes(
          '  ${ligne.quantite} x ${ligne.prixUnitaire.enFrancs}',
          ligne.montant.enFrancs,
        ),
      ];

  /// Deux textes sur une ligne : l'un à gauche, l'autre collé à droite.
  ///
  /// Si les deux ne tiennent pas, c'est la gauche qui cède : le montant ne se
  /// tronque jamais, c'est le seul chiffre qui compte sur un ticket.
  List<int> _colonnes(String gauche, String droite, {bool large = false}) {
    final colonnes = large ? largeur ~/ 2 : largeur;
    final place = colonnes - droite.length;
    final debut = place <= 0 ? '' : _tronquer(gauche, place);
    final vide = colonnes - debut.length - droite.length;
    return _ligne(debut + ' ' * (vide < 0 ? 0 : vide) + droite, large: large);
  }

  List<int> _separateur() => _ligne('-' * largeur);

  /// La date, comme on l'écrit ici : jour, mois, année, puis l'heure.
  static String _date(DateTime quand) =>
      '${_d(quand.day)}/${_d(quand.month)}/${quand.year} '
      '${_d(quand.hour)}h${_d(quand.minute)}';

  static String _d(int valeur) => valeur < 10 ? '0$valeur' : '$valeur';

  static String _tronquer(String texte, int taille) =>
      texte.length <= taille ? texte : texte.substring(0, taille);

  // ------------------------------------------------------------- ESC/POS

  List<int> _initialiser() => [
        _esc, 0x40, // ESC @ : remet l'imprimante à zéro
        if (page.numero != null) ...[_esc, 0x74, page.numero!],
      ];

  List<int> _gauche() => [_esc, 0x61, 0x00];
  List<int> _centre() => [_esc, 0x61, 0x01];
  List<int> _gras(bool actif) => [_esc, 0x45, actif ? 0x01 : 0x00];

  /// `GS ! n` : le quartet haut double la largeur, le bas double la hauteur.
  List<int> _doubleHauteur(bool actif) => [_gs, 0x21, actif ? 0x11 : 0x00];

  /// Coupe le papier en laissant de quoi le saisir.
  List<int> _couper() => [_gs, 0x56, 0x42, 0x00];

  /// Une ligne, tronquée à ce que le papier accepte.
  ///
  /// En double largeur, un caractère occupe deux colonnes : la ligne ne tient
  /// donc plus que sur la moitié. Sans cette division, le nom d'un commerce un
  /// peu long débordait et l'imprimante coupait où ça tombait.
  List<int> _ligne(String texte, {bool large = false}) => [
        ..._encoder(_tronquer(texte, large ? largeur ~/ 2 : largeur)),
        0x0A,
      ];

  /// Encode un texte pour l'imprimante.
  ///
  /// En repli, les accents tombent. Sinon on envoie l'octet de la page
  /// choisie — et tout ce qui n'y figure pas devient un point d'interrogation
  /// plutôt qu'un octet au hasard, qui ferait dérailler l'imprimante.
  List<int> _encoder(String texte) {
    final prepare = page == PageDeCode.sansAccents ? sansAccents(texte) : texte;
    return [
      for (final unite in prepare.codeUnits) _octet(unite),
    ];
  }

  int _octet(int unite) {
    if (unite < 0x80) return unite;
    final table = _tables[page];
    return table?[unite] ?? 0x3F; // « ? »
  }

  /// Les caractères accentués dont j'ai besoin, et leur octet dans chaque
  /// page. Le français d'un ticket de caisse tient dans cette poignée-là.
  static const _tables = <PageDeCode, Map<int, int>>{
    PageDeCode.cp858: {
      0xE0: 0x85, 0xE2: 0x83, 0xE4: 0x84, // à â ä
      0xE7: 0x87, // ç
      0xE9: 0x82, 0xE8: 0x8A, 0xEA: 0x88, 0xEB: 0x89, // é è ê ë
      0xEE: 0x8C, 0xEF: 0x8B, // î ï
      0xF4: 0x93, 0xF6: 0x94, // ô ö
      0xF9: 0x97, 0xFB: 0x96, 0xFC: 0x81, // ù û ü
      0xC0: 0xB7, 0xC7: 0x80, 0xC9: 0x90, // À Ç É
      0x20AC: 0xD5, // €
    },
    PageDeCode.cp1252: {
      0xE0: 0xE0, 0xE2: 0xE2, 0xE4: 0xE4,
      0xE7: 0xE7,
      0xE9: 0xE9, 0xE8: 0xE8, 0xEA: 0xEA, 0xEB: 0xEB,
      0xEE: 0xEE, 0xEF: 0xEF,
      0xF4: 0xF4, 0xF6: 0xF6,
      0xF9: 0xF9, 0xFB: 0xFB, 0xFC: 0xFC,
      0xC0: 0xC0, 0xC7: 0xC7, 0xC9: 0xC9,
      0x20AC: 0x80,
    },
  };
}
