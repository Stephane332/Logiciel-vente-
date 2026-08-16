/// Tests de la sauvegarde et de la restauration.
///
/// C'est la seule fonction de l'application qui peut détruire des données
/// sans retour. Une restauration ratée ne se rattrape pas : le carnet
/// d'avant est déjà effacé.
///
/// Trois règles s'y vérifient, et rien d'autre ne compte autant :
/// un fichier abîmé est refusé **avant** que la base ne soit touchée, une
/// sauvegarde restaurée sur un autre téléphone rend exactement la même
/// boutique, et le fichier suffit à tout reconstruire — projections
/// comprises, puisqu'elles n'y sont pas.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/donnees/sauvegarde.dart';

void main() {
  late BaseLocale base;
  late Journal journal;
  late Depot depot;
  late Parametres parametres;
  late Sauvegardes sauvegardes;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    journal = Journal(base, appareil: 'CAISSE1');
    depot = Depot(base, journal);
    parametres = Parametres(base);
    sauvegardes = Sauvegardes(base, journal, version: '0.6.0');
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Future<String> vendre(num prix, {String? clientId, String? par}) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'RIZ',
            designation: 'Riz 1 kg',
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
            mode: clientId == null ? ModePaiement.especes : ModePaiement.credit,
            montant: f(prix),
          )
        ],
        clientId: clientId,
        operateur: par,
      );

  /// Une boutique qui a vécu : des ventes, un client endetté, des réglages.
  Future<void> garnir() async {
    final client = await depot.creerClient(nom: 'Salif', telephone: '70000000');
    await vendre(650);
    await vendre(1200, clientId: client);
    await depot.creerArticle(designation: 'Savon Omo', prix: f(500));
    await parametres.definirNomCommerce('Alimentation Nabonswendé');
    await parametres.definirVendeurs(['Awa', 'Salif']);
  }

  /// Un second téléphone, vierge, avec son propre identifiant d'appareil.
  (BaseLocale, Depot, Sauvegardes) nouveauTelephone() {
    final autre = BaseLocale(NativeDatabase.memory());
    final sonJournal = Journal(autre, appareil: 'CAISSE2');
    return (
      autre,
      Depot(autre, sonJournal),
      Sauvegardes(autre, sonJournal, version: '0.6.0'),
    );
  }

  group('Composer le fichier', () {
    test('il porte les événements et les réglages, pas les projections',
        () async {
      await garnir();

      final contenu = await sauvegardes.composer(nomCommerce: 'Ma boutique');
      final lu = jsonDecode(contenu) as Map<String, Object?>;

      expect(lu['application'], 'carnet');
      expect(lu['format'], formatSauvegarde);
      expect(lu['version'], '0.6.0');
      expect((lu['evenements'] as List), isNotEmpty);
      expect((lu['reglages'] as Map)['commerce.nom'],
          'Alimentation Nabonswendé');
      // Les tables reconstructibles n'ont rien à faire dans le fichier.
      expect(lu.containsKey('articles'), isFalse);
      expect(lu.containsKey('ventes'), isFalse);
    });

    test('une boutique neuve donne un fichier valide mais vide', () async {
      final ouvert = Sauvegardes.ouvrir(await sauvegardes.composer());

      expect(ouvert, isNotNull);
      expect(ouvert!.apercu.estVide, isTrue);
    });

    test("le nom de fichier se lit d'un coup d'œil", () {
      final nom = Sauvegardes.nomDeFichier(
          'Alimentation Nabonswendé', DateTime(2026, 8, 8, 9, 5));

      expect(nom, 'carnet-alimentation-nabonswend-20260808-0905.carnet');
    });

    test('un commerce sans nom donne quand même un nom de fichier', () {
      expect(Sauvegardes.nomDeFichier('', DateTime(2026, 1, 2, 3, 4)),
          'carnet-boutique-20260102-0304.carnet');
    });
  });

  group('Ouvrir un fichier', () {
    test("ce qui n'est pas du JSON est refusé", () {
      expect(Sauvegardes.ouvrir('bonjour'), isNull);
      expect(Sauvegardes.ouvrir(''), isNull);
    });

    test("le fichier d'une autre application est refusé", () {
      expect(Sauvegardes.ouvrir('{"application":"autre","evenements":[]}'),
          isNull);
    });

    test('un format plus récent est refusé plutôt que mal lu', () {
      // Mieux vaut dire « je ne sais pas lire ça » que restaurer de travers.
      expect(
        Sauvegardes.ouvrir(jsonEncode({
          'application': 'carnet',
          'format': formatSauvegarde + 1,
          'evenements': [],
        })),
        isNull,
      );
    });

    test("l'aperçu annonce ce que porte le fichier", () async {
      await garnir();
      final ouvert = Sauvegardes.ouvrir(
          await sauvegardes.composer(nomCommerce: 'Chez Awa'));

      expect(ouvert!.apercu.nomCommerce, 'Chez Awa');
      expect(ouvert.apercu.nombreEvenements, greaterThan(3));
      expect(ouvert.apercu.version, '0.6.0');
      expect(ouvert.apercu.dernierEvenement, isNotNull);
    });

    test('une ligne mutilée fait refuser tout le fichier', () async {
      await garnir();
      final lu = jsonDecode(await sauvegardes.composer())
          as Map<String, Object?>;
      (lu['evenements'] as List)[1] = {'id': 'X'};

      // Sauver la moitié d'un journal reviendrait à inventer une boutique.
      expect(Sauvegardes.ouvrir(jsonEncode(lu)), isNull);
    });
  });

  group('Restaurer', () {
    test('un autre téléphone retrouve exactement la même boutique', () async {
      await garnir();
      final avant = await depot.rapportDuJour();
      final dettesAvant = await depot.clientsDebiteurs();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);

      final resultat = await autresSauvegardes
          .restaurer(Sauvegardes.ouvrir(contenu)!);
      await autreDepot.reconstruireProjections();

      expect(resultat.reussie, isTrue);

      final apres = await autreDepot.rapportDuJour();
      expect(apres.encaisse, avant.encaisse);
      expect(apres.aCredit, avant.aCredit);
      expect(apres.nombreVentes, avant.nombreVentes);

      final dettesApres = await autreDepot.clientsDebiteurs();
      expect(dettesApres.map((c) => c.nom), dettesAvant.map((c) => c.nom));
      expect(dettesApres.single.encoursCentimes,
          dettesAvant.single.encoursCentimes);
    });

    test('le catalogue revient avec ses noms et ses prix', () async {
      await garnir();
      final avant = await depot.catalogue();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);
      await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);
      await autreDepot.reconstruireProjections();

      final apres = await autreDepot.catalogue();
      expect(apres.map((a) => a.designation), avant.map((a) => a.designation));
      expect(apres.map((a) => a.prixCentimes), avant.map((a) => a.prixCentimes));
    });

    test('les réglages voyagent avec', () async {
      await garnir();
      final contenu = await sauvegardes.composer();

      final (autreBase, _, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);
      await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);

      final reglage = await Parametres(autreBase).tout();
      expect(reglage.nomCommerce, 'Alimentation Nabonswendé');
      expect(reglage.vendeurs, ['Awa', 'Salif']);
    });

    test('le téléphone qui restaure peut continuer à vendre', () async {
      // Le journal restauré porte l'identifiant du premier appareil. Le
      // second doit pouvoir écrire à la suite sans casser aucune chaîne.
      await garnir();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);
      await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);
      await autreDepot.reconstruireProjections();

      await autreDepot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(3000),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(3000))
        ],
      );

      expect((await autreDepot.journal.verifier()).intact, isTrue);
      expect((await autreDepot.rapportDuJour()).nombreVentes, 3);
    });

    test('une sauvegarde vide ne détruit pas ce qui est là', () async {
      await garnir();
      final avant = await depot.rapportDuJour();

      final vide = Sauvegardes.ouvrir(
          jsonEncode({'application': 'carnet', 'format': 1, 'evenements': []}));
      final resultat = await sauvegardes.restaurer(vide!);

      expect(resultat.reussie, isFalse);
      expect(resultat.motif, contains('vide'));
      expect((await depot.rapportDuJour()).nombreVentes, avant.nombreVentes);
    });

    test('un fichier retouché est refusé, et rien n\'est effacé', () async {
      await garnir();
      final avant = await depot.rapportDuJour();

      // Quelqu'un gonfle une vente dans le fichier. L'empreinte ne suit pas.
      final lu = jsonDecode(await sauvegardes.composer())
          as Map<String, Object?>;
      final evenements = lu['evenements'] as List;
      final vente = evenements.firstWhere(
          (e) => (e as Map)['type'] == 'vente_enregistree') as Map;
      (vente['charge'] as Map)['totalCentimes'] = 99999999;

      final resultat =
          await sauvegardes.restaurer(Sauvegardes.ouvrir(jsonEncode(lu))!);

      expect(resultat.reussie, isFalse);
      expect(resultat.motif, contains('abîmé ou modifié'));
      // Le contrôle passe avant l'écriture : la boutique est intacte.
      expect((await depot.rapportDuJour()).nombreVentes, avant.nombreVentes);
      expect((await journal.verifier()).intact, isTrue);
    });

    test('un trou dans la chaîne est refusé', () async {
      await garnir();
      final lu = jsonDecode(await sauvegardes.composer())
          as Map<String, Object?>;
      (lu['evenements'] as List).removeAt(1);

      final resultat =
          await sauvegardes.restaurer(Sauvegardes.ouvrir(jsonEncode(lu))!);

      expect(resultat.reussie, isFalse);
      expect(resultat.motif, contains('manquent'));
    });

    test('restaurer écrase, sans mélanger deux boutiques', () async {
      await garnir();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);
      // Le second téléphone a déjà vendu de son côté.
      await autreDepot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(9999),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(9999))
        ],
      );

      await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);
      await autreDepot.reconstruireProjections();

      // Deux journaux mélangés donneraient des ventes en double que personne
      // ne saurait démêler.
      final rapport = await autreDepot.rapportDuJour();
      expect(rapport.nombreVentes, 2);
      expect(rapport.encaisse, f(650));
    });

    test('la même sauvegarde restaurée deux fois donne le même résultat',
        () async {
      await garnir();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);

      for (var i = 0; i < 2; i++) {
        await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);
        await autreDepot.reconstruireProjections();
      }

      expect((await autreDepot.rapportDuJour()).nombreVentes, 2);
      expect((await autreDepot.journal.verifier()).intact, isTrue);
    });

    test('un aller-retour complet ne perd rien du journal', () async {
      await garnir();
      final avant = await journal.tous();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);
      await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);

      final apres = await autreDepot.journal.tous();
      expect(apres.length, avant.length);
      for (var i = 0; i < avant.length; i++) {
        expect(apres[i].id, avant[i].id);
        expect(apres[i].type, avant[i].type);
        expect(apres[i].empreinte, avant[i].empreinte);
        expect(apres[i].charge, avant[i].charge);
      }
    });
  });

  group('Le journal après restauration', () {
    test('les événements des deux appareils se rejouent ensemble', () async {
      await garnir();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);
      await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);
      await autreDepot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(400),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(400))
        ],
      );

      // Un filtre par appareil rendrait la moitié du passé invisible.
      final appareils = await autreDepot.journal.appareils();
      expect(appareils, containsAll(['CAISSE1', 'CAISSE2']));

      await autreDepot.reconstruireProjections();
      expect((await autreDepot.rapportDuJour()).nombreVentes, 3);
    });

    test('chaque chaîne se vérifie séparément', () async {
      await garnir();
      final contenu = await sauvegardes.composer();

      final (autreBase, autreDepot, autresSauvegardes) = nouveauTelephone();
      addTearDown(autreBase.close);
      await autresSauvegardes.restaurer(Sauvegardes.ouvrir(contenu)!);
      await autreDepot.creerArticle(designation: 'Sucre', prix: f(750));

      final verification = await autreDepot.journal.verifier();
      expect(verification.intact, isTrue);
      // Le compte couvre bien les deux chaînes.
      expect(verification.nombreEvenements,
          (await autreDepot.journal.tous()).length);
    });
  });

  group('Savoir si le carnet est sorti du téléphone', () {
    test("aucune date tant qu'on n'a jamais envoyé", () async {
      expect(await parametres.derniereSauvegarde(), isNull);
    });

    test('la date se relit telle qu\'elle a été notée', () async {
      final quand = DateTime(2026, 8, 10, 18, 30);
      await parametres.noterSauvegarde(quand);

      expect(await parametres.derniereSauvegarde(), quand);
    });

    test('une nouvelle sauvegarde remplace la précédente', () async {
      await parametres.noterSauvegarde(DateTime(2026, 8, 1));
      await parametres.noterSauvegarde(DateTime(2026, 8, 12));

      expect(await parametres.derniereSauvegarde(), DateTime(2026, 8, 12));
    });

    // Les horodatages du journal sont à la seconde : les dates sont posées
    // explicitement, sinon trois ventes de suite tomberaient dans la même et
    // le test dépendrait de la vitesse de la machine.
    Future<void> vendreLe(DateTime quand, num prix) => depot.enregistrerVente(
          lignes: [
            LigneAEnregistrer(
              codeArticle: 'RIZ',
              designation: 'Riz 1 kg',
              prixUnitaire: f(prix),
              quantite: const Quantite.unites(1),
            )
          ],
          paiements: [
            PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(prix))
          ],
          horodatage: quand,
        );

    test('le compte des écritures depuis une date ignore ce qui précède',
        () async {
      await vendreLe(DateTime(2026, 8, 10, 9), 500);
      await vendreLe(DateTime(2026, 8, 14, 9), 650);
      await vendreLe(DateTime(2026, 8, 15, 9), 700);

      expect(await journal.nombreDepuis(DateTime(2026, 8, 12)), 2);
      expect(await journal.nombreDepuis(null), 3);
    });

    test('rien depuis la dernière sauvegarde veut dire rien à perdre',
        () async {
      await vendreLe(DateTime(2026, 8, 10, 9), 500);

      expect(await journal.nombreDepuis(DateTime(2026, 8, 11)), 0);
    });
  });
}
