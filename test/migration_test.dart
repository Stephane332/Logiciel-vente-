/// Ce qui se passe quand une base ancienne rencontre du code neuf.
///
/// Dix versions de schéma se sont succédé sans qu'aucun test ne vérifie
/// qu'une base d'hier s'ouvre aujourd'hui. Tant que la clé de signature n'est
/// pas posée, personne ne peut mettre à jour sans désinstaller, donc ça ne
/// s'est jamais vu. Le jour où elle sera posée, une migration fausse fera
/// perdre son carnet à un commerçant — c'est-à-dire ses dettes.
///
/// Ce fichier couvre le passage de la version 9 à la version 10, celui que je
/// viens d'écrire. **Les étapes antérieures ne sont pas couvertes** : je n'ai
/// pas gardé les schémas d'alors, et un test bâti sur un schéma reconstitué de
/// mémoire vérifierait une fiction. Je le dis plutôt que de laisser croire à
/// une couverture complète.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('carnet-migration');
    fichier = File('${dossier.path}/carnet.sqlite');
  });

  tearDown(() async {
    if (await dossier.exists()) await dossier.delete(recursive: true);
  });

  Montant f(num francs) => Montant.depuisDecimal(francs);

  /// Écrit une vente dans une base neuve, puis la referme.
  Future<void> poserDesDonnees() async {
    final base = BaseLocale(NativeDatabase(fichier));
    final depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    await depot.enregistrerVente(
      lignes: [
        LigneAEnregistrer(
          codeArticle: 'RIZ',
          designation: 'Riz 1 kg',
          prixUnitaire: f(650),
          quantite: const Quantite.unites(2),
        )
      ],
      paiements: [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(1300))
      ],
    );
    await base.close();
  }

  /// Remet la base dans l'état d'une version antérieure : on retire ce que la
  /// migration doit rajouter, et on recule le numéro de version.
  Future<void> reculerEnVersion9() async {
    final base = BaseLocale(NativeDatabase(fichier));
    await base.customStatement('DROP INDEX IF EXISTS idx_evenements_type');
    await base.customStatement('PRAGMA user_version = 9');
    await base.close();
  }

  test('la version du schéma est bien celle du code', () async {
    await poserDesDonnees();

    final base = BaseLocale(NativeDatabase(fichier));
    final ligne = await base.customSelect('PRAGMA user_version').getSingle();
    await base.close();

    expect(ligne.data.values.first, 10);
  });

  group('De la version 9 à la version 10', () {
    test("la base s'ouvre et la migration passe", () async {
      await poserDesDonnees();
      await reculerEnVersion9();

      final base = BaseLocale(NativeDatabase(fichier));
      final version =
          (await base.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first;
      await base.close();

      expect(version, 10, reason: 'la migration doit avoir tourné');
    });

    test("l'index que la migration ajoute existe après coup", () async {
      await poserDesDonnees();
      await reculerEnVersion9();

      final base = BaseLocale(NativeDatabase(fichier));
      final index = await base
          .customSelect("SELECT name FROM sqlite_master "
              "WHERE type = 'index' AND name = 'idx_evenements_type'")
          .get();
      await base.close();

      // Sans lui, la lecture par type retombe sur un parcours complet du
      // journal — exactement ce que la migration vient corriger.
      expect(index, hasLength(1));
    });

    test('rien ne se perd en chemin', () async {
      await poserDesDonnees();
      await reculerEnVersion9();

      final base = BaseLocale(NativeDatabase(fichier));
      final ventes = await base.select(base.ventes).get();
      final evenements = await base.select(base.evenements).get();
      final lignes = await base.select(base.lignesVente).get();
      await base.close();

      expect(ventes, hasLength(1));
      expect(ventes.single.totalCentimes, 130000);
      expect(evenements, hasLength(1));
      expect(lignes.single.designation, 'Riz 1 kg');
    });

    test('le journal reste vérifiable après la migration', () async {
      await poserDesDonnees();
      await reculerEnVersion9();

      final base = BaseLocale(NativeDatabase(fichier));
      final verification =
          await Journal(base, appareil: 'CAISSE1').verifier();
      await base.close();

      // Le chaînage d'empreintes est ce qui rend une altération détectable.
      // Une migration qui le casserait ferait passer une base saine pour
      // falsifiée, et le commerçant ne saurait plus quoi croire.
      expect(verification.intact, isTrue, reason: verification.motif ?? '');
      expect(verification.nombreEvenements, 1);
    });

    test('les projections se reconstruisent depuis le journal migré',
        () async {
      await poserDesDonnees();
      await reculerEnVersion9();

      final base = BaseLocale(NativeDatabase(fichier));
      final depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
      await depot.reconstruireProjections();
      final ventes = await base.select(base.ventes).get();
      await base.close();

      expect(ventes, hasLength(1));
      expect(ventes.single.totalCentimes, 130000);
    });
  });
}
