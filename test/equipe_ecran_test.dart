/// Tests d'écran de « qui tient la caisse ».
///
/// Le nom du vendeur doit rester visible en permanence : c'est ce qui empêche
/// d'encaisser toute une journée sous l'identité de quelqu'un d'autre. Et il
/// ne doit apparaître nulle part chez un commerçant seul — l'application ne
/// pose jamais une question dont la réponse ne sert à rien.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/periode.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/interface/ecrans/rapport.dart';
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

  Future<void> vendre(num prix, {String? par, DateTime? quand}) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(prix))
        ],
        operateur: par,
        horodatage: quand,
      );

  Widget caisse({List<String> vendeurs = const [], String? actif}) =>
      MaterialApp(
        theme: themeClair(),
        home: EcranVente(
          depot: depot,
          documents: documents,
          vendeurs: vendeurs,
          vendeurActif: actif,
          surVendeur: (_) {},
        ),
      );

  Widget rapport() => MaterialApp(
        theme: themeClair(),
        home: Scaffold(
          body: EcranRapport(
            depot: depot,
            documents: documents,
            analyses: analyses,
          ),
        ),
      );

  group('La pastille de caisse', () {
    testWidgets('un commerçant seul ne voit aucune pastille', (tester) async {
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      // « Caisse ouverte » ne changeait jamais : deux mots constants en haut
      // de l'écran le plus regardé de la journée. Un libellé qui affiche
      // toujours la même valeur ne transporte aucune information — la place
      // revient au chiffre, qui est la seule chose qu'il regarde.
      expect(find.text('Caisse ouverte'), findsNothing);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
    });

    testWidgets("l'état du réseau ne s'affiche plus", (tester) async {
      await tester.pumpWidget(caisse());
      await tester.pumpAndSettle();

      // Il était écrit en dur et ne consultait rien. Un nuage barré en
      // permanence se lit comme une panne, alors que le hors-ligne est le
      // mode de fonctionnement normal.
      expect(find.text('Hors ligne'), findsNothing);
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });

    testWidgets('avec une équipe, le nom du vendeur remplace le libellé',
        (tester) async {
      await tester.pumpWidget(caisse(vendeurs: ['Awa', 'Salif'], actif: 'Awa'));
      await tester.pumpAndSettle();

      expect(find.text('Awa'), findsOneWidget);
      expect(find.text('Caisse ouverte'), findsNothing);
    });

    testWidgets("une équipe sans personne de choisi pose la question",
        (tester) async {
      await tester.pumpWidget(caisse(vendeurs: ['Awa', 'Salif']));
      await tester.pumpAndSettle();

      expect(find.text('Qui encaisse ?'), findsOneWidget);
    });

    testWidgets("la question ne bloque pas la vente", (tester) async {
      // Une caisse qui refuse de vendre est une caisse qu'on repose. La vente
      // part sans nom, et le rapport le montrera.
      await tester.pumpWidget(caisse(vendeurs: ['Awa', 'Salif']));
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).enabled,
        isFalse,
        reason: 'panier vide',
      );
      expect(find.text('Choisir un article'), findsOneWidget);
    });

    testWidgets('appuyer dessus ouvre la liste des vendeurs', (tester) async {
      await tester.pumpWidget(caisse(vendeurs: ['Awa', 'Salif'], actif: 'Awa'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Awa'));
      await tester.pumpAndSettle();

      expect(find.text('Qui tient la caisse ?'), findsOneWidget);
      expect(find.text('Salif'), findsOneWidget);
    });

    testWidgets("la vente retient qui l'a faite", (tester) async {
      await tester.pumpWidget(caisse(vendeurs: ['Awa'], actif: 'Awa'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Montant\nlibre'));
      await tester.pumpAndSettle();
      for (final touche in ['1', '0', '0', '0']) {
        await tester.tap(find.descendant(
          of: find.byType(InkWell),
          matching: find.text(touche),
        ).first);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaisser'));
      await tester.pumpAndSettle();

      final (debut, fin) = Periode.jour.bornes();
      final parts = await depot.parVendeur(debut, fin);
      expect(parts.single.vendeur, 'Awa');
    });
  });

  group('La répartition au rapport', () {
    testWidgets("elle ne s'affiche pas chez un commerçant seul",
        (tester) async {
      await vendre(1000);
      await vendre(2000);

      await tester.pumpWidget(rapport());
      await tester.pumpAndSettle();

      // « Non attribué : tout » n'apprendrait rien à personne.
      expect(find.text('Qui a encaissé'), findsNothing);
    });

    testWidgets('chacun apparaît avec ses ventes', (tester) async {
      await vendre(2000, par: 'Salif');
      await vendre(1000, par: 'Awa');
      await vendre(500, par: 'Awa');

      await tester.pumpWidget(rapport());
      await tester.pumpAndSettle();

      expect(find.text('Qui a encaissé'), findsOneWidget);
      expect(find.text('Salif'), findsOneWidget);
      expect(find.text('Awa'), findsOneWidget);
      expect(find.text('2 ventes'), findsOneWidget);
      expect(find.text('1 vente'), findsOneWidget);
    });

    testWidgets("une vente sans nom se voit et ne s'attribue à personne",
        (tester) async {
      await vendre(1000, par: 'Awa');
      await vendre(3000);

      await tester.pumpWidget(rapport());
      await tester.pumpAndSettle();

      expect(find.text('Non attribué'), findsOneWidget);
    });
  });

  group('La période du rapport', () {
    testWidgets('la journée est le choix de départ', (tester) async {
      await vendre(1000);

      await tester.pumpWidget(rapport());
      await tester.pumpAndSettle();

      expect(find.text("Aujourd'hui"), findsOneWidget);
      expect(find.text('1 vente'), findsOneWidget);
    });

    testWidgets('hier retrouve la journée qui vient de passer',
        (tester) async {
      final hier = DateTime.now().subtract(const Duration(days: 1));
      await vendre(5000, quand: DateTime(hier.year, hier.month, hier.day, 10));
      await vendre(1000);

      await tester.pumpWidget(rapport());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hier'));
      await tester.pumpAndSettle();

      // Le patron qui ouvre le lendemain matin ne doit pas croire que ses
      // chiffres de la veille ont disparu.
      expect(find.textContaining('5 000'), findsWidgets);
    });

    testWidgets('la semaine additionne les journées', (tester) async {
      final avantHier = DateTime.now().subtract(const Duration(days: 2));
      await vendre(5000,
          quand: DateTime(
              avantHier.year, avantHier.month, avantHier.day, 10));
      await vendre(1000);

      await tester.pumpWidget(rapport());
      await tester.pumpAndSettle();

      await tester.tap(find.text('7 jours'));
      await tester.pumpAndSettle();

      expect(find.text('3 ventes'), findsNothing);
      expect(find.text('2 ventes'), findsOneWidget);
    });

    testWidgets('le résumé envoyé porte la période regardée', (tester) async {
      final hier = DateTime.now().subtract(const Duration(days: 1));
      await vendre(5000, quand: DateTime(hier.year, hier.month, hier.day, 10));

      await tester.pumpWidget(rapport());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hier'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Envoyer le résumé'));
      await tester.pumpAndSettle();

      // Sans cette date, le patron lirait « Journée du » suivi du jour où il
      // appuie, et croirait avoir encaissé ça aujourd'hui.
      final attendue = Periode.hier.intitule();
      expect(find.textContaining(attendue), findsOneWidget);
    });
  });
}
