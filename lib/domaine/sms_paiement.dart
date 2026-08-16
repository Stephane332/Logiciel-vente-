/// Lire un SMS de confirmation d'un opérateur mobile money.
///
/// Le client compose le code, l'opérateur débite son compte et crédite celui
/// du commerçant, puis lui envoie un SMS. Jusqu'ici, c'est le commerçant qui
/// regardait ce SMS et confirmait à la main. Ce fichier fait la moitié qui
/// peut se faire seule : reconnaître le message, en tirer le montant et
/// l'expéditeur, et le rapprocher de la vente en cours.
///
/// **Deux précautions qui tiennent tout le reste.**
///
/// Les règles sont des **données**, pas du code. Un opérateur peut changer le
/// format de ses messages du jour au lendemain ; je dois pouvoir corriger sans
/// publier une mise à jour, et un jour les faire descendre du serveur. Elles
/// se lisent et s'écrivent en JSON pour cette raison.
///
/// Un SMS reconnu **ne valide jamais une vente tout seul**. Il la marque comme
/// confirmée et l'affiche au commerçant, qui garde le dernier geste. Un faux
/// positif — un message d'un autre client, un remboursement, un transfert
/// entre proches — encaisserait sinon une vente que personne n'a payée, et
/// c'est une erreur qu'on ne rattrape pas au comptoir.
library;

import 'dart:convert';

import 'mobile_money.dart';
import 'montant.dart';
import 'telephone.dart';

/// Ce qu'un SMS de confirmation a permis de lire.
class PaiementRecu {
  final OperateurMobile operateur;
  final Montant montant;

  /// Le numéro qui a payé, normalisé. Nul quand le message ne le porte pas.
  final String? expediteur;

  /// La référence de transaction de l'opérateur, quand il en donne une.
  ///
  /// C'est elle qu'on montre en cas de litige : « ton paiement porte le
  /// numéro tant », et l'opérateur peut le retrouver.
  final String? reference;

  /// Quand le SMS est arrivé sur le téléphone.
  final DateTime recuLe;

  const PaiementRecu({
    required this.operateur,
    required this.montant,
    required this.recuLe,
    this.expediteur,
    this.reference,
  });

  /// Ce qui s'affiche au commerçant : court, et ça tient sur une ligne.
  String get resume {
    final qui = expediteur == null ? '' : ' de ${presenterTelephone(expediteur)}';
    return '${operateur.abrege} · ${montant.enFrancs}$qui';
  }
}

/// Comment reconnaître les messages d'un opérateur.
///
/// Une règle par opérateur, décrite en JSON. Les expressions doivent capturer
/// leur valeur dans le premier groupe.
class RegleSms {
  final OperateurMobile operateur;

  /// Les numéros ou noms courts qui envoient ces messages. Comparés sans
  /// tenir compte de la casse ni des espaces.
  final List<String> expediteurs;

  /// Ce que le corps doit contenir pour qu'on tente la lecture. Sert à écarter
  /// tout de suite les messages publicitaires du même expéditeur, qui sont
  /// nombreux et qui portent parfois des montants.
  final List<String> exige;

  /// Ce qui disqualifie le message même s'il contient tout le reste : un
  /// débit, un transfert sortant, un rappel de solde.
  final List<String> exclut;

  final RegExp montant;
  final RegExp? numero;
  final RegExp? reference;

  RegleSms({
    required this.operateur,
    required this.expediteurs,
    required this.montant,
    this.exige = const [],
    this.exclut = const [],
    this.numero,
    this.reference,
  });

  factory RegleSms.depuisJson(Map<String, Object?> brut) {
    final nom = brut['operateur'] as String?;
    final operateur = OperateurMobile.values.firstWhere(
      (o) => o.name == nom,
      orElse: () => throw ArgumentError('Opérateur inconnu : $nom'),
    );
    RegExp? expression(String cle) {
      final motif = brut[cle] as String?;
      return motif == null ? null : RegExp(motif, caseSensitive: false);
    }

    return RegleSms(
      operateur: operateur,
      expediteurs: [
        for (final e in (brut['expediteurs'] as List? ?? const [])) '$e'
      ],
      exige: [for (final e in (brut['exige'] as List? ?? const [])) '$e'],
      exclut: [for (final e in (brut['exclut'] as List? ?? const [])) '$e'],
      montant: expression('montant')!,
      numero: expression('numero'),
      reference: expression('reference'),
    );
  }

