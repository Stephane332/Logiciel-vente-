/// Faire une facture depuis la caisse.
///
/// Le bouton vit dans la feuille du reçu, et c'est délibéré : le client
/// réclame sa facture au comptoir, juste après avoir payé. Un écran séparé
/// obligerait à retrouver la vente, et personne ne le ferait.
///
/// La règle qui compte autant que le reste : **une boutique sans fiche
/// entreprise ne voit jamais ce bouton**. Sans IFU ni adresse, la facture qui
/// sortirait ne porterait aucune des mentions qu'un client professionnel vient
/// chercher — elle ne servirait qu'à décevoir.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/fiche_entreprise.dart';
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

  final entreprise = FicheEntreprise(
    nomCommercial: 'Quincaillerie du Faso',
    ifu: '00012345A',
    adresse: 'Gounghin, Ouagadougou',
    cadastre: ReferenceCadastrale.analyser('12345678901'),
    telephone: '70 00 00 00',
    regime: RegimeImposition.rni,
    serviceImpots: 'DME Ouaga 1',
  );

  Widget caisse({FicheEntreprise? fiche}) => MaterialApp(
        theme: themeClair(),
        home: EcranVente(
          depot: depot,
          documents: Documents(
            base,
            nomCommerce: fiche?.nomCommercial ?? 'Chez Awa',
            fiche: fiche,
          ),
        ),
      );

  /// Encaisse 10 000 F au montant libre, puis ouvre le reçu.
  Future<void> vendreEtOuvrirLeRecu(WidgetTester tester) async {
    await tester.tap(find.text('Montant\nlibre'));
    await tester.pumpAndSettle();
    for (final touche in ['1', '0', '0', '0', '0']) {
      await tester.tap(find.widgetWithText(InkWell, touche));
      await tester.pump();
    }
    await tester.tap(find.text('Encaisser').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Espèces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider la vente'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reçu'));
    await tester.pumpAndSettle();
  }

  group('Qui voit le bouton', () {
    testWidgets('une boutique sans fiche ne le voit pas', (tester) async {
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();
      await vendreEtOuvrirLeRecu(tester);

      expect(find.text('Faire une facture'), findsNothing);
    });

    testWidgets('une entreprise le voit', (tester) async {
      await tester.pumpWidget(caisse(fiche: entreprise));
      await tester.pumpAndSettle();
      await vendreEtOuvrirLeRecu(tester);

      expect(find.text('Faire une facture'), findsOneWidget);
    });
  });

  group('La facture se fait', () {
    Future<void> facturer(WidgetTester tester) async {
      await tester.tap(find.text('Faire une facture'));
      await tester.pumpAndSettle();
    }

    testWidgets('elle demande à qui, et une personne morale doit être nommée',
        (tester) async {
      await tester.pumpWidget(caisse(fiche: entreprise));
      await tester.pumpAndSettle();
      await vendreEtOuvrirLeRecu(tester);
      await facturer(tester);

      expect(find.text('À qui ?'), findsOneWidget);

      // Valider sans rien remplir doit reprocher, pas produire une facture
      // anonyme : une facture sans destinataire ne vaut rien.
      await tester.tap(find.text('Faire la facture'));
      await tester.pumpAndSettle();

      expect(find.textContaining('doit être nommé'), findsOneWidget);
      expect(find.textContaining('FV-2026'), findsNothing);
    });

    testWidgets('un client comptant ne demande rien', (tester) async {
      await tester.pumpWidget(caisse(fiche: entreprise));
      await tester.pumpAndSettle();
      await vendreEtOuvrirLeRecu(tester);
      await facturer(tester);

      await tester.tap(find.text('Client comptant'));
      await tester.pumpAndSettle();

      // Ni champ nom, ni champ IFU : la note ne les exige pas pour ce type.
      expect(find.widgetWithText(TextField, 'Nom du client'), findsNothing);
      expect(find.widgetWithText(TextField, 'IFU du client'), findsNothing);

      await tester.tap(find.text('Faire la facture'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Facture FV-'), findsOneWidget);
    });

    testWidgets('la facture porte ses mentions et son numéro', (tester) async {
      await tester.pumpWidget(caisse(fiche: entreprise));
      await tester.pumpAndSettle();
      await vendreEtOuvrirLeRecu(tester);
      await facturer(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'Nom du client'), 'SONABEL');
      await tester.enterText(
          find.widgetWithText(TextField, 'IFU du client'), '00099887B');
      await tester.tap(find.text('Faire la facture'));
      await tester.pumpAndSettle();

      final texte = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');

      expect(texte, contains('IFU : 00012345A'));
      expect(texte, contains('SONABEL'));
      expect(texte, contains('IFU client : 00099887B'));
      expect(texte, contains('dix mille francs CFA'));
      // Et la phrase que je ne veux jamais voir disparaître.
      expect(texte, contains('FACTURE NON CERTIFIÉE'));
    });

    testWidgets('le numéro est enregistré, pas seulement affiché',
        (tester) async {
      await tester.pumpWidget(caisse(fiche: entreprise));
      await tester.pumpAndSettle();
      await vendreEtOuvrirLeRecu(tester);
      await facturer(tester);

      await tester.tap(find.text('Client comptant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Faire la facture'));
      await tester.pumpAndSettle();

      final vente = (await base.select(base.ventes).get()).single;
      expect(vente.numero, 1);
      expect(vente.anneeGestion, DateTime.now().year);
    });

    testWidgets('renoncer ne consomme pas de numéro', (tester) async {
      await tester.pumpWidget(caisse(fiche: entreprise));
      await tester.pumpAndSettle();
      await vendreEtOuvrirLeRecu(tester);
      await facturer(tester);

      // On referme la feuille sans valider. Un numéro consommé ici trouerait
      // la série pour toujours.
      Navigator.of(tester.element(find.text('À qui ?'))).pop();
      await tester.pumpAndSettle();

      expect((await base.select(base.ventes).get()).single.numero, isNull);
      expect(await depot.trousDeSerie(annee: DateTime.now().year), isEmpty);
    });
  });
}
