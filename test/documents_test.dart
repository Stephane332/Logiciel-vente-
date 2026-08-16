/// Tests des documents destinés au client.
///
/// Ces textes partent par WhatsApp ou par SMS sur le téléphone d'un client
/// qui n'a rien installé. Ils doivent être justes, courts et lisibles sur un
/// petit écran.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/document_client.dart';
import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/domaine/ticket_escpos.dart';
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

  group('Rapport du soir', () {
    RapportDuJour chiffres({
      num encaisse = 0,
      num credit = 0,
      num remises = 0,
      int ventes = 0,
    }) =>
        RapportDuJour(
          encaisse: f(encaisse),
          aCredit: f(credit),
          remisesAccordees: f(remises),
          nombreVentes: ventes,
          articlesEnRupture: 0,
        );

    test('une journée ordinaire tient en quelques lignes alignées', () {
      final texte = documents
          .rapportDuSoir(
            rapport: chiffres(encaisse: 145000, credit: 32000, ventes: 27),
            date: quand,
          )
          .texte;

      expect(texte, contains('CHEZ AWA'));
      expect(texte, contains('Journée du 05/08/2026'));
      // Chaque montant tombe sur la même colonne, comme sur un ticket.
      for (final ligne in texte
          .split('\n')
          .where((l) => l.contains(' F') && l.contains(' '))) {
        expect(ligne.length, 38);
      }
      expect(texte, contains('Rien à racheter.'));
    });

    test('ce qui ne bouge pas ne s\'affiche pas', () {
      final texte = documents.rapportDuSoir(rapport: chiffres()).texte;

      expect(texte, isNot(contains('À crédit')));
      expect(texte, isNot(contains('Remises')));
    });

    test('les alertes de stock arrivent telles que les analyses les disent',
        () {
      final texte = documents
          .rapportDuSoir(
            rapport: chiffres(encaisse: 5000, ventes: 3),
            aRacheter: const ['Riz 1 kg — rupture', 'Huile — il te reste 2 jours'],
          )
          .texte;

      expect(texte, contains('À racheter :'));
      expect(texte, contains('· Riz 1 kg — rupture'));
      expect(texte, contains('· Huile — il te reste 2 jours'));
    });
  });

  group('Qui a servi', () {
    Future<String> recuAvec({String? vendeur}) async {
      final id = await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz 1 kg', 650)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(650))
        ],
        operateur: vendeur,
        horodatage: quand,
      );
      return (await documents.pourVente(id))!.texte;
    }

    test('le nom du vendeur figure sur le reçu', () async {
      expect(await recuAvec(vendeur: 'Awa'), contains('Servi par Awa'));
    });

    test("rien ne s'ajoute quand le commerçant vend seul", () async {
      expect(await recuAvec(), isNot(contains('Servi par')));
    });

    test('un nom vide ne laisse pas une ligne orpheline', () async {
      expect(await recuAvec(vendeur: '   '), isNot(contains('Servi par')));
    });

    test('le nom arrive avant le détail, pas après le total', () async {
      final texte = await recuAvec(vendeur: 'Issouf');
      expect(texte.indexOf('Servi par Issouf'),
          lessThan(texte.indexOf('Riz 1 kg')));
    });

    // La note de service n° 2025-0889 range le nom de l'opérateur parmi les
    // mentions obligatoires de la facture (§3, mention 25). Le journal le
    // portait déjà ; ce test garde le chemin jusqu'au client.
    test('la mention 25 est tenue de bout en bout', () async {
      final id = await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz 1 kg', 650)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(650))
        ],
        operateur: 'Salif',
        horodatage: quand,
      );

      expect((await documents.pourVente(id))!.operateur, 'Salif');

      // Et il y survit à une reconstruction : c'est le journal qui le porte.
      await depot.reconstruireProjections();
      expect((await documents.pourVente(id))!.operateur, 'Salif');
    });
  });

  group("Les mentions de l'entreprise", () {
    Future<DocumentClient> recu(Documents fabrique) async {
      final id = await depot.enregistrerVente(
        lignes: [ligne('RIZ', 'Riz 1 kg', 650)],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(650))
        ],
        horodatage: quand,
      );
      return (await fabrique.pourVente(id))!;
    }

    test('un reçu de boutique ne porte que le nom', () async {
      // C'est le cas de la quasi-totalité de mes utilisateurs, et le reçu ne
      // doit pas avoir changé d'un caractère depuis qu'une fiche existe.
      final lignes = (await recu(documents)).texte.split('\n');

      expect(lignes.first, 'CHEZ AWA');
      expect(lignes[1], 'Reçu');
    });

    test('une fiche sans mention fiscale ne change rien non plus', () async {
      // Ouvrir la section sans rien y taper ne doit pas modifier les reçus.
      final lignes = (await recu(Documents(
        base,
        nomCommerce: 'Chez Awa',
        fiche: const FicheEntreprise(nomCommercial: 'Chez Awa'),
      )))
          .texte
          .split('\n');

      expect(lignes[1], 'Reçu');
    });

    test('une entreprise voit ses mentions sur ce que le client emporte',
        () async {
      final texte = (await recu(Documents(
        base,
        nomCommerce: 'Chez Awa',
        fiche: FicheEntreprise(
          nomCommercial: 'Chez Awa',
          ifu: '00012345A',
          adresse: 'Gounghin, Ouagadougou',
          cadastre: ReferenceCadastrale.analyser('12345678901'),
          regime: RegimeImposition.rni,
        ),
      )))
          .texte;

      expect(texte, contains('IFU : 00012345A'));
      expect(texte, contains('Gounghin, Ouagadougou'));
      expect(texte, contains('Parcelle : 1234 567 8901'));
      // Elles précèdent le titre : ce sont des mentions d'en-tête, pas une
      // note de bas de page.
      expect(texte.indexOf('IFU : 00012345A'), lessThan(texte.indexOf('Reçu')));
    });

    test('le papier dit la même chose que le message', () async {
      // Deux versions d'un même reçu qui divergeraient, c'est une
      // contestation gagnée d'avance par le client.
      final document = await recu(Documents(
        base,
        nomCommerce: 'Chez Awa',
        fiche: const FicheEntreprise(
          nomCommercial: 'Chez Awa',
          ifu: '00012345A',
        ),
      ));

      final papier = latin1.decode(
        const TicketEscPos(page: PageDeCode.cp1252).composer(document),
        allowInvalid: true,
      );

      expect(document.texte, contains('IFU : 00012345A'));
      expect(papier, contains('IFU : 00012345A'));
    });
  });
}
