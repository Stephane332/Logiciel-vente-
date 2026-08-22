/// Tests de « qui tient la caisse ».
///
/// Le patron qui emploie quelqu'un ne demande pas un tableau de bord : il
/// demande qui a vendu combien, et si l'un accorde plus de remises que les
/// autres. C'est aussi la seule fonction de tout le logiciel qui puisse
/// accuser quelqu'un à tort — donc celle où un nom faux coûte le plus cher.
///
/// Deux règles s'y vérifient : un vendeur retiré de la liste cesse
/// immédiatement d'encaisser, et une vente que personne n'a revendiquée reste
/// visible plutôt que d'être répartie au hasard.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/periode.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';

void main() {
  late BaseLocale base;
  late Depot depot;
  late Parametres parametres;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    parametres = Parametres(base);
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  /// Une vente, attribuée ou non, éventuellement remisée.
  Future<void> vendre(
    num prix, {
    String? par,
    num? catalogue,
    DateTime? quand,
  }) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'RIZ',
            designation: 'Riz 1 kg',
            prixUnitaire: f(prix),
            prixCatalogue: catalogue == null ? null : f(catalogue),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(prix))
        ],
        operateur: par,
        horodatage: quand,
      );

  /// Les bornes de la journée en cours, celles que le rapport utilise.
  (DateTime, DateTime) aujourdHui() => Periode.jour.bornes();

  group("Déclarer l'équipe", () {
    test('un commerçant seul ne déclare personne', () async {
      final reglage = await parametres.tout();

      expect(reglage.vendeurs, isEmpty);
      expect(reglage.vendeurActif, isNull);
      // Rien ne doit s'afficher tant que la question ne se pose pas.
      expect(reglage.equipe, isFalse);
      expect(reglage.vendeurAChoisir, isFalse);
    });

    test('les noms se déclarent et se relisent dans le même ordre', () async {
      await parametres.definirVendeurs(['Salif', 'Awa', 'Boukary']);

      expect((await parametres.tout()).vendeurs, ['Salif', 'Awa', 'Boukary']);
    });

    test('un nom vide ou en double ne rentre pas', () async {
      await parametres.definirVendeurs(['Awa', '  ', 'Awa', ' Salif ']);

      expect((await parametres.tout()).vendeurs, ['Awa', 'Salif']);
    });

    test('un retour à la ligne dans un nom ne coupe pas la liste en deux',
        () async {
      // C'est ce caractère qui sépare les noms dans la valeur enregistrée :
      // un nom collé au clavier depuis ailleurs pourrait en contenir un.
      await parametres.definirVendeurs(['Awa\nSalif', 'Boukary']);

      expect((await parametres.tout()).vendeurs, ['Awa Salif', 'Boukary']);
    });

    test('une équipe déclarée mais personne de choisi se signale', () async {
      await parametres.definirVendeurs(['Awa', 'Salif']);

      final reglage = await parametres.tout();
      expect(reglage.equipe, isTrue);
      expect(reglage.vendeurAChoisir, isTrue);
    });

    test('le vendeur choisi survit à la fermeture', () async {
      await parametres.definirVendeurs(['Awa', 'Salif']);
      await parametres.definirVendeurActif('Salif');

      final reglage = await parametres.tout();
      expect(reglage.vendeurActif, 'Salif');
      expect(reglage.vendeurAChoisir, isFalse);
    });

    test("un vendeur retiré cesse aussitôt de tenir la caisse", () async {
      await parametres.definirVendeurs(['Awa', 'Salif']);
      await parametres.definirVendeurActif('Salif');

      // Salif s'en va. Sans ce filtre, son nom continuerait de s'écrire sur
      // les ventes de son remplaçant.
      await parametres.definirVendeurs(['Awa']);

      final reglage = await parametres.tout();
      expect(reglage.vendeurs, ['Awa']);
      expect(reglage.vendeurActif, isNull);
      expect(reglage.vendeurAChoisir, isTrue);
    });

    test("vider l'équipe efface aussi le vendeur en poste", () async {
      await parametres.definirVendeurs(['Awa']);
      await parametres.definirVendeurActif('Awa');
      await parametres.definirVendeurs([]);

      final reglage = await parametres.tout();
      expect(reglage.vendeurs, isEmpty);
      expect(reglage.vendeurActif, isNull);
      expect(reglage.equipe, isFalse);
    });
  });

  group('Qui a encaissé', () {
    test('chacun a sa ligne, le plus gros en tête', () async {
      await vendre(1000, par: 'Awa');
      await vendre(2000, par: 'Salif');
      await vendre(500, par: 'Awa');

      final (debut, fin) = aujourdHui();
      final parts = await depot.parVendeur(debut, fin);

      expect(parts.map((p) => p.vendeur), ['Salif', 'Awa']);
      expect(parts.first.total, f(2000));
      expect(parts.first.nombreVentes, 1);
      expect(parts.last.total, f(1500));
      expect(parts.last.nombreVentes, 2);
    });

    test('les remises se comptent par vendeur', () async {
      // Awa lâche 200 F, Salif rien. C'est le chiffre que le patron cherche.
      await vendre(800, par: 'Awa', catalogue: 1000);
      await vendre(1000, par: 'Salif');

      final (debut, fin) = aujourdHui();
      final parts = await depot.parVendeur(debut, fin);
      final awa = parts.firstWhere((p) => p.vendeur == 'Awa');
      final salif = parts.firstWhere((p) => p.vendeur == 'Salif');

      expect(awa.remises, f(200));
      expect(salif.remises, const Montant.zero());
    });

    test("une vente que personne n'a revendiquée reste visible", () async {
      // Le patron a déclaré une équipe mais a encaissé sans choisir : ce
      // trou doit se voir, pas se répartir sur les autres.
      await vendre(1000, par: 'Awa');
      await vendre(3000);

      final (debut, fin) = aujourdHui();
      final parts = await depot.parVendeur(debut, fin);
      final orphelines = parts.where((p) => p.estAnonyme);

      expect(orphelines, hasLength(1));
      expect(orphelines.first.total, f(3000));
      expect(orphelines.first.vendeur, isEmpty);
    });

    test('chez un commerçant seul, tout tient sur une ligne anonyme',
        () async {
      await vendre(1000);
      await vendre(2000);

      final (debut, fin) = aujourdHui();
      final parts = await depot.parVendeur(debut, fin);

      expect(parts, hasLength(1));
      expect(parts.first.estAnonyme, isTrue);
      expect(parts.first.total, f(3000));
    });

    test('une vente annulée ne compte plus pour personne', () async {
      await vendre(1000, par: 'Awa');
      final id = await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            prixUnitaire: f(5000),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(5000))
        ],
        operateur: 'Awa',
      );
      await depot.annulerVente(id);

      final (debut, fin) = aujourdHui();
      final parts = await depot.parVendeur(debut, fin);

      expect(parts.single.vendeur, 'Awa');
      expect(parts.single.total, f(1000));
      expect(parts.single.nombreVentes, 1);
    });

    test("les ventes d'hier ne remontent pas dans la journée", () async {
      final hier = DateTime.now().subtract(const Duration(days: 1));
      await vendre(9000, par: 'Salif', quand: hier);
      await vendre(1000, par: 'Awa');

      final (debut, fin) = aujourdHui();
      final parts = await depot.parVendeur(debut, fin);

      expect(parts.single.vendeur, 'Awa');
    });

    test('une journée sans vente ne rend aucune ligne', () async {
      final (debut, fin) = aujourdHui();

      expect(await depot.parVendeur(debut, fin), isEmpty);
    });
  });
}
