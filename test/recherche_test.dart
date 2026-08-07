/// Tests de la recherche au catalogue.
///
/// La grille de la caisse ne montre que les articles les plus vendus. Tant
/// que la boutique en compte une douzaine, c'est parfait. Passé ce nombre,
/// un article existe en base mais n'apparaît plus nulle part — et le
/// commerçant croit l'avoir perdu, ou pire, le ressaisit en double.
///
/// La recherche lève ce plafond. C'est le seul endroit de l'application où
/// l'on tape des lettres, donc elle ne doit apparaître que lorsqu'elle sert
/// vraiment.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/interface/composants/tuile_produit.dart';
import 'package:carnet/interface/ecrans/vente.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Documents documents;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    documents = Documents(base, nomCommerce: 'Alimentation Nabonswendé');
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  /// Remplit la boutique de [combien] articles numérotés.
  Future<void> remplir(int combien) async {
    for (var i = 1; i <= combien; i++) {
      await depot.creerArticle(designation: 'Article $i', prix: f(100 * i));
    }
  }

  group('Chercher dans la base', () {
    test('un article au-delà du plafond reste trouvable', () async {
      await remplir(70);
      await depot.creerArticle(designation: 'Savon Omo', prix: f(500));

      // Il n'est nulle part dans la grille : elle s'arrête à soixante.
      final grille = await depot.catalogue();
      expect(grille, hasLength(60));
      expect(grille.any((a) => a.designation == 'Savon Omo'), isFalse);

      // Il ressort dès qu'on le cherche.
      final trouve = await depot.catalogue(recherche: 'omo');
      expect(trouve.single.designation, 'Savon Omo');
    });

    test('la casse ne compte pas', () async {
      await depot.creerArticle(designation: 'Sucre en morceaux', prix: f(750));

      expect((await depot.catalogue(recherche: 'SUCRE')), hasLength(1));
      expect((await depot.catalogue(recherche: 'sucre')), hasLength(1));
    });

    test('un morceau de mot au milieu suffit', () async {
      await depot.creerArticle(designation: 'Huile de palme', prix: f(1200));

      expect((await depot.catalogue(recherche: 'palme')).single.designation,
          'Huile de palme');
    });

    test('les espaces autour du mot cherché ne gênent pas', () async {
      await depot.creerArticle(designation: 'Riz parfumé', prix: f(650));

      expect(await depot.catalogue(recherche: '  riz  '), hasLength(1));
    });

    test('une recherche vide rend la grille ordinaire', () async {
      await remplir(70);

      expect(await depot.catalogue(recherche: ''), hasLength(60));
      expect(await depot.catalogue(recherche: '   '), hasLength(60));
    });

    test('un mot qui ne correspond à rien ne rend rien', () async {
      await remplir(5);

      expect(await depot.catalogue(recherche: 'tracteur'), isEmpty);
    });

    test('le compte des articles ignore le plafond de la grille', () async {
      await remplir(70);

      expect(await depot.nombreDArticles(), 70);
      expect(await depot.catalogue(), hasLength(60));
    });
  });

  group('La barre de recherche à la caisse', () {
    /// La tuile d'un article, et pas le texte tapé dans la barre de
    /// recherche : les deux portent le même mot à l'écran.
    Finder tuile(String nom) => find.descendant(
          of: find.byType(TuileProduit),
          matching: find.text(nom),
        );

    Future<void> ouvrirCaisse(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: EcranVente(depot: depot, documents: documents),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('une petite boutique ne voit aucune barre', (tester) async {
      // Chercher dans six articles reviendrait à ouvrir un clavier pour
      // trouver ce qui est déjà sous les yeux.
      await remplir(6);
      await ouvrirCaisse(tester);

      expect(find.widgetWithText(TextField, 'Chercher un article'),
          findsNothing);
    });

    testWidgets('elle apparaît quand la grille cesse de suffire',
        (tester) async {
      await remplir(EcranVenteState.seuilDeRecherche + 1);
      await ouvrirCaisse(tester);

      expect(find.widgetWithText(TextField, 'Chercher un article'),
          findsOneWidget);
    });

    testWidgets('taper filtre la grille', (tester) async {
      await remplir(20);
      await depot.creerArticle(designation: 'Savon Omo', prix: f(500));
      await ouvrirCaisse(tester);

      await tester.enterText(find.byType(TextField), 'omo');
      await tester.pumpAndSettle();

      expect(find.text('Savon Omo'), findsOneWidget);
      expect(find.text('Article 1'), findsNothing);
      // Le montant libre et le scanner ne sont pas des résultats de
      // recherche : ils s'effacent le temps qu'on cherche.
      expect(find.byType(TuileAction), findsNothing);
    });

    testWidgets('une recherche infructueuse le dit au lieu de vider l\'écran',
        (tester) async {
      await remplir(20);
      await ouvrirCaisse(tester);

      await tester.enterText(find.byType(TextField), 'tracteur');
      await tester.pumpAndSettle();

      // Un écran vide sans explication laisse croire que la boutique a perdu
      // ses articles.
      expect(find.textContaining('tracteur'), findsWidgets);
      expect(find.byType(TuileProduit), findsNothing);
    });

    testWidgets('la croix rend toute la boutique', (tester) async {
      await remplir(20);
      await ouvrirCaisse(tester);

      // « Article 7 » ne désigne que lui : « Article 17 » ne le contient pas.
      await tester.enterText(find.byType(TextField), 'Article 7');
      await tester.pumpAndSettle();
      expect(find.byType(TuileProduit), findsOneWidget);
      expect(find.text('Article 1'), findsNothing);

      await tester.tap(find.byTooltip('Effacer'));
      await tester.pumpAndSettle();

      expect(find.text('Article 1'), findsOneWidget);
      expect(find.byType(TuileAction), findsNWidgets(2));
    });

    testWidgets('la recherche se vide après une vente', (tester) async {
      // Le client suivant ne demande pas la même chose : une grille restée
      // filtrée lui donnerait l'impression d'une boutique vide.
      await remplir(20);
      await ouvrirCaisse(tester);

      await tester.enterText(find.byType(TextField), 'Article 7');
      await tester.pumpAndSettle();
      await tester.tap(tuile('Article 7'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      expect(find.text('Article 1'), findsOneWidget);
      expect(find.byType(TuileAction), findsNWidgets(2));
    });
  });
}
