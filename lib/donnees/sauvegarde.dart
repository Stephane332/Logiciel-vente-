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
///
/// Le même fichier sert deux gestes très différents, et il ne faut pas les
/// confondre. **Restaurer** remplace tout : c'est le geste du téléphone perdu.
/// **Réunir** ajoute sans rien retirer : c'est le geste des deux caisses
/// d'une même boutique, qui doivent finir avec le même catalogue, les mêmes
/// ardoises et le même stock, chacune gardant ses propres ventes.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domaine/evenements.dart';
import '../domaine/numerotation.dart';
import 'base.dart';
import 'coffre.dart';
import 'journal.dart';
import 'parametres.dart';

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

  /// Quand chaque réglage a été touché pour la dernière fois.
  ///
  /// Une restauration n'en a pas besoin — elle remplace tout. Une réunion,
  /// si : quand deux caisses portent chacune une valeur pour la même clé, il
  /// faut départager, et la seule chose qui départage honnêtement, c'est la
  /// date. Sans elle, la dernière personne à avoir tendu son fichier gagne,
  /// ce qui n'a rien à voir avec la dernière personne à avoir corrigé l'IFU.
  ///
  /// Vide quand le fichier vient d'une version qui ne l'écrivait pas : la
  /// réunion se replie alors sur « je ne prends que ce qui me manque ».
  final Map<String, DateTime> reglagesModifies;

  const Sauvegarde({
    required this.apercu,
    required this.evenements,
    required this.reglages,
    this.reglagesModifies = const {},
  });
}

/// Ce qu'une réunion a ajouté, ou pourquoi elle n'a rien ajouté.
class ResultatFusion {
  final bool reussie;

  /// Écritures reçues qui n'étaient pas déjà là.
  final int evenementsAjoutes;

  /// Les caisses dont des écritures sont arrivées.
  final List<String> caissesRecues;

  /// Réglages repris du fichier — ceux qui manquaient, et ceux que l'autre
  /// téléphone avait corrigés plus récemment.
  final int reglagesAdoptes;

  /// De combien l'autre téléphone est en avance sur celui-ci, quand ça se
  /// voit. Nul quand les deux horloges s'accordent.
  ///
  /// Ça ne bloque rien — la réunion se fait quand même — mais il faut le
  /// dire : les projections se rejouent dans l'ordre des horodatages, et
  /// deux téléphones qui ne sont pas à la même heure rejouent dans un ordre
  /// qui n'est pas celui des faits. Une déclaration de stock peut alors
  /// passer après une vente qui l'a précédée, et le stock affiché se met à
  /// mentir. Les journées et les rapports Z se coupent au mauvais endroit
  /// pour la même raison.
  ///
  /// Seule l'avance se détecte : un fichier ne peut pas avoir été écrit
  /// après maintenant. Un téléphone en retard ressemble à un fichier ancien,
  /// et rien ne les distingue.
  final Duration? decalageHorloge;

  /// En deçà, ça ne vaut pas la peine d'en parler : les rapports se comptent
  /// par journée, et quelques minutes ne déplacent rien.
  static const seuilDecalage = Duration(minutes: 5);

  /// Les références de facture que les deux caisses ont attribuées chacune de
  /// son côté au même numéro.
  ///
  /// La note de service impose une série **ascendante et ininterrompue par
  /// année**, une référence par facture (§2.18). Or chaque caisse calcule son
  /// rang suivant dans son propre journal : deux caisses hors réseau qui
  /// facturent le même jour sortent toutes les deux `FV-2026-000001`, et la
  /// réunion des carnets ne peut pas les renuméroter — le journal ne se
  /// réécrit pas, et le client est déjà reparti avec sa facture.
  ///
  /// Je ne bloque donc pas la réunion : les deux factures existent déjà dans
  /// le monde, refuser ne les défait pas, et refuser cacherait le problème
  /// au lieu de le montrer. Je le dis, et fort. La règle qui va avec tient en
  /// une ligne : **une seule caisse fait les factures.**
  final List<String> facturesEnDouble;

