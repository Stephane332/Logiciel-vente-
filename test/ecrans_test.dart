/// Tests du cahier de dettes et du rapport du soir.
///
/// Ces deux écrans ne servent pas à encaisser : ils servent à décider. Ce que
/// je vérifie ici, c'est donc moins le pixel que le chiffre affiché — un
/// commerçant qui relance un client sur un mauvais montant perd le client.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/domaine/telephone.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/domaine/mobile_money.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/interface/composants/montant_anime.dart';
import 'package:carnet/interface/ecrans/accueil.dart';
import 'package:carnet/interface/ecrans/dettes.dart';
import 'package:carnet/interface/ecrans/rapport.dart';
import 'package:carnet/interface/ecrans/stock.dart';
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
    documents = Documents(base, nomCommerce: 'Alimentation Nabonswendé');
    analyses = Analyses(base);
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  /// Retrouve un montant lu à voix haute par un lecteur d'écran.
  ///
  /// Les cartes fusionnent leur contenu en un seul nœud — « Salif, 70 11 22
  /// 33, 2 600 F » se lit d'une traite — donc je cherche le montant dans
  /// l'étiquette plutôt que de la comparer entièrement.
  Finder montantDit(String texte) =>
      find.bySemanticsLabel(RegExp(RegExp.escape(texte)));

  /// Une vente, éventuellement à crédit et éventuellement datée.
  Future<String> vendre(
    String code,
    String nom,
    num prix, {
    num quantite = 1,
    String? clientId,
    DateTime? quand,
    ModePaiement mode = ModePaiement.especes,
  }) {
    final total = f(prix).multiplieParQuantite(Quantite.depuisDecimal(quantite));
    return depot.enregistrerVente(
      lignes: [
        LigneAEnregistrer(
          codeArticle: code,
          designation: nom,
          prixUnitaire: f(prix),
          quantite: Quantite.depuisDecimal(quantite),
        )
      ],
      paiements: [PaiementAEnregistrer(mode: mode, montant: total)],
      clientId: clientId,
      horodatage: quand,
    );
  }

  group('Cahier de dettes', () {
    Widget application() => MaterialApp(
          theme: themeClair(),
          home: Scaffold(
            body: EcranDettes(depot: depot, documents: documents),
          ),
        );

    testWidgets('un cahier vide le dit clairement', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text('Personne ne te doit rien'), findsOneWidget);
    });

    testWidgets('une vente à crédit fait apparaître le débiteur',
        (tester) async {
      final client = await depot.creerClient(
        nom: 'Salif Ouédraogo',
        telephone: '70 11 22 33',
      );
      await vendre('RIZ', 'Riz 1 kg', 650,
          quantite: 4, clientId: client, mode: ModePaiement.credit);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text('Salif Ouédraogo'), findsOneWidget);
      expect(find.text('70 11 22 33'), findsOneWidget);

      final semantique = tester.ensureSemantics();
      await tester.pumpAndSettle();
      // 2 600 F dus, annoncés deux fois : dans le total du haut et sur la
      // carte du client.
      expect(montantDit('2 600 F'), findsNWidgets(2));
      semantique.dispose();
    });

    testWidgets('le total additionne tous les débiteurs', (tester) async {
      for (final (nom, montant) in const [('Awa', 1000), ('Boukary', 500)]) {
        final client = await depot.creerClient(nom: nom);
        await vendre('DIVERS', 'Divers', montant,
            clientId: client, mode: ModePaiement.credit);
      }

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text('2 clients'), findsOneWidget);

      final semantique = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(montantDit('1 500 F'), findsOneWidget);
      semantique.dispose();
    });

    testWidgets('les plus vieilles dettes remontent en tête', (tester) async {
      final ancien = await depot.creerClient(nom: 'Vieille dette');
      final recent = await depot.creerClient(nom: 'Dette du jour');

      await vendre('DIVERS', 'Divers', 1000,
          clientId: ancien,
          mode: ModePaiement.credit,
          quand: DateTime.now().subtract(const Duration(days: 60)));
      await vendre('DIVERS', 'Divers', 1000,
          clientId: recent, mode: ModePaiement.credit);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      final cartes = tester.getTopLeft(find.text('Vieille dette'));
      final apres = tester.getTopLeft(find.text('Dette du jour'));
      expect(cartes.dy, lessThan(apres.dy));

      // Passé un mois, la dette se signale d'elle-même.
      expect(find.text('Depuis 60 jours'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('encaisser un remboursement partiel réduit la dette',
        (tester) async {
      final client = await depot.creerClient(nom: 'Salif');
      await vendre('DIVERS', 'Divers', 3000,
          clientId: client, mode: ModePaiement.credit);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();

      for (final touche in ['1', '0', '0', '0']) {
        await tester.tap(find.widgetWithText(InkWell, touche));
        await tester.pump();
      }
      await tester.tap(find.text('Enregistrer le paiement'));
      await tester.pumpAndSettle();

      final debiteurs = await depot.clientsDebiteurs();
      expect(debiteurs.single.encoursCentimes, f(2000).centimes);
    });

    testWidgets('le raccourci « Tout » solde la dette', (tester) async {
      final client = await depot.creerClient(nom: 'Salif');
      await vendre('DIVERS', 'Divers', 3000,
          clientId: client, mode: ModePaiement.credit);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tout : 3 000 F'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer le paiement'));
      await tester.pumpAndSettle();

      expect(await depot.clientsDebiteurs(), isEmpty);
      expect(find.text('Personne ne te doit rien'), findsOneWidget);
    });
  });

  group('Rapport du soir', () {
    Widget application() => MaterialApp(
          theme: themeClair(),
          home: Scaffold(
            body: EcranRapport(
              depot: depot,
              documents: documents,
              analyses: analyses,
            ),
          ),
        );

    testWidgets('une journée sans vente affiche zéro sans planter',
        (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text("Aujourd'hui"), findsOneWidget);
      expect(find.text('0 vente'), findsOneWidget);
    });

    testWidgets("le rapport montre ce qui a été encaissé aujourd'hui",
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650, quantite: 2);
      await vendre('HUILE', 'Huile 1 L', 1200);

      // Une vente d'hier ne doit pas remonter dans le total du jour.
      await vendre('RIZ', 'Riz 1 kg', 650,
          quand: DateTime.now().subtract(const Duration(days: 1)));

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      final semantique = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(montantDit('2 500 F'), findsOneWidget);
      semantique.dispose();

      expect(find.text('2 ventes'), findsOneWidget);
    });

    testWidgets('le crédit du jour est distingué de l\'encaissé',
        (tester) async {
      final client = await depot.creerClient(nom: 'Salif');
      await vendre('RIZ', 'Riz 1 kg', 650);
      await vendre('HUILE', 'Huile 1 L', 1200,
          clientId: client, mode: ModePaiement.credit);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      // Encaissé en grand, crédit dans sa pastille : ce sont deux natures
      // d'argent différentes et l'écran ne doit jamais les additionner.
      final entete = tester.widget<MontantAnime>(find.byType(MontantAnime).first);
      expect(entete.montant, f(650));

      final credit = tester.widget<PastilleMontant>(
          find.widgetWithText(PastilleMontant, 'À crédit'));
      expect(credit.montant, f(1200));
    });

    testWidgets('« Ce qui rapporte » classe les articles de la semaine',
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650, quantite: 10);
      await vendre('HUILE', 'Huile 1 L', 1200);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text('Ce qui rapporte'), findsOneWidget);

      final riz = tester.getTopLeft(find.text('Riz 1 kg'));
      final huile = tester.getTopLeft(find.text('Huile 1 L'));
      expect(riz.dy, lessThan(huile.dy));
    });

    testWidgets('la rupture de stock apparaît dans « À racheter »',
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650, quantite: 5);
      await depot.definirSuiviStock('RIZ', SuiviStock.direct);
      await depot.ajusterStock('RIZ', const Quantite.unites(0));

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text('À racheter'), findsOneWidget);
      // Le même mot qu'au patron : l'écran et le message envoyé sortent
      // maintenant de la même règle.
      expect(find.text('rupture'), findsOneWidget);
    });

    testWidgets('le résumé envoyé reprend les chiffres affichés',
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650, quantite: 2);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Envoyer le résumé'));
      await tester.pumpAndSettle();

      // Le document part en un seul bloc de texte, aligné en chasse fixe.
      expect(
        find.textContaining(RegExp(r'ALIMENTATION NABONSWENDÉ[\s\S]*'
            r'Encaissé\s+1 300 F')),
        findsOneWidget,
      );
    });
  });

  group('Coquille de navigation', () {
    Widget application() => MaterialApp(
          theme: themeClair(),
          home: Accueil(
            depot: depot,
            documents: documents,
            analyses: analyses,
            parametres: Parametres(base),
            reglage: const Reglage(
              nomCommerce: 'Alimentation Nabonswendé',
              comptes: ComptesMarchands.aucun(),
            ),
          ),
        );

    testWidgets('les trois destinations sont accessibles', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text('Choisir un article'), findsOneWidget);

      await tester.tap(find.text('Dettes'));
      await tester.pumpAndSettle();
      expect(find.text('On te doit'), findsOneWidget);

      await tester.tap(find.text('Rapport'));
      await tester.pumpAndSettle();
      expect(find.text('encaissés'), findsOneWidget);
    });

    testWidgets('revenir à la caisse ne perd pas le panier en cours',
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rapport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse'));
      await tester.pumpAndSettle();

      // Un client qui pose une question ne doit pas coûter le panier.
      expect(find.text('1 article'), findsOneWidget);
    });

    testWidgets('le rapport se remet à jour après une vente', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      // Ouvrir le rapport une première fois : rien encaissé.
      await tester.tap(find.text('Rapport'));
      await tester.pumpAndSettle();
      expect(find.text('0 vente'), findsOneWidget);

      // Vendre, puis revenir au rapport : les écrans sont gardés en vie, donc
      // sans rechargement explicite ce chiffre resterait à zéro.
      await tester.tap(find.text('Caisse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Montant\nlibre'));
      await tester.pumpAndSettle();
      for (final touche in ['5', '0', '0']) {
        await tester.tap(find.widgetWithText(InkWell, touche));
        await tester.pump();
      }
      await tester.tap(find.text('Encaisser').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rapport'));
      await tester.pumpAndSettle();

      expect(find.text('1 vente'), findsOneWidget);
      final entete =
          tester.widget<MontantAnime>(find.byType(MontantAnime).first);
      expect(entete.montant, f(500));
    });

    testWidgets('un article créé au stock est vendable à la caisse',
        (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Article'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, "Nom de l'article"), 'Savon');
      await tester.enterText(
          find.widgetWithText(TextField, 'Prix de vente'), '350');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      // De retour à la caisse, il doit être là tout de suite : sinon le
      // commerçant croit que sa saisie n'a servi à rien.
      await tester.tap(find.text('Caisse'));
      await tester.pumpAndSettle();
      expect(find.text('Savon'), findsOneWidget);
    });

    testWidgets('le cahier de dettes se remet à jour après une vente à crédit',
        (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dettes'));
      await tester.pumpAndSettle();
      expect(find.text('Personne ne te doit rien'), findsOneWidget);

      final client = await depot.creerClient(nom: 'Salif');
      await vendre('DIVERS', 'Divers', 2000,
          clientId: client, mode: ModePaiement.credit);

      await tester.tap(find.text('Caisse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dettes'));
      await tester.pumpAndSettle();

      expect(find.text('Salif'), findsOneWidget);
    });
  });

  group("Règles descendues dans le domaine", () {
    test('un numéro se rend en forme internationale quelle que soit sa saisie',
        () {
      for (final saisie in ['70112233', '+226 70 11 22 33', '0022670112233']) {
        expect(telephoneInternational(saisie), '22670112233');
      }
      expect(telephoneInternational(null), isNull);
      expect(telephoneInternational('12'), isNull);
    });

    test("l'ancienneté d'une dette se mesure au jour près", () async {
      final client = await depot.creerClient(nom: 'Salif');
      final maintenant = DateTime(2026, 8, 5, 12);

      await vendre('DIVERS', 'Divers', 1000,
          clientId: client,
          mode: ModePaiement.credit,
          quand: maintenant.subtract(const Duration(days: 40)));

      final ligne = (await depot.clientsDebiteurs()).single;
      expect(ligne.ageEnJours(maintenant), 40);
      expect(ligne.detteAncienne(maintenant), isTrue);
    });

    test('une dette de la veille reste une facilité, pas une créance',
        () async {
      final client = await depot.creerClient(nom: 'Awa');
      final maintenant = DateTime(2026, 8, 5, 12);

      await vendre('DIVERS', 'Divers', 1000,
          clientId: client,
          mode: ModePaiement.credit,
          quand: maintenant.subtract(const Duration(days: 1)));

      final ligne = (await depot.clientsDebiteurs()).single;
      expect(ligne.detteAncienne(maintenant), isFalse);
    });

    test('le seuil est franc : 30 jours bascule, 29 non', () async {
      final client = await depot.creerClient(nom: 'Boukary');
      final maintenant = DateTime(2026, 8, 5, 12);

      await vendre('DIVERS', 'Divers', 1000,
          clientId: client,
          mode: ModePaiement.credit,
          quand: maintenant.subtract(Duration(days: Depot.joursDetteAncienne)));

      final ligne = (await depot.clientsDebiteurs()).single;
      expect(ligne.detteAncienne(maintenant), isTrue);
      expect(
        ligne.detteAncienne(
            maintenant.subtract(const Duration(days: 1))),
        isFalse,
      );
    });
  });

  group('Encaissement par téléphone', () {
    Widget caisse({ComptesMarchands comptes = const ComptesMarchands.aucun()}) =>
        MaterialApp(
          theme: themeClair(),
          home: EcranVente(
            depot: depot,
            documents: documents,
            comptes: comptes,
          ),
        );

    Future<void> ouvrirMobileMoney(WidgetTester tester) async {
      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile money'));
      await tester.pumpAndSettle();
    }

    testWidgets("sans compte marchand, on explique au lieu d'afficher un code",
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 2500);
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await ouvrirMobileMoney(tester);

      // Un code QR sans numéro configuré ne paierait personne.
      expect(find.textContaining('sur quel numéro tu veux être payé'),
          findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('avec un compte, le code du client est affiché en entier',
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 2500);
      await tester.pumpWidget(caisse(
        comptes: const ComptesMarchands({OperateurMobile.orange: '70000000'}),
      ));
      await tester.pumpAndSettle();

      await ouvrirMobileMoney(tester);

      expect(find.text('*144*10*70000000*2500#'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets("seuls les opérateurs configurés sont proposés",
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 2500);
      await tester.pumpWidget(caisse(
        comptes: const ComptesMarchands({
          OperateurMobile.orange: '70000000',
          OperateurMobile.moov: '60112233',
        }),
      ));
      await tester.pumpAndSettle();

      await ouvrirMobileMoney(tester);

      expect(find.text('Orange'), findsOneWidget);
      expect(find.text('Moov'), findsOneWidget);
      expect(find.text('Telecel'), findsNothing);
    });

    testWidgets("changer d'opérateur change le code affiché", (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 2500);
      await tester.pumpWidget(caisse(
        comptes: const ComptesMarchands({
          OperateurMobile.orange: '70000000',
          OperateurMobile.moov: '60112233',
        }),
      ));
      await tester.pumpAndSettle();

      await ouvrirMobileMoney(tester);
      await tester.tap(find.text('Moov'));
      await tester.pumpAndSettle();

      expect(find.text('*555*60112233*2500#'), findsOneWidget);
    });
  });

  group('Stock', () {
    Widget application() => MaterialApp(
          theme: themeClair(),
          home: Scaffold(body: EcranStock(depot: depot)),
        );

    Quantite q(num unites) => Quantite.depuisDecimal(unites);

    /// Saisit une quantité sur le pavé, puis valide.
    Future<void> saisir(WidgetTester tester, String chiffres,
        String valider) async {
      for (final touche in chiffres.split('')) {
        await tester.tap(find.widgetWithText(InkWell, touche));
        await tester.pump();
      }
      await tester.tap(find.text(valider));
      await tester.pumpAndSettle();
    }

    testWidgets('une boutique neuve ne montre aucun stock', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      // Aucun inventaire à saisir : c'est le principe.
      expect(find.text('Rien à compter pour le moment'), findsOneWidget);
    });

    testWidgets('un article vendu souvent finit par être proposé',
        (tester) async {
      for (var i = 0; i < Depot.seuilDeSuiviStock; i++) {
        await vendre('RIZ', 'Riz 1 kg', 650);
      }

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.textContaining('Tu vends souvent Riz 1 kg'), findsOneWidget);
    });

    testWidgets('accepter le suivi fait entrer l\'article dans le stock',
        (tester) async {
      for (var i = 0; i < Depot.seuilDeSuiviStock; i++) {
        await vendre('RIZ', 'Riz 1 kg', 650);
      }

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compter'));
      await tester.pumpAndSettle();
      await saisir(tester, '40', 'Commencer à suivre');

      expect(find.textContaining('Tu vends souvent'), findsNothing);
      expect(find.text('Ce que je suis'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
    });

    testWidgets('« plus tard » range l\'article sans le perdre', (tester) async {
      for (var i = 0; i < Depot.seuilDeSuiviStock; i++) {
        await vendre('RIZ', 'Riz 1 kg', 650);
      }

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();

      // La proposition disparaît, rien n'est compté — mais l'article reste
      // à portée de main, dans la liste du bas.
      expect(find.textContaining('Tu vends souvent'), findsNothing);
      expect(await depot.articlesEnStock(), isEmpty);
      expect(find.text('Pas encore suivis'), findsOneWidget);
      expect(find.text('Riz 1 kg'), findsOneWidget);
    });

    testWidgets('on peut compter un article rangé après un « plus tard »',
        (tester) async {
      for (var i = 0; i < Depot.seuilDeSuiviStock; i++) {
        await vendre('RIZ', 'Riz 1 kg', 650);
      }
      await depot.reporterPropositionSuivi('RIZ');

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compter'));
      await tester.pumpAndSettle();
      await saisir(tester, '30', 'Commencer à suivre');

      expect(find.text('Ce que je suis'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('un article peut être créé de toutes pièces', (tester) async {
      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Article'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, "Nom de l'article"), 'Savon');
      await tester.enterText(
          find.widgetWithText(TextField, 'Prix de vente'), '350');
      await tester.enterText(
          find.widgetWithText(TextField, 'Quantité en stock (facultatif)'),
          '24');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.text('Savon'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
    });

    testWidgets('un article sans nom se signale dans la liste du bas',
        (tester) async {
      // Trois ventes à montant libre : l'article existe mais n'a pas de nom.
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

      // Le commerçant peut le nommer quand il veut, sans attendre qu'on le
      // lui demande à la caisse.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('une réception s\'ajoute au stock', (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);
      await depot.ajusterStock('RIZ', q(40));

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reçu'));
      await tester.pumpAndSettle();
      await saisir(tester, '20', 'Ajouter au stock');

      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('un comptage remplace le stock théorique', (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);
      await depot.ajusterStock('RIZ', q(40));

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compté'));
      await tester.pumpAndSettle();
      await saisir(tester, '37', 'Corriger le stock');

      expect(find.text('37'), findsOneWidget);

      // L'écart constaté est tracé : c'est ce qui répond à « où est passée
      // la différence ».
      final dernier = (await depot.mouvementsDe('RIZ')).first;
      expect(dernier.variationMilliemes, q(3).milliemes * -1);
    });

    testWidgets('un stock épuisé se signale', (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);
      await depot.ajusterStock('RIZ', q(0));

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(find.text('Rupture'), findsOneWidget);
    });

    testWidgets('les plus bas remontent en tête', (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);
      await vendre('HUILE', 'Huile 1 L', 1200);
      await depot.ajusterStock('RIZ', q(40));
      await depot.ajusterStock('HUILE', q(2));

      await tester.pumpWidget(application());
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Huile 1 L')).dy,
        lessThan(tester.getTopLeft(find.text('Riz 1 kg')).dy),
      );
    });
  });

  group('Vente à crédit', () {
    Widget caisse() => MaterialApp(
          theme: themeClair(),
          home: EcranVente(depot: depot, documents: documents),
        );

    Future<void> ouvrirCredit(WidgetTester tester) async {
      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crédit'));
      await tester.pumpAndSettle();
    }

    testWidgets('on ne peut pas valider une dette sans savoir à qui',
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await ouvrirCredit(tester);

      // Une dette sans nom, c'est de l'argent perdu.
      expect(find.text('À qui ?'), findsWidgets);
      final bouton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'À qui ?'));
      expect(bouton.onPressed, isNull);
    });

    testWidgets('créer un client au comptoir puis noter la dette',
        (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await ouvrirCredit(tester);
      await tester.tap(find.text('Nouveau client'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Salif');
      await tester.enterText(
          find.widgetWithText(TextField, 'Téléphone (facultatif)'),
          '70112233');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Noter la dette'));
      await tester.pumpAndSettle();

      // La dette arrive vraiment dans le cahier, au nom du bon client.
      final debiteurs = await depot.clientsDebiteurs();
      expect(debiteurs.single.nom, 'Salif');
      expect(debiteurs.single.encoursCentimes, f(650).centimes);
    });

    testWidgets('un habitué se retrouve d\'un geste', (tester) async {
      await depot.creerClient(nom: 'Awa', telephone: '70998877');
      await vendre('RIZ', 'Riz 1 kg', 650);

      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await ouvrirCredit(tester);
      await tester.tap(find.text('Awa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Noter la dette'));
      await tester.pumpAndSettle();

      final debiteurs = await depot.clientsDebiteurs();
      expect(debiteurs.single.nom, 'Awa');
    });

    testWidgets('les espèces ne demandent aucun client', (tester) async {
      await vendre('RIZ', 'Riz 1 kg', 650);
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Riz 1 kg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Espèces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider la vente'));
      await tester.pumpAndSettle();

      expect(await depot.clientsDebiteurs(), isEmpty);
      final rapport = await depot.rapportDuJour();
      expect(rapport.nombreVentes, 2);
    });
  });
}
