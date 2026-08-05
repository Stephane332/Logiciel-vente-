/// Tests des analyses de vente.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Analyses analyses;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    analyses = Analyses(base);
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Future<void> vendre(
    String code,
    String nom,
    num prix, {
    num quantite = 1,
    DateTime? quand,
    String? clientId,
    ModePaiement mode = ModePaiement.especes,
  }) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: code,
            designation: nom,
            prixUnitaire: f(prix),
            quantite: Quantite.depuisDecimal(quantite),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
            mode: mode,
            montant: f(prix).multiplieParQuantite(Quantite.depuisDecimal(quantite)),
          )
        ],
        clientId: clientId,
        horodatage: quand,
      );

  final maintenant = DateTime(2026, 8, 5, 12);
  DateTime ilYA(int jours) => maintenant.subtract(Duration(days: jours));

  group('Meilleures ventes', () {
    test('classe par chiffre, pas par quantité', () async {
      // Dix sachets d'eau rapportent moins qu'un sac de riz : c'est le riz
      // qui décide du réapprovisionnement.
      await vendre('EAU', 'Sachet d\'eau', 100, quantite: 10, quand: ilYA(1));
      await vendre('RIZ', 'Sac de riz', 20000, quand: ilYA(1));

      final top = await analyses.meilleuresVentes(
          debut: ilYA(7), fin: maintenant);

      expect(top.first.code, 'RIZ');
      expect(top.first.chiffre, f(20000));
      expect(top.last.code, 'EAU');
      expect(top.last.quantiteVendue, const Quantite.unites(10));
    });

    test('agrège plusieurs ventes du même article', () async {
      await vendre('RIZ', 'Riz', 650, quand: ilYA(3));
      await vendre('RIZ', 'Riz', 650, quantite: 2, quand: ilYA(2));

      final top = await analyses.meilleuresVentes(
          debut: ilYA(7), fin: maintenant);

      expect(top, hasLength(1));
      expect(top.single.chiffre, f(1950));
      expect(top.single.nombreVentes, 2);
      expect(top.single.quantiteVendue, const Quantite.unites(3));
    });

    test('ignore ce qui est hors de la période', () async {
      await vendre('RIZ', 'Riz', 650, quand: ilYA(30));
      await vendre('SAVON', 'Savon', 300, quand: ilYA(2));

      final top = await analyses.meilleuresVentes(
          debut: ilYA(7), fin: maintenant);

      expect(top.map((p) => p.code), ['SAVON']);
    });

    test('respecte la limite demandée', () async {
      for (var i = 0; i < 5; i++) {
        await vendre('ART$i', 'Article $i', 1000 * (i + 1), quand: ilYA(1));
      }

      final top = await analyses.meilleuresVentes(
          debut: ilYA(7), fin: maintenant, limite: 2);

      expect(top, hasLength(2));
      expect(top.first.code, 'ART4');
    });
  });

  group('Articles qui dorment', () {
    test('remonte un article vendu régulièrement puis abandonné', () async {
      for (var j = 40; j > 30; j--) {
        await vendre('PILES', 'Piles', 500, quand: ilYA(j));
      }
      await vendre('RIZ', 'Riz', 650, quand: ilYA(1));

      final endormis =
          await analyses.articlesQuiDorment(maintenant: maintenant);

      expect(endormis.map((a) => a.code), ['PILES']);
      expect(endormis.single.joursSansVente, greaterThanOrEqualTo(21));
    });

    test('ignore un article qui vient de se vendre', () async {
      for (var i = 0; i < 5; i++) {
        await vendre('RIZ', 'Riz', 650, quand: ilYA(i + 1));
      }

      expect(await analyses.articlesQuiDorment(maintenant: maintenant),
          isEmpty);
    });

    test("ignore un article vendu trop rarement pour conclure", () async {
      // Deux ventes il y a longtemps ne suffisent pas à parler d'abandon.
      await vendre('RARE', 'Article rare', 500, quand: ilYA(60));
      await vendre('RARE', 'Article rare', 500, quand: ilYA(59));

      expect(await analyses.articlesQuiDorment(maintenant: maintenant),
          isEmpty);
    });

    test("chiffre l'argent immobilisé quand le stock est connu", () async {
      for (var j = 40; j > 35; j--) {
        await vendre('PILES', 'Piles', 500, quand: ilYA(j));
      }
      await depot.ajusterStock('PILES', const Quantite.unites(12));

      final endormis =
          await analyses.articlesQuiDorment(maintenant: maintenant);

      expect(endormis.single.valeurImmobilisee, f(6000));
    });

    test("ne chiffre rien quand le stock n'est pas déclaré", () async {
      for (var j = 40; j > 35; j--) {
        await vendre('PILES', 'Piles', 500, quand: ilYA(j));
      }

      final endormis =
          await analyses.articlesQuiDorment(maintenant: maintenant);

      expect(endormis.single.valeurImmobilisee, isNull);
    });
  });

  group('Évolution entre deux périodes', () {
    test('met en tête ce qui baisse le plus', () async {
      // Semaine précédente : le riz marche fort.
      await vendre('RIZ', 'Riz', 10000, quand: ilYA(10));
      await vendre('SAVON', 'Savon', 1000, quand: ilYA(10));
      // Semaine en cours : le riz s'effondre, le savon progresse.
      await vendre('RIZ', 'Riz', 2000, quand: ilYA(2));
      await vendre('SAVON', 'Savon', 3000, quand: ilYA(2));

      final evolutions =
          await analyses.evolution(debut: ilYA(7), fin: maintenant);

      expect(evolutions.first.code, 'RIZ');
      expect(evolutions.first.enBaisse, isTrue);
      expect(evolutions.first.ecart, f(-8000));
      expect(evolutions.first.variation, closeTo(-80, 0.01));

      expect(evolutions.last.code, 'SAVON');
      expect(evolutions.last.enBaisse, isFalse);
    });

    test('ne calcule pas de pourcentage à partir de zéro', () async {
      await vendre('NOUVEAU', 'Nouveauté', 5000, quand: ilYA(2));

      final evolutions =
          await analyses.evolution(debut: ilYA(7), fin: maintenant);

      expect(evolutions.single.chiffrePrecedent.estNul, isTrue);
      expect(evolutions.single.variation, isNull);
    });

    test('remonte un article qui a totalement disparu', () async {
      await vendre('PILES', 'Piles', 4000, quand: ilYA(10));

      final evolutions =
          await analyses.evolution(debut: ilYA(7), fin: maintenant);

      expect(evolutions.single.code, 'PILES');
      expect(evolutions.single.chiffreActuel.estNul, isTrue);
      expect(evolutions.single.ecart, f(-4000));
    });
  });

  group('Habitudes client', () {
    test('dit ce que le client achète et depuis quand il manque', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');

      await vendre('RIZ', 'Riz', 650, quantite: 2,
          quand: ilYA(30), clientId: awa, mode: ModePaiement.credit);
      await vendre('RIZ', 'Riz', 650, quand: ilYA(25), clientId: awa);
      await vendre('SAVON', 'Savon', 300, quand: ilYA(25), clientId: awa);

      final habitudes = (await analyses.habitudesDe(awa))!;

      expect(habitudes.nom, 'Awa');
      expect(habitudes.articlesHabituels.first.code, 'RIZ');
      expect(habitudes.articlesHabituels.first.chiffre, f(1950));
      expect(habitudes.nombreVisites, 3);
      expect(habitudes.totalDepense, f(2250));
      expect(habitudes.dernierePresence, isNotNull);
    });

    test('ne compte pas les ventes des autres clients', () async {
      final awa = await depot.creerClient(nom: 'Awa');
      final ali = await depot.creerClient(nom: 'Ali');

      await vendre('RIZ', 'Riz', 650, quand: ilYA(2), clientId: awa);
      await vendre('RIZ', 'Riz', 650, quand: ilYA(2), clientId: ali);

      final habitudes = (await analyses.habitudesDe(awa))!;
      expect(habitudes.nombreVisites, 1);
    });

    test('un client inconnu ne renvoie rien', () async {
      expect(await analyses.habitudesDe('INEXISTANT'), isNull);
    });
  });
}