  final String? motif;

  const ResultatFusion.reussie({
    required this.evenementsAjoutes,
    required this.caissesRecues,
    required this.reglagesAdoptes,
    this.decalageHorloge,
    this.facturesEnDouble = const [],
  }) : reussie = true,
       motif = null;

  const ResultatFusion.refusee(this.motif)
    : reussie = false,
      evenementsAjoutes = 0,
      caissesRecues = const [],
      reglagesAdoptes = 0,
      decalageHorloge = null,
      facturesEnDouble = const [];

  /// Vrai quand la réunion a marché mais que les deux caisses étaient déjà
  /// à jour l'une de l'autre. Ce n'est pas un échec, et l'écran ne doit pas
  /// le présenter comme tel.
  bool get rienDeNouveau => reussie && evenementsAjoutes == 0;
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
  ///
  /// Avec un [motDePasse], le même contenu part dans une enveloppe scellée —
  /// voir `coffre.dart`. Sans, il reste tel quel : lisible, inspectable, et
  /// c'est ce qu'on veut le jour où une restauration échoue.
  Future<String> composer({
    String? nomCommerce,
    DateTime? quand,
    String? motDePasse,
  }) async {
    final clair = await _composerEnClair(
      nomCommerce: nomCommerce,
      quand: quand,
    );
    if (motDePasse == null || motDePasse.isEmpty) return clair;

    return Coffre.fermer(
      clair,
      motDePasse: motDePasse,
      format: formatSauvegarde,
      nomCommerce: nomCommerce ?? '',
      faiteLe: quand ?? DateTime.now(),
    );
  }

  /// Vrai quand le fichier est scellé : l'écran doit demander le mot de passe
  /// **avant** de proposer quoi que ce soit.
  static bool estChiffree(String contenu) => Coffre.estChiffre(contenu);

  /// Ouvre un fichier scellé. `null` si le mot de passe ne va pas — ou si le
  /// fichier a été abîmé, ce qui se traite pareil : on n'écrit rien.
  static Future<Sauvegarde?> ouvrirAvec(
    String contenu,
    String motDePasse,
  ) async {
    final clair = await Coffre.ouvrir(contenu, motDePasse);
    return clair == null ? null : ouvrir(clair);
  }

