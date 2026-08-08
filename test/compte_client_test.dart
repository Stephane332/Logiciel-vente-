/// Tests du détail d'une dette, et de la quantité vendue d'un coup.
///
/// Le cahier n'affichait qu'un total. Quand le client conteste — et il
/// conteste toujours — le commerçant n'avait rien à lui montrer, alors que
/// tout est en base. C'est précisément la dispute que l'ardoise devait
/// éteindre.
///
/// Et vendre un carton se faisait appui par appui, douze fois, pendant que le
/// client regardait.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/interface/composants/tuile_produit.dart';
import 'package:carnet/interface/ecrans/dettes.dart';
import 'package:carnet/interface/ecrans/vente.dart';
import 'package:carnet/interface/theme/theme.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Documents documents;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    documents = Documents(base, nomCommerce: 'Alimentation Nabonswendé');
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  /// Un achat à crédit, d'une ou plusieurs lignes.
  Future<String> aCredit(
    String clientId,
    List<(String, num, int)> articles, {
    DateTime? quand,
  }) {
    var total = 0;
    final lignes = <LigneAEnregistrer>[];
    for (final (nom, prix, combien) in articles) {
      total += (f(prix).centimes * combien);
      lignes.add(LigneAEnregistrer(
        codeArticle: nom.toUpperCase(),
        designation: nom,
        prixUnitaire: f(prix),
        quantite: Quantite.unites(combien),
      ));
    }
    return depot.enregistrerVente(
      lignes: lignes,
      paiements: [
        PaiementAEnregistrer(
            mode: ModePaiement.credit, montant: Montant(total))
      ],
      clientId: clientId,
      horodatage: quand,
    );
  }

  group("Le détail d'une dette", () {
    test('chaque achat à crédit a sa ligne', () async {
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 1)],
          quand: DateTime.now().subtract(const Duration(days: 2)));
      await aCredit(salif, [('Sucre', 750, 2)]);

      final compte = await depot.compteDe(salif);

      expect(compte, hasLength(2));
      // Du plus récent au plus ancien : la contestation porte presque
      // toujours sur le dernier achat.
      expect(compte.first.montant, f(1500));
      expect(compte.last.montant, f(650));
      expect(compte.every((m) => m.estAchat), isTrue);
    });

    test('on voit ce que chaque achat contenait', () async {
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 2), ('Savon', 300, 1)]);

      final achat = (await depot.compteDe(salif)).single;

      expect(achat.detail.map((d) => d.designation), ['Riz 1 kg', 'Savon']);
      expect(achat.detail.first.quantite, const Quantite.unites(2));
      expect(achat.detail.first.total, f(1300));
      expect(achat.detail.last.total, f(300));
    });

    test('les remboursements apparaissent aussi, en sens inverse', () async {
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 2)]);
      await depot.rembourserCredit(salif, f(500));

      final compte = await depot.compteDe(salif);

      expect(compte, hasLength(2));
      expect(compte.first.estAchat, isFalse);
      expect(compte.first.montant, f(500));
      expect(compte.first.detail, isEmpty);
    });

    test('une vente payée comptant ne pollue pas le compte', () async {
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 1)]);
      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'SUCRE',
            designation: 'Sucre',
            prixUnitaire: f(750),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(750))
        ],
        clientId: salif,
      );

      // Une ardoise ne contient que ce qui est dû.
      expect(await depot.compteDe(salif), hasLength(1));
    });

    test('un achat annulé reste visible, marqué comme tel', () async {
      // Le faire disparaître ferait croire au client qu'on lui a effacé une
      // ligne dans le dos.
      final salif = await depot.creerClient(nom: 'Salif');
      final vente = await aCredit(salif, [('Riz 1 kg', 650, 1)]);
      await depot.annulerVente(vente);

      final compte = await depot.compteDe(salif);
      expect(compte, hasLength(1));
      expect(compte.single.annule, isTrue);
    });

    test("le compte d'un client ne mélange pas celui d'un autre", () async {
      final salif = await depot.creerClient(nom: 'Salif');
      final awa = await depot.creerClient(nom: 'Awa');
      await aCredit(salif, [('Riz 1 kg', 650, 1)]);
      await aCredit(awa, [('Sucre', 750, 1)]);
      await depot.rembourserCredit(awa, f(200));

      final compte = await depot.compteDe(salif);
      expect(compte, hasLength(1));
      expect(compte.single.montant, f(650));
    });

    test('un client sans rien ne rend rien', () async {
      final salif = await depot.creerClient(nom: 'Salif');
      expect(await depot.compteDe(salif), isEmpty);
    });

    test("la somme du détail redonne l'encours", () async {
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 2)]);
      await aCredit(salif, [('Sucre', 750, 1)]);
      await depot.rembourserCredit(salif, f(1000));

      final compte = await depot.compteDe(salif);
      final solde = compte.fold(
        0,
        (somme, m) => somme + (m.estAchat ? m.montant.centimes : -m.montant.centimes),
      );

      final client = (await depot.clientsDebiteurs()).single;
      expect(Montant(solde), Montant(client.encoursCentimes));
    });
  });

  group("Le détail à l'écran", () {
    /// La tête de carte porte son propre nœud d'accessibilité.
    ///
    /// Rendre la carte entière tactile fusionnait tout ce qu'elle contient
    /// en un seul nœud : un lecteur d'écran n'entendait plus que « Envoyer
    /// Encaisser », sans le nom du client ni ce qu'il doit.
    Finder tete(String nom) => find.bySemanticsLabel(RegExp('^$nom, doit'));

    Future<void> ouvrir(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: Scaffold(
          body: EcranDettes(depot: depot, documents: documents),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('appuyer sur la carte ouvre le détail', (tester) async {
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 2)]);

      await ouvrir(tester);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Riz 1 kg  ×2'), findsOneWidget);
      expect(find.textContaining('+ 1 300'), findsOneWidget);
    });

    testWidgets('un remboursement se distingue par son signe', (tester) async {
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 2)]);
      await depot.rembourserCredit(salif, f(500));

      await ouvrir(tester);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('− 500'), findsOneWidget);
    });

    testWidgets("la carte s'annonce avec le nom et le montant", (tester) async {
      final semantique = tester.ensureSemantics();
      final salif = await depot.creerClient(nom: 'Salif');
      await aCredit(salif, [('Riz 1 kg', 650, 2)]);

      await ouvrir(tester);

      expect(tete('Salif'), findsOneWidget);
      semantique.dispose();
    });
  });

  group("Vendre plusieurs d'un coup", () {
    Future<void> ouvrirCaisse(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: EcranVente(depot: depot, documents: documents),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets("l'appui long propose les conditionnements courants",
        (tester) async {
      await depot.creerArticle(designation: 'Sachet d\'eau', prix: f(50));
      await ouvrirCaisse(tester);

      await tester.longPress(find.text("Sachet d'eau"));
      await tester.pumpAndSettle();

      expect(find.text('×12'), findsOneWidget);
      expect(find.text('×24'), findsOneWidget);
      expect(find.text('Autre'), findsOneWidget);
    });

    testWidgets('choisir un nombre met tout le carton au panier',
        (tester) async {
      await depot.creerArticle(designation: 'Sachet d\'eau', prix: f(50));
      await ouvrirCaisse(tester);

      await tester.longPress(find.text("Sachet d'eau"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('×12'));
      await tester.pumpAndSettle();

      // Douze appuis remplacés par deux gestes. Le total est peint chiffre
      // par chiffre par le compteur animé : c'est le décompte d'articles qui
      // se lit d'un seul tenant.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('12 articles'), findsOneWidget);
    });

    testWidgets('le nombre choisi remplace la quantité, il ne s\'ajoute pas',
        (tester) async {
      await depot.creerArticle(designation: 'Sachet d\'eau', prix: f(50));
      await ouvrirCaisse(tester);

      await tester.tap(find.text("Sachet d'eau"));
      await tester.tap(find.text("Sachet d'eau"));
      await tester.pumpAndSettle();

      await tester.longPress(find.text("Sachet d'eau"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('×6'));
      await tester.pumpAndSettle();

      expect(find.text('6'), findsOneWidget);
      expect(find.text('8'), findsNothing);
    });

    testWidgets("le conseil n'apparaît qu'une fois", (tester) async {
      // Personne ne devine un appui long : on le dit au moment exact où il
      // servirait, et pas une fois de plus.
      await depot.creerArticle(designation: 'Sachet d\'eau', prix: f(50));
      await ouvrirCaisse(tester);

      for (var i = 0; i < EcranVenteState.tapesAvantConseil; i++) {
        await tester.tap(find.descendant(
          of: find.byType(TuileProduit),
          matching: find.text("Sachet d'eau"),
        ));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Appui long'), findsOneWidget);

      // Le bandeau s'efface, et ne revient plus.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      for (var i = 0; i < EcranVenteState.tapesAvantConseil + 2; i++) {
        await tester.tap(find.descendant(
          of: find.byType(TuileProduit),
          matching: find.text("Sachet d'eau"),
        ));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Appui long'), findsNothing);
    });
  });
}
