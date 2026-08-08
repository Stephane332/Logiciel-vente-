/// Sauvegarde et restauration.
///
/// Les téléphones sont volés, cassés, reformatés, revendus. Sans sortie du
/// téléphone, la première perte efface tout — et c'est la seule panne dont un
/// commerçant ne se relève pas : ses dettes clients sont dedans, et personne
/// ne rembourse une ardoise que plus personne ne peut montrer.
///
/// Ce qui est sauvegardé, c'est **le journal**, pas les écrans. Les tables de
/// projection ne sont pas dans le fichier : elles se reconstruisent
/// entièrement à partir des événements. Le fichier est donc à la fois plus
/// petit et plus fidèle qu'une copie de la base — et il reste lisible même
/// quand le schéma aura changé.
///
/// Les réglages voyagent avec, parce qu'ils ne sont pas des événements : le
/// nom du commerce, les numéros marchands, l'équipe.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domaine/evenements.dart';
import 'base.dart';
import 'journal.dart';

/// Numéro de format du fichier.
///
/// Il ne suit pas la version de l'application : il ne bouge que le jour où la
/// forme du fichier change vraiment. Une application récente doit pouvoir
/// relire une sauvegarde ancienne, sinon la sauvegarde ne sert à rien le jour
/// où elle sert.
const formatSauvegarde = 1;

/// Ce qu'une sauvegarde annonce d'elle-même, avant d'être ouverte.
class ApercuSauvegarde {
  final String nomCommerce;
  final DateTime faiteLe;
  final int nombreEvenements;
  final DateTime? premierEvenement;
  final DateTime? dernierEvenement;

  /// Version de l'application qui a écrit le fichier. Informatif : c'est ce
  /// que je demanderai au téléphone quand un commerçant appellera.
  final String version;

  const ApercuSauvegarde({
    required this.nomCommerce,
    required this.faiteLe,
    required this.nombreEvenements,
    required this.version,
    this.premierEvenement,
    this.dernierEvenement,
  });

  bool get estVide => nombreEvenements == 0;
}

/// Ce qu'une restauration a fait, ou pourquoi elle n'a rien fait.
class ResultatRestauration {
  final bool reussie;
  final int evenementsRestaures;
  final String? motif;

  const ResultatRestauration.reussie(this.evenementsRestaures)
      : reussie = true,
        motif = null;

  const ResultatRestauration.refusee(this.motif)
      : reussie = false,
        evenementsRestaures = 0;
}

/// Le fichier de sauvegarde ouvert, prêt à être examiné puis restauré.
class Sauvegarde {
  final ApercuSauvegarde apercu;
  final List<Evenement> evenements;
  final Map<String, String> reglages;

  const Sauvegarde({
    required this.apercu,
    required this.evenements,
    required this.reglages,
  });
}

/// Lecture et écriture du fichier de sauvegarde.
class Sauvegardes {
  final BaseLocale base;
  final Journal journal;

  /// Version de l'application, portée dans le fichier.
  final String version;

  const Sauvegardes(this.base, this.journal, {required this.version});

  /// Nom de fichier proposé : le commerce et la date, pour que le commerçant
  /// reconnaisse sa sauvegarde au milieu de ses téléchargements.
  static String nomDeFichier(String nomCommerce, [DateTime? quand]) {
    final date = quand ?? DateTime.now();
    final base = nomCommerce
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    return 'carnet-${base.isEmpty ? 'boutique' : base}-'
        '${date.year}${_deuxChiffres(date.month)}${_deuxChiffres(date.day)}'
        '-${_deuxChiffres(date.hour)}${_deuxChiffres(date.minute)}.carnet';
  }

  /// Compose le fichier.
  ///
  /// Du JSON lisible, et pas une copie binaire de la base : le jour où une
  /// restauration échouera, je veux pouvoir ouvrir le fichier et voir ce
  /// qu'il contient. Une sauvegarde qu'on ne peut pas inspecter est une
  /// sauvegarde en laquelle on ne peut pas avoir confiance.
  Future<String> composer({String? nomCommerce, DateTime? quand}) async {
    final evenements = await journal.tous();
    final lignes = await base.select(base.reglages).get();

    return jsonEncode({
      'format': formatSauvegarde,
      'application': 'carnet',
      'version': version,
      'faiteLe': (quand ?? DateTime.now()).toIso8601String(),
      'nomCommerce': nomCommerce ?? '',
      'reglages': {for (final ligne in lignes) ligne.cle: ligne.valeur},
      'evenements': [
        for (final evenement in evenements)
          {
            'id': evenement.id,
            'appareil': evenement.appareil,
            'sequence': evenement.sequence,
            'horodatage': evenement.horodatage.toIso8601String(),
            'type': evenement.type.cle,
            'charge': evenement.charge,
            'empreinte': evenement.empreinte,
            'empreintePrecedente': evenement.empreintePrecedente,
          }
      ],
    });
  }

