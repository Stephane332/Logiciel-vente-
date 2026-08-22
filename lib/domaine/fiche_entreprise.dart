/// La fiche de l'entreprise.
///
/// Ce que la note de service n° 2025-0889 appelle les mentions obligatoires de
/// l'émetteur (§3, mentions a à f et n à p) : le nom, l'IFU, l'adresse de
/// vente avec ses références cadastrales, les contacts, le régime
/// d'imposition, le service des impôts de rattachement, les références
/// bancaires.
///
/// **Rien n'est obligatoire ici, et c'est délibéré.** L'application encaisse
/// sans qu'on soit passé par cet écran, comme au premier jour. Une boutique de
/// quartier n'a pas d'IFU et n'en aura jamais besoin ; lui demander le sien
/// avant sa première vente, c'est la perdre. La fiche se remplit le jour où
/// elle sert : une facture pour un client qui la réclame, ou le passage au
/// Régime Normal.
///
/// Ce fichier ne contient que des **règles**, sans base ni écran : ce qui fait
/// une référence cadastrale valable, ce qui manque encore pour une facture
/// certifiée, et à partir de quel chiffre d'affaires la certification devient
/// obligatoire.
library;

/// Le régime d'imposition, qui décide de presque tout le reste.
///
/// Les seuils sont ceux du CGI en vigueur. Ils sont donnés en francs CFA
/// entiers — ce sont des seuils annoncés, pas des sommes encaissées, donc ils
/// ne passent pas par [Montant] : aucune arithmétique ne les touche.
enum RegimeImposition {
  /// Contribution des micro-entreprises. Le cas de la très grande majorité
  /// des commerçants que je vise, et celui où la certification n'est pas
  /// exigée.
  cme('CME', 'Contribution des micro-entreprises', 0, 15000000),

  /// Régime simplifié d'imposition.
  rsi('RSI', "Régime simplifié d'imposition", 15000000, 50000000),

  /// Régime normal d'imposition. La facture électronique certifiée y est
  /// obligatoire depuis le 1er juillet 2026.
  rni('RNI', "Régime normal d'imposition", 50000000, null);

  final String etiquette;
  final String libelle;

  /// Chiffre d'affaires annuel à partir duquel le régime s'applique.
  final int planchierFcfa;

  /// Chiffre d'affaires au-delà duquel on change de régime. Nul pour le RNI,
  /// qui n'a pas de plafond.
  final int? plafondFcfa;

  const RegimeImposition(
      this.etiquette, this.libelle, this.planchierFcfa, this.plafondFcfa);

  /// Vrai quand la facture électronique certifiée est exigée.
  ///
  /// Seul le Régime Normal est concerné à ce jour. Les autres suivront
  /// probablement — la DGI l'a laissé entendre — mais je ne fais pas dire à
  /// l'application ce que l'administration n'a pas écrit.
  bool get certificationObligatoire => this == rni;

  static RegimeImposition? parEtiquette(String? etiquette) {
    if (etiquette == null) return null;
    for (final regime in values) {
      if (regime.etiquette == etiquette) return regime;
    }
    return null;
  }

  /// Le régime que le chiffre d'affaires annoncé désigne.
  ///
  /// Sert à prévenir un commerçant qui s'approche du seuil, pas à décider à
  /// sa place : c'est l'administration qui classe, pas moi.
  static RegimeImposition depuisChiffreAffaires(int fcfa) {
    if (fcfa >= rni.planchierFcfa) return rni;
    if (fcfa >= rsi.planchierFcfa) return rsi;
    return cme;
  }
}

/// Les références cadastrales du lieu de vente (§3, mention c).
///
/// La note impose un format précis : `SSSS LLL PPPP`, onze caractères
/// **numériques**. Section sur quatre chiffres, lot sur trois, parcelle sur
/// quatre. C'est l'une des rares mentions dont la spécification donne la forme
/// exacte, donc l'une des rares que je peux valider sans rien deviner.
class ReferenceCadastrale {
  /// Section, quatre chiffres.
  final String section;

  /// Lot, trois chiffres.
  final String lot;

  /// Parcelle, quatre chiffres.
  final String parcelle;

  const ReferenceCadastrale._(this.section, this.lot, this.parcelle);

  /// Les onze chiffres à la suite, tels qu'ils partent au module de contrôle.
  String get compact => '$section$lot$parcelle';

  /// La forme lisible, telle qu'elle s'imprime sur la facture.
  String get lisible => '$section $lot $parcelle';

