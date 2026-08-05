/// Tests du journal et du dépôt.
///
/// Le journal étant la source de vérité, ces tests portent sur ses trois
/// promesses : rien ne se perd, rien ne se modifie sans être détecté, et
/// l'état courant est toujours reconstructible à partir de lui.
library;

// `show Value` : drift exporte aussi un `isNull`, qui entre en collision avec
// celui de matcher.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/evenements.dart';
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

  Future<String> vendre(
    num prix, {
    num quantite = 1,
    String? code,
    String? nom,
    ModePaiement mode = ModePaiement.especes,
    String? clientId,
    num? prixCatalogue,
    DateTime? quand,
  }) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: code,
            designation: nom,
            prixUnitaire: f(prix),
            quantite: Quantite.depuisDecimal(quantite),
            prixCatalogue: prixCatalogue == null ? null : f(prixCatalogue),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
              mode: mode, montant: f(prix).multiplieParQuantite(
                  Quantite.depuisDecimal(quantite)))
        ],
        clientId: clientId,
        horodatage: quand,
      );

  group('Journal', () {
    test('les séquences se suivent sans trou', () async {
      for (var i = 0; i < 5; i++) {
        await journal.ajouter(TypeEvenement.caisseMouvement, {'n': i});
      }

      final evenements = await journal.tous();
      expect(evenements.map((e) => e.sequence), [1, 2, 3, 4, 5]);
    });

    test('chaque événement est chaîné au précédent', () async {
      await journal.ajouter(TypeEvenement.caisseMouvement, {'n': 1});
      await journal.ajouter(TypeEvenement.caisseMouvement, {'n': 2});

      final evenements = await journal.tous();
      expect(evenements.first.empreintePrecedente, isNull);
      expect(evenements.last.empreintePrecedente, evenements.first.empreinte);
    });

    test('les identifiants sont triés par ordre chronologique', () async {
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        final e = await journal.ajouter(TypeEvenement.caisseMouvement, {'n': i});
        ids.add(e.id);
      }
      expect(ids, orderedEquals(List.of(ids)..sort()));
    });

    test('un journal intact est reconnu comme tel', () async {
      await vendre(650);
      await vendre(1200);

      final verification = await journal.verifier();
      expect(verification.intact, isTrue);
      expect(verification.nombreEvenements, 2);
    });

    test('un journal vide est intact', () async {
      final verification = await journal.verifier();
      expect(verification.intact, isTrue);
      expect(verification.nombreEvenements, 0);
    });

    test('modifier un événement écrit est détecté', () async {
      await vendre(650);
      await vendre(1200);
      await vendre(300);

      // Falsification directe en base, comme le ferait quelqu'un qui veut
      // effacer une vente de sa comptabilité.
      final cible = (await journal.tous())[1];
      await (base.update(base.evenements)..where((e) => e.id.equals(cible.id)))
          .write(const EvenementsCompanion(charge: Value('{"total":0}')));

      final verification = await journal.verifier();
      expect(verification.intact, isFalse);
      expect(verification.premierFautif, cible.id);
      expect(verification.motif, contains('modifié'));
    });

    test('supprimer un événement est détecté', () async {
      await vendre(650);
      await vendre(1200);
      await vendre(300);

      final cible = (await journal.tous())[1];
      await (base.delete(base.evenements)..where((e) => e.id.equals(cible.id)))
          .go();

      final verification = await journal.verifier();
      expect(verification.intact, isFalse);
      expect(verification.motif, contains('manquent'));
    });

    test('la file de synchronisation se vide quand on la marque', () async {
      await vendre(650);
      await vendre(1200);

      var enAttente = await journal.enAttenteDeSynchronisation();
      expect(enAttente, hasLength(2));

      await journal.marquerSynchronises(enAttente.map((e) => e.id));

      enAttente = await journal.enAttenteDeSynchronisation();
      expect(enAttente, isEmpty);

      // Marquer la synchronisation ne doit pas casser la chaîne : cette
      // colonne ne participe pas au calcul de l'empreinte.
      expect((await journal.verifier()).intact, isTrue);
    });
  });

  group('Catalogue auto-construit', () {
    test('une vente à montant libre crée un article sans nom', () async {
      await vendre(500);

      final catalogue = await depot.catalogue();
      expect(catalogue, hasLength(1));
      expect(catalogue.single.nomme, isFalse);
      expect(catalogue.single.nombreVentes, 1);
      expect(catalogue.single.prixCentimes, 50000);
    });

    test('le même prix répété alimente le même article', () async {
      await vendre(500);
      await vendre(500);
      await vendre(500);

      final catalogue = await depot.catalogue();
      expect(catalogue, hasLength(1));
      expect(catalogue.single.nombreVentes, 3);
    });

    test('au bout de trois ventes, on propose de le nommer', () async {
      await vendre(500);
      await vendre(500);
      expect(await depot.articlesANommer(), isEmpty);

      await vendre(500);
      final aNommer = await depot.articlesANommer();
      expect(aNommer, hasLength(1));
      expect(aNommer.single.code, 'AUTO-50000');
    });

    test('nommer un article le sort de la liste des propositions', () async {
      await vendre(500);
      await vendre(500);
      await vendre(500);

      await depot.nommerArticle('AUTO-50000', 'Sachet d\'eau');

      expect(await depot.articlesANommer(), isEmpty);
      final catalogue = await depot.catalogue();
      expect(catalogue.single.designation, 'Sachet d\'eau');
      expect(catalogue.single.nomme, isTrue);
    });

    test('un article nommé dès la vente ne demande rien', () async {
      await vendre(650, code: 'RIZ', nom: 'Riz 1 kg');
      await vendre(650, code: 'RIZ', nom: 'Riz 1 kg');
      await vendre(650, code: 'RIZ', nom: 'Riz 1 kg');

      expect(await depot.articlesANommer(), isEmpty);
      expect((await depot.catalogue()).single.nomme, isTrue);
    });

    test('le catalogue met les plus vendus en tête', () async {
      await vendre(650, code: 'RIZ', nom: 'Riz');
      await vendre(300, code: 'SAVON', nom: 'Savon');
      await vendre(300, code: 'SAVON', nom: 'Savon');

      final catalogue = await depot.catalogue();
      expect(catalogue.first.code, 'SAVON');
    });
  });

  group('Stock', () {
    test("le stock n'est pas suivi tant qu'il n'est pas déclaré", () async {
      await vendre(650, code: 'RIZ', nom: 'Riz');
      expect((await depot.catalogue()).single.stockMilliemes, isNull);
    });

    test('une fois déclaré, il se décrémente à chaque vente', () async {
      await vendre(650, code: 'RIZ', nom: 'Riz');
      await depot.ajusterStock('RIZ', const Quantite.unites(10));

      await vendre(650, code: 'RIZ', quantite: 3);

      expect((await depot.catalogue()).single.stockMilliemes, 7000);
    });
  });

  group('Crédit client', () {
    test("une vente à crédit alimente l'encours", () async {
      final client = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await vendre(1500, mode: ModePaiement.credit, clientId: client);

      final debiteurs = await depot.clientsDebiteurs();
      expect(debiteurs, hasLength(1));
      expect(debiteurs.single.nom, 'Awa');
      expect(Montant(debiteurs.single.encoursCentimes), f(1500));
    });

    test('un remboursement réduit la dette', () async {
      final client = await depot.creerClient(nom: 'Awa');
      await vendre(1500, mode: ModePaiement.credit, clientId: client);
      await depot.rembourserCredit(client, f(1000));

      final debiteurs = await depot.clientsDebiteurs();
      expect(Montant(debiteurs.single.encoursCentimes), f(500));
    });

    test('une dette soldée sort de la liste', () async {
      final client = await depot.creerClient(nom: 'Awa');
      await vendre(1500, mode: ModePaiement.credit, clientId: client);
      await depot.rembourserCredit(client, f(1500));

      expect(await depot.clientsDebiteurs(), isEmpty);
    });

    test('une vente comptant ne crée aucune dette', () async {
      final client = await depot.creerClient(nom: 'Awa');
      await vendre(1500, clientId: client);

      expect(await depot.clientsDebiteurs(), isEmpty);
    });
  });

  group('Rapport du jour', () {
    test('sépare ce qui est encaissé de ce qui part à crédit', () async {
      final client = await depot.creerClient(nom: 'Awa');
      await vendre(1000);
      await vendre(500);
      await vendre(2000, mode: ModePaiement.credit, clientId: client);

      final rapport = await depot.rapportDuJour();
      expect(rapport.encaisse, f(1500));
      expect(rapport.aCredit, f(2000));
      expect(rapport.nombreVentes, 3);
    });

    test('ne compte pas les ventes des autres jours', () async {
      await vendre(1000, quand: DateTime.now().subtract(const Duration(days: 2)));
      await vendre(500);

      final rapport = await depot.rapportDuJour();
      expect(rapport.nombreVentes, 1);
      expect(rapport.encaisse, f(500));
    });

    test('totalise les remises accordées', () async {
      await vendre(800, code: 'RIZ', nom: 'Riz', prixCatalogue: 1000);
      await vendre(900, code: 'RIZ', prixCatalogue: 1000);

      final rapport = await depot.rapportDuJour();
      expect(rapport.remisesAccordees, f(300));
    });

    test('compte les articles en rupture', () async {
      await vendre(650, code: 'RIZ', nom: 'Riz');
      await depot.ajusterStock('RIZ', const Quantite.unites(2));
      await vendre(650, code: 'RIZ', quantite: 2);

      final rapport = await depot.rapportDuJour();
      expect(rapport.articlesEnRupture, 1);
    });
  });

  group('Reconstruction depuis le journal', () {
    test('rejouer le journal redonne exactement le même état', () async {
      final client = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await vendre(650, code: 'RIZ', nom: 'Riz 1 kg');
      await vendre(650, code: 'RIZ');
      await vendre(500);
      await vendre(500);
      await vendre(500);
      await depot.nommerArticle('AUTO-50000', 'Sachet d\'eau');
      await depot.ajusterStock('RIZ', const Quantite.unites(8));
      await vendre(2000, mode: ModePaiement.credit, clientId: client);
      await depot.rembourserCredit(client, f(500));

      final avant = await depot.rapportDuJour();
      final catalogueAvant = await depot.catalogue();
      final debiteursAvant = await depot.clientsDebiteurs();

      await depot.reconstruireProjections();

      final apres = await depot.rapportDuJour();
      expect(apres.encaisse, avant.encaisse);
      expect(apres.aCredit, avant.aCredit);
      expect(apres.nombreVentes, avant.nombreVentes);

      final catalogueApres = await depot.catalogue();
      expect(catalogueApres.map((a) => a.code), catalogueAvant.map((a) => a.code));
      expect(catalogueApres.map((a) => a.designation),
          catalogueAvant.map((a) => a.designation));
      expect(catalogueApres.map((a) => a.nombreVentes),
          catalogueAvant.map((a) => a.nombreVentes));
      expect(catalogueApres.map((a) => a.stockMilliemes),
          catalogueAvant.map((a) => a.stockMilliemes));

      final debiteursApres = await depot.clientsDebiteurs();
      expect(debiteursApres.map((c) => c.encoursCentimes),
          debiteursAvant.map((c) => c.encoursCentimes));
    });

    test('le journal survit intact à une reconstruction', () async {
      await vendre(650);
      await vendre(1200);
      final avant = (await journal.tous()).map((e) => e.empreinte).toList();

      await depot.reconstruireProjections();

      final apres = (await journal.tous()).map((e) => e.empreinte).toList();
      expect(apres, avant);
      expect((await journal.verifier()).intact, isTrue);
    });
  });
}
