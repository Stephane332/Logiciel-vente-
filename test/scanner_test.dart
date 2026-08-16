/// Ce qu'on fait d'un code-barres lu.
///
/// Aucun test ne peut ouvrir un appareil photo. Ce qui se teste, et qui est
/// tout ce qui compte, c'est la décision prise **après** la lecture : article
/// connu ou pas, et ce que ça change au panier et au catalogue.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/interface/ecrans/vente.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Documents documents;

  const codeBarre = '3017620422003';

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    documents = Documents(base, nomCommerce: 'Chez Awa');
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  final cle = GlobalKey<EcranVenteState>();

  Widget caisse() => MaterialApp(
        theme: themeClair(),
        home: EcranVente(key: cle, depot: depot, documents: documents),
      );

  group('Retrouver un article par son code', () {
    test("le code lu est le code de l'article", () async {
      await depot.creerArticle(
          code: codeBarre, designation: 'Lait concentré', prix: f(750));

      final trouve = await depot.articleParCode(codeBarre);

      expect(trouve, isNotNull);
      expect(trouve!.designation, 'Lait concentré');
    });

    test("un code jamais vu ne rend rien", () async {
      expect(await depot.articleParCode('0000000000000'), isNull);
    });

    test('un article retiré du catalogue ne remonte plus', () async {
      await depot.creerArticle(
          code: codeBarre, designation: 'Lait concentré', prix: f(750));
      await depot.retirerArticle(codeBarre);

      // Retiré, pas supprimé : ses ventes passées restent au journal. Mais il
      // n'a plus à retomber au panier parce qu'on a rescanné le sachet.
      expect(await depot.articleParCode(codeBarre), isNull);
    });

    test('les espaces autour du code ne le rendent pas introuvable', () async {
      await depot.creerArticle(
          code: codeBarre, designation: 'Lait concentré', prix: f(750));

      expect(await depot.articleParCode('  $codeBarre  '), isNotNull);
    });

    test('un code vide ne cherche rien', () async {
      expect(await depot.articleParCode('   '), isNull);
    });
  });

  group('Scanner à la caisse', () {
    testWidgets('un article connu tombe au panier', (tester) async {
      await depot.creerArticle(
          code: codeBarre, designation: 'Lait concentré', prix: f(750));

      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await cle.currentState!.ajouterParCodeBarre(codeBarre);
      await tester.pumpAndSettle();

      expect(find.text('1 article'), findsOneWidget);
      expect(find.text('Encaisser'), findsOneWidget);
    });

    testWidgets('un article inconnu demande son prix, puis entre au catalogue',
        (tester) async {
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      final scan = cle.currentState!.ajouterParCodeBarre(codeBarre);
      await tester.pumpAndSettle();

      // Le pavé s'ouvre, et il dit pourquoi.
      expect(find.text('Prix de cet article'), findsOneWidget);
      expect(find.textContaining("pas encore au catalogue"), findsOneWidget);

      for (final touche in ['7', '5', '0']) {
        await tester.tap(find.widgetWithText(InkWell, touche));
        await tester.pump();
      }
      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      await scan;
      await tester.pumpAndSettle();

      // Il est au panier, et il est au catalogue sous son code-barres — le
      // commerçant n'a jamais saisi d'inventaire.
      expect(find.text('1 article'), findsOneWidget);

      final cree = await depot.articleParCode(codeBarre);
      expect(cree, isNotNull);
      expect(cree!.prixCentimes, f(750).centimes);
    });

    testWidgets("renoncer au prix n'ajoute rien du tout", (tester) async {
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      final scan = cle.currentState!.ajouterParCodeBarre(codeBarre);
      await tester.pumpAndSettle();

      // On referme le pavé sans rien saisir.
      Navigator.of(tester.element(find.text('Prix de cet article'))).pop();
      await tester.pumpAndSettle();
      await scan;
      await tester.pumpAndSettle();

      expect(find.text('Choisir un article'), findsOneWidget);
      expect(await depot.articleParCode(codeBarre), isNull);
    });

    testWidgets('scanner deux fois le même sachet en met deux au panier',
        (tester) async {
      await depot.creerArticle(
          code: codeBarre, designation: 'Lait concentré', prix: f(750));

      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await cle.currentState!.ajouterParCodeBarre(codeBarre);
      await tester.pumpAndSettle();
      await cle.currentState!.ajouterParCodeBarre(codeBarre);
      await tester.pumpAndSettle();

      expect(find.text('2 articles'), findsOneWidget);
    });
  });

  group("Ce que le scanner laisse au journal", () {
    test("un article créé par scan se rejoue depuis le journal", () async {
      await depot.creerArticle(
          code: codeBarre, designation: 'Article à 750 F', prix: f(750));

      await depot.reconstruireProjections();

      final rejoue = await depot.articleParCode(codeBarre);
      expect(rejoue, isNotNull);
      expect(rejoue!.prixCentimes, f(750).centimes);
    });
  });
}
