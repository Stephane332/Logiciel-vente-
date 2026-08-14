/// L'application est en français, y compris ce qu'elle ne écrit pas elle-même.
///
/// Flutter fournit ses propres libellés — la barre de sélection de texte, les
/// infobulles, le sélecteur de date, l'étiquette du voile qui ferme une
/// feuille. Sans les délégués de traduction, ils restent en anglais : un
/// commerçant qui appuie longuement dans le champ « Donne-lui un nom » lisait
/// « Paste ». Ces tests échouent si les délégués disparaissent.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/mobile_money.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/interface/ecrans/accueil.dart';
import 'package:carnet/main.dart';

void main() {
  late BaseLocale base;

  setUp(() => base = BaseLocale(NativeDatabase.memory()));
  tearDown(() => base.close());

  Widget application() => Application(
        depot: Depot(base, Journal(base, appareil: 'CAISSE1')),
        documents: Documents(base, nomCommerce: 'Boutique Test'),
        analyses: Analyses(base),
        parametres: Parametres(base),
        reglage: const Reglage(
          nomCommerce: 'Boutique Test',
          comptes: ComptesMarchands.aucun(),
        ),
      );

  BuildContext contexteDe(WidgetTester tester) =>
      tester.element(find.byType(Accueil));

  group('La langue de l’application', () {
    testWidgets('est le français, quelle que soit celle du téléphone',
        (tester) async {
      await tester.pumpWidget(application());
      await tester.pump();

      expect(Localizations.localeOf(contexteDe(tester)).languageCode, 'fr');
    });

    testWidgets('vaut aussi pour les libellés fournis par Flutter',
        (tester) async {
      await tester.pumpWidget(application());
      await tester.pump();

      final libelles = MaterialLocalizations.of(contexteDe(tester));

      // `Dismiss` est la valeur anglaise. La voir ici signifie que les
      // délégués ont sauté et que toute la mécanique de Flutter est repassée
      // en anglais — sans que rien d'autre ne le signale.
      expect(libelles.modalBarrierDismissLabel, isNot('Dismiss'));
      expect(libelles.cancelButtonLabel, 'Annuler');
      expect(libelles.pasteButtonLabel, 'Coller');
      expect(libelles.selectAllButtonLabel, isNot('Select all'));
    });

    testWidgets('les dates se lisent en français', (tester) async {
      await tester.pumpWidget(application());
      await tester.pump();

      final libelles = MaterialLocalizations.of(contexteDe(tester));
      final janvier = DateTime(2026, 1, 15);

      expect(libelles.formatMonthYear(janvier), contains('janvier'));
    });

    testWidgets('une seule langue est déclarée, et c’est le français',
        (tester) async {
      await tester.pumpWidget(application());
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, const Locale('fr'));
      expect(app.supportedLocales, const [Locale('fr')]);
    });
  });
}
