/// Tests de l'écran de vente.
///
/// L'écran lit maintenant un vrai catalogue et écrit de vraies ventes : ces
/// tests vérifient le comportement de bout en bout, depuis le geste du
/// commerçant jusqu'à l'écriture dans le journal.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/domaine/mobile_money.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/interface/ecrans/accueil.dart';
import 'package:carnet/interface/ecrans/vente.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Documents documents;
  late Analyses analyses;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    documents = Documents(base, nomCommerce: 'Boutique Test');
    analyses = Analyses(base);
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Widget application() => MaterialApp(
        theme: themeClair(),
        home: EcranVente(depot: depot, documents: documents),
      );

  /// Garnit le catalogue comme le ferait l'usage : par des ventes.
  Future<void> garnirCatalogue() async {
    for (final (code, nom, prix) in const [
      ('RIZ', 'Riz 1 kg', 650),
      ('HUILE', 'Huile 1 L', 1200),
    ]) {
      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: code,
            designation: nom,
            prixUnitaire: Montant.depuisDecimal(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
            mode: ModePaiement.especes,
            montant: Montant.depuisDecimal(prix),
          )
        ],
      );
    }
  }

  testWidgets('une caisse neuve démarre sur un catalogue vide', (tester) async {
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    // Aucun article, mais le montant libre est là : le commerçant peut
    // encaisser dès la première seconde, sans rien configurer.
    expect(find.text('Montant\nlibre'), findsOneWidget);
    expect(find.text('Choisir un article'), findsOneWidget);

    // Et rien d'autre. Une tuile « Scanner » qui ne faisait rien occupait la
    // moitié de la zone d'action, dessinée comme celle qui fonctionne. Elle
    // reviendra quand le code-barres sera branché, pas avant.
    expect(find.text('Scanner'), findsNothing);
  });

  testWidgets('le catalogue affiche ce qui a déjà été vendu', (tester) async {
    await garnirCatalogue();
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    expect(find.text('Riz 1 kg'), findsOneWidget);
    expect(find.text('Huile 1 L'), findsOneWidget);
  });

  testWidgets('ajouter des articles met le total à jour', (tester) async {
    await garnirCatalogue();
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riz 1 kg'));
    await tester.pump();
    await tester.tap(find.text('Riz 1 kg'));
    await tester.pump();
    await tester.tap(find.text('Huile 1 L'));
    await tester.pumpAndSettle();

    final semantique = tester.ensureSemantics();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 500 F'), findsOneWidget);
    semantique.dispose();

    expect(find.text('3 articles'), findsOneWidget);
    expect(find.text('Encaisser'), findsOneWidget);
  });

  testWidgets('vider le panier remet le total à zéro', (tester) async {
    await garnirCatalogue();
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riz 1 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Choisir un article'), findsOneWidget);
  });

  testWidgets('encaisser écrit vraiment la vente', (tester) async {
    await garnirCatalogue();
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riz 1 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encaisser'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Espèces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider la vente'));
    await tester.pumpAndSettle();

    // Le riz a été vendu deux fois : une pour garnir, une par l'écran.
    final catalogue = await depot.catalogue();
    final riz = catalogue.firstWhere((a) => a.code == 'RIZ');
    expect(riz.nombreVentes, 2);

    // Et le panier est reparti à zéro.
    expect(find.text('Choisir un article'), findsOneWidget);
  });

  testWidgets('la vente survit à un redémarrage', (tester) async {
    await garnirCatalogue();
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Huile 1 L'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encaisser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Espèces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider la vente'));
    await tester.pumpAndSettle();

    // On rouvre l'écran comme après une fermeture de l'application.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    final rapport = await depot.rapportDuJour();
    expect(rapport.nombreVentes, 3);
    expect(rapport.encaisse, f(650 + 1200 + 1200));
  });

  testWidgets("le bandeau de nommage n'apparaît qu'après trois ventes",
      (tester) async {
    Future<void> vendreMontantLibre() => depot.enregistrerVente(
          lignes: [
            LigneAEnregistrer(
              prixUnitaire: f(500),
              quantite: const Quantite.unites(1),
            )
          ],
          paiements: [
            PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
          ],
        );

    await vendreMontantLibre();
    await vendreMontantLibre();

    await tester.pumpWidget(application());
    await tester.pumpAndSettle();
    expect(find.textContaining("C'est quoi ?"), findsNothing);

    await vendreMontantLibre();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    expect(find.textContaining("Tu vends souvent à 500 F"), findsOneWidget);
  });

  testWidgets("nommer un article le renomme dans le catalogue", (tester) async {
    for (var i = 0; i < 3; i++) {
      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(500),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
        ],
      );
    }

    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Tu vends souvent'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), "Sachet d'eau");
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text("Sachet d'eau"), findsOneWidget);
    expect(find.textContaining('Tu vends souvent'), findsNothing);
  });

  testWidgets("répondre « plusieurs choses » arrête la question", (tester) async {
    for (var i = 0; i < 3; i++) {
      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(500),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
        ],
      );
    }

    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Tu vends souvent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ce sont plusieurs choses différentes'));
    await tester.pumpAndSettle();

    // Tant qu'il n'y a pas deux noms, on ne crée rien.
    expect(find.text('Ajoute au moins deux noms'), findsOneWidget);

    await tester.enterText(find.byType(TextField), "Sachet d'eau");
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Beignet');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer ces 2 articles'));
    await tester.pumpAndSettle();

    // Deux vrais articles existent maintenant, au même prix, et la question
    // ne revient plus sur le fourre-tout.
    final catalogue = await depot.catalogue();
    final crees = catalogue.where((a) => !a.code.startsWith('AUTO-')).toList();
    expect(crees.map((a) => a.designation).toSet(), {"Sachet d'eau", 'Beignet'});
    expect(crees.every((a) => a.prixCentimes == f(500).centimes), isTrue);

    expect(find.textContaining('Tu vends souvent'), findsNothing);
    expect(await depot.articlesANommer(), isEmpty);
  });

  testWidgets('les ventes déjà faites restent sur le fourre-tout',
      (tester) async {
    for (var i = 0; i < 3; i++) {
      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(500),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
        ],
      );
    }

    await tester.pumpWidget(application());
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Tu vends souvent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ce sont plusieurs choses différentes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Pain');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Savon');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer ces 2 articles'));
    await tester.pumpAndSettle();

    // Personne ne saurait dire lesquelles des trois ventes étaient du pain :
    // le journal ne se réécrit pas, et on ne devine pas le passé.
    final ancien = (await depot.catalogue())
        .firstWhere((a) => a.code == 'AUTO-50000');
    expect(ancien.nombreVentes, 3);

    final rapport = await depot.rapportDuJour();
    expect(rapport.encaisse, f(1500));
  });

  testWidgets('le pavé numérique encaisse un montant libre', (tester) async {
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Montant\nlibre'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('7'));
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('00'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Encaisser').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Espèces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider la vente'));
    await tester.pumpAndSettle();

    final rapport = await depot.rapportDuJour();
    expect(rapport.nombreVentes, 1);
    expect(rapport.encaisse, f(7500));
  });

  group('Prix négocié', () {
    /// Ouvre le pavé de négociation sur un article et y saisit un prix.
    ///
    /// L'appui long ouvre d'abord la feuille d'ajustement — la quantité et le
    /// prix y tombent au même endroit, plutôt que d'inventer un second geste
    /// que personne ne trouverait.
    Future<void> negocier(WidgetTester tester, String nom, String saisie) async {
      await tester.longPress(find.text(nom));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Changer le prix pour cette vente'));
      await tester.pumpAndSettle();

      // On vise l'InkWell de la touche : le montant affiché au-dessus du
      // pavé contient les mêmes chiffres, et un simple find.text taperait
      // dessus.
      for (final touche in saisie.split('')) {
        await tester.tap(find.widgetWithText(InkWell, touche));
        await tester.pump();
      }
      await tester.tap(find.text('Utiliser ce prix'));
      await tester.pumpAndSettle();
    }

    testWidgets("l'appui long change le prix pour cette vente seulement",
        (tester) async {
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await negocier(tester, 'Riz 1 kg', '500');

      // L'article est entré au panier au prix discuté, pas à celui du
      // catalogue : le total le prouve.
      final semantique = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('500 F'), findsWidgets);
      semantique.dispose();

      expect(find.text('1 article'), findsOneWidget);
    });

    testWidgets('le catalogue garde son prix après la vente négociée',
        (tester) async {
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await negocier(tester, 'Riz 1 kg', '500');
      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      // Le prix négocié valait pour cette vente. Le prix de référence, lui,
      // ne bouge pas : sinon une remise de complaisance déformerait le
      // catalogue pour tous les clients suivants.
      final catalogue = await depot.catalogue();
      final riz = catalogue.firstWhere((a) => a.code == 'RIZ');
      expect(Montant(riz.prixCentimes), f(650));
    });

    testWidgets('la remise consentie est comptée dans le rapport',
        (tester) async {
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await negocier(tester, 'Riz 1 kg', '500');
      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      // 650 au catalogue, 500 encaissés : 150 F offerts. C'est ce que le
      // commerçant doit voir le soir.
      final rapport = await depot.rapportDuJour();
      expect(rapport.remisesAccordees, f(150));
      expect(rapport.encaisse, f(650 + 1200 + 500));
    });

    testWidgets('vider le panier oublie les prix négociés', (tester) async {
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await negocier(tester, 'Riz 1 kg', '500');
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      // Le client suivant repart du prix affiché.
      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();

      final semantique = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('650 F'), findsWidgets);
      semantique.dispose();
    });
  });

  group('Rattraper une erreur', () {
    testWidgets('la pastille retire une unité', (tester) async {
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Riz 1 kg'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('3 articles'), findsOneWidget);

      // La tuile ajoute, la pastille enlève.
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(find.text('2 articles'), findsOneWidget);
    });

    testWidgets("retirer le dernier vide l'article du panier", (tester) async {
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      expect(find.text('Choisir un article'), findsOneWidget);
    });

    testWidgets('annuler une vente la retire du rapport', (tester) async {
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      expect((await depot.rapportDuJour()).nombreVentes, 3);

      // Le bandeau de confirmation porte l'annulation : c'est le moment où
      // l'erreur se voit.
      await tester.tap(find.textContaining('Annuler'));
      await tester.pumpAndSettle();

      expect((await depot.rapportDuJour()).nombreVentes, 2);
      expect(find.textContaining('Vente annulée'), findsOneWidget);
    });

    testWidgets("le reste du bandeau n'annule rien", (tester) async {
      // Le bandeau flotte trois secondes au-dessus de la grille. En faire une
      // cible d'annulation entière ferait annuler la vente précédente chaque
      // fois qu'un doigt vise la tuile suivante — c'est arrivé en pilotant
      // l'application pour de vrai.
      await garnirCatalogue();
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Vente enregistrée'));
      await tester.pumpAndSettle();

      expect((await depot.rapportDuJour()).nombreVentes, 3);
      expect(find.textContaining('Vente annulée'), findsNothing);
    });

    testWidgets('un montant énorme demande confirmation', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Montant\nlibre'));
      await tester.pumpAndSettle();
      for (final touche in ['9', '9', '9', '9', '9', '9']) {
        await tester.tap(find.widgetWithText(InkWell, touche));
        await tester.pump();
      }
      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      expect(find.textContaining("beaucoup plus que d'habitude"), findsOneWidget);

      // Corriger : rien ne s'enregistre.
      await tester.tap(find.text('Corriger'));
      await tester.pumpAndSettle();
      expect((await depot.rapportDuJour()).nombreVentes, 0);
    });

    testWidgets('un montant ordinaire ne dérange personne', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Montant\nlibre'));
      await tester.pumpAndSettle();
      for (final touche in ['5', '0', '0']) {
        await tester.tap(find.widgetWithText(InkWell, touche));
        await tester.pump();
      }
      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      expect(find.textContaining("beaucoup plus que d'habitude"), findsNothing);
      expect((await depot.rapportDuJour()).nombreVentes, 1);
    });

    testWidgets('zéro franc ne peut pas être validé', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Montant\nlibre'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, '00'));
      await tester.pumpAndSettle();

      // Le bouton reste inerte au lieu de fermer la feuille sans rien dire.
      final bouton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Encaisser'));
      expect(bouton.onPressed, isNull);
    });
  });

  group('Le stockage se prouve, il ne se promet pas', () {
    testWidgets('un stockage non démontré se signale', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: Accueil(
          depot: depot,
          documents: documents,
          analyses: analyses,
          parametres: Parametres(base),
          reglage: const Reglage(
              nomCommerce: 'Test', comptes: ComptesMarchands.aucun()),
          stockageSur: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('peut ne pas être retrouvé'), findsOneWidget);
    });

    testWidgets("l'avertissement se ferme et ne revient pas", (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: Accueil(
          depot: depot,
          documents: documents,
          analyses: analyses,
          parametres: Parametres(base),
          reglage: const Reglage(
              nomCommerce: 'Test', comptes: ComptesMarchands.aucun()),
          stockageSur: false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip("J'ai compris"));
      await tester.pumpAndSettle();
      expect(find.textContaining('peut ne pas être retrouvé'), findsNothing);
    });

    testWidgets('sur un téléphone, rien ne prévient de rien', (tester) async {
      // La base y est un fichier : la question ne se pose pas, et un
      // avertissement inutile use la confiance.
      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: Accueil(
          depot: depot,
          documents: documents,
          analyses: analyses,
          parametres: Parametres(base),
          reglage: const Reglage(
              nomCommerce: 'Test', comptes: ComptesMarchands.aucun()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('peut ne pas être retrouvé'), findsNothing);
    });
  });

  group('Le témoin de stockage', () {
    test('absent la première fois, présent la suivante', () async {
      final parametres = Parametres(base);

      // Rien à retrouver au premier lancement : on ne peut rien affirmer.
      expect(await parametres.temoinRetrouve(), isFalse);
      // Au suivant, le témoin est là : la preuve est faite.
      expect(await parametres.temoinRetrouve(), isTrue);
    });

    test("il ne compte pas comme un réglage du commerçant", () async {
      final parametres = Parametres(base);
      await parametres.temoinRetrouve();

      final reglage = await parametres.tout();
      expect(reglage.nomCommerce, Parametres.nomCommerceParDefaut);
      expect(reglage.vendeurs, isEmpty);
    });
  });
}
