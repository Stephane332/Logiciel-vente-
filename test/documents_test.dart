/// Tests des documents destinés au client.
///
/// Ces textes partent par WhatsApp ou par SMS sur le téléphone d'un client
/// qui n'a rien installé. Ils doivent être justes, courts et lisibles sur un
/// petit écran.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/document_client.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Documents documents;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    documents = Documents(base, nomCommerce: 'Chez Awa');
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  LigneAEnregistrer ligne(String code, String nom, num prix,
          {num quantite = 1}) =>
      LigneAEnregistrer(
        codeArticle: code,
        designation: nom,
        prixUnitaire: f(prix),
        quantite: Quantite.depuisDecimal(quantite),
      );

  final quand = DateTime(2026, 8, 5, 14, 32);

  group('Reçu au comptoir', () {
    test('porte le commerce, la date, les lignes et le total', () async {
      final id = await depot.enregistrerVente(
        lignes: [
          ligne('RIZ', 'Riz 1 kg', 650, quantite: 2),
          ligne('HUILE', 'Huile 1 L', 1200),
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(2500))
        ],
        horodatage: quand,
      );

      final recu = (await documents.pourVente(id))!;
      final texte = recu.texte;

      expect(recu.nature, NatureDocument.recu);
      expect(texte, contains('CHEZ AWA'));
      expect(texte, contains('05/08/2026 à 14h32'));
      expect(texte, contains('Riz 1 kg'));
      expect(texte, contains('1 300 F'));
      expect(texte, contains('Huile 1 L'));
      expect(texte, contains('2 500 F'));
      expect(texte, contains('Payé en espèces'));
      expect(texte, contains('Merci !'));
    });

    test('nomme les deux modes quand le règlement est partagé', () async {
      final id = await depot.enregistrerVente(
        lignes: [ligne('PLAT', 'Plat', 3000)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(1000)),
          PaiementAEnregistrer(
              mode: ModePaiement.mobileMoney, montant: f(2000)),
        ],
        horodatage: quand,
      );

      final recu = (await documents.pourVente(id))!;
      expect(recu.texte, contains('espèces et mobile money'));
    });

    test('reste lisible sur un petit écran', () async {
      final id = await depot.enregistrerVente(
        lignes: [
          ligne('LONG', 'Sachet de riz parfumé importé qualité supérieure',
              12500, quantite: 3),
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(37500))
        ],
        horodatage: quand,
      );

      final recu = (await documents.pourVente(id))!;
      for (final ligne in recu.texte.split('\n')) {
        expect(ligne.length, lessThanOrEqualTo(40),
            reason: 'ligne trop longue : « $ligne »');
      }
      // Le montant reste présent malgré la troncature du libellé.
      expect(recu.texte, contains('37 500 F'));
    });
  });

  group('Note ouverte au restaurant', () {
    test('montre la table et ce qui reste à payer', () async {
      final table = await depot.ouvrirVente(
        contenant: 'Table 4',
        typeContenant: TypeContenant.table,
        horodatage: quand,
      );
      await depot.ajouterAVente(table, [ligne('RIZGRAS', 'Riz gras', 1500)]);
      await depot.ajouterAVente(
          table, [ligne('EAU', 'Eau', 500, quantite: 2)]);

      final note = (await documents.pourVente(table))!;
      final texte = note.texte;

      expect(note.nature, NatureDocument.note);
      expect(texte, contains('Table 4'));
      expect(texte, contains('Riz gras'));
      expect(texte, contains('Eau'));
      expect(texte, contains('2 500 F'));
      // Rien n'est encore réglé : « À payer » suffit, et le montant
      // n'apparaît qu'une fois.
      expect(texte, contains('À payer'));
      expect(texte, isNot(contains('Total')));
      expect(texte, contains('Bon appétit'));
    });

    test('devient un reçu une fois la note soldée', () async {
      final table = await depot.ouvrirVente(
          contenant: 'Table 4', horodatage: quand);
      await depot.ajouterAVente(table, [ligne('TO', 'Tô', 500)]);
      await depot.solder(table, [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
      ]);

      final document = (await documents.pourVente(table))!;
      expect(document.nature, NatureDocument.recu);
      expect(document.estSolde, isTrue);
      expect(document.texte, isNot(contains('Reste à payer')));
      expect(document.texte, contains('Payé en espèces'));
    });
  });

  group('Ardoise', () {
    test('dit ce que le client doit, et depuis quand', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');

      await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz', 2000)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.credit, montant: f(2000))
        ],
        clientId: awa,
        horodatage: DateTime(2026, 7, 12, 9),
      );
      await depot.enregistrerVente(
        lignes: [ligne('HUILE', 'Huile', 1500)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.credit, montant: f(1500))
        ],
        clientId: awa,
        horodatage: DateTime(2026, 7, 20, 9),
      );
      await depot.rembourserCredit(awa, f(500));

      final ardoise = (await documents.ardoise(awa, arreteeAu: quand))!;
      final texte = ardoise.texte;

      expect(ardoise.encours, f(3000));
      expect(texte, contains('CHEZ AWA'));
      expect(texte, contains('Ardoise de Awa'));
      expect(texte, contains('Tu dois : 3 000 F'));
      expect(texte, contains('Depuis le 12/07/2026'));
      expect(texte, contains('2 achats à crédit'));
      expect(texte, contains('1 remboursement'));
      expect(texte, contains('Arrêté au 05/08/2026'));
      expect(texte, contains('Réponds à ce message'));
    });

    test('une ardoise soldée le dit simplement', () async {
      final ali = await depot.creerClient(nom: 'Ali');
      await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz', 1000)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.credit, montant: f(1000))
        ],
        clientId: ali,
        horodatage: quand,
      );
      await depot.rembourserCredit(ali, f(1000));

      final ardoise = (await documents.ardoise(ali, arreteeAu: quand))!;
      expect(ardoise.estSoldee, isTrue);
      expect(ardoise.texte, contains('Tu ne dois plus rien'));
      expect(ardoise.texte, isNot(contains('Tu dois :')));
    });

    test('un client inconnu ne renvoie rien', () async {
      expect(await documents.ardoise('INEXISTANT'), isNull);
    });
  });

  group('Lisibilité', () {
    test('aucun document ne dépasse la largeur d\'un petit écran', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');

      final comptoir = await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz 1 kg', 650, quantite: 2)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(1300))
        ],
        horodatage: quand,
      );
      final table = await depot.ouvrirVente(
          contenant: 'Table 12', typeContenant: TypeContenant.table,
          horodatage: quand);
      await depot.ajouterAVente(
          table, [ligne('RG', 'Riz gras poulet', 1500, quantite: 2)]);
      final credit = await depot.enregistrerVente(
        lignes: [ligne('SAC', 'Sac de riz 50 kg', 25000)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(10000)),
          PaiementAEnregistrer(mode: ModePaiement.credit, montant: f(15000)),
        ],
        clientId: awa,
        horodatage: quand,
      );

      final textes = <String>[
        (await documents.pourVente(comptoir))!.texte,
        (await documents.pourVente(table))!.texte,
        (await documents.pourVente(credit))!.texte,
        (await documents.ardoise(awa, arreteeAu: quand))!.texte,
      ];

      for (final texte in textes) {
        for (final ligne in texte.split('\n')) {
          expect(ligne.length, lessThanOrEqualTo(40),
              reason: 'ligne trop longue : « $ligne »');
        }
      }
    });

    test('un règlement partiel montre les trois montants', () async {
      final awa = await depot.creerClient(nom: 'Awa');
      final id = await depot.enregistrerVente(
        lignes: [ligne('SAC', 'Sac de riz', 25000)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(10000)),
          PaiementAEnregistrer(mode: ModePaiement.credit, montant: f(15000)),
        ],
        clientId: awa,
        horodatage: quand,
      );

      final texte = (await documents.pourVente(id))!.texte;
      expect(texte, contains('Total'));
      expect(texte, contains('Déjà payé'));
      expect(texte, contains('Reste à payer'));
    });
  });

  group('Cas limites', () {
    test('une vente inconnue ne renvoie rien', () async {
      expect(await documents.pourVente('INEXISTANT'), isNull);
    });

    test('une vente à crédit affiche le reste dû, pas « payé »', () async {
      final awa = await depot.creerClient(nom: 'Awa');
      final id = await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz', 2000)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.credit, montant: f(2000))
        ],
        clientId: awa,
        horodatage: quand,
      );

      final document = (await documents.pourVente(id))!;
      expect(document.estSolde, isFalse);
      expect(document.texte, contains('À payer'));
      expect(document.texte, isNot(contains('Payé en')));
    });
  });
}