  /// Ouvre un fichier sans rien écrire.
  ///
  /// Renvoie `null` si ce n'en est pas un. Tout ce qui suit — l'aperçu montré
  /// au commerçant, la vérification de la chaîne — se fait avant que la base
  /// en place ne soit touchée.
  static Sauvegarde? ouvrir(String contenu) {
    final Object? brut;
    try {
      brut = jsonDecode(contenu);
    } on FormatException {
      return null;
    }
    if (brut is! Map<String, Object?>) return null;
    if (brut['application'] != 'carnet') return null;

    final format = brut['format'];
    if (format is! int || format > formatSauvegarde) return null;

    final evenements = <Evenement>[];
    final brutEvenements = brut['evenements'];
    if (brutEvenements is! List) return null;

    for (final element in brutEvenements) {
      if (element is! Map<String, Object?>) return null;
      final evenement = _lireEvenement(element);
      if (evenement == null) return null;
      evenements.add(evenement);
    }

    final reglages = <String, String>{};
    final brutReglages = brut['reglages'];
    if (brutReglages is Map) {
      brutReglages.forEach((cle, valeur) {
        if (cle is String && valeur is String) reglages[cle] = valeur;
      });
    }

    final dates = [for (final e in evenements) e.horodatage]..sort();

    return Sauvegarde(
      apercu: ApercuSauvegarde(
        nomCommerce: brut['nomCommerce'] as String? ?? '',
        faiteLe: DateTime.tryParse(brut['faiteLe'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        nombreEvenements: evenements.length,
        version: brut['version'] as String? ?? '?',
        premierEvenement: dates.isEmpty ? null : dates.first,
        dernierEvenement: dates.isEmpty ? null : dates.last,
      ),
      evenements: evenements,
      reglages: reglages,
    );
  }

  /// Remplace tout ce qui est en place par le contenu du fichier.
  ///
  /// La vérification passe **avant** l'écriture : restaurer d'abord et
  /// contrôler ensuite reviendrait à détruire des données en place pour
  /// découvrir que le fichier était abîmé.
  ///
  /// Une restauration écrase. Ce n'est pas une fusion : deux journaux qui se
  /// mélangeraient donneraient des doublons de ventes, et un commerçant ne
  /// pourrait plus démêler lesquelles sont réelles. La fusion viendra avec la
  /// synchronisation, où chaque appareil garde sa propre chaîne.
  Future<ResultatRestauration> restaurer(Sauvegarde sauvegarde) async {
    if (sauvegarde.evenements.isEmpty) {
      return const ResultatRestauration.refusee(
        "Cette sauvegarde est vide : elle n'effacera pas ce qui est là.",
      );
    }

    // Chaque appareil porte sa propre chaîne d'empreintes.
    final parAppareil = <String, List<Evenement>>{};
    for (final evenement in sauvegarde.evenements) {
      parAppareil.putIfAbsent(evenement.appareil, () => []).add(evenement);
    }
    for (final chaine in parAppareil.values) {
      chaine.sort((a, b) => a.sequence.compareTo(b.sequence));
      final verification = Journal.verifierChaine(chaine);
      if (!verification.intact) {
        return ResultatRestauration.refusee(
          'Ce fichier a été abîmé ou modifié : ${verification.motif}',
        );
      }
    }

    await base.transaction(() async {
      await base.delete(base.evenements).go();
      await base.delete(base.reglages).go();

      await base.batch((lot) {
        lot.insertAll(base.evenements, [
          for (final evenement in sauvegarde.evenements)
            EvenementsCompanion.insert(
              id: evenement.id,
              appareil: evenement.appareil,
              sequence: evenement.sequence,
              horodatage: evenement.horodatage,
              type: evenement.type.cle,
              charge: evenement.chargeJson,
              empreinte: evenement.empreinte,
              empreintePrecedente: Value(evenement.empreintePrecedente),
            )
        ]);
        lot.insertAll(base.reglages, [
          for (final entree in sauvegarde.reglages.entries)
            ReglagesCompanion.insert(
              cle: entree.key,
              valeur: entree.value,
              modifieLe: DateTime.now(),
            )
        ]);
      });
    });

    return ResultatRestauration.reussie(sauvegarde.evenements.length);
  }

  /// Un événement du fichier, ou `null` si la ligne est inexploitable.
  ///
  /// Un type inconnu n'est pas une erreur de fichier : c'est une sauvegarde
  /// écrite par une version plus récente. Elle se relit, et l'événement
  /// inconnu se rejouera le jour où l'application saura quoi en faire — le
  /// journal le garde en attendant.
  static Evenement? _lireEvenement(Map<String, Object?> ligne) {
    final id = ligne['id'];
    final appareil = ligne['appareil'];
    final sequence = ligne['sequence'];
    final type = ligne['type'];
    final empreinte = ligne['empreinte'];
    final horodatage = DateTime.tryParse(ligne['horodatage'] as String? ?? '');

    if (id is! String ||
        appareil is! String ||
        sequence is! int ||
        type is! String ||
        empreinte is! String ||
        horodatage == null) {
      return null;
    }

    final charge = ligne['charge'];
    if (charge is! Map) return null;

    final TypeEvenement lu;
    try {
      lu = TypeEvenement.parCle(type);
    } on ArgumentError {
      return null;
    }

    return Evenement(
      id: id,
      appareil: appareil,
      sequence: sequence,
      horodatage: horodatage,
      type: lu,
      charge: {
        for (final entree in charge.entries) '${entree.key}': entree.value
      },
      empreinte: empreinte,
      empreintePrecedente: ligne['empreintePrecedente'] as String?,
    );
  }

  static String _deuxChiffres(int valeur) =>
      valeur < 10 ? '0$valeur' : '$valeur';
}
