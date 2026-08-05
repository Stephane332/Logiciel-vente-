/// Tests de l'écran de vente.
///
/// Vérifie le comportement que le commerçant constate réellement : le total
/// suit les articles ajoutés, et l'encaissement ne s'ouvre pas sur un panier
/// vide.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/interface/ecrans/vente.dart';
import 'package:carnet/interface/theme/theme.dart';

Widget _application() => MaterialApp(
      theme: themeClair(),
      home: const EcranVente(),
    );

void main() {
  testWidgets('le panier démarre vide', (tester) async {
    final semantique = tester.ensureSemantics();
    await tester.pumpWidget(_application());

    expect(find.bySemanticsLabel('0 F'), findsOneWidget);
    expect(find.text('Choisir un article'), findsOneWidget);
    expect(find.text('Encaisser'), findsNothing);
    semantique.dispose();
  });

  testWidgets('ajouter un article met le total à jour', (tester) async {
    await tester.pumpWidget(_application());

    await tester.tap(find.text('Riz 1 kg'));
    await tester.pumpAndSettle();

    // Le prix de la tuile est un texte simple, le total une étiquette
    // d'accessibilité : le montant animé est découpé caractère par caractère.
    expect(find.text('650 F'), findsOneWidget);
    expect(find.text('1 article'), findsOneWidget);
    expect(find.text('Encaisser'), findsOneWidget);
  });

  testWidgets('le total additionne plusieurs articles', (tester) async {
    await tester.pumpWidget(_application());

    await tester.tap(find.text('Riz 1 kg')); //   650
    await tester.pump();
    await tester.tap(find.text('Riz 1 kg')); //   650
    await tester.pump();
    await tester.tap(find.text('Huile 1 L')); // 1200
    await tester.pumpAndSettle();

    final semantique = tester.ensureSemantics();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 500 F'), findsOneWidget);
    semantique.dispose();
    expect(find.text('3 articles'), findsOneWidget);
  });

  testWidgets('vider le panier remet le total à zéro', (tester) async {
    await tester.pumpWidget(_application());

    await tester.tap(find.text('Riz 1 kg'));
    await tester.pumpAndSettle();
    expect(find.text('Encaisser'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    final semantique = tester.ensureSemantics();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 F'), findsOneWidget);
    semantique.dispose();
    expect(find.text('Choisir un article'), findsOneWidget);
  });

  testWidgets("la feuille d'encaissement propose les trois modes",
      (tester) async {
    await tester.pumpWidget(_application());

    await tester.tap(find.text('Riz 1 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encaisser'));
    await tester.pumpAndSettle();

    expect(find.text('Montant à encaisser'), findsOneWidget);
    expect(find.text('Espèces'), findsOneWidget);
    expect(find.text('Mobile money'), findsOneWidget);
    expect(find.text('Crédit'), findsOneWidget);
    expect(find.text('Choisir un mode'), findsOneWidget);
  });

  testWidgets('le mobile money affiche le code marchand pré-rempli',
      (tester) async {
    await tester.pumpWidget(_application());

    await tester.tap(find.text('Riz 1 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encaisser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile money'));
    // Pas de pumpAndSettle ici : le point d'attente pulse en boucle, et
    // l'animation ne se termine jamais.
    await tester.pump(const Duration(milliseconds: 600));

    // Le montant et le numéro marchand sont déjà dans le code : le client
    // n'a rien à saisir d'autre que son code secret.
    expect(find.text('*144*10*70123456*650#'), findsOneWidget);
    expect(find.text('En attente du SMS de confirmation'), findsOneWidget);
  });
}
