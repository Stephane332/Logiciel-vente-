/// Tables de référence de la facturation électronique certifiée.
///
/// Valeurs issues de la note de service n° 2025-0889/MEF/SG/DGI/DLC du
/// 29 décembre 2025, spécification version 2.0.
///
/// Ces tables sont paramétrables (§2.35) : les taux changent, et les groupes
/// O et P sont explicitement réservés pour un usage futur.
library;

/// Groupe de taxation (§2.15). Seize groupes, de A à P.
class GroupeTaxation {
  final String etiquette;
  final String description;

  /// Taux de TVA applicable, exprimé en millièmes (18 % vaut 180).
  /// Nul lorsqu'aucun taux ne s'applique.
  final int? tauxMillieme;

  const GroupeTaxation(this.etiquette, this.description, this.tauxMillieme);

  bool get estTaxe => tauxMillieme != null && tauxMillieme! > 0;

  static const a = GroupeTaxation('A', 'Exonéré', null);
  static const b = GroupeTaxation('B', 'TVA taxable 1', 180);
  static const c = GroupeTaxation('C', 'TVA taxable 2', 100);
  static const d = GroupeTaxation('D', 'Exportation de produits taxables', null);
  static const e = GroupeTaxation('E', 'TVA régime dérogatoire', null);
  static const f = GroupeTaxation('F', 'TVA régime dérogatoire', 180);
  static const g = GroupeTaxation('G', 'TVA régime dérogatoire', 100);
  static const h = GroupeTaxation('H', 'Régime synthétique', null);
  static const i = GroupeTaxation('I', "Consignation d'emballage", null);
  static const j = GroupeTaxation('J', 'Dépôts, garantie et caution', null);
  static const k = GroupeTaxation('K', 'Débours', null);
  static const l = GroupeTaxation('L', 'TDT - Taxe de développement touristique', 100);
  static const m = GroupeTaxation(
      'M', 'Taxe de séjour hôtelier perçue par les communes', 100);
  static const n = GroupeTaxation(
      'N', 'PBA - Droits fixes en fonction de la destination et de la classe', null);
  static const o = GroupeTaxation('O', 'Réservé', null);
  static const p = GroupeTaxation('P', 'Réservé', null);

  static const tous = <GroupeTaxation>[
    a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p,
  ];

  static GroupeTaxation parEtiquette(String etiquette) =>
      tous.firstWhere((g) => g.etiquette == etiquette,
          orElse: () => throw ArgumentError(
              'Groupe de taxation inconnu : $etiquette'));

  @override
  String toString() => etiquette;
}

/// Groupe de prélèvement à la source sur vente de biens (§2.16).
class GroupePsvb {
  final String etiquette;

  /// Taux exprimé en dix-millièmes (2 % vaut 200, 0,2 % vaut 20).
  final int tauxDixMillieme;

  const GroupePsvb(this.etiquette, this.tauxDixMillieme);

  static const a = GroupePsvb('A', 200); // 2 %
  static const b = GroupePsvb('B', 100); // 1 %
  static const c = GroupePsvb('C', 20); //  0,2 %
  static const d = GroupePsvb('D', 0); //   0 %

  static const tous = <GroupePsvb>[a, b, c, d];

  static GroupePsvb parEtiquette(String etiquette) =>
      tous.firstWhere((g) => g.etiquette == etiquette,
          orElse: () => throw ArgumentError('Groupe PSVB inconnu : $etiquette'));

  @override
  String toString() => etiquette;
}

/// Type de facture (§2.7).
enum TypeFacture {
  vente('FV', 'Facture de vente'),
  acompte('FT', "Facture d'acompte ou d'avance"),
  avoir('FA', "Facture d'avoir"),
  venteExport('EV', "Facture de vente à l'exportation"),
  acompteExport('ET', "Facture d'acompte à l'exportation"),
  avoirExport('EA', "Facture d'avoir à l'exportation");

  final String etiquette;
  final String libelle;
  const TypeFacture(this.etiquette, this.libelle);

  bool get estAvoir => this == avoir || this == avoirExport;
  bool get estExport =>
      this == venteExport || this == acompteExport || this == avoirExport;
}

/// Type de client (§2.14).
enum TypeClient {
  comptant('CC', 'Client comptant', nomRequis: false, ifuRequis: false),
  personneMorale('PM', 'Personne morale', nomRequis: true, ifuRequis: true),
  personnePhysique('PP', 'Personne physique', nomRequis: true, ifuRequis: false),
  personnePhysiqueCommercant('PC', 'Personne physique commerçant',
      nomRequis: true, ifuRequis: true);

  final String etiquette;
  final String libelle;
  final bool nomRequis;
  final bool ifuRequis;
  const TypeClient(this.etiquette, this.libelle,
      {required this.nomRequis, required this.ifuRequis});
}

/// Type d'article.
enum TypeArticle {
  bienLocal('LOCBIE', 'Bien local', null),
  serviceLocal('LOCSER', 'Service local', null),
  bienImporte('IMPBIE', 'Bien (importation)', null),
  serviceImporte('IMPSERV', 'Service (importation)', '[IMPSER]');

  final String etiquette;
  final String libelle;

  /// Mention à porter sur la facture, le cas échéant.
  final String? mention;
  const TypeArticle(this.etiquette, this.libelle, this.mention);
}

/// Nature de facture d'avoir (§2.28).
enum NatureAvoir {
  correction('COR', 'Correction', 'Correction'),
  annulation('RAN', 'Annulation', 'Annulation'),
  reprise('RAM', 'Avoir suite reprise de biens/services', 'Avoir suite reprise'),
  remise('RRR', 'Remise, ristourne, rabais', 'RRR');

  final String code;
  final String libelle;

  /// Mention obligatoire à porter sur la facture.
  final String mention;
  const NatureAvoir(this.code, this.libelle, this.mention);
}

/// Mode de paiement (§2.21).
enum ModePaiement {
  virement('Virement'),
  carteBancaire('Carte bancaire'),
  mobileMoney('Mobile money'),
  cheque('Chèque'),
  especes('Espèces'),
  credit('Crédit');

  final String libelle;
  const ModePaiement(this.libelle);
}

/// Mode de saisie du prix unitaire (§6.3).
enum ModePrix {
  horsTaxe('HT'),
  toutesTaxesComprises('TTC');

  final String etiquette;
  const ModePrix(this.etiquette);
}

/// Étiquettes des lignes de commentaire (§2.27). Huit lignes au minimum.
enum LigneCommentaire {
  referenceExoneration('A', 'Réf. exo.', "Référence du certificat d'exonération"),
  baseJuridique('B', 'Base juridique', 'Base juridique'),
  reserveC('C', 'Réservé', ''),
  reserveD('D', 'Réservé', ''),
  reserveE('E', 'Réservé', ''),
  reserveF('F', 'Réservé', ''),
  reserveG('G', 'Réservé', ''),
  reserveH('H', 'Réservé', '');

  final String code;
  final String etiquette;
  final String description;
  const LigneCommentaire(this.code, this.etiquette, this.description);
}