  /// Relit une saisie. Rend nul si elle ne fait pas onze chiffres.
  ///
  /// Tout ce qui n'est pas un chiffre est ignoré : le commerçant tape ce qu'il
  /// lit sur son papier, avec des espaces, des tirets ou des points selon
  /// l'humeur du document, et l'application n'a pas à lui reprocher sa
  /// ponctuation.
  static ReferenceCadastrale? analyser(String? saisie) {
    if (saisie == null) return null;
    final chiffres = saisie.replaceAll(RegExp(r'\D'), '');
    if (chiffres.length != 11) return null;

    return ReferenceCadastrale._(
      chiffres.substring(0, 4),
      chiffres.substring(4, 7),
      chiffres.substring(7, 11),
    );
  }

  /// Ce qui cloche dans une saisie, en une phrase adressée au commerçant.
  /// Nul quand elle est bonne — ou vide, ce qui reste permis.
  static String? defaut(String? saisie) {
    if (saisie == null || saisie.trim().isEmpty) return null;

    final chiffres = saisie.replaceAll(RegExp(r'\D'), '');
    if (chiffres.length == 11) return null;

    if (chiffres.isEmpty) {
      return 'Les références cadastrales sont onze chiffres.';
    }
    final manque = 11 - chiffres.length;
    return manque > 0
        ? 'Onze chiffres attendus, il en manque $manque.'
        : 'Onze chiffres attendus, il y en a ${-manque} de trop.';
  }

  @override
  String toString() => lisible;

  @override
  bool operator ==(Object other) =>
      other is ReferenceCadastrale && other.compact == compact;

  @override
  int get hashCode => compact.hashCode;
}

/// L'identifiant financier unique du contribuable.
///
/// Je valide sa **forme** — huit chiffres suivis d'une lettre — sans prétendre
/// valider son existence : seule l'administration sait si un IFU est attribué.
/// Un IFU mal recopié passerait donc, et c'est assumé : refuser un IFU
/// valable parce que mon contrôle est trop strict serait bien pire.
class Ifu {
  static final _forme = RegExp(r'^[0-9]{8}[A-Z]$');

  /// Ramène une saisie à sa forme canonique, ou rend nul.
  static String? normaliser(String? saisie) {
    if (saisie == null) return null;
    final propre =
        saisie.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    return _forme.hasMatch(propre) ? propre : null;
  }

  /// Ce qui cloche, en une phrase. Nul quand c'est bon ou vide.
  static String? defaut(String? saisie) {
    if (saisie == null || saisie.trim().isEmpty) return null;
    if (normaliser(saisie) != null) return null;
    return "L'IFU est huit chiffres suivis d'une lettre.";
  }
}

/// Ce qu'il manque à la fiche pour émettre une facture certifiée.
///
/// Chaque manque nomme la mention de la note qui l'exige : c'est ce que je
/// montrerai au comité d'homologation, et c'est aussi ce qui permet à un
/// commerçant de savoir quoi aller chercher, plutôt que de deviner.
typedef Manque = ({String quoi, String pourquoi});

/// La fiche, telle qu'elle est enregistrée et telle qu'elle s'imprime.
class FicheEntreprise {
  /// Le nom qui coiffe les documents. Le seul champ toujours rempli — il a un
  /// repli, « Ma boutique ».
  final String nomCommercial;

  /// Raison sociale, quand elle diffère du nom commercial. Une entreprise
  /// s'appelle « SARL Sawadogo et Frères » et son enseigne « Chez Awa ».
  final String? raisonSociale;

  final String? ifu;
  final ReferenceCadastrale? cadastre;

  /// L'adresse en clair : quartier, rue, ville. Les références cadastrales ne
  /// disent rien à un client qui cherche la boutique.
  final String? adresse;

  final String? telephone;
  final String? courriel;
  final RegimeImposition? regime;

  /// Le service des impôts de rattachement, tel qu'il est écrit sur
  /// l'attestation — « DME Ouaga 1 », « CIME Bobo ». Texte libre : la liste
  /// change, et une liste périmée bloquerait le commerçant.
  final String? serviceImpots;

  /// Les références bancaires (§3, mention l), en une ligne : la banque et le
  /// numéro de compte tels qu'ils doivent figurer sur la facture.
  final String? referencesBancaires;

  const FicheEntreprise({
    required this.nomCommercial,
    this.raisonSociale,
    this.ifu,
    this.cadastre,
    this.adresse,
    this.telephone,
    this.courriel,
    this.regime,
    this.serviceImpots,
    this.referencesBancaires,
  });

