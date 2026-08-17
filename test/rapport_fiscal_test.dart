/// Les rapports X, Z et A (§5 de la note de service n° 2025-0889).
///
/// Deux exigences se superposent, et je tiens les deux ici. Celle de la DGI :
/// des totaux par type de facture, par groupe de taxation, par mode de
/// règlement, avec le nombre de ventes incomplètes. Et celle du commerçant,
/// qui est plus simple et plus urgente : **combien doit-il y avoir dans le
/// tiroir ce soir**.
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
  late Journal journal;
  late Rapports rapports;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    journal = Journal(base, appareil: 'CAISSE1');
    depot = Depot(base, journal);
    rapports = Rapports(
      base,
      journal,
      fiche: const FicheEntreprise(
        nomCommercial: 'Chez Awa',
        ifu: '00012345A',
      ),
    );
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Future<String> vendre({
    num prix = 1000,
    GroupeTaxation groupe = GroupeTaxation.a,
    ModePaiement mode = ModePaiement.especes,
    String code = 'RIZ',
    num quantite = 1,
    DateTime? quand,
  }) async {
    final total = f(prix * quantite);
    return depot.enregistrerVente(
      lignes: [
        LigneAEnregistrer(
          codeArticle: code,
          designation: 'Riz 1 kg',
          prixUnitaire: f(prix),
          quantite: Quantite.depuisDecimal(quantite),
          groupeTaxation: groupe,
        )
      ],
      paiements: [PaiementAEnregistrer(mode: mode, montant: total)],
      horodatage: quand,
    );
  }

  group('Le chiffre que le commerçant vient chercher', () {
    test('le Z dit ce qui doit être dans le tiroir', () async {
      await vendre(prix: 1000);
      await vendre(prix: 500);
      // Le mobile money est sur le téléphone, pas dans le tiroir.
      await vendre(prix: 2000, mode: ModePaiement.mobileMoney);

      final z = await rapports.z();

      expect(z.especes, f(1500));
      expect(z.total, f(3500));
      expect(z.texte, contains('À avoir en caisse (espèces)'));
    });

    test('une vente à crédit ne met rien dans le tiroir', () async {
      await vendre(prix: 3000, mode: ModePaiement.credit);

      final z = await rapports.z();

      expect(z.especes, const Montant.zero());
      expect(z.parMode[ModePaiement.credit], f(3000));
    });
  });

  group('Ce que la note veut voir', () {
    test('les totaux par type de facture', () async {
      await vendre();
      await vendre();

      final z = await rapports.z();

      expect(z.parType.single.type, TypeFacture.vente);
      expect(z.parType.single.nombre, 2);
      expect(z.nombreFactures, 2);
    });

    test('les totaux par groupe de taxation, avec la taxe extraite', () async {
      // Prix pratiqués TTC : la taxe s'en extrait, arrondie à la valeur
      // supérieure comme l'impose le §6.7.
      await vendre(prix: 1180, groupe: GroupeTaxation.b);

      final z = await rapports.z();
      final groupe = z.parGroupe.single;

      expect(groupe.groupe.etiquette, 'B');
      expect(groupe.total, f(1180));
      expect(groupe.taxe, f(180));
      expect(groupe.taxable, f(1000));
      // L'égalité du §6.7, sur laquelle tout repose.
      expect(groupe.taxable + groupe.taxe, groupe.total);
    });

    test('un groupe exonéré ne porte pas de taxe', () async {
      await vendre(prix: 1000, groupe: GroupeTaxation.a);

      final groupe = (await rapports.z()).parGroupe.single;

      expect(groupe.taxe, const Montant.zero());
      expect(groupe.taxable, f(1000));
    });

    test('les totaux par mode de règlement', () async {
      await vendre(prix: 1000);
      await vendre(prix: 2000, mode: ModePaiement.mobileMoney);
      await vendre(prix: 500);

      final parMode = (await rapports.z()).parMode;

      expect(parMode[ModePaiement.especes], f(1500));
      expect(parMode[ModePaiement.mobileMoney], f(2000));
    });

    test('les ventes annulées comptent en réduction, pas en vente', () async {
      final vente = await vendre(prix: 1000);
      await vendre(prix: 500);
      await depot.annulerVente(vente);

      final z = await rapports.z();

      expect(z.nombreFactures, 1);
      expect(z.total, f(500));
      expect(z.autresReductions, f(1000));
    });

    test('les ventes incomplètes se comptent à part', () async {
      await vendre(prix: 1000);
      await depot.ouvrirVente(contenant: 'Table 3');

      final z = await rapports.z();

      // Une note de restaurant que personne n'a payée ne doit pas gonfler la
      // journée — mais son existence doit se voir.
      expect(z.ventesIncompletes, 1);
      expect(z.nombreFactures, 1);
      expect(z.total, f(1000));
    });

    test("l'en-tête porte le nom et l'IFU", () async {
      final texte = (await rapports.z()).texte;

      expect(texte, contains('CHEZ AWA'));
      expect(texte, contains('IFU : 00012345A'));
      expect(texte, contains('Z-rapport n° 1'));
    });

    test("il annonce qu'il n'est pas certifié", () async {
      expect((await rapports.z()).texte, contains('RAPPORT NON CERTIFIÉ'));
    });
  });

  group('Le Z clôture, le X ne clôture pas', () {
    test('un second Z ne recompte pas le premier', () async {
      await vendre(prix: 1000, quand: DateTime(2026, 8, 10, 10));
      final premier = await rapports.z(quand: DateTime(2026, 8, 10, 20));

      await vendre(prix: 2000, quand: DateTime(2026, 8, 11, 10));
      final second = await rapports.z(quand: DateTime(2026, 8, 11, 20));

      expect(premier.total, f(1000));
      // C'est toute la raison d'être de la clôture : sans elle, le second Z
      // rendrait 3 000 F et le commerçant compterait deux fois la même vente.
      expect(second.total, f(2000));
      expect(second.debut, premier.fin);
      expect(second.numero, 2);
    });

    test('le X se retire autant de fois qu\'on veut', () async {
      await vendre(prix: 1000, quand: DateTime(2026, 8, 10, 10));

      final midi = await rapports.x(fin: DateTime(2026, 8, 10, 12));
      final soir = await rapports.x(fin: DateTime(2026, 8, 10, 20));

      expect(midi.total, f(1000));
      expect(soir.total, f(1000));
      expect(NatureRapport.x.cloture, isFalse);
      expect(NatureRapport.z.cloture, isTrue);
    });

    test('le X est au journal lui aussi (§2.23)', () async {
      // « Journal électronique contenant toutes les factures et **tous les
      // rapports** ». Un X n'arrête rien, mais il a été tiré, et un X de midi
      // qui ne recoupe pas le Z du soir doit pouvoir se vérifier.
      await vendre(prix: 1000);
      await rapports.x();
      await rapports.x();

      final tires = await rapports.clotures(nature: NatureRapport.x);
      expect(tires.map((c) => c.numero), [2, 1]);
      expect(tires.first.total, f(1000));
    });

    test("un X ne déplace pas la borne du Z", () async {
      await vendre(prix: 1000, quand: DateTime(2026, 8, 10, 10));
      await rapports.x();

      // C'est la seule chose qui compte : écrire le X au journal ne doit pas
      // faire repartir le Z d'après le X.
      expect((await rapports.z()).total, f(1000));
    });

    test('le X reprend depuis la dernière clôture', () async {
      await vendre(prix: 1000, quand: DateTime(2026, 8, 10, 10));
      await rapports.z(quand: DateTime(2026, 8, 10, 20));
      await vendre(prix: 2000, quand: DateTime(2026, 8, 11, 10));

      expect((await rapports.x()).total, f(2000));
    });

    test('un X périodique regarde en arrière sans rien déplacer', () async {
      await vendre(prix: 1000, quand: DateTime(2026, 8, 10, 10));
      await rapports.z(quand: DateTime(2026, 8, 10, 20));
      await vendre(prix: 2000, quand: DateTime(2026, 8, 11, 10));

      final periodique = await rapports.x(
        debut: DateTime(2026, 8, 10),
        fin: DateTime(2026, 8, 12),
      );

      expect(periodique.total, f(3000));
      // Et la clôture n'a pas bougé.
      expect((await rapports.x()).total, f(2000));
    });
  });

  group('La clôture est au journal', () {
    test('les totaux y sont figés, pas seulement recalculables', () async {
      await vendre(prix: 1000);
      await rapports.z();

      final cloture = (await rapports.clotures()).single;

      expect(cloture.nature, NatureRapport.z);
      expect(cloture.numero, 1);
      expect(cloture.total, f(1000));
      expect(cloture.especes, f(1000));
      expect(cloture.nombreFactures, 1);
    });

    test("un Z déjà tiré ne change pas quand la caisse continue", () async {
      await vendre(prix: 1000, quand: DateTime(2026, 8, 10, 10));
      await rapports.z(quand: DateTime(2026, 8, 10, 20));
      await vendre(prix: 5000, quand: DateTime(2026, 8, 11, 10));

      // Le Z a été remis, imprimé, peut-être signé. Le recalculer plus tard
      // et trouver autre chose ferait de la clôture une opinion.
      expect((await rapports.clotures()).single.total, f(1000));
    });

    test('les clôtures se relisent, de la plus récente à la plus ancienne',
        () async {
      await rapports.z(quand: DateTime(2026, 8, 10, 20));
      await rapports.z(quand: DateTime(2026, 8, 11, 20));

      final liste = await rapports.clotures(nature: NatureRapport.z);

      expect(liste.map((c) => c.numero), [2, 1]);
    });

    test('elle survit à une reconstruction des projections', () async {
      await vendre(prix: 1000, quand: DateTime(2026, 8, 10, 10));
      await rapports.z(quand: DateTime(2026, 8, 10, 20));

      await depot.reconstruireProjections();

      expect((await rapports.clotures()).single.total, f(1000));
      expect(await rapports.derniereCloture(NatureRapport.z),
          DateTime(2026, 8, 10, 20));
    });
  });

  group('Le A-rapport', () {
    test('il compte par article ce qui est sorti et ce qui reste', () async {
      await vendre(code: 'RIZ', prix: 1000, quantite: 3);
      await depot.ajusterStock('RIZ', Quantite.depuisDecimal(10));

      final a = await rapports.a();
      final ligne = a.articles.single;

      expect(ligne.code, 'RIZ');
      expect(ligne.venduee, Quantite.depuisDecimal(3));
      expect(ligne.enStock, Quantite.depuisDecimal(10));
      expect(a.texte, contains('A-rapport n° 1'));
    });

    test('une vente annulée compte en retour', () async {
      final vente = await vendre(code: 'RIZ', quantite: 2);
      await vendre(code: 'RIZ', quantite: 5);
      await depot.annulerVente(vente);

      final ligne = (await rapports.a()).articles.single;

      // La marchandise est bien sortie puis revenue : c'est ce que le
      // A-rapport demande, et c'est plus honnête que de l'effacer.
      expect(ligne.venduee, Quantite.depuisDecimal(5));
      expect(ligne.retournee, Quantite.depuisDecimal(2));
    });

    test('il a sa propre série de clôtures', () async {
      await rapports.z();
      await rapports.a();
      await rapports.a();

      expect((await rapports.clotures(nature: NatureRapport.a)).first.numero, 2);
      expect((await rapports.clotures(nature: NatureRapport.z)).single.numero, 1);
    });

    test('un article sans suivi de stock ne ment pas sur ce qui reste',
        () async {
      await vendre(code: 'RIZ');

      // La plupart des articles ne sont pas suivis. Afficher « 0 en stock »
      // serait faux ; ne rien afficher est juste.
      expect((await rapports.a()).articles.single.enStock, isNull);
    });
  });

  group('Une caisse vide', () {
    test('le Z d\'une journée sans vente ne plante pas', () async {
      final z = await rapports.z();

      expect(z.total, const Montant.zero());
      expect(z.nombreFactures, 0);
      expect(z.texte, contains('Aucune facture sur la période.'));
    });

    test("le A d'une période sans vente non plus", () async {
      expect((await rapports.a()).texte,
          contains('Aucun article vendu sur la période.'));
    });
  });
}
