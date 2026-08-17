/// Arrêter la caisse, depuis l'écran du patron.
///
/// C'est le geste du soir. Le commerçant compte son argent et veut savoir ce
/// qu'il devrait trouver ; la DGI, elle, veut un Z-rapport. Le même bouton
/// sert les deux, et c'est ce qui le rend acceptable : personne n'appuie sur
/// un bouton qui ne sert qu'à l'administration.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/rapport_fiscal.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/rapports.dart';
import 'package:carnet/interface/ecrans/rapport.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  late BaseLocale base;
  late Journal journal;
  late Depot depot;
  late Rapports rapports;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    journal = Journal(base, appareil: 'CAISSE1');
    depot = Depot(base, journal);
    rapports = Rapports(base, journal,
        fiche: const FicheEntreprise(nomCommercial: 'Chez Awa'));
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Future<void> vendre({num prix = 1000, ModePaiement? mode}) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'RIZ',
            designation: 'Riz 1 kg',
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
              mode: mode ?? ModePaiement.especes, montant: f(prix))
        ],
      );

  Future<void> ouvrir(WidgetTester tester, {bool avecCloture = true}) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: themeClair(),
      home: Scaffold(
        body: EcranRapport(
          depot: depot,
          documents: Documents(base, nomCommerce: 'Chez Awa'),
          analyses: Analyses(base),
          rapports: avecCloture ? rapports : null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('La section est là où on la cherche', () {
    testWidgets("elle dit qu'on n'a jamais clôturé", (tester) async {
      await ouvrir(tester);

      expect(find.text('Arrêter la caisse'), findsOneWidget);
      expect(find.textContaining("jamais clôturé"), findsOneWidget);
    });

    testWidgets('elle rappelle la dernière clôture', (tester) async {
      await vendre();
      await rapports.z();
      await ouvrir(tester);

      expect(find.textContaining('Dernière clôture le'), findsOneWidget);
    });
  });

  group('Le point de caisse ne clôture pas', () {
    testWidgets('il montre le total sans arrêter la journée', (tester) async {
      await vendre(prix: 1500);
      await ouvrir(tester);

      await tester.tap(find.text('Point de caisse, sans clôturer'));
      await tester.pumpAndSettle();

      expect(find.text('Point de caisse'), findsOneWidget);
      // Aucune clôture Z : le prochain Z comptera toujours cette vente.
      expect(await rapports.derniereCloture(NatureRapport.z), isNull);
    });
  });

  group('La clôture demande confirmation', () {
    testWidgets('renoncer ne clôture rien', (tester) async {
      await vendre();
      await ouvrir(tester);

      await tester.tap(find.text('Clôturer la journée'));
      await tester.pumpAndSettle();
      expect(find.text('Clôturer la journée ?'), findsOneWidget);

      await tester.tap(find.text('Pas maintenant'));
      await tester.pumpAndSettle();

      // Une clôture ne se défait pas. Un Z tiré par erreur à midi couperait
      // la journée en deux, et rien ne la recollerait.
      expect(await rapports.derniereCloture(NatureRapport.z), isNull);
    });

    testWidgets('confirmer clôture et montre le rapport', (tester) async {
      await vendre(prix: 1500);
      await vendre(prix: 2000, mode: ModePaiement.mobileMoney);
      await ouvrir(tester);

      await tester.tap(find.text('Clôturer la journée'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clôturer'));
      await tester.pumpAndSettle();

      expect(find.text('Clôture n° 1'), findsOneWidget);

      final texte = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');

      // Le chiffre que le commerçant vient chercher : les espèces seules.
      expect(texte, contains('À avoir en caisse (espèces)'));
      expect(texte, contains('1 500 F'));

      expect(await rapports.derniereCloture(NatureRapport.z), isNotNull);
    });
  });

  group("L'état des articles", () {
    testWidgets('il liste ce qui est sorti', (tester) async {
      await vendre();
      await ouvrir(tester);

      await tester.tap(find.text('État des articles'));
      await tester.pumpAndSettle();

      expect(find.text('État des articles'), findsWidgets);
      final texte = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texte, contains('Riz 1 kg'));
    });
  });

  group('Sans arrêté de caisse', () {
    testWidgets('la section disparaît entièrement', (tester) async {
      await ouvrir(tester, avecCloture: false);

      // Le reste de l'écran ne doit pas dépendre de la clôture : le rapport
      // du soir est l'écran le plus consulté de l'application.
      expect(find.text('Arrêter la caisse'), findsNothing);
      expect(find.text('Envoyer le résumé'), findsOneWidget);
    });
  });
}