  Map<String, Object?> versJson() => {
        'operateur': operateur.name,
        'expediteurs': expediteurs,
        if (exige.isNotEmpty) 'exige': exige,
        if (exclut.isNotEmpty) 'exclut': exclut,
        'montant': montant.pattern,
        if (numero != null) 'numero': numero!.pattern,
        if (reference != null) 'reference': reference!.pattern,
      };
}

/// Lit les SMS entrants et en tire les paiements.
class LecteurSms {
  final List<RegleSms> regles;

  const LecteurSms(this.regles);

  /// Les règles par défaut.
  ///
  /// **Elles sont à confirmer sur de vrais messages.** Je n'ai pas encore de
  /// compte marchand actif chez les trois opérateurs, et un format deviné est
  /// un format faux. Elles sont volontairement tolérantes — le montant peut
  /// s'écrire `3500`, `3 500`, `3.500` ou `3,500 FCFA` — et surtout elles se
  /// remplacent sans toucher au code.
  ///
  /// Tant qu'elles n'ont pas été vérifiées au comptoir, un message non reconnu
  /// n'est pas une panne : le commerçant confirme à la main, comme avant.
  static LecteurSms get parDefaut => LecteurSms([
        RegleSms(
          operateur: OperateurMobile.orange,
          expediteurs: const ['OrangeMoney', 'Orange Money', 'OM', '144'],
          exige: const ['recu', 'reçu'],
          exclut: const ['transfert vers', 'retrait', 'solde insuffisant'],
          montant: RegExp(r'([\d][\d\s., ]*)\s*(?:F\b|FCFA|XOF)',
              caseSensitive: false),
          numero: RegExp(r'\b((?:226)?[2567]\d{7})\b'),
          // Le séparateur est de la ponctuation, pas « n'importe quoi qui
          // n'est pas un chiffre » : `\D` avalait le début d'une référence
          // qui commence par des lettres.
          reference: RegExp(
              r'(?:ref|reference|transaction)[\s:=#]{0,5}([A-Z0-9.\-]{6,})',
              caseSensitive: false),
        ),
        RegleSms(
          operateur: OperateurMobile.moov,
          expediteurs: const ['MoovMoney', 'Moov Money', 'Moov', '555'],
          exige: const ['recu', 'reçu'],
          exclut: const ['transfert vers', 'retrait'],
          montant: RegExp(r'([\d][\d\s., ]*)\s*(?:F\b|FCFA|XOF)',
              caseSensitive: false),
          numero: RegExp(r'\b((?:226)?[2567]\d{7})\b'),
          // Le séparateur est de la ponctuation, pas « n'importe quoi qui
          // n'est pas un chiffre » : `\D` avalait le début d'une référence
          // qui commence par des lettres.
          reference: RegExp(
              r'(?:ref|reference|transaction)[\s:=#]{0,5}([A-Z0-9.\-]{6,})',
              caseSensitive: false),
        ),
        RegleSms(
          operateur: OperateurMobile.telecel,
          expediteurs: const ['TelecelMoney', 'Telecel Money', 'Telecel', '800'],
          exige: const ['recu', 'reçu'],
          exclut: const ['transfert vers', 'retrait'],
          montant: RegExp(r'([\d][\d\s., ]*)\s*(?:F\b|FCFA|XOF)',
              caseSensitive: false),
          numero: RegExp(r'\b((?:226)?[2567]\d{7})\b'),
          // Le séparateur est de la ponctuation, pas « n'importe quoi qui
          // n'est pas un chiffre » : `\D` avalait le début d'une référence
          // qui commence par des lettres.
          reference: RegExp(
              r'(?:ref|reference|transaction)[\s:=#]{0,5}([A-Z0-9.\-]{6,})',
              caseSensitive: false),
        ),
      ]);

  static LecteurSms depuisJson(String json) {
    final brut = jsonDecode(json);
    if (brut is! List) throw ArgumentError('Une liste de règles est attendue.');
    return LecteurSms([
      for (final r in brut) RegleSms.depuisJson(Map<String, Object?>.from(r as Map))
    ]);
  }