  Future<String> _composerEnClair({
    String? nomCommerce,
    DateTime? quand,
  }) async {
    final evenements = await journal.tous();
    final lignes = await base.select(base.reglages).get();

    return jsonEncode({
      'format': formatSauvegarde,
      'application': 'carnet',
      'version': version,
      'faiteLe': (quand ?? DateTime.now()).toIso8601String(),
      'nomCommerce': nomCommerce ?? '',
      'reglages': {for (final ligne in lignes) ligne.cle: ligne.valeur},
      // Une clé en plus, pas un format en plus : une application ancienne
      // relit le fichier sans la voir, une récente s'en sert pour départager
      // deux caisses. Changer le numéro de format aurait rendu tous les
      // fichiers d'aujourd'hui illisibles par les téléphones d'hier.
      'reglagesModifies': {
        for (final ligne in lignes)
          ligne.cle: ligne.modifieLe.toIso8601String(),
      },
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
          },
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

    final reglagesModifies = <String, DateTime>{};
    final brutModifies = brut['reglagesModifies'];
    if (brutModifies is Map) {
      brutModifies.forEach((cle, valeur) {
        if (cle is! String || valeur is! String) return;
        final quand = DateTime.tryParse(valeur);
        if (quand != null) reglagesModifies[cle] = quand;
      });
    }

    final dates = [for (final e in evenements) e.horodatage]..sort();

    return Sauvegarde(
      apercu: ApercuSauvegarde(
        nomCommerce: brut['nomCommerce'] as String? ?? '',
        faiteLe:
            DateTime.tryParse(brut['faiteLe'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        nombreEvenements: evenements.length,
        version: brut['version'] as String? ?? '?',
        premierEvenement: dates.isEmpty ? null : dates.first,
        dernierEvenement: dates.isEmpty ? null : dates.last,
      ),
      evenements: evenements,
      reglages: reglages,
      reglagesModifies: reglagesModifies,
    );
  }

  /// Remplace tout ce qui est en place par le contenu du fichier.
  ///
  /// La vérification passe **avant** l'écriture : restaurer d'abord et
  /// contrôler ensuite reviendrait à détruire des données en place pour
  /// découvrir que le fichier était abîmé.
  ///
  /// Une restauration écrase, et c'est voulu : c'est le geste du téléphone
  /// perdu, où ce qui est en place ne vaut rien. Pour deux caisses qui
  /// travaillent en même temps, ce geste est le mauvais — il effacerait les
  /// ventes de celle qui reçoit. C'est [fusionner] qu'il faut.
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
            ),
        ]);
        lot.insertAll(base.reglages, [
          for (final entree in sauvegarde.reglages.entries)
            ReglagesCompanion.insert(
              cle: entree.key,
              valeur: entree.value,
              modifieLe: DateTime.now(),
            ),
        ]);
      });
    });

    return ResultatRestauration.reussie(sauvegarde.evenements.length);
  }

  /// Réunit le carnet d'une autre caisse à celui-ci, sans rien effacer.
  ///
  /// C'est la réponse à une boutique qui a deux vendeuses, deux téléphones,
  /// et un seul commerce. Chacune encaisse de son côté — y compris hors
  /// réseau, y compris toute la journée — puis on réunit les deux le soir.
  /// Les deux téléphones finissent avec le même catalogue, les mêmes
  /// ardoises, le même stock et **toutes** les ventes des deux.
  ///
  /// Ça marche sans serveur parce que le journal a été bâti pour : les
  /// empreintes se chaînent **par appareil**, pas à travers tout le journal.
  /// Deux caisses qui écrivent en même temps ne se marchent donc pas dessus,
  /// et réunir leurs journaux revient à poser deux chaînes côte à côte — pas
  /// à en recoudre une seule, ce qui serait impossible sans arbitre commun.
  ///
  /// L'échange reste **manuel** : un fichier qui passe par WhatsApp, par
  /// Bluetooth ou par une carte mémoire, et quelqu'un qui l'ouvre ici. Ce
  /// n'est pas une synchronisation automatique, et je préfère le dire que le
  /// laisser croire : personne ne remonte rien tout seul.
  ///
  /// Trois refus, tous avant la moindre écriture :
  ///
  /// * le fichier est vide — il n'y a rien à réunir ;
  /// * une chaîne reçue ne tient pas debout — le fichier a été abîmé ;
  /// * les deux carnets se contredisent sur une même caisse — deux
  ///   téléphones portent le même nom d'appareil et n'ont pas écrit la même
  ///   chose. Réunir effacerait des ventes réelles, donc on ne réunit pas.
  ///
  /// Les projections ne sont pas touchées ici : l'appelant enchaîne sur
  /// `reconstruireProjections()`, comme après une restauration.
  Future<ResultatFusion> fusionner(Sauvegarde autre) async {
    if (autre.evenements.isEmpty) {
      return const ResultatFusion.refusee(
        "Ce fichier ne porte aucune écriture : il n'y a rien à réunir.",
      );
    }

    // Chaque caisse reçue doit tenir debout toute seule, avant qu'on écrive
    // quoi que ce soit.
    final recues = <String, List<Evenement>>{};
    for (final evenement in autre.evenements) {
      recues.putIfAbsent(evenement.appareil, () => []).add(evenement);
    }
    for (final chaine in recues.values) {
      chaine.sort((a, b) => a.sequence.compareTo(b.sequence));
      final verification = Journal.verifierChaine(chaine);
      if (!verification.intact) {
        return ResultatFusion.refusee(
          'Ce fichier a été abîmé ou modifié : ${verification.motif}',
        );
      }
    }

    // Et aucune ne doit contredire ce qui est déjà là.
    final aEcrire = <Evenement>[];
    final caissesRecues = <String>[];

    for (final entree in recues.entries) {
      final ici = await journal.chaine(entree.key);
      final connues = {for (final evenement in ici) evenement.sequence};
      final empreintes = {
        for (final evenement in ici) evenement.sequence: evenement.empreinte,
      };

      var nouveaux = 0;
      for (final evenement in entree.value) {
        if (!connues.contains(evenement.sequence)) {
          aEcrire.add(evenement);
          nouveaux++;
          continue;
        }
        if (empreintes[evenement.sequence] != evenement.empreinte) {
          return ResultatFusion.refusee(
            'Les deux carnets ne racontent pas la même histoire pour la '
            'caisse « ${entree.key} ». Les réunir effacerait des ventes '
            "réelles : rien n'a été touché.",
          );
        }
      }
      if (nouveaux > 0) caissesRecues.add(entree.key);
    }

    final reglages = await _reglagesAAdopter(autre);
    final decalage = _decalage(autre);
    final doublons = await _facturesEnDouble(aEcrire);

    if (aEcrire.isEmpty && reglages.isEmpty) {
      return ResultatFusion.reussie(
        evenementsAjoutes: 0,
        caissesRecues: const [],
        reglagesAdoptes: 0,
        decalageHorloge: decalage,
      );
    }

    caissesRecues.sort();

    await base.transaction(() async {
      if (aEcrire.isNotEmpty) {
        await base.batch((lot) {
          lot.insertAll(
            base.evenements,
            [
              for (final evenement in aEcrire)
                EvenementsCompanion.insert(
                  id: evenement.id,
                  appareil: evenement.appareil,
                  sequence: evenement.sequence,
                  horodatage: evenement.horodatage,
                  type: evenement.type.cle,
                  charge: evenement.chargeJson,
                  empreinte: evenement.empreinte,
                  empreintePrecedente: Value(evenement.empreintePrecedente),
                ),
            ],
            // Le même fichier réuni deux fois ne doit pas casser. Les
            // événements déjà là ont été comparés empreinte par empreinte
            // juste au-dessus : les réécrire à l'identique ne change rien.
            mode: InsertMode.insertOrIgnore,
          );
        });
      }

      for (final entree in reglages.entries) {
        await base
            .into(base.reglages)
            .insertOnConflictUpdate(
              ReglagesCompanion.insert(
                cle: entree.key,
                valeur: entree.value.$1,
                modifieLe: entree.value.$2,
              ),
            );
      }

      // La trace de la réunion, écrite sur la chaîne de cette caisse-ci.
      //
      // Seulement quand quelque chose est arrivé : sans ce garde-fou, deux
      // téléphones qui se réunissent à tour de rôle s'échangeraient des
      // événements de réunion sans fin, chacun réagissant à celui de l'autre.
      if (aEcrire.isNotEmpty) {
        await journal.ajouter(TypeEvenement.journalFusionne, {
          'caisses': caissesRecues,
          'ajoutes': aEcrire.length,
          'reglages': reglages.length,
        });
      }
    });

    return ResultatFusion.reussie(
      evenementsAjoutes: aEcrire.length,
      caissesRecues: caissesRecues,
      reglagesAdoptes: reglages.length,
      decalageHorloge: decalage,
      facturesEnDouble: doublons,
    );
  }

  /// Les références qu'une facture d'ici et une facture d'ailleurs se
  /// disputent.
  ///
  /// Comparées par (type, année, rang), c'est-à-dire par ce qui est imprimé
  /// sur le papier, et rapportées à la vente couverte : la même facture reçue
  /// deux fois n'est pas un doublon, deux ventes différentes sous le même
  /// numéro en sont un.
  Future<List<String>> _facturesEnDouble(List<Evenement> recus) async {
    final ventesParReference = <String, Set<String>>{};

    void poser(Evenement evenement) {
      final reference = ReferenceFacture(
        type: evenement.charge['type']! as String,
        annee: evenement.charge['annee']! as int,
        rang: evenement.charge['rang']! as int,
      ).texte;
      final vente = evenement.charge['venteId'] as String? ?? evenement.id;
      ventesParReference.putIfAbsent(reference, () => <String>{}).add(vente);
    }

    for (final evenement in await journal.parType(TypeEvenement.factureEmise)) {
      poser(evenement);
    }
    for (final evenement in recus) {
      if (evenement.type == TypeEvenement.factureEmise) poser(evenement);
    }

    final doubles = [
      for (final entree in ventesParReference.entries)
        if (entree.value.length > 1) entree.key,
    ]..sort();
    return doubles;
  }

  /// De combien l'autre téléphone avance sur celui-ci.
  ///
  /// On regarde deux choses : la date d'écriture du fichier, et son dernier
  /// événement. Ni l'une ni l'autre ne peut se situer après maintenant. Ce
  /// qui dépasse est de l'avance, et c'est l'horloge de l'autre appareil.
  static Duration? _decalage(Sauvegarde autre) {
    final maintenant = DateTime.now();
    var avance = Duration.zero;

    for (final quand in [autre.apercu.faiteLe, autre.apercu.dernierEvenement]) {
      if (quand == null) continue;
      final ecart = quand.difference(maintenant);
      if (ecart > avance) avance = ecart;
    }

    return avance < ResultatFusion.seuilDecalage ? null : avance;
  }

  /// Les réglages à reprendre du fichier, avec la date à leur donner.
  ///
  /// Trois traitements, parce que les réglages ne sont pas tous de la même
  /// nature :
  ///
  /// * ceux qui décrivent **ce téléphone-ci** ne bougent jamais — voir
  ///   [Parametres.clesPropresAuTelephone] ;
  /// * l'**équipe** prend l'union des deux listes. C'est le seul réglage où
  ///   choisir un camp serait faux : une boutique qui a embauché sur un
  ///   téléphone et sur l'autre a bien tous ces vendeurs-là ;
  /// * le **reste** revient au plus récent des deux. À défaut de date dans le
  ///   fichier, on ne prend que ce qui manque ici : un fichier ancien ne doit
  ///   pas écraser une correction d'aujourd'hui.
  Future<Map<String, (String, DateTime)>> _reglagesAAdopter(
    Sauvegarde autre,
  ) async {
    final lignes = await base.select(base.reglages).get();
    final ici = {for (final ligne in lignes) ligne.cle: ligne};
    final aPoser = <String, (String, DateTime)>{};

    for (final entree in autre.reglages.entries) {
      final cle = entree.key;
      if (Parametres.clesPropresAuTelephone.contains(cle)) continue;
      if (cle == Parametres.cleVendeurs) continue;

      final quand = autre.reglagesModifies[cle] ?? DateTime.now();
      final present = ici[cle];
      if (present == null) {
        aPoser[cle] = (entree.value, quand);
        continue;
      }
      if (present.valeur == entree.value) continue;
      if (autre.reglagesModifies[cle] case final datee?
          when datee.isAfter(present.modifieLe)) {
        aPoser[cle] = (entree.value, datee);
      }
    }

    final equipe = _vendeurs(ici[Parametres.cleVendeurs]?.valeur);
    final avant = equipe.length;
    for (final nom in _vendeurs(autre.reglages[Parametres.cleVendeurs])) {
      if (!equipe.contains(nom)) equipe.add(nom);
    }
    if (equipe.length > avant) {
      aPoser[Parametres.cleVendeurs] = (
        equipe.join(Parametres.separateurVendeurs),
        DateTime.now(),
      );
    }

    return aPoser;
  }

  static List<String> _vendeurs(String? valeur) {
    if (valeur == null) return [];
    return [
      for (final nom in valeur.split(Parametres.separateurVendeurs))
        if (nom.trim().isNotEmpty) nom.trim(),
    ];
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
        for (final entree in charge.entries) '${entree.key}': entree.value,
      },
      empreinte: empreinte,
      empreintePrecedente: ligne['empreintePrecedente'] as String?,
    );
  }

  static String _deuxChiffres(int valeur) =>
      valeur < 10 ? '0$valeur' : '$valeur';
}
