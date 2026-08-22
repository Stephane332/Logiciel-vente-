/// Tests de l'annulation d'une vente.
///
/// Dans un cahier, on rature. C'est le geste qui manquait le plus : sans lui,
/// une erreur de saisie fausse la journée pour toujours, et le commerçant
/// referme l'application en concluant que son cahier était mieux.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/evenements.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  late BaseLocale base;
  late Depot depot;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);
  Quantite q(num unites) => Quantite.depuisDecimal(unites);

  Future<String> vendre({
    num prix = 650,
    num quantite = 1,
    String? clientId,
    ModePaiement mode = ModePaiement.especes,
  }) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'RIZ',
            designation: 'Riz 1 kg',
            prixUnitaire: f(prix),
            quantite: q(quantite),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
            mode: mode,
            montant: f(prix).multiplieParQuantite(q(quantite)),
          )
        ],
        clientId: clientId,
      );

  Future<LigneArticle> riz() async =>
      (await depot.catalogue()).firstWhere((a) => a.code == 'RIZ');

  group('Annuler une vente', () {
    test("la vente sort du rapport du jour", () async {
      await vendre(prix: 650);
      final erreur = await vendre(prix: 65000);

      expect((await depot.rapportDuJour()).encaisse, f(65650));

      await depot.annulerVente(erreur);

      final rapport = await depot.rapportDuJour();
      expect(rapport.encaisse, f(650));
      expect(rapport.nombreVentes, 1);
    });

    test('le stock revient sur les étagères', () async {
      await vendre();
      await depot.ajusterStock('RIZ', q(40));

      final erreur = await vendre(quantite: 5);
      expect((await riz()).stockMilliemes, q(35).milliemes);

      await depot.annulerVente(erreur);
      expect((await riz()).stockMilliemes, q(40).milliemes);
    });

    test('le compteur de ventes recule', () async {
      await vendre();
      final erreur = await vendre();
      expect((await riz()).nombreVentes, 2);

      await depot.annulerVente(erreur);
      expect((await riz()).nombreVentes, 1);
    });

    test('une dette annulée disparaît du cahier', () async {
      final salif = await depot.creerClient(nom: 'Salif');
      await vendre(prix: 2000, clientId: salif, mode: ModePaiement.credit);
      final erreur =
          await vendre(prix: 50000, clientId: salif, mode: ModePaiement.credit);

      expect((await depot.clientsDebiteurs()).single.encoursCentimes,
          f(52000).centimes);

      await depot.annulerVente(erreur);

      // Réclamer de l'argent qu'on ne doit pas, c'est perdre le client.
      expect((await depot.clientsDebiteurs()).single.encoursCentimes,
          f(2000).centimes);
    });

    test("une vente annulée ne compte plus dans ce qui rapporte", () async {
      final analyses = Analyses(base);
      await vendre(prix: 650);
      final erreur = await vendre(prix: 99000);

      await depot.annulerVente(erreur);

      final meilleures = await analyses.meilleuresVentes();
      expect(meilleures.single.chiffre, f(650));
    });

    test('annuler deux fois ne rend pas le stock deux fois', () async {
      await vendre();
      await depot.ajusterStock('RIZ', q(40));
      final erreur = await vendre(quantite: 5);

      await depot.annulerVente(erreur);
      await depot.annulerVente(erreur);

      expect((await riz()).stockMilliemes, q(40).milliemes);
    });

    test('annuler une vente inconnue ne casse rien', () async {
      await vendre();
      await depot.annulerVente('vente-qui-nexiste-pas');
      expect((await depot.rapportDuJour()).nombreVentes, 1);
    });

    test('le motif est conservé au journal', () async {
      final erreur = await vendre();
      await depot.annulerVente(erreur, motif: 'Doigt sur le zéro');

      final evenements = await depot.journal.tous();
      final annulation = evenements
          .firstWhere((e) => e.type == TypeEvenement.venteAnnulee);
      expect(annulation.charge['motif'], 'Doigt sur le zéro');
    });
  });

  group('Le journal reste la vérité', () {
    test("rejouer reconstruit l'état d'après annulation", () async {
      final salif = await depot.creerClient(nom: 'Salif');
      await vendre();
      await depot.ajusterStock('RIZ', q(40));
      final erreur =
          await vendre(quantite: 5, clientId: salif, mode: ModePaiement.credit);
      await depot.annulerVente(erreur);

      final stockAvant = (await riz()).stockMilliemes;
      final ventesAvant = (await riz()).nombreVentes;
      final encoursAvant = (await depot.clientsDebiteurs()).length;

      await depot.reconstruireProjections();

      expect((await riz()).stockMilliemes, stockAvant);
      expect((await riz()).nombreVentes, ventesAvant);
      expect((await depot.clientsDebiteurs()).length, encoursAvant);
    });

    test('la vente annulée reste dans le journal', () async {
      final erreur = await vendre();
      await depot.annulerVente(erreur);

      // Le passé ne se réécrit pas : c'est ce qu'impose la DGI, et c'est ce
      // qui permet de prouver qu'on n'a rien effacé.
      final evenements = await depot.journal.tous();
      expect(
        evenements.where((e) => e.type == TypeEvenement.venteEnregistree).length,
        1,
      );
      expect((await depot.journal.verifier()).intact, isTrue);
    });
  });

  group('Les dernières ventes', () {
    test('les plus récentes en tête, annulées comprises', () async {
      final a = await vendre(prix: 100);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = await vendre(prix: 200);
      await depot.annulerVente(b);

      final dernieres = await depot.dernieresVentes();
      expect(dernieres.first.id, b);
      expect(dernieres.first.annulee, isTrue);
      expect(dernieres.last.id, a);
    });
  });

  group('Montant inhabituel', () {
    test("une boutique neuve n'est jugée que sur le plancher", () async {
      expect(await depot.montantInhabituel(f(50000)), isFalse);
      expect(await depot.montantInhabituel(f(200000)), isTrue);
    });

    test('un commerce connu est jugé sur ses propres ventes', () async {
      // Dix ventes autour de 1 000 F : la boutique est modeste.
      for (var i = 0; i < 10; i++) {
        await vendre(prix: 1000);
      }

      // Le plancher protège encore : on ne descend jamais en dessous.
      expect(await depot.seuilDeVigilance(), Depot.plancherDeVigilance);
      expect(await depot.montantInhabituel(f(90000)), isFalse);
    });

    test('un grossiste ne se fait pas déranger pour ses ventes normales',
        () async {
      for (var i = 0; i < 6; i++) {
        await vendre(prix: 400000);
      }

      // Dix fois sa plus grosse vente : quatre millions.
      expect(await depot.seuilDeVigilance(), f(4000000));
      expect(await depot.montantInhabituel(f(500000)), isFalse);
      expect(await depot.montantInhabituel(f(9000000)), isTrue);
    });

    test('le doigt resté sur le zéro est rattrapé', () async {
      for (var i = 0; i < 10; i++) {
        await vendre(prix: 2000);
      }

      // 2 000 devient 2 000 000 : deux zéros de trop.
      expect(await depot.montantInhabituel(f(2000)), isFalse);
      expect(await depot.montantInhabituel(f(2000000)), isTrue);
    });

    test('les ventes annulées ne servent pas de référence', () async {
      for (var i = 0; i < 6; i++) {
        await vendre(prix: 1000);
      }
      final enorme = await vendre(prix: 5000000);

      // Sans annulation, l'erreur relèverait le seuil et couvrirait les
      // suivantes.
      expect(await depot.montantInhabituel(f(9000000)), isFalse);

      await depot.annulerVente(enorme);
      expect(await depot.montantInhabituel(f(9000000)), isTrue);
    });
  });
}
