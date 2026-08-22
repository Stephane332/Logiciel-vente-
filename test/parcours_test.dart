/// Tests des parcours de vente.
///
/// Un seul concept — la vente — traverse trois moments : commander, servir,
/// payer. Ce qui distingue les métiers, c'est l'ordre dans lequel ils les
/// enchaînent. Ces tests vérifient que le même modèle porte les six parcours.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  late BaseLocale base;
  late Journal journal;
  late Depot depot;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    journal = Journal(base, appareil: 'CAISSE1');
    depot = Depot(base, journal);
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  LigneAEnregistrer ligne(String code, String nom, num prix, {num quantite = 1}) =>
      LigneAEnregistrer(
        codeArticle: code,
        designation: nom,
        prixUnitaire: f(prix),
        quantite: Quantite.depuisDecimal(quantite),
      );

  Future<LigneVente> venteDe(String id) =>
      (base.select(base.ventes)..where((v) => v.id.equals(id))).getSingle();

  group('Comptoir — boutique', () {
    test('les trois moments tiennent en un seul geste', () async {
      final id = await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz', 650)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(650))
        ],
      );

      final vente = await venteDe(id);
      expect(vente.etat, EtatVente.soldee.cle);
      expect(vente.contenant, isNull);
      expect(vente.totalCentimes, 65000);
    });
  });

  group('Note ouverte — restaurant', () {
    test('une table se remplit au fil du repas', () async {
      final table = await depot.ouvrirVente(
        contenant: 'Table 4',
        typeContenant: TypeContenant.table,
      );

      expect((await venteDe(table)).etat, EtatVente.ouverte.cle);
      expect((await venteDe(table)).totalCentimes, 0);

      await depot.ajouterAVente(table, [ligne('RIZGRAS', 'Riz gras', 1500)]);
      expect((await venteDe(table)).totalCentimes, 150000);

      // Le serveur revient avec une boisson.
      await depot.ajouterAVente(table, [ligne('EAU', 'Eau', 500, quantite: 2)]);
      expect((await venteDe(table)).totalCentimes, 250000);

      // Puis on encaisse.
      await depot.solder(table, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(2500))
      ]);

      final vente = await venteDe(table);
      expect(vente.etat, EtatVente.soldee.cle);
      expect(vente.contenant, 'Table 4');
      expect(vente.typeContenant, TypeContenant.table.cle);
    });

    test('les tables en cours se retrouvent', () async {
      await depot.ouvrirVente(
          contenant: 'Table 1', typeContenant: TypeContenant.table);
      final table2 = await depot.ouvrirVente(
          contenant: 'Table 2', typeContenant: TypeContenant.table);
      await depot.ajouterAVente(table2, [ligne('TO', 'Tô', 500)]);
      await depot.solder(table2, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
      ]);

      final ouvertes = await depot.ventesOuvertes();
      expect(ouvertes.map((v) => v.contenant), ['Table 1']);
    });

    test('on ne peut pas ajouter à une vente déjà soldée', () async {
      final table = await depot.ouvrirVente(
          contenant: 'Table 3', typeContenant: TypeContenant.table);
      await depot.ajouterAVente(table, [ligne('TO', 'Tô', 500)]);
      await depot.solder(table, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
      ]);

      expect(
        () => depot.ajouterAVente(table, [ligne('EAU', 'Eau', 200)]),
        throwsA(isA<StateError>()),
      );
    });

    test('un règlement partagé entre deux modes est enregistré', () async {
      final table = await depot.ouvrirVente(
          contenant: 'Table 5', typeContenant: TypeContenant.table);
      await depot.ajouterAVente(table, [ligne('PLAT', 'Plat', 3000)]);

      await depot.solder(table, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(1000)),
        PaiementAEnregistrer(
            mode: ModePaiement.mobileMoney, montant: f(2000)),
      ]);

      final reglements = await (base.select(base.paiements)
            ..where((p) => p.venteId.equals(table)))
          .get();
      expect(reglements, hasLength(2));
      expect(
        reglements.fold(0, (s, p) => s + p.montantCentimes),
        (await venteDe(table)).totalCentimes,
      );
    });
  });

  group('À emporter — fast-food', () {
    test('on paie avant de servir', () async {
      final commande = await depot.ouvrirVente(
        contenant: '12',
        typeContenant: TypeContenant.ticket,
      );
      await depot.ajouterAVente(commande, [ligne('BURGER', 'Burger', 2000)]);
      await depot.solder(commande, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(2000))
      ]);

      final vente = await venteDe(commande);
      expect(vente.etat, EtatVente.soldee.cle);
      expect(vente.typeContenant, TypeContenant.ticket.cle);
      expect(vente.contenant, '12');
    });
  });

  group('Crédit — servi mais pas payé', () {
    test('une vente servie reste à encaisser', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      final vente = await depot.ouvrirVente(
        clientId: awa,
        contenant: 'Awa',
        typeContenant: TypeContenant.client,
      );
      await depot.ajouterAVente(vente, [ligne('RIZ', 'Riz', 5000)]);
      await depot.marquerServie(vente);

      expect((await venteDe(vente)).etat, EtatVente.servie.cle);
      expect((await depot.ventesAEncaisser()).map((v) => v.id), [vente]);
      expect(await depot.ventesOuvertes(), isEmpty);

      // Le client règle plus tard.
      await depot.solder(vente, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(5000))
      ]);
      expect(await depot.ventesAEncaisser(), isEmpty);
    });

    test("solder à crédit alimente l'encours du client", () async {
      final awa = await depot.creerClient(nom: 'Awa');
      final vente = await depot.ouvrirVente(clientId: awa);
      await depot.ajouterAVente(vente, [ligne('RIZ', 'Riz', 3000)]);
      await depot.solder(vente, [
        PaiementAEnregistrer(mode: ModePaiement.credit, montant: f(3000))
      ]);

      final debiteurs = await depot.clientsDebiteurs();
      expect(Montant(debiteurs.single.encoursCentimes), f(3000));
    });
  });

  group('Réservation — acompte puis solde', () {
    test('un acompte puis le reste', () async {
      final client = await depot.creerClient(nom: 'Ali', telephone: '70998877');
      final reservation = await depot.ouvrirVente(
        clientId: client,
        contenant: 'Ali · 70998877',
        typeContenant: TypeContenant.client,
      );
      await depot.ajouterAVente(reservation, [ligne('SALLE', 'Salle', 50000)]);

      // Arrhes à la réservation.
      await depot.solder(reservation, [
        PaiementAEnregistrer(mode: ModePaiement.mobileMoney, montant: f(20000)),
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(30000)),
      ]);

      final reglements = await (base.select(base.paiements)
            ..where((p) => p.venteId.equals(reservation)))
          .get();
      expect(reglements.fold(0, (s, p) => s + p.montantCentimes), 5000000);
    });
  });

  group('Journal et rejeu', () {
    test('un parcours en plusieurs temps reste vérifiable', () async {
      final table = await depot.ouvrirVente(
          contenant: 'Table 7', typeContenant: TypeContenant.table);
      await depot.ajouterAVente(table, [ligne('TO', 'Tô', 500)]);
      await depot.ajouterAVente(table, [ligne('EAU', 'Eau', 200)]);
      await depot.solder(table, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(700))
      ]);

      expect((await journal.verifier()).intact, isTrue);
    });

    test('le rejeu du journal restitue les états et les contenants', () async {
      final table = await depot.ouvrirVente(
          contenant: 'Table 9', typeContenant: TypeContenant.table);
      await depot.ajouterAVente(table, [ligne('TO', 'Tô', 500, quantite: 2)]);
      await depot.ajouterAVente(table, [ligne('EAU', 'Eau', 200)]);
      await depot.solder(table, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(1200))
      ]);

      final ouverte = await depot.ouvrirVente(
          contenant: 'Table 10', typeContenant: TypeContenant.table);
      await depot.ajouterAVente(ouverte, [ligne('TO', 'Tô', 500)]);

      final avant = await venteDe(table);

      await depot.reconstruireProjections();

      final apres = await venteDe(table);
      expect(apres.etat, avant.etat);
      expect(apres.contenant, avant.contenant);
      expect(apres.typeContenant, avant.typeContenant);
      expect(apres.totalCentimes, avant.totalCentimes);

      // La table encore ouverte l'est toujours après rejeu.
      expect((await depot.ventesOuvertes()).map((v) => v.id), [ouverte]);

      // Et les lignes ne se sont pas dupliquées.
      final lignes = await (base.select(base.lignesVente)
            ..where((l) => l.venteId.equals(table)))
          .get();
      expect(lignes, hasLength(2));
    });
  });
}
