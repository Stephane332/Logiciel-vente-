/// Tests du catalogue : retirer un article, et lire un nom trop long.
///
/// Deux défauts de l'audit tombent ici. Un article créé par erreur restait à
/// vie — on pouvait corriger une faute de frappe, jamais l'effacer. Et deux
/// noms longs d'une même famille donnaient exactement la même tuile, si bien
/// que le commerçant vendait l'un pour l'autre sans s'en apercevoir.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/domaine/texte.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/interface/composants/tuile_produit.dart';
import 'package:carnet/interface/theme/theme.dart';

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

  Future<void> vendre(String code, String nom, num prix,
          {DateTime? quand}) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: code,
            designation: nom,
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(prix))
        ],
        horodatage: quand,
      );

  group('Retirer un article', () {
    test('il disparaît de la caisse', () async {
      final code = await depot.creerArticle(
          designation: 'Savon Omo', prix: f(500));
      await depot.creerArticle(designation: 'Sucre', prix: f(750));

      await depot.retirerArticle(code);

      final catalogue = await depot.catalogue();
      expect(catalogue.map((a) => a.designation), ['Sucre']);
      expect(await depot.nombreDArticles(), 1);
    });

    test('il ne ressort pas non plus par la recherche', () async {
      final code = await depot.creerArticle(
          designation: 'Savon Omo', prix: f(500));
      await depot.retirerArticle(code);

      expect(await depot.catalogue(recherche: 'omo'), isEmpty);
    });

    test('ses ventes passées restent comptées', () async {
      // C'est la promesse qui permet d'oser le geste : la journée ne bouge
      // pas quand on retire une faute de frappe.
      final code = await depot.creerArticle(
          designation: 'Savonn Omo', prix: f(500));
      await vendre(code, 'Savonn Omo', 500);
      final avant = await depot.rapportDuJour();

      await depot.retirerArticle(code);

      final apres = await depot.rapportDuJour();
      expect(apres.encaisse, avant.encaisse);
      expect(apres.nombreVentes, avant.nombreVentes);
    });

    test('on peut le remettre', () async {
      final code =
          await depot.creerArticle(designation: 'Savon Omo', prix: f(500));
      await depot.retirerArticle(code);
      await depot.retirerArticle(code, retire: false);

      expect((await depot.catalogue()).single.designation, 'Savon Omo');
    });

    test('il sort aussi du stock et des alertes', () async {
      final code = await depot.creerArticle(
          designation: 'Riz 25 kg', prix: f(18500), stock: const Quantite.unites(1));
      await depot.definirSuiviStock(code, SuiviStock.direct);
      await depot.ajusterStock(code, const Quantite.unites(0));

      expect(await depot.articlesEnStock(), isNotEmpty);

      await depot.retirerArticle(code);

      expect(await depot.articlesEnStock(), isEmpty);
      expect(await analyses.aReapprovisionner(), isEmpty);
      expect((await depot.rapportDuJour()).articlesEnRupture, 0);
    });

    test("il ne demande plus qu'on le nomme", () async {
      // Trois ventes au même montant libre déclenchent la proposition.
      for (var i = 0; i < Depot.seuilDeNommage; i++) {
        await depot.enregistrerVente(
          lignes: [
            LigneAEnregistrer(
              prixUnitaire: f(300),
              quantite: const Quantite.unites(1),
            )
          ],
          paiements: [
            PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(300))
          ],
        );
      }
      final propose = await depot.articlesANommer();
      expect(propose, hasLength(1));

      await depot.retirerArticle(propose.single.code);

      expect(await depot.articlesANommer(), isEmpty);
    });

    test('le retrait se rejoue depuis le journal', () async {
      final code =
          await depot.creerArticle(designation: 'Savon Omo', prix: f(500));
      await depot.retirerArticle(code);

      await depot.reconstruireProjections();

      expect(await depot.catalogue(), isEmpty);
    });

    test('la remise en place aussi', () async {
      final code =
          await depot.creerArticle(designation: 'Savon Omo', prix: f(500));
      await depot.retirerArticle(code);
      await depot.retirerArticle(code, retire: false);

      await depot.reconstruireProjections();

      expect((await depot.catalogue()).single.designation, 'Savon Omo');
    });
  });

  group('Un nom trop long', () {
    test('un nom court ne bouge pas', () {
      expect(nomAbrege('Riz 1 kg'), 'Riz 1 kg');
    });

    test('un nom long garde ses deux bouts', () {
      const long = 'Sac de riz parfumé importé 25 kg qualité supérieure';
      final court = nomAbrege(long);

      expect(court.length, lessThanOrEqualTo(30));
      expect(court, startsWith('Sac de riz'));
      // C'est la fin qui distingue, et c'est elle qu'on coupait.
      expect(court, endsWith('supérieure'));
    });

    test('deux variantes ne se confondent plus', () {
      const superieure = 'Sac de riz parfumé importé 25 kg qualité supérieure';
      const normale = 'Sac de riz parfumé importé 25 kg qualité normale';

      expect(nomAbrege(superieure), isNot(nomAbrege(normale)));
    });

    testWidgets('la tuile affiche le nom abrégé', (tester) async {
      const long = 'Sac de riz parfumé importé 25 kg qualité supérieure';

      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: TuileProduit(
                nom: long,
                prix: Montant.depuisDecimal(18500),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(nomAbrege(long)), findsOneWidget);
      expect(find.text(long), findsNothing);
    });
  });
}
