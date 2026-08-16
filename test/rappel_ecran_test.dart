/// Le rappel de sauvegarde, tel qu'il apparaît — ou pas — à l'écran.
///
/// Les règles sont testées à part, sans écran. Ici on vérifie qu'elles sont
/// bien branchées : un rappel juste qui ne s'affiche jamais ne sauve aucun
/// carnet, et un rappel qui s'affiche toujours devient un décor.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/mobile_money.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/rappel_sauvegarde.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/main.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Parametres parametres;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    parametres = Parametres(base);
  });

  tearDown(() => base.close());

  Future<void> vendre(int combien) async {
    for (var i = 0; i < combien; i++) {
      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'RIZ',
            designation: 'Riz 1 kg',
            prixUnitaire: Montant.depuisDecimal(650),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
            mode: ModePaiement.especes,
            montant: Montant.depuisDecimal(650),
          )
        ],
        horodatage: DateTime(2026, 8, 16, 8, i),
      );
    }
  }

  Widget application() => Application(
        depot: depot,
        documents: Documents(base, nomCommerce: 'Chez Awa'),
        analyses: Analyses(base),
        parametres: parametres,
        reglage: const Reglage(
          nomCommerce: 'Chez Awa',
          comptes: ComptesMarchands.aucun(),
        ),
      );

  Future<void> ouvrir(WidgetTester tester) async {
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();
  }

  final rappelVisible = find.textContaining('jamais sorti');

  group("Le bandeau de sauvegarde", () {
    testWidgets('ne paraît pas sur un carnet tout neuf', (tester) async {
      await ouvrir(tester);

      expect(rappelVisible, findsNothing);
    });

    testWidgets("ne paraît pas pour trois ventes", (tester) async {
      await vendre(3);
      await ouvrir(tester);

      expect(rappelVisible, findsNothing);
    });

    testWidgets("paraît quand le carnet n'est jamais sorti du téléphone",
        (tester) async {
      await vendre(RappelSauvegarde.avantLePremier);
      await ouvrir(tester);

      expect(rappelVisible, findsOneWidget);
      // Avec le geste qu'il demande : chercher soi-même entre deux clients,
      // personne ne le fait.
      expect(find.widgetWithText(TextButton, 'Sauvegarder'), findsOneWidget);
    });

    testWidgets('se tait après une sauvegarde envoyée', (tester) async {
      await vendre(RappelSauvegarde.avantLePremier);
      await parametres.noterSauvegarde(DateTime.now());
      await ouvrir(tester);

      expect(rappelVisible, findsNothing);
    });

    testWidgets("s'écarte d'un appui, et ne revient pas de la session",
        (tester) async {
      await vendre(RappelSauvegarde.avantLePremier);
      await ouvrir(tester);
      expect(rappelVisible, findsOneWidget);

      await tester.tap(find.byTooltip('Plus tard'));
      await tester.pumpAndSettle();

      expect(rappelVisible, findsNothing);
    });
  });
}
