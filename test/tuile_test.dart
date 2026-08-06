/// Tests de la tuile d'article.
///
/// La pastille de quantité porte le geste « retirer un ». Une pile rogne ses
/// enfants par défaut : si la pastille dépassait, elle sortirait amputée et le
/// commerçant taperait à côté.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/interface/composants/tuile_produit.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  Widget tuile({int quantite = 0, VoidCallback? onRetirer}) => MaterialApp(
        theme: themeClair(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: TuileProduit(
                nom: 'Riz 1 kg',
                prix: Montant.depuisDecimal(650),
                quantiteAuPanier: quantite,
                onPressed: () {},
                onRetirer: onRetirer,
              ),
            ),
          ),
        ),
      );

  testWidgets('la pastille tient entièrement dans la tuile', (tester) async {
    await tester.pumpWidget(tuile(quantite: 3, onRetirer: () {}));
    await tester.pumpAndSettle();

    final carte = tester.getRect(find.byType(TuileProduit));
    final pastille = tester.getRect(find.text('3'));

    expect(pastille.top, greaterThanOrEqualTo(carte.top));
    expect(pastille.right, lessThanOrEqualTo(carte.right));
  });

  testWidgets('la pastille offre une cible large', (tester) async {
    var retires = 0;
    await tester.pumpWidget(tuile(quantite: 3, onRetirer: () => retires++));
    await tester.pumpAndSettle();

    // Un doigt vise mal un rond de vingt-six pixels : la zone tactile doit
    // dépasser les quarante.
    final zone = tester.getRect(find.ancestor(
      of: find.text('3'),
      matching: find.byType(GestureDetector),
    ).first);
    expect(zone.height, greaterThanOrEqualTo(40));

    await tester.tap(find.text('3'));
    expect(retires, 1);
  });

  testWidgets('sans quantité, la pastille ne prend pas les appuis',
      (tester) async {
    // Elle reste dans l'arbre, réduite à rien pour pouvoir rebondir à
    // l'apparition — mais elle ne doit voler aucun appui au passage.
    var ajouts = 0;
    var retires = 0;
    await tester.pumpWidget(MaterialApp(
      theme: themeClair(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            height: 180,
            child: TuileProduit(
              nom: 'Riz 1 kg',
              prix: Montant.depuisDecimal(650),
              onPressed: () => ajouts++,
              onRetirer: () => retires++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final carte = tester.getRect(find.byType(TuileProduit));
    await tester.tapAt(Offset(carte.right - 14, carte.top + 14));
    await tester.pumpAndSettle();

    expect(ajouts, 1);
    expect(retires, 0);
  });

  testWidgets('le moins ne paraît que si le geste existe', (tester) async {
    await tester.pumpWidget(tuile(quantite: 2));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.remove_rounded), findsNothing);

    await tester.pumpWidget(tuile(quantite: 2, onRetirer: () {}));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
  });
}