  /// La raison sociale s'il y en a une, l'enseigne sinon. C'est ce nom-là qui
  /// engage l'entreprise sur une facture.
  String get denomination =>
      (raisonSociale != null && raisonSociale!.trim().isNotEmpty)
          ? raisonSociale!.trim()
          : nomCommercial;

  /// Vrai quand la fiche porte au moins une mention fiscale. Sert à décider si
  /// l'écran affiche la section repliée ou dépliée : un commerçant qui n'a
  /// rien rempli n'a pas à voir un formulaire d'administration.
  bool get renseignee =>
      ifu != null ||
      cadastre != null ||
      regime != null ||
      (serviceImpots?.trim().isNotEmpty ?? false);

  /// Ce qui manque pour une facture certifiée, dans l'ordre où le commerçant
  /// peut l'obtenir.
  ///
  /// Vide ne veut pas dire « prêt à certifier » : il manque encore le module
  /// de contrôle, et lui ne vient pas d'un formulaire. Voir
  /// `docs/07-protocole-mcf.md`.
  List<Manque> get manques => [
        if (ifu == null)
          (
            quoi: 'IFU',
            pourquoi: "L'identifiant financier unique, sur l'attestation "
                "d'immatriculation fiscale. Mention b."
          ),
        if (cadastre == null)
          (
            quoi: 'Références cadastrales',
            pourquoi: 'Onze chiffres identifiant la parcelle où se fait la '
                'vente, au service du cadastre. Mention c.'
          ),
        if (adresse == null || adresse!.trim().isEmpty)
          (
            quoi: 'Adresse de vente',
            pourquoi: 'Le lieu où la vente se fait, en clair. Mention c.'
          ),
        if (telephone == null || telephone!.trim().isEmpty)
          (
            quoi: 'Contact',
            pourquoi: "Le téléphone de l'entreprise. Mention d."
          ),
        if (regime == null)
          (
            quoi: "Régime d'imposition",
            pourquoi: 'CME, RSI ou RNI, tel que la Direction générale des '
                "impôts t'a classé. Mention n."
          ),
        if (serviceImpots == null || serviceImpots!.trim().isEmpty)
          (
            quoi: 'Service des impôts',
            pourquoi: 'Ton service de rattachement. Mention o.'
          ),
      ];

  /// Vrai quand tout ce qui dépend du commerçant est là.
  bool get complete => manques.isEmpty;

  /// L'en-tête tel qu'il s'imprime sur une facture, ligne par ligne.
  ///
  /// Les lignes vides sont retirées : une facture d'une boutique de quartier
  /// n'a pas à porter cinq lignes blanches là où une entreprise en a cinq
  /// remplies.
  List<String> get enTete => [
        denomination.toUpperCase(),
        if (raisonSociale != null && raisonSociale!.trim().isNotEmpty)
          nomCommercial,
        if (ifu != null) 'IFU : $ifu',
        if (adresse != null && adresse!.trim().isNotEmpty) adresse!.trim(),
        if (cadastre != null) 'Parcelle : ${cadastre!.lisible}',
        if (telephone != null && telephone!.trim().isNotEmpty)
          'Tél. : ${telephone!.trim()}',
        if (courriel != null && courriel!.trim().isNotEmpty) courriel!.trim(),
        if (regime != null) 'Régime : ${regime!.etiquette}',
        if (serviceImpots != null && serviceImpots!.trim().isNotEmpty)
          'Service des impôts : ${serviceImpots!.trim()}',
        if (referencesBancaires != null &&
            referencesBancaires!.trim().isNotEmpty)
          referencesBancaires!.trim(),
      ];

  FicheEntreprise copieAvec({
    String? nomCommercial,
    String? raisonSociale,
    String? ifu,
    ReferenceCadastrale? cadastre,
    String? adresse,
    String? telephone,
    String? courriel,
    RegimeImposition? regime,
    String? serviceImpots,
    String? referencesBancaires,
  }) =>
      FicheEntreprise(
        nomCommercial: nomCommercial ?? this.nomCommercial,
        raisonSociale: raisonSociale ?? this.raisonSociale,
        ifu: ifu ?? this.ifu,
        cadastre: cadastre ?? this.cadastre,
        adresse: adresse ?? this.adresse,
        telephone: telephone ?? this.telephone,
        courriel: courriel ?? this.courriel,
        regime: regime ?? this.regime,
        serviceImpots: serviceImpots ?? this.serviceImpots,
        referencesBancaires: referencesBancaires ?? this.referencesBancaires,
      );
}
