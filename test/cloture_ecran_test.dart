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
    rapports = Rapports(
      base,
      journal,
      fiche: const FicheEntreprise(nomCommercial: 'Chez Awa'),
    );
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
          ),
        ],
        paiements: [
          PaiementAEnregistrer(
            mode: mode ?? ModePaiement.especes,
            montant: f(prix),
          ),
        ],
      );

  Future<void> ouvrir(WidgetTester tester, {bool avecCloture = true}) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: themeClair(),
        home: Scaffold(
          body: EcranRapport(
            depot: depot,
            documents: Documents(base, nomCommerce: 'Chez Awa'),
            analyses: Analyses(base),
            rapports: avecCloture ? rapports : null,
          ),
        ),
      ),
    );
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

      // Le comptage s'intercale, et on peut le passer.
      await tester.tap(find.text('Je ne compte pas'));
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

  group('Le comptage de la caisse', () {
    /// Va jusqu'au champ de saisie du comptage.
    Future<void> jusquAuComptage(WidgetTester tester) async {
      await tester.tap(find.text('Clôturer la journée'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clôturer'));
      await tester.pumpAndSettle();
    }

    testWidgets("il ne montre jamais l'attendu avant la saisie", (
      tester,
    ) async {
      // C'est toute la valeur du geste. Un comptage dont on connaît déjà le
      // résultat ne mesure rien : il suffit de recopier le nombre affiché.
      await vendre(prix: 1500);
      await ouvrir(tester);
      await jusquAuComptage(tester);

      expect(find.text('Compte la caisse'), findsOneWidget);

      // Le contenu de la boîte, et rien d'autre : l'écran du rapport est
      // derrière, et lui affiche bien le total du jour. C'est une limite
      // que j'assume et que le manuel dit — compter le tiroir avant
      // d'ouvrir l'application, pas après.
      final texte = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texte, isNot(contains('1 500')));
      expect(texte, isNot(contains('avoir en caisse')));
      expect(texte, isNot(contains('encaissé')));
    });

    testWidgets("ce qui est compté donne l'écart, et il est enregistré", (
      tester,
    ) async {
      await vendre(prix: 1500);
      await ouvrir(tester);
      await jusquAuComptage(tester);

      await tester.enterText(find.byType(TextField), '1000');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(find.text('Il manque 500 F'), findsOneWidget);
      expect(find.text('Ce que tu as compté'), findsOneWidget);
      expect(find.text('Ce qui aurait dû y être'), findsOneWidget);

      final ecarts = await depot.ecartsParVendeur(
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(ecarts.single.manques, Montant.depuisDecimal(500));

      // Et le rapport doit le montrer sans qu'on ait à ressortir de l'écran.
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ce que la caisse a donné au comptage'),
        findsOneWidget,
        reason: "un écran qui oublie ce qu'il vient d'enregistrer est un "
            'écran auquel on cesse de croire',
      );
    });

    testWidgets('une caisse juste se dit autrement, et se note quand même', (
      tester,
    ) async {
      await vendre(prix: 1500);
      await ouvrir(tester);
      await jusquAuComptage(tester);

      await tester.enterText(find.byType(TextField), '1500');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(find.text('La caisse tombe juste'), findsOneWidget);

      final ecarts = await depot.ecartsParVendeur(
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(ecarts.single.comptages, 1);
      expect(ecarts.single.impeccable, isTrue);
    });

    testWidgets('passer le comptage ne bloque pas la clôture', (tester) async {
      await vendre(prix: 1500);
      await ouvrir(tester);
      await jusquAuComptage(tester);

      await tester.tap(find.text('Je ne compte pas'));
      await tester.pumpAndSettle();

      expect(find.text('Clôture n° 1'), findsOneWidget);
      final ecarts = await depot.ecartsParVendeur(
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(ecarts, isEmpty, reason: 'ne rien compter ne s\'invente pas');
    });

    testWidgets('le rapport montre qui accumule les manques', (tester) async {
      await depot.pointerLaCaisse(
        compte: Montant.depuisDecimal(99500),
        attendu: Montant.depuisDecimal(100000),
        operateur: 'Awa',
      );
      await ouvrir(tester);

      expect(
        find.text('Ce que la caisse a donné au comptage'),
        findsOneWidget,
      );
      expect(find.text('Awa'), findsWidgets);
      expect(find.text('− 500 F'), findsOneWidget);
      expect(
        find.textContaining("c'est la répétition qui parle"),
        findsOneWidget,
        reason: "nommer des gens à côté de sommes manquantes se lit comme "
            'une accusation si personne ne prévient du contraire',
      );
    });

    testWidgets("l'argent sorti du tiroir n'est pas compté comme un manque", (
      tester,
    ) async {
      // Le cas qui rendait le comptage nuisible : le commerçant paie son
      // fournisseur en liquide, et le soir l'application l'accuse d'un
      // manque de 1 000 F qui sont partis avec une facture.
      await vendre(prix: 1500);
      await depot.sortirDeCaisse(
        Montant.depuisDecimal(1000),
        motif: 'Sac de riz',
      );
      await ouvrir(tester);
      await jusquAuComptage(tester);

      await tester.enterText(find.byType(TextField), '500');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(find.text('La caisse tombe juste'), findsOneWidget);
    });

    testWidgets("sortir de l'argent se note depuis l'écran", (tester) async {
      await vendre(prix: 1500);
      await ouvrir(tester);

      await tester.tap(find.text('Sortir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.tap(find.text('Noter'));
      await tester.pumpAndSettle();

      final mouvements = await depot.mouvementsDeCaisse(
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(mouvements.single.montantCentimes, 100000);
      expect(mouvements.single.nature, NatureMouvementCaisse.retrait);
    });

    testWidgets('le résumé envoyé au patron porte le comptage', (
      tester,
    ) async {
      // Le patron absent ne lit que ce message. Un écart qui n'y figure pas
      // est un écart que personne ne voit, et le comptage n'aura servi à
      // rien.
      await vendre(prix: 1500);
      await depot.pointerLaCaisse(
        compte: Montant.depuisDecimal(1000),
        attendu: Montant.depuisDecimal(1500),
        operateur: 'Awa',
      );
      await ouvrir(tester);

      await tester.tap(find.text('Envoyer le résumé'));
      await tester.pumpAndSettle();

      final texte = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texte, contains('Caisse comptée'));
      expect(texte, contains('il manque 500 F'));
    });

    testWidgets("sans comptage, la section n'existe pas", (tester) async {
      await vendre();
      await ouvrir(tester);

      expect(find.text('Ce que la caisse a donné au comptage'), findsNothing);
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
