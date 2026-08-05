/// Éléments de sécurité d'une facture certifiée.
///
/// Ce sont les données que le module de contrôle renvoie après avoir certifié
/// une facture, et que le SFE doit imprimer sur celle-ci : code SECeF/DGI,
/// identificateur du module, compteurs, date et heure du module, code QR.
///
/// Le format retenu ici est celui de la spécification e-MECeF v1.0 de la DGI
/// du Bénin, dont le dispositif burkinabè est directement issu. **Il reste à
/// faire confirmer par la DGI du Burkina** — voir `docs/07-protocole-mcf.md`.
library;

/// Erreur de lecture d'un code QR de facture certifiée.
class CodeQrInvalide implements Exception {
  final String message;
  const CodeQrInvalide(this.message);

  @override
  String toString() => 'CodeQrInvalide : $message';
}

/// Les éléments de sécurité fournis par le module de contrôle.
class ElementsSecurite {
  /// Marqueur de type porté par le code QR.
  final String marqueur;

  /// Numéro d'identification du module, le NIM.
  final String nim;

  /// Code SECeF/DGI, tel que renvoyé par le module — avec ses tirets.
  final String codeSecefDgi;

  /// Identifiant fiscal unique du vendeur.
  final String ifu;

  /// Date et heure de la certification, telles que datées par le module.
  ///
  /// C'est l'horodatage du module qui fait foi, pas celui de l'appareil : le
  /// téléphone d'un commerçant est rarement à l'heure.
  final DateTime horodatage;

  /// Compteurs du module, sous la forme `64/64 FV`.
  final String compteurs;

  const ElementsSecurite({
    required this.nim,
    required this.codeSecefDgi,
    required this.ifu,
    required this.horodatage,
    required this.compteurs,
    this.marqueur = 'F',
  });

  /// Le code SECeF/DGI débarrassé de ses tirets, tel qu'il figure dans le QR.
  String get codeCompact => codeSecefDgi.replaceAll('-', '');

  /// Compose le contenu du code QR.
  ///
  /// Cinq champs séparés par des points-virgules. Le QR ne contient **aucun
  /// montant** et **aucune adresse de vérification** : l'application de
  /// contrôle interroge le serveur de la DGI avec ces seuls identifiants.
  String get codeQr => [
        marqueur,
        nim,
        codeCompact,
        ifu,
        _horodatageCompact,
      ].join(';');

  String get _horodatageCompact {
    String d(int v, [int n = 2]) => v.toString().padLeft(n, '0');
    return '${d(horodatage.year, 4)}${d(horodatage.month)}${d(horodatage.day)}'
        '${d(horodatage.hour)}${d(horodatage.minute)}${d(horodatage.second)}';
  }

  /// Relit un code QR de facture certifiée.
  ///
  /// Sert à vérifier une facture reçue d'un fournisseur, et à contrôler mes
  /// propres factures pendant la démonstration d'homologation.
  factory ElementsSecurite.depuisCodeQr(String codeQr, {String compteurs = ''}) {
    final champs = codeQr.split(';');
    if (champs.length != 5) {
      throw CodeQrInvalide(
          'Cinq champs attendus, ${champs.length} trouvés dans « $codeQr ».');
    }

    final horodatage = champs[4];
    if (horodatage.length != 14 || int.tryParse(horodatage) == null) {
      throw CodeQrInvalide(
          'Horodatage « $horodatage » : 14 chiffres attendus au format '
          'AAAAMMJJHHMMSS.');
    }

    int part(int debut, int longueur) =>
        int.parse(horodatage.substring(debut, debut + longueur));

    return ElementsSecurite(
      marqueur: champs[0],
      nim: champs[1],
      codeSecefDgi: champs[2],
      ifu: champs[3],
      horodatage: DateTime(part(0, 4), part(4, 2), part(6, 2), part(8, 2),
          part(10, 2), part(12, 2)),
      compteurs: compteurs,
    );
  }

  @override
  String toString() => codeQr;
}

/// État de certification d'une vente.
///
/// La certification exige d'être en ligne et de se boucler dans une fenêtre
/// courte. Or la caisse fonctionne hors ligne par défaut. Une vente est donc
/// enregistrée d'abord et certifiée ensuite, quand le réseau le permet.
enum EtatCertification {
  /// Vente enregistrée localement, pas encore présentée au module.
  enAttente,

  /// Présentée au module, en attente de confirmation.
  enCours,

  /// Certifiée : les éléments de sécurité sont disponibles.
  certifiee,

  /// Refusée par le module. Le motif est conservé pour correction.
  refusee,
}