  String versJson() =>
      jsonEncode([for (final regle in regles) regle.versJson()]);

  /// Lit un message. Rend `null` quand ce n'en est pas un — et c'est le cas le
  /// plus fréquent, un téléphone recevant surtout de la publicité.
  PaiementRecu? lire({
    required String expediteur,
    required String corps,
    required DateTime recuLe,
  }) {
    final regle = _regleDe(expediteur);
    if (regle == null) return null;

    final texte = _sansAccents(corps.toLowerCase());
    for (final mot in regle.exclut) {
      if (texte.contains(_sansAccents(mot.toLowerCase()))) return null;
    }
    if (regle.exige.isNotEmpty &&
        !regle.exige.any((m) => texte.contains(_sansAccents(m.toLowerCase())))) {
      return null;
    }

    final montant = _montantDe(regle.montant, corps);
    if (montant == null || !montant.estPositif) return null;

    return PaiementRecu(
      operateur: regle.operateur,
      montant: montant,
      recuLe: recuLe,
      expediteur: _premier(regle.numero, corps, normaliserTelephone),
      reference: _premier(regle.reference, corps, (v) => v),
    );
  }

  RegleSms? _regleDe(String expediteur) {
    final propre = _compact(expediteur);
    for (final regle in regles) {
      for (final connu in regle.expediteurs) {
        if (_compact(connu) == propre) return regle;
      }
    }
    return null;
  }

  /// Lit un montant écrit à la burkinabè.
  ///
  /// `3 500 F`, `3.500 FCFA`, `3,500F`, `3500 XOF` : le séparateur de milliers
  /// varie d'un opérateur à l'autre et parfois d'un message à l'autre. Aucun
  /// n'écrit de centimes — le franc CFA n'en a pas en circulation — donc tout
  /// ce qui sépare des chiffres est un séparateur de milliers, et rien d'autre.
  static Montant? _montantDe(RegExp expression, String corps) {
    final trouve = expression.firstMatch(corps);
    if (trouve == null) return null;

    final chiffres = trouve.group(1)!.replaceAll(RegExp(r'[^\d]'), '');
    if (chiffres.isEmpty) return null;

    final francs = int.tryParse(chiffres);
    if (francs == null) return null;
    return Montant.depuisDecimal(francs);
  }

  static String? _premier(
    RegExp? expression,
    String corps,
    String? Function(String) transforme,
  ) {
    if (expression == null) return null;
    for (final trouve in expression.allMatches(corps)) {
      final brut = trouve.group(1);
      if (brut == null) continue;
      final valeur = transforme(brut);
      if (valeur != null && valeur.isNotEmpty) return valeur;
    }
    return null;
  }

  static String _compact(String valeur) =>
      valeur.toLowerCase().replaceAll(RegExp(r'[\s\-_+]'), '');

  static String _sansAccents(String valeur) {
    const accents = 'àâäçéèêëîïôöùûüÿ';
    const nus = 'aaaceeeeiioouuuy';
    var sortie = valeur;
    for (var i = 0; i < accents.length; i++) {
      sortie = sortie.replaceAll(accents[i], nus[i]);
    }
    return sortie;
  }
}

/// Rapproche un paiement reçu d'un encaissement en attente.
///
/// Deux conditions, et pas une de moins : **le montant exact**, et une
/// **fenêtre de temps courte**. Un commerçant qui encaisse 3 500 F deux fois
/// dans la journée ne doit pas voir le second SMS pointer sur la première
/// vente ; et un SMS arrivé une heure après ne parle plus de ce qui est à
/// l'écran.
class Rapprochement {
  /// Au-delà, on ne rapproche plus. Le client compose le code devant le
  /// comptoir : la confirmation arrive en quelques secondes, rarement plus
  /// d'une minute même sur un réseau chargé.
  static const fenetre = Duration(minutes: 3);

  /// Vrai si ce paiement correspond à l'encaissement présenté.
  static bool correspond({
    required PaiementRecu paiement,
    required Montant attendu,
    required OperateurMobile operateur,
    required DateTime depuis,
  }) {
    if (paiement.operateur != operateur) return false;
    if (paiement.montant.centimes != attendu.centimes) return false;

    final ecart = paiement.recuLe.difference(depuis);
    if (ecart.isNegative) return false;
    return ecart <= fenetre;
  }
}
