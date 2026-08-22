/// Plusieurs produits au même prix, vus depuis la caisse.
///
/// C'est la situation ordinaire d'une boutique, pas un cas limite : le savon,
/// le pain et le sachet d'eau se vendent tous à 500 F. Le montant seul ne dit
/// pas lequel, et l'application ne doit pas faire semblant de le savoir.
///
/// Le défaut que ces tests remplacent : une fois « Sachet d'eau » nommé à
/// 500 F, tout ce qui passait au montant libre à 500 F était enregistré comme
/// du sachet d'eau. Le stock d'eau baissait quand on vendait du pain, et le
/// rapport du soir disait qu'on avait vendu de l'eau. Rien ne le signalait.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/interface/ecrans/vente.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  late BaseLocale base;
  late Depot depot;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Widget caisse() => MaterialApp(
        theme: themeClair(),
        home: EcranVente(
          depot: depot,
          documents: Documents(base, nomCommerce: 'Chez Awa'),
        ),
      );

  /// Vend au montant libre, sans passer par l'écran.
  Future<void> vendreDirect(num prix) => depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(prix))
        ],
      );

  /// Trois ventes à 500 F, puis on nomme l'article.
  Future<void> nommerEauA500() async {
    for (var i = 0; i < 3; i++) {
      await vendreDirect(500);
    }
    await depot.nommerArticle('AUTO-50000', "Sachet d'eau");
  }

  /// Tape un montant au pavé et valide.
  Future<void> taper(WidgetTester tester, String montant) async {
    await tester.tap(find.text('Montant\nlibre'));
    await tester.pumpAndSettle();
    for (final touche in montant.split('')) {
      await tester.tap(find.widgetWithText(InkWell, touche));
      await tester.pump();
    }
    await tester.tap(find.text('Encaisser').last);
    await tester.pumpAndSettle();
  }

  group('Quand rien n\'est nommé à ce prix', () {
    testWidgets('la caisse ne demande rien du tout', (tester) async {
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await taper(tester, '500');

      // Le chemin d'origine ne bouge pas : première vente en quelques
      // secondes, sans question. C'est la règle à laquelle je ne touche pas.
      expect(find.textContaining("c'est lequel"), findsNothing);
      expect(find.text('Espèces'), findsOneWidget);
    });
  });

  group('Quand un produit est déjà nommé à ce prix', () {
    testWidgets('elle demande lequel', (tester) async {
      await nommerEauA500();
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await taper(tester, '500');

      expect(find.textContaining("c'est lequel"), findsOneWidget);
      expect(find.text("Sachet d'eau"), findsWidgets);
      expect(find.text('Autre chose'), findsOneWidget);
    });

    testWidgets('« Autre chose » n\'attribue rien au sachet d\'eau',
        (tester) async {
      await nommerEauA500();
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await taper(tester, '500');
      await tester.tap(find.text('Autre chose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      final eau = (await depot.catalogue())
          .firstWhere((a) => a.code == 'AUTO-50000');
      expect(eau.nombreVentes, 3, reason: 'le pain ne compte pas pour de l\'eau');

      final autre =
          (await depot.catalogue()).firstWhere((a) => a.code != 'AUTO-50000');
      expect(autre.nomme, isFalse);
      expect(autre.nombreVentes, 1);
    });

    testWidgets('choisir le sachet d\'eau l\'attribue bien à lui',
        (tester) async {
      await nommerEauA500();
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await taper(tester, '500');
      await tester.tap(find.text("Sachet d'eau").last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      final eau = (await depot.catalogue())
          .firstWhere((a) => a.code == 'AUTO-50000');
      expect(eau.nombreVentes, 4);
      expect(await depot.catalogue(), hasLength(1));
    });

    testWidgets('fermer la feuille annule la vente', (tester) async {
      await nommerEauA500();
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await taper(tester, '500');
      Navigator.of(tester.element(find.textContaining("c'est lequel"))).pop();
      await tester.pumpAndSettle();

      // Refermer sans choisir n'enregistre rien : « autre chose » et « je
      // renonce » sont deux réponses différentes.
      expect(find.text('Espèces'), findsNothing);
      expect(await base.select(base.ventes).get(), hasLength(3));
    });
  });
}
