/// Le comptage de la caisse, le soir.
///
/// C'est la seule mesure honnête d'une caisse. Tout le reste se raconte : on
/// dit qu'on a bien vendu, qu'il y a eu du monde, que le client d'hier est
/// repassé. Le tiroir, lui, contient une somme, et cette somme se compare.
///
/// Ce fichier vérifie surtout ce qui ne se voit pas en usage normal : qu'un
/// comptage juste s'enregistre comme les autres — sinon on ne distingue plus
/// « la caisse tombait juste » de « personne n'a compté » — et que l'écart se
/// rejoue depuis le journal, parce qu'un chiffre qui accuse quelqu'un ne doit
/// pas disparaître à la première restauration.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/rapport_fiscal.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/rapports.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Rapports rapports;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    final journal = Journal(base, appareil: 'CAISSE1');
    depot = Depot(base, journal);
    rapports = Rapports(
      base,
      journal,
      fiche: const FicheEntreprise(nomCommercial: 'Chez Awa'),
    );
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  DateTime jour(int n) => DateTime(2026, 8, n, 19, 30);

  Future<Montant> compter(
    num compte,
    num attendu, {
    String? par,
    DateTime? quand,
  }) => depot.pointerLaCaisse(
    compte: f(compte),
    attendu: f(attendu),
    operateur: par,
    horodatage: quand,
  );

  Future<List<EcartsDeVendeur>> lire() =>
      depot.ecartsParVendeur(DateTime(2026, 8, 1), DateTime(2026, 9, 1));

  group('Compter la caisse', () {
    test('ce qui manque se note en négatif', () async {
      final ecart = await compter(144500, 145000, quand: jour(10));

      expect(ecart, f(-500));
      final lignes = await lire();
      expect(lignes, hasLength(1));
      expect(lignes.single.manques, f(500));
      expect(lignes.single.cumul, f(-500));
    });

    test("ce qu'il y a en trop se note aussi", () async {
      final ecart = await compter(145200, 145000, quand: jour(10));

      expect(ecart, f(200));
      final lignes = await lire();
      expect(lignes.single.manques, const Montant.zero());
      expect(lignes.single.cumul, f(200));
    });

    test('un comptage juste laisse quand même une trace', () async {
      // Sans cet enregistrement, une caisse comptée tous les soirs et une
      // caisse jamais comptée se ressemblent : aucune ligne d'écart. Le
      // patron ne saurait pas laquelle des deux il a.
      await compter(145000, 145000, par: 'Awa', quand: jour(10));

      final lignes = await lire();
      expect(lignes, hasLength(1));
      expect(lignes.single.comptages, 1);
      expect(lignes.single.impeccable, isTrue);
    });

    test('la caisse vidée le soir se compte à zéro', () async {
      // Zéro est une réponse, pas une absence de réponse.
      final ecart = await compter(0, 145000, quand: jour(10));

      expect(ecart, f(-145000));
      expect((await lire()).single.comptages, 1);
    });

    test('le comptage retient qui tenait la caisse', () async {
      await compter(99500, 100000, par: 'Awa', quand: jour(10));
      await compter(50000, 50000, par: 'Fatou', quand: jour(10));

      final lignes = await lire();
      expect(lignes.map((e) => e.vendeur), ['Awa', 'Fatou']);
      expect(lignes.first.manques, f(500), reason: 'les manques en tête');
    });

    test("une caisse sans vendeur désigné n'accuse personne", () async {
      await compter(99500, 100000, quand: jour(10));

      final ligne = (await lire()).single;
      expect(ligne.estAnonyme, isTrue);
      expect(ligne.vendeur, isEmpty);
    });

    test('le motif écrit dit les deux nombres, sans être recalculé', () async {
      // Le journal doit se relire seul dans dix ans, sans l'application.
      await compter(144500, 145000, quand: jour(10));

      final mouvement = await base.select(base.mouvementsCaisse).getSingle();
      expect(mouvement.nature, NatureMouvementCaisse.ecart);
      expect(mouvement.motif, 'Attendu 145 000 F, compté 144 500 F');
    });
  });

  group('Ce que le patron lit', () {
    test('les manques et les excédents se cumulent séparément', () async {
      // Awa manque 500 F un soir et en a 500 de trop le lendemain : elle
      // s'est trompée deux fois, elle n'a rien pris. Le cumul le dit, les
      // manques seuls ne le diraient pas.
      await compter(99500, 100000, par: 'Awa', quand: jour(10));
      await compter(100500, 100000, par: 'Awa', quand: jour(11));

      final ligne = (await lire()).single;
      expect(ligne.comptages, 2);
      expect(ligne.cumul, const Montant.zero());
      expect(ligne.manques, f(500));
      expect(ligne.impeccable, isFalse);
    });

    test('les plus gros manques passent en tête', () async {
      await compter(100000, 100000, par: 'Awa', quand: jour(10));
      await compter(97000, 100000, par: 'Salif', quand: jour(10));
      await compter(99500, 100000, par: 'Fatou', quand: jour(10));

      expect((await lire()).map((e) => e.vendeur), [
        'Salif',
        'Fatou',
        'Awa',
      ]);
    });

    test('la période demandée est respectée', () async {
      await compter(99000, 100000, par: 'Awa', quand: DateTime(2026, 7, 30));
      await compter(99500, 100000, par: 'Awa', quand: jour(10));

      final aout = await lire();
      expect(aout.single.comptages, 1);
      expect(aout.single.manques, f(500));
    });
  });

  group("Ce qui entre et sort du tiroir sans être une vente", () {
    test("l'attendu tient compte du fonds du matin et des sorties", () async {
      // Sans ça, l'application accuse d'un manque de 20 000 F quelqu'un qui
      // a payé un fournisseur en liquide, facture à l'appui. Une accusation
      // fausse coûte plus cher que pas de contrôle du tout.
      await depot.mettreEnCaisse(
        f(10000),
        motif: 'Fonds du matin',
        horodatage: jour(10).subtract(const Duration(hours: 12)),
      );
      await depot.sortirDeCaisse(
        f(20000),
        motif: 'Sac de riz',
        horodatage: jour(10).subtract(const Duration(hours: 4)),
      );

      final rapport = await rapports.x();

      expect(rapport.especes, const Montant.zero(), reason: 'aucune vente');
      expect(rapport.depotsCaisse, f(10000));
      expect(rapport.retraitsCaisse, f(20000));
      expect(rapport.enCaisse, f(-10000));
    });

    test('le document montre le détail quand le tiroir a bougé', () async {
      await depot.mettreEnCaisse(f(10000), horodatage: jour(10));

      final texte = (await rapports.x()).texte;

      expect(texte, contains('Mis en caisse'));
      expect(texte, contains('Sorti de caisse'));
      expect(texte, contains('À avoir en caisse'));
    });

    test("sans mouvement, le document ne montre pas deux lignes à zéro",
        () async {
      final texte = (await rapports.x()).texte;

      expect(texte, isNot(contains('Mis en caisse')));
      expect(texte, contains('À avoir en caisse'));
    });

    test('un comptage ne compte pas comme un mouvement du tiroir', () async {
      // Sinon l'écart d'aujourd'hui se reporterait sur l'attendu de demain,
      // et s'effacerait tout seul.
      await depot.mettreEnCaisse(f(10000), horodatage: jour(10));
      await compter(9000, 10000, quand: jour(10));

      final rapport = await rapports.x();
      expect(rapport.depotsCaisse, f(10000));
      expect(rapport.retraitsCaisse, const Montant.zero());
      expect(rapport.enCaisse, f(10000));
    });

    test('un mouvement fait après la clôture compte dans la journée neuve',
        () async {
      // Les bornes sont celles des ventes, et il faut que ça reste vrai : un
      // retrait et une vente faits au même moment doivent tomber dans la
      // même journée. Les heures sont explicites ici — à la seconde près,
      // rien ne distingue « juste avant » de « juste après » une clôture.
      await depot.mettreEnCaisse(f(10000), horodatage: jour(10));
      await rapports.z(quand: jour(10).add(const Duration(minutes: 1)));

      await depot.sortirDeCaisse(
        f(2500),
        horodatage: jour(10).add(const Duration(minutes: 5)),
      );

      final apres = await rapports.x();
      expect(
        apres.depotsCaisse,
        const Montant.zero(),
        reason: 'le fonds appartient à la journée fermée',
      );
      expect(apres.retraitsCaisse, f(2500));
    });

    test('la clôture fige le tiroir, pas seulement les ventes', () async {
      // Le contrôleur demande d'où sort le chiffre imprimé sur la feuille.
      // Si le journal ne garde que les ventes en espèces, la réponse manque.
      await depot.mettreEnCaisse(f(10000), horodatage: jour(10));
      await rapports.z(quand: jour(10).add(const Duration(minutes: 1)));

      final cloture = (await rapports.clotures(nature: NatureRapport.z)).single;
      expect(cloture.especes, f(10000));
    });

    test('les mouvements se rejouent depuis le journal', () async {
      await depot.mettreEnCaisse(f(10000), horodatage: jour(10));
      await depot.sortirDeCaisse(f(2500), horodatage: jour(10));

      await depot.reconstruireProjections();

      final rapport = await rapports.x();
      expect(rapport.depotsCaisse, f(10000));
      expect(rapport.retraitsCaisse, f(2500));
    });
  });

  test('le comptage se rejoue depuis le journal', () async {
    await compter(144500, 145000, par: 'Awa', quand: jour(10));
    await compter(50000, 50000, par: 'Fatou', quand: jour(11));
    final avant = await lire();

    await depot.reconstruireProjections();

    final apres = await lire();
    expect(apres, hasLength(avant.length));
    for (var i = 0; i < avant.length; i++) {
      expect(apres[i].vendeur, avant[i].vendeur);
      expect(apres[i].comptages, avant[i].comptages);
      expect(apres[i].cumul, avant[i].cumul);
      expect(apres[i].manques, avant[i].manques);
    }
  });
}
