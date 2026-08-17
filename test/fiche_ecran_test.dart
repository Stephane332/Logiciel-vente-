/// La fiche entreprise vue depuis l'écran.
///
/// Le risque ici n'est pas technique, il est commercial : cette section est la
/// seule de l'application qui ressemble à un formulaire d'administration. Si
/// une vendeuse de rue tombe dessus en cherchant à changer le nom de sa
/// boutique, elle croit que l'application est faite pour les grandes
/// entreprises et elle la désinstalle.
///
/// Ces tests tiennent donc deux choses : elle reste fermée tant qu'elle est
/// vide, et ce qu'on y tape ne se perd pas en silence.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/domaine/mobile_money.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/interface/ecrans/reglages.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  late BaseLocale base;
  late Parametres parametres;
  late Depot depot;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    parametres = Parametres(base);
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
  });

  tearDown(() => base.close());

  Future<Widget> ecran() async => MaterialApp(
        theme: themeClair(),
        home: EcranReglages(
          parametres: parametres,
          reglage: await parametres.tout(),
          depot: depot,
        ),
      );

  /// Ouvre l'écran sur une surface assez haute pour que tout y tienne.
  ///
  /// Les réglages sont plus longs qu'un téléphone, et une `ListView` ne
  /// construit que ce qui approche du bord de l'écran. Sur une surface de
  /// téléphone, un test qui cherche un champ plus bas ne mesurerait donc que
  /// sa propre gymnastique de défilement.
  Future<void> ouvrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await ecran());
    await tester.pumpAndSettle();
  }

  Future<void> deplier(WidgetTester tester) async {
    await tester.tap(find.text('Ma fiche entreprise'));
    await tester.pumpAndSettle();
  }

  Future<void> enregistrer(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();
  }

  group('Elle reste discrète', () {
    testWidgets('fermée tant que rien n\'est rempli', (tester) async {
      await ouvrir(tester);

      // Le titre est là — on doit pouvoir la trouver — mais aucun champ
      // fiscal n'est déplié.
      expect(find.text('Ma fiche entreprise'), findsOneWidget);
      expect(find.text('IFU'), findsNothing);
      expect(find.text('Références cadastrales'), findsNothing);
    });

    testWidgets('ouverte quand elle porte déjà des mentions', (tester) async {
      await parametres.definirFiche(const FicheEntreprise(
        nomCommercial: 'Chez Awa',
        ifu: '00012345A',
      ));

      await ouvrir(tester);

      // Une entreprise qui a commencé à la remplir y revient : la laisser
      // fermée lui ferait croire que sa saisie a disparu.
      expect(find.text('IFU'), findsOneWidget);
    });

    testWidgets('elle dit à quoi elle sert, et à quoi elle ne sert pas',
        (tester) async {
      await ouvrir(tester);

      expect(find.textContaining('Inutile pour vendre au comptoir'),
          findsOneWidget);
    });

    testWidgets('elle tient sur la largeur d\'un téléphone', (tester) async {
      // Trouvé en la dépliant sur un écran étroit : « CME — Contribution des
      // micro-entreprises » débordait de trois cent cinquante pixels. Les
      // autres tests de ce fichier travaillent sur une surface large pour
      // éviter la gymnastique de défilement, et n'auraient jamais vu ça.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await ecran());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Ma fiche entreprise'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Ma fiche entreprise'));
      await tester.pumpAndSettle();

      // Un débordement de mise en page lève une exception que le test
      // capture : arriver ici sans erreur, c'est la preuve.
      expect(tester.takeException(), isNull);

      final champ = find.byType(DropdownButtonFormField<RegimeImposition?>);
      await tester.scrollUntilVisible(champ, 100,
          scrollable: find.byType(Scrollable).first);
      expect(tester.getSize(champ).width, lessThanOrEqualTo(400));
    });
  });

  group('Ce qu\'un lecteur d\'écran entend', () {
    testWidgets('le nom de la boutique porte un libellé', (tester) async {
      // Le champ arrive **rempli** — « Ma boutique » par défaut — donc son
      // texte de remplacement ne s'affiche jamais, et il n'avait aucun
      // libellé. À l'œil le titre de section suffisait ; pour quelqu'un qui
      // n'a que la voix, c'était une zone de saisie anonyme. Trouvé en lisant
      // l'arbre d'accessibilité de l'application pilotée.
      await ouvrir(tester);

      expect(find.widgetWithText(TextField, 'Nom de la boutique'),
          findsOneWidget);
    });
  });

  group('Ce qui est tapé est gardé', () {
    testWidgets('une fiche remplie se retrouve dans les réglages',
        (tester) async {
      await ouvrir(tester);

      await deplier(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'IFU'), '00012345A');
      await tester.enterText(
          find.widgetWithText(TextField, 'Adresse de vente'), 'Gounghin');
      await tester.enterText(
          find.widgetWithText(TextField, 'Références cadastrales'),
          '1234 567 8901');

      await enregistrer(tester);

      final fiche = (await parametres.tout()).fiche;
      expect(fiche.ifu, '00012345A');
      expect(fiche.adresse, 'Gounghin');
      expect(fiche.cadastre?.lisible, '1234 567 8901');
    });

    testWidgets('un IFU mal recopié est signalé, pas avalé', (tester) async {
      await ouvrir(tester);

      await deplier(tester);

      await tester.enterText(find.widgetWithText(TextField, 'IFU'), '123');
      await enregistrer(tester);

      // Le défaut s'affiche sous le champ, et l'écran ne se ferme pas : sans
      // ça, le commerçant croirait avoir enregistré son IFU jusqu'au jour où
      // sa facture partirait sans.
      expect(find.text("L'IFU est huit chiffres suivis d'une lettre."),
          findsOneWidget);
      expect(find.text('Ma fiche entreprise'), findsOneWidget);
      expect((await parametres.tout()).fiche.ifu, isNull);
    });

    testWidgets('le nom de la boutique survit à la fiche', (tester) async {
      // La fiche écrit désormais le nom du commerce. Si elle l'écrasait avec
      // du vide, chaque reçu repartirait sous « Ma boutique ».
      await parametres.definirNomCommerce('Chez Awa');

      await ouvrir(tester);

      await enregistrer(tester);

      expect((await parametres.tout()).nomCommerce, 'Chez Awa');
    });

    testWidgets('les numéros marchands ne sont pas emportés par la fiche',
        (tester) async {
      await parametres.definirNumeroMarchand(
          OperateurMobile.orange, '70000000');

      await ouvrir(tester);

      await enregistrer(tester);

      expect(
          (await parametres.tout()).comptes.numeroDe(OperateurMobile.orange),
          '70000000');
    });
  });

  group('Ce qui manque', () {
    testWidgets('la liste des manques se compte', (tester) async {
      await ouvrir(tester);

      await deplier(tester);

      expect(find.textContaining('Il manque 6 mentions'), findsOneWidget);
    });

    testWidgets("elle ne laisse pas croire qu'une fiche complète suffit",
        (tester) async {
      await parametres.definirFiche(FicheEntreprise(
        nomCommercial: 'Chez Awa',
        ifu: '00012345A',
        cadastre: ReferenceCadastrale.analyser('12345678901'),
        adresse: 'Gounghin',
        telephone: '70000000',
        regime: RegimeImposition.rni,
        serviceImpots: 'DME Ouaga 1',
      ));

      await ouvrir(tester);

      expect(find.text('Ta fiche est complète.'), findsOneWidget);

      // Et juste en dessous, ce que la fiche ne donne pas. C'est la phrase
      // que je ne veux surtout pas oublier : une fiche complète n'est pas
      // une facture certifiée.
      expect(find.textContaining('module de contrôle'), findsOneWidget);
    });
  });
}
