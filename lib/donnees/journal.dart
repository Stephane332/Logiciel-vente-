/// Le journal d'événements.
///
/// Écriture append-only, avec chaînage d'empreintes : l'empreinte de chaque
/// événement est calculée sur son contenu **et** sur celle de l'événement
/// précédent. Modifier ou supprimer un événement ancien invalide toute la
/// suite de la chaîne, et la falsification devient détectable.
///
/// C'est ce qui permet de répondre à l'exigence d'inaltérabilité du §2.23 de
/// la note de service, et c'est aussi ce qui rend la synchronisation fiable :
/// une rupture de séquence signale une perte, une rupture d'empreinte signale
/// une altération.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../domaine/evenements.dart';
import 'base.dart';

/// Résultat d'une vérification d'intégrité du journal.
class VerificationJournal {
  final bool intact;
  final int nombreEvenements;

  /// Identifiant du premier événement fautif, s'il y en a un.
  final String? premierFautif;

  final String? motif;

  const VerificationJournal({
    required this.intact,
    required this.nombreEvenements,
    this.premierFautif,
    this.motif,
  });
}

class Journal {
  final BaseLocale _base;
  final String appareil;
  final GenerateurIdentifiant _identifiants;

  Journal(this._base, {required this.appareil})
      : _identifiants = GenerateurIdentifiant(appareil);

  /// Calcule l'empreinte d'un événement.
  static String empreinteDe(Evenement evenement) =>
      sha256.convert(utf8.encode(evenement.representationCanonique)).toString();

