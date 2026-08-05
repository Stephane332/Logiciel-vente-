/// Tests du suivi de stock.
///
/// Le stock ne se saisit jamais d'un coup : il se construit article par
/// article, quand le commerçant en a envie. Ce que je vérifie ici, c'est
/// surtout qu'on peut répondre à sa vraie question — « où est passée la
/// différence » — et pas seulement afficher un nombre.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/analyses.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  late BaseLocale base;
  late Depot depot;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);
  Quantite q(num unites) => Quantite.depuisDecimal(unites);

  Future<void> vendre(String code, {num quantite = 1, DateTime? quand}) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: code,
            designation: 'Riz 1 kg',
            prixUnitaire: f(650),
            quantite: q(quantite),
          )
        ],
        paiements: [
          PaiementAEnregistrer(
            mode: ModePaiement.especes,
            montant: f(650).multiplieParQuantite(q(quantite)),
          )
        ],
        horodatage: quand,
      );

  Future<LigneArticle> article(String code) async =>
      (await depot.catalogue()).firstWhere((a) => a.code == code);

  group('Déclarer un stock', () {
    test('compter son étagère met le stock à ce chiffre', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));

      expect((await article('RIZ')).stockMilliemes, q(40).milliemes);
      // Déclarer un stock, c'est décider de le suivre.
      expect((await article('RIZ')).suiviStock, SuiviStock.direct.cle);
    });

    test('une réception s\'ajoute au stock connu', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.entrerStock('RIZ', q(20));

      expect((await article('RIZ')).stockMilliemes, q(60).milliemes);
    });

    test('recompter remplace, réceptionner ajoute', () async {
      await vendre('RIZ');
      await depot.entrerStock('RIZ', q(30));
      await depot.entrerStock('RIZ', q(30));
      expect((await article('RIZ')).stockMilliemes, q(60).milliemes);

      // Le comptage physique fait autorité, quel que soit le stock théorique.
      await depot.ajusterStock('RIZ', q(52));
      expect((await article('RIZ')).stockMilliemes, q(52).milliemes);
    });

    test('une perte retire du stock', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.declarerPerte('RIZ', q(3), motif: 'Sacs éventrés');

      expect((await article('RIZ')).stockMilliemes, q(37).milliemes);
    });

    test('un mouvement négatif est refusé', () async {
      await vendre('RIZ');
      expect(
        () => depot.entrerStock('RIZ', Quantite(-1000)),
        throwsArgumentError,
      );
    });
  });

  group('Vendre décrémente', () {
    test('chaque vente retire du stock une fois celui-ci suivi', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await vendre('RIZ', quantite: 3);

      expect((await article('RIZ')).stockMilliemes, q(37).milliemes);
    });

    test('sans suivi déclaré, vendre ne touche à rien', () async {
      await vendre('RIZ');
      await vendre('RIZ');

      // C'est le défaut : un prestataire de services n'a pas de stock, et un
      // commerçant qui n'a rien déclaré ne doit pas voir de chiffre faux.
      expect((await article('RIZ')).stockMilliemes, isNull);
    });
  });

  group('Où est passée la différence', () {
    test('chaque mouvement laisse une trace lisible', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.entrerStock('RIZ', q(10));
      await depot.declarerPerte('RIZ', q(2), motif: 'Casse');

      final mouvements = await depot.mouvementsDe('RIZ');
      expect(mouvements.length, 3);

      // Du plus récent au plus ancien.
      expect(mouvements.first.nature, NatureMouvementStock.perte.cle);
      expect(mouvements.first.motif, 'Casse');
      expect(mouvements.first.variationMilliemes, q(2).milliemes * -1);
      expect(mouvements.first.stockApresMilliemes, q(48).milliemes);
    });

    test("l'inventaire enregistre l'écart, pas le total compté", () async {
      await vendre('RIZ');
      await depot.entrerStock('RIZ', q(50));

      // Il en manque trois à l'appel : c'est cet écart qui intéresse le patron.
      await depot.ajusterStock('RIZ', q(47));

      final dernier = (await depot.mouvementsDe('RIZ')).first;
      expect(dernier.nature, NatureMouvementStock.inventaire.cle);
      expect(dernier.variationMilliemes, q(3).milliemes * -1);
    });

    test('un article sans mouvement déclaré n\'a pas d\'historique', () async {
      await vendre('RIZ');
      expect(await depot.mouvementsDe('RIZ'), isEmpty);
    });
  });

  group('Construction progressive', () {
    Future<void> vendreNFois(int fois) async {
      for (var i = 0; i < fois; i++) {
        await vendre('RIZ');
      }
    }

    test("on ne propose rien tant que l'article n'a pas de nom", () async {
      // Des ventes à montant libre : l'article existe, il est vendu souvent,
      // mais il s'appelle encore « Article à 650 F ».
      for (var i = 0; i < Depot.seuilDeSuiviStock + 2; i++) {
        await depot.enregistrerVente(
          lignes: [
            LigneAEnregistrer(
              prixUnitaire: f(650),
              quantite: const Quantite.unites(1),
            )
          ],
          paiements: [
            PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(650))
          ],
        );
      }

      // Le nom vient d'abord. Demander de compter un « Article à 650 F »
      // n'aurait aucun sens pour le commerçant.
      expect(await depot.articlesASuivre(), isEmpty);
    });

    test('un article nommé et vendu souvent finit par être proposé', () async {
      await vendreNFois(Depot.seuilDeSuiviStock);
      await depot.nommerArticle('RIZ', 'Riz 1 kg');

      final aSuivre = await depot.articlesASuivre();
      expect(aSuivre.single.code, 'RIZ');
    });

    test('un article nommé mais peu vendu attend son tour', () async {
      await vendreNFois(Depot.seuilDeSuiviStock - 1);
      await depot.nommerArticle('RIZ', 'Riz 1 kg');

      expect(await depot.articlesASuivre(), isEmpty);
    });

    test('une fois le stock déclaré, on ne repropose plus', () async {
      await vendreNFois(Depot.seuilDeSuiviStock);
      await depot.nommerArticle('RIZ', 'Riz 1 kg');
      await depot.ajusterStock('RIZ', q(40));

      expect(await depot.articlesASuivre(), isEmpty);
    });

    test('refuser le suivi retire définitivement la proposition', () async {
      await vendreNFois(Depot.seuilDeSuiviStock);
      await depot.nommerArticle('RIZ', 'Riz 1 kg');
      await depot.definirSuiviStock('RIZ', SuiviStock.recette);

      expect(await depot.articlesASuivre(), isEmpty);
    });
  });

  group('Liste du stock', () {
    test('les articles suivis remontent, les plus bas en premier', () async {
      for (final (code, nom, stock) in const [
        ('RIZ', 'Riz', 40),
        ('HUILE', 'Huile', 3),
        ('SUCRE', 'Sucre', 12),
      ]) {
        await depot.enregistrerVente(
          lignes: [
            LigneAEnregistrer(
              codeArticle: code,
              designation: nom,
              prixUnitaire: f(500),
              quantite: const Quantite.unites(1),
            )
          ],
          paiements: [
            PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
          ],
        );
        await depot.ajusterStock(code, q(stock));
      }

      final liste = await depot.articlesEnStock();
      expect(liste.map((a) => a.code), ['HUILE', 'SUCRE', 'RIZ']);
    });

    test('un article sans suivi n\'apparaît pas dans le stock', () async {
      await vendre('RIZ');
      expect(await depot.articlesEnStock(), isEmpty);
    });
  });

  group('Le journal reste la vérité', () {
    test('rejouer le journal reconstruit le stock à l\'identique', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.entrerStock('RIZ', q(10));
      await depot.declarerPerte('RIZ', q(2), motif: 'Casse');
      await vendre('RIZ', quantite: 5);

      final avant = (await article('RIZ')).stockMilliemes;
      final mouvementsAvant = await depot.mouvementsDe('RIZ');

      await depot.reconstruireProjections();

      expect((await article('RIZ')).stockMilliemes, avant);
      expect((await depot.mouvementsDe('RIZ')).length, mouvementsAvant.length);
    });

    test('changer le mode de suivi se rejoue aussi', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.definirSuiviStock('RIZ', SuiviStock.aucun);

      await depot.reconstruireProjections();

      final riz = await article('RIZ');
      expect(riz.suiviStock, SuiviStock.aucun.cle);
      // Repasser en « aucun » oublie le stock : mieux vaut ne rien afficher
      // qu'un chiffre qu'on a cessé de tenir à jour.
      expect(riz.stockMilliemes, isNull);
    });
  });

  group('Ce qui est parti sans être vendu', () {
    late Analyses analyses;

    setUp(() => analyses = Analyses(base));

    test('une perte est valorisée au prix de vente', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.declarerPerte('RIZ', q(3), motif: 'Casse');

      // Trois sacs à 650 F : c'est la recette que le commerce ne fera pas.
      expect(await analyses.pertesEtEcarts(), f(1950));
    });

    test('un écart d\'inventaire compte comme une perte', () async {
      await vendre('RIZ');
      await depot.entrerStock('RIZ', q(50));
      await depot.ajusterStock('RIZ', q(47));

      expect(await analyses.pertesEtEcarts(), f(1950));
    });

    test('une réception ne compte pas comme une perte', () async {
      await vendre('RIZ');
      await depot.entrerStock('RIZ', q(50));

      expect(await analyses.pertesEtEcarts(), const Montant.zero());
    });

    test('un inventaire à la hausse ne compte pas non plus', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(10));
      await depot.ajusterStock('RIZ', q(15));

      expect(await analyses.pertesEtEcarts(), const Montant.zero());
    });

    test('les pertes d\'hier ne polluent pas le rapport du jour', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.declarerPerte('RIZ', q(3),
          horodatage: DateTime.now().subtract(const Duration(days: 2)));

      expect(await analyses.pertesEtEcarts(), const Montant.zero());
    });

    test('une boutique sans mouvement ne perd rien', () async {
      await vendre('RIZ');
      expect(await analyses.pertesEtEcarts(), const Montant.zero());
    });
  });

  group('Rien n\'est définitif', () {
    Future<void> vendreNFois(int fois) async {
      for (var i = 0; i < fois; i++) {
        await vendre('RIZ');
      }
    }

    test('« plus tard » masque la proposition mais garde l\'article',
        () async {
      await vendreNFois(Depot.seuilDeSuiviStock);
      await depot.nommerArticle('RIZ', 'Riz 1 kg');
      await depot.reporterPropositionSuivi('RIZ');

      expect(await depot.articlesASuivre(), isEmpty);

      // Il reste retrouvable, et le suivi peut démarrer à tout moment.
      final restants = await depot.articlesSansSuivi();
      expect(restants.map((a) => a.code), contains('RIZ'));
    });

    test('on peut suivre un article après avoir dit « plus tard »', () async {
      await vendreNFois(Depot.seuilDeSuiviStock);
      await depot.nommerArticle('RIZ', 'Riz 1 kg');
      await depot.reporterPropositionSuivi('RIZ');

      await depot.ajusterStock('RIZ', q(25));

      expect((await article('RIZ')).stockMilliemes, q(25).milliemes);
      expect((await depot.articlesEnStock()).single.code, 'RIZ');
    });

    test('arrêter de suivre remet l\'article dans la liste du bas', () async {
      await vendre('RIZ');
      await depot.ajusterStock('RIZ', q(40));
      await depot.definirSuiviStock('RIZ', SuiviStock.aucun);

      expect(await depot.articlesEnStock(), isEmpty);
      expect((await depot.articlesSansSuivi()).map((a) => a.code),
          contains('RIZ'));
    });

    test('le report se rejoue depuis le journal', () async {
      await vendreNFois(Depot.seuilDeSuiviStock);
      await depot.nommerArticle('RIZ', 'Riz 1 kg');
      await depot.reporterPropositionSuivi('RIZ');

      await depot.reconstruireProjections();

      expect(await depot.articlesASuivre(), isEmpty);
    });
  });

  group('Saisir son catalogue à l\'avance', () {
    test('un commerçant peut créer un article avec son stock', () async {
      final code = await depot.creerArticle(
        designation: 'Riz 1 kg',
        prix: f(650),
        stock: q(50),
      );

      final cree = await article(code);
      expect(cree.designation, 'Riz 1 kg');
      expect(cree.prixCentimes, f(650).centimes);
      expect(cree.stockMilliemes, q(50).milliemes);
      expect(cree.nomme, isTrue);
    });

    test('le stock est facultatif à la création', () async {
      final code = await depot.creerArticle(
        designation: 'Coupe de cheveux',
        prix: f(1000),
      );

      // Un prestataire de services n'a pas de stock à compter.
      expect((await article(code)).stockMilliemes, isNull);
      expect(await depot.articlesEnStock(), isEmpty);
    });

    test('un article créé à la main est vendable tout de suite', () async {
      final code = await depot.creerArticle(
        designation: 'Riz 1 kg',
        prix: f(650),
        stock: q(50),
      );

      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: code,
            designation: 'Riz 1 kg',
            prixUnitaire: f(650),
            quantite: q(2),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(1300))
        ],
      );

      expect((await article(code)).stockMilliemes, q(48).milliemes);
    });

    test('un nom vide ou un prix nul est refusé', () async {
      expect(
        () => depot.creerArticle(designation: '  ', prix: f(650)),
        throwsArgumentError,
      );
      expect(
        () => depot.creerArticle(
            designation: 'Riz', prix: const Montant.zero()),
        throwsArgumentError,
      );
    });

    test('les accents ne partent pas dans le code', () async {
      final code = await depot.creerArticle(
        designation: 'Café éthiopien',
        prix: f(2500),
      );
      expect(code, startsWith('CAFE-ETHIOPIEN-'));
    });

    test('deux articles du même nom ne s\'écrasent pas', () async {
      final premier = await depot.creerArticle(
          designation: 'Sachet', prix: f(100));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await depot.creerArticle(
          designation: 'Sachet', prix: f(200));

      expect(premier, isNot(second));
      expect((await depot.catalogue()).length, 2);
    });

    test('la création se rejoue depuis le journal', () async {
      final code = await depot.creerArticle(
        designation: 'Riz 1 kg',
        prix: f(650),
        stock: q(50),
      );

      await depot.reconstruireProjections();

      final rejoue = await article(code);
      expect(rejoue.designation, 'Riz 1 kg');
      expect(rejoue.stockMilliemes, q(50).milliemes);
    });
  });

  group('Corriger nom et prix', () {
    test('un article se renomme à tout moment', () async {
      await vendre('RIZ');
      await depot.nommerArticle('RIZ', 'Riz parfumé 1 kg');

      expect((await article('RIZ')).designation, 'Riz parfumé 1 kg');
    });

    test('le prix se change sans toucher aux ventes passées', () async {
      await vendre('RIZ');
      await depot.modifierPrix('RIZ', f(700));

      expect((await article('RIZ')).prixCentimes, f(700).centimes);

      // La vente d'hier garde le prix pratiqué ce jour-là.
      final rapport = await depot.rapportDuJour();
      expect(rapport.encaisse, f(650));
    });

    test('un prix nul est refusé', () async {
      await vendre('RIZ');
      expect(
        () => depot.modifierPrix('RIZ', const Montant.zero()),
        throwsArgumentError,
      );
    });

    test('le changement de prix se rejoue depuis le journal', () async {
      await vendre('RIZ');
      await depot.modifierPrix('RIZ', f(700));

      await depot.reconstruireProjections();
      expect((await article('RIZ')).prixCentimes, f(700).centimes);
    });
  });
}
