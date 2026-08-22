/// Tests de l'identité client et de l'historique d'achats.
///
/// L'identité repose sur le numéro de téléphone, seule référence stable
/// d'une personne ici. Le consentement à ce que l'historique suive le client
/// d'une boutique à l'autre est un accord distinct, et daté.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/domaine/telephone.dart';
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

  Future<void> acheter(
    String clientId,
    String nom,
    num prix, {
    DateTime? quand,
    ModePaiement mode = ModePaiement.especes,
    List<String> autres = const [],
  }) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: nom.toUpperCase(),
            designation: nom,
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          ),
          for (final autre in autres)
            LigneAEnregistrer(
              codeArticle: autre.toUpperCase(),
              designation: autre,
              prixUnitaire: f(100),
              quantite: const Quantite.unites(1),
            ),
        ],
        paiements: [
          PaiementAEnregistrer(
              mode: mode, montant: f(prix + 100 * autres.length))
        ],
        clientId: clientId,
        horodatage: quand,
      );

  group('Normalisation du numéro', () {
    test('toutes les écritures usuelles donnent le même numéro', () {
      for (final saisie in [
        '70112233',
        '70 11 22 33',
        '+226 70 11 22 33',
        '+22670112233',
        '0022670112233',
        '226-70-11-22-33',
      ]) {
        expect(normaliserTelephone(saisie), '70112233',
            reason: 'échec sur « $saisie »');
      }
    });

    test('un numéro implausible est refusé plutôt que deviné', () {
      // Mieux vaut ne rien enregistrer qu'une identité fausse.
      expect(normaliserTelephone('123'), isNull);
      expect(normaliserTelephone('123456789012'), isNull);
      expect(normaliserTelephone('90112233'), isNull); // préfixe inexistant
      expect(normaliserTelephone(''), isNull);
      expect(normaliserTelephone(null), isNull);
    });

    test('les mobiles et les fixes sont acceptés', () {
      expect(normaliserTelephone('70112233'), '70112233'); // mobile
      expect(normaliserTelephone('60112233'), '60112233'); // mobile
      expect(normaliserTelephone('50112233'), '50112233'); // mobile
      expect(normaliserTelephone('25301122'), '25301122'); // fixe
    });

    test("s'affiche par groupes de deux", () {
      expect(presenterTelephone('70112233'), '70 11 22 33');
    });
  });

  group('Reconnaissance du client', () {
    test('un client se retrouve quelle que soit la saisie', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70 11 22 33');

      for (final saisie in ['70112233', '+22670112233', '70 11 22 33']) {
        final trouve = await depot.clientParTelephone(saisie);
        expect(trouve?.id, awa, reason: 'échec sur « $saisie »');
      }
    });

    test('un numéro inconnu ne renvoie rien', () async {
      await depot.creerClient(nom: 'Awa', telephone: '70112233');
      expect(await depot.clientParTelephone('60998877'), isNull);
    });

    test('un client sans numéro reste anonyme', () async {
      await depot.creerClient(nom: 'Passant');
      expect(await depot.clientParTelephone('70112233'), isNull);
    });
  });

  group('Consentement', () {
    test("n'est pas donné du seul fait d'avoir laissé un numéro", () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      final client = await depot.clientParTelephone('70112233');

      expect(client!.telephoneNormalise, '70112233');
      // Donner son numéro pour un reçu n'est pas consentir à un profil.
      expect(client.consentementLe, isNull);
      expect(awa, isNotEmpty);
    });

    test('une fois donné, il est daté', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await depot.enregistrerConsentement(awa);

      final client = await depot.clientParTelephone('70112233');
      expect(client!.consentementLe, isNotNull);
    });

    test('il survit au rejeu du journal', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await depot.enregistrerConsentement(awa);
      final avant = (await depot.clientParTelephone('70112233'))!.consentementLe;

      await depot.reconstruireProjections();

      final apres = (await depot.clientParTelephone('70112233'))!;
      expect(apres.consentementLe, avant);
      expect(apres.telephoneNormalise, '70112233');
    });
  });

  group('Historique des achats', () {
    final maintenant = DateTime(2026, 8, 5, 12);

    test('liste les achats du plus récent au plus ancien', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await acheter(awa, 'Riz', 2000, quand: DateTime(2026, 7, 10));
      await acheter(awa, 'Huile', 1500, quand: DateTime(2026, 7, 25));
      await acheter(awa, 'Savon', 500, quand: DateTime(2026, 8, 2));

      final historique =
          (await documents.historique(awa, jusqua: maintenant))!;

      expect(historique.achats, hasLength(3));
      expect(historique.achats.first.montant, f(500));
      expect(historique.achats.last.montant, f(2000));
      expect(historique.total, f(4000));
    });

    test('abrège une vente à plusieurs articles', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await acheter(awa, 'Riz', 2000,
          quand: DateTime(2026, 8, 2), autres: ['Savon', 'Eau']);

      final historique =
          (await documents.historique(awa, jusqua: maintenant))!;
      expect(historique.achats.single.resume, 'Riz +2');
    });

    test('signale ce qui reste dû', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await acheter(awa, 'Riz', 2000,
          quand: DateTime(2026, 8, 2), mode: ModePaiement.credit);

      final historique =
          (await documents.historique(awa, jusqua: maintenant))!;
      expect(historique.encours, f(2000));
      expect(historique.texte, contains('Reste à payer'));
    });

    test('reste lisible sur un petit écran', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await acheter(awa, 'Sac de riz parfumé importé 50 kg', 25000,
          quand: DateTime(2026, 8, 2), autres: ['Savon', 'Eau', 'Sucre']);

      final historique =
          (await documents.historique(awa, jusqua: maintenant))!;
      for (final ligne in historique.texte.split('\n')) {
        expect(ligne.length, lessThanOrEqualTo(40),
            reason: 'ligne trop longue : « $ligne »');
      }
    });

    test('une période sans achat le dit', () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      await acheter(awa, 'Riz', 2000, quand: DateTime(2025, 1, 10));

      final historique = (await documents.historique(
        awa,
        depuis: DateTime(2026, 1, 1),
        jusqua: maintenant,
      ))!;

      expect(historique.achats, isEmpty);
      expect(historique.texte, contains('Aucun achat'));
    });

    test("ne mélange jamais les clients", () async {
      final awa = await depot.creerClient(nom: 'Awa', telephone: '70112233');
      final ali = await depot.creerClient(nom: 'Ali', telephone: '60998877');
      await acheter(awa, 'Riz', 2000, quand: DateTime(2026, 8, 2));
      await acheter(ali, 'Huile', 1500, quand: DateTime(2026, 8, 2));

      final historique =
          (await documents.historique(awa, jusqua: maintenant))!;
      expect(historique.achats, hasLength(1));
      expect(historique.total, f(2000));
      expect(historique.nomClient, 'Awa');
    });
  });
}