  /// Écrit un événement à la suite du journal.
  ///
  /// Renvoie l'événement complet, avec sa séquence et son empreinte.
  /// Ramène un horodatage à la seconde entière.
  ///
  /// L'empreinte est calculée sur l'horodatage, et doit donc rester
  /// identique après un aller-retour en base. Or la base ne conserve pas les
  /// millisecondes : sans cette normalisation, tout journal relu paraîtrait
  /// falsifié.
  ///
  /// La seconde suffit largement : c'est aussi la précision de l'horodatage
  /// que la DGI porte dans le code QR, au format AAAAMMJJHHMMSS.
  static DateTime alaSeconde(DateTime instant) {
    final millis = instant.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
      millis - millis.remainder(1000),
      isUtc: instant.isUtc,
    );
  }

  Future<Evenement> ajouter(
    TypeEvenement type,
    Map<String, Object?> charge, {
    DateTime? horodatage,
  }) async {
    final quand = alaSeconde(horodatage ?? DateTime.now());

    return _base.transaction(() async {
      final dernier = await _dernierEvenement();
      final sequence = (dernier?.sequence ?? 0) + 1;

      final provisoire = Evenement(
        id: _identifiants.suivant(quand),
        appareil: appareil,
        sequence: sequence,
        horodatage: quand,
        type: type,
        charge: charge,
        empreintePrecedente: dernier?.empreinte,
        empreinte: '',
      );

      final evenement = Evenement(
        id: provisoire.id,
        appareil: provisoire.appareil,
        sequence: provisoire.sequence,
        horodatage: provisoire.horodatage,
        type: provisoire.type,
        charge: provisoire.charge,
        empreintePrecedente: provisoire.empreintePrecedente,
        empreinte: empreinteDe(provisoire),
      );

      await _base.into(_base.evenements).insert(
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
          );

      return evenement;
    });
  }

  Future<LigneEvenement?> _dernierEvenement() {
    final requete = _base.select(_base.evenements)
      ..where((e) => e.appareil.equals(appareil))
      ..orderBy([(e) => OrderingTerm.desc(e.sequence)])
      ..limit(1);
    return requete.getSingleOrNull();
  }

  /// Tous les événements en base, dans l'ordre où il faut les rejouer.
  ///
  /// Tous, et pas seulement ceux de cet appareil : une sauvegarde restaurée
  /// sur un autre téléphone porte l'identifiant du premier, et un filtre par
  /// appareil rendrait le passé entièrement invisible — le commerçant
  /// restaurerait sa sauvegarde et retrouverait une boutique vide.
  ///
  /// L'ordre est chronologique, la séquence ne départageant que deux
  /// événements du même appareil arrivés dans la même seconde. C'est l'ordre
  /// des faits, et c'est celui dans lequel les projections doivent se
  /// reconstruire.
  Future<List<Evenement>> tous() async {
    final requete = _base.select(_base.evenements)
      ..orderBy([
        (e) => OrderingTerm.asc(e.horodatage),
        (e) => OrderingTerm.asc(e.appareil),
        (e) => OrderingTerm.asc(e.sequence),
      ]);
    final lignes = await requete.get();
    return lignes.map(_versEvenement).toList();
  }

  /// La chaîne d'un appareil, dans l'ordre de ses séquences.
  ///
  /// C'est l'unité d'intégrité : les empreintes se chaînent par appareil, pas
  /// à travers tout le journal — deux caisses qui écrivent en même temps hors
  /// ligne ne peuvent pas se chaîner l'une à l'autre.
  Future<List<Evenement>> chaine([String? lequel]) async {
    final requete = _base.select(_base.evenements)
      ..where((e) => e.appareil.equals(lequel ?? appareil))
      ..orderBy([(e) => OrderingTerm.asc(e.sequence)]);
    final lignes = await requete.get();
    return lignes.map(_versEvenement).toList();
  }

  /// Les appareils qui ont écrit dans ce journal.
  Future<List<String>> appareils() async {
    final lignes = await _base
        .customSelect(
          'SELECT DISTINCT appareil FROM evenements ORDER BY appareil',
          readsFrom: {_base.evenements},
        )
        .get();
    return [for (final ligne in lignes) ligne.read<String>('appareil')];
  }

  /// Les événements pas encore remontés au serveur, dans l'ordre.
  Future<List<Evenement>> enAttenteDeSynchronisation({int limite = 200}) async {
    final requete = _base.select(_base.evenements)
      ..where((e) => e.synchronise.equals(false))
      ..orderBy([(e) => OrderingTerm.asc(e.sequence)])
      ..limit(limite);
    final lignes = await requete.get();
    return lignes.map(_versEvenement).toList();
  }

  /// Marque des événements comme remontés.
  ///
  /// C'est la seule colonne du journal qui évolue après écriture, et elle ne
  /// participe pas au calcul de l'empreinte.
  Future<void> marquerSynchronises(Iterable<String> identifiants) async {
    final liste = identifiants.toList();
    if (liste.isEmpty) return;
    await (_base.update(_base.evenements)..where((e) => e.id.isIn(liste)))
        .write(const EvenementsCompanion(synchronise: Value(true)));
  }

  /// Vérifie l'intégrité du journal, chaîne par chaîne.
  ///
  /// À lancer au démarrage, avant toute remontée au serveur, et avant de
  /// restaurer une sauvegarde. Contrôle la continuité des séquences, le
  /// chaînage des empreintes, et recalcule chaque empreinte à partir du
  /// contenu.
  ///
  /// Chaque appareil a sa propre chaîne : un journal qui en porte plusieurs —
  /// après une restauration, ou plus tard avec deux caisses — est intact si
  /// toutes le sont.
  Future<VerificationJournal> verifier() async {
    final lesquels = await appareils();
    if (lesquels.isEmpty) {
      return const VerificationJournal(intact: true, nombreEvenements: 0);
    }

    var total = 0;
    for (final lequel in lesquels) {
      final resultat = verifierChaine(await chaine(lequel));
      total += resultat.nombreEvenements;
      if (!resultat.intact) {
        return VerificationJournal(
          intact: false,
          nombreEvenements: total,
          premierFautif: resultat.premierFautif,
          motif: resultat.motif,
        );
      }
    }
    return VerificationJournal(intact: true, nombreEvenements: total);
  }

  /// Vérifie une chaîne déjà en main.
  ///
  /// Statique et sans base : c'est ce qui permet de contrôler une sauvegarde
  /// **avant** de l'écrire. Restaurer d'abord et vérifier ensuite reviendrait
  /// à détruire les données en place pour découvrir que le fichier est
  /// abîmé.
  static VerificationJournal verifierChaine(List<Evenement> evenements) {
    if (evenements.isEmpty) {
      return const VerificationJournal(intact: true, nombreEvenements: 0);
    }

    String? precedente;
    var attendue = 1;

    for (final evenement in evenements) {
      if (evenement.sequence != attendue) {
        return VerificationJournal(
          intact: false,
          nombreEvenements: evenements.length,
          premierFautif: evenement.id,
          motif: 'Séquence $attendue attendue, ${evenement.sequence} trouvée : '
              'des événements manquent.',
        );
      }

      if (evenement.empreintePrecedente != precedente) {
        return VerificationJournal(
          intact: false,
          nombreEvenements: evenements.length,
          premierFautif: evenement.id,
          motif: 'La chaîne est rompue : cet événement ne suit pas le '
              'précédent.',
        );
      }

      final recalculee = empreinteDe(evenement);
      if (recalculee != evenement.empreinte) {
        return VerificationJournal(
          intact: false,
          nombreEvenements: evenements.length,
          premierFautif: evenement.id,
          motif: 'Le contenu de cet événement a été modifié après écriture.',
        );
      }

      precedente = evenement.empreinte;
      attendue++;
    }

    return VerificationJournal(
      intact: true,
      nombreEvenements: evenements.length,
    );
  }

  static Evenement _versEvenement(LigneEvenement ligne) => Evenement(
        id: ligne.id,
        appareil: ligne.appareil,
        sequence: ligne.sequence,
        horodatage: ligne.horodatage,
        type: TypeEvenement.parCle(ligne.type),
        charge: Evenement.chargeDepuisJson(ligne.charge),
        empreinte: ligne.empreinte,
        empreintePrecedente: ligne.empreintePrecedente,
      );
}
