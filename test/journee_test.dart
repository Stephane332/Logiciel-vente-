/// Une journée entière, et les chiffres qui doivent se recouper.
///
/// Chaque écran a ses tests. Ce qu'aucun ne vérifie, c'est que les écrans
/// **disent la même chose** : le rapport du soir, la clôture Z, la facture et
/// le cahier de dettes calculent chacun de leur côté, à partir des mêmes
/// ventes, par des chemins différents.
///
/// Un commerçant qui voit 145 000 F sur un écran et 143 500 F sur l'autre
/// n'appelle pas pour demander lequel est juste. Il cesse d'ouvrir
/// l'application, et il a raison — un carnet qui se contredit ne vaut pas
/// mieux qu'un carnet faux.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/facture.dart';
import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/periode.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/documents.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/rapports.dart';

void main() {
  late BaseLocale base;
  late Journal journal;
  late Depot depot;
  late Documents documents;
  late Rapports rapports;

  /// La quincaillerie du rapport de veille : elle vend au comptoir toute la
  /// journée, fait crédit à deux habitués, et facture une entreprise.
  final fiche = FicheEntreprise(
    nomCommercial: 'Quincaillerie du Faso',
    ifu: '00012345A',
    adresse: 'Gounghin, Ouagadougou',
    cadastre: ReferenceCadastrale.analyser('12345678901'),
    telephone: '70000000',
    regime: RegimeImposition.rni,
    serviceImpots: 'DME Ouaga 1',
  );

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    journal = Journal(base, appareil: 'CAISSE1');
    depot = Depot(base, journal);
    documents = Documents(base,
        nomCommerce: fiche.nomCommercial, fiche: fiche);
    rapports = Rapports(base, journal, fiche: fiche);
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  final jour = DateTime(2026, 8, 10);
  DateTime heure(int h, [int m = 0]) =>
      DateTime(jour.year, jour.month, jour.day, h, m);

  Future<String> vendre({
    required num prix,
    required ModePaiement mode,
    String? client,
    String code = 'CIM',
    String designation = 'Ciment CPJ 45',
    required DateTime quand,
  }) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: code,
            designation: designation,
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [PaiementAEnregistrer(mode: mode, montant: f(prix))],
        clientId: client,
        horodatage: quand,
      );

  /// La journée : huit ventes au comptoir, deux à crédit, une par téléphone.
  Future<({String pourFacture, String salif, String awa})> journee() async {
    final salif = await depot.creerClient(nom: 'Salif', telephone: '70112233');
    final awa = await depot.creerClient(nom: 'Awa');

    // Le comptoir, du matin au soir.
    for (var i = 0; i < 8; i++) {
      await vendre(
        prix: 2500,
        mode: ModePaiement.especes,
        quand: heure(8 + i),
      );
    }

    // Un client qui paie par téléphone.
    await vendre(
      prix: 12000,
      mode: ModePaiement.mobileMoney,
      quand: heure(11, 30),
    );

    // Deux habitués à crédit.
    await vendre(
      prix: 7500,
      mode: ModePaiement.credit,
      client: salif,
      quand: heure(14),
    );
    await vendre(
      prix: 3000,
      mode: ModePaiement.credit,
      client: awa,
      quand: heure(16),
    );

    // Et l'entreprise qui réclamera une facture.
    final pourFacture = await vendre(
      prix: 45000,
      mode: ModePaiement.especes,
      quand: heure(17),
    );

    return (pourFacture: pourFacture, salif: salif, awa: awa);
  }

  // Encaissé au comptoir : 8 × 2 500 + 45 000 = 65 000 en espèces.
  // Par téléphone : 12 000. À crédit : 10 500. Total vendu : 87 500.
  final especes = f(65000);
  final mobile = f(12000);
  final credit = f(10500);
  final total = f(87500);

  group('Le rapport du soir et la clôture disent la même chose', () {
    test("l'encaissé du rapport correspond aux modes de la clôture", () async {
      await journee();

      final rapport = await depot.rapportSurPeriode(
          Periode.jour.bornes(heure(23)).$1, heure(23));
      final z = await rapports.z(quand: heure(23));

      // Le rapport du soir compte ce qui est rentré ; la clôture le ventile
      // par mode. Les deux doivent tomber sur le même chiffre.
      expect(rapport.encaisse, especes + mobile);
      expect(
        (z.parMode[ModePaiement.especes] ?? const Montant.zero()) +
            (z.parMode[ModePaiement.mobileMoney] ?? const Montant.zero()),
        rapport.encaisse,
      );
    });

    test('le crédit du rapport correspond au crédit de la clôture', () async {
      await journee();

      final rapport = await depot.rapportSurPeriode(
          Periode.jour.bornes(heure(23)).$1, heure(23));
      final z = await rapports.z(quand: heure(23));

      expect(rapport.aCredit, credit);
      expect(z.parMode[ModePaiement.credit], credit);
    });

    test('le total de la clôture est tout ce qui a été vendu', () async {
      await journee();

      final z = await rapports.z(quand: heure(23));

      // Y compris ce qui n'est pas encore payé : une vente à crédit est une
      // vente, la note de service ne fait pas de différence.
      expect(z.total, total);
      expect(z.nombreFactures, 12);
    });

    test('ce qui doit être dans le tiroir, ce sont les espèces seules',
        () async {
      await journee();

      final z = await rapports.z(quand: heure(23));

      // Le mobile money est sur le téléphone, le crédit n'est nulle part.
      expect(z.especes, especes);
      expect(z.especes.centimes, lessThan(z.total.centimes));
    });
  });

  group('Le cahier de dettes correspond à la clôture', () {
    test("la somme des ardoises égale le crédit du jour", () async {
      final ids = await journee();
      await rapports.z(quand: heure(23));

      final salif = await documents.ardoise(ids.salif, arreteeAu: heure(23));
      final awa = await documents.ardoise(ids.awa, arreteeAu: heure(23));

      expect(salif!.encours + awa!.encours, credit);
    });

    test('un remboursement descend la dette sans toucher au Z déjà tiré',
        () async {
      final ids = await journee();
      final z = await rapports.z(quand: heure(23));

      await depot.rembourserCredit(ids.salif, f(2500));

      final salif = await documents.ardoise(ids.salif);
      expect(salif!.encours, f(5000));
      // Le Z a été remis au commerçant : il ne bouge plus.
      expect((await rapports.clotures()).first.total, z.total);
    });
  });

  group('La facture correspond à la vente', () {
    test('son total est celui de la vente, au franc près', () async {
      final ids = await journee();

      final reference = await depot.emettreFacture(ids.pourFacture);
      final facture = await documents.composerFacture(
        ids.pourFacture,
        reference: reference,
        client: const ClientFacture(
          type: TypeClient.personneMorale,
          nom: 'SONABEL',
          ifu: '00099887B',
        ),
      );

      expect(facture!.calcul.totalTtc, f(45000));
      expect(facture.defaut, isNull);
      expect(facture.texte, contains('quarante-cinq mille francs CFA'));
    });

    test('facturer ne change rien aux totaux du jour', () async {
      final ids = await journee();

      final avant = await rapports.x(fin: heure(23));
      await depot.emettreFacture(ids.pourFacture);
      final apres = await rapports.x(fin: heure(23));

      // Une facture est une **sortie**, pas une vente de plus. La confondre
      // ferait compter deux fois la même marchandise.
      expect(apres.total, avant.total);
      expect(apres.nombreFactures, avant.nombreFactures);
    });
  });

  group('Tout se retrouve après une reconstruction', () {
    test('les chiffres sont identiques avant et après', () async {
      final ids = await journee();
      await depot.emettreFacture(ids.pourFacture);

      final avant = await rapports.x(fin: heure(23));
      await depot.reconstruireProjections();
      final apres = await rapports.x(fin: heure(23));

      expect(apres.total, avant.total);
      expect(apres.especes, avant.especes);
      expect(apres.nombreFactures, avant.nombreFactures);
      // Et la facture garde son numéro : c'est le journal qui le porte.
      expect(await depot.referenceFacture(ids.pourFacture), isNotNull);
    });

    test('les dettes reviennent telles quelles', () async {
      final ids = await journee();
      await depot.reconstruireProjections();

      final salif = await documents.ardoise(ids.salif, arreteeAu: heure(23));
      final awa = await documents.ardoise(ids.awa, arreteeAu: heure(23));

      expect(salif!.encours + awa!.encours, credit);
    });

    test('le journal reste intact', () async {
      await journee();
      await rapports.z(quand: heure(23));
      await depot.reconstruireProjections();

      final verification = await journal.verifier();
      expect(verification.intact, isTrue, reason: verification.motif ?? '');
    });
  });

  group('Une annulation se répercute partout', () {
    test('elle sort du total, de la caisse et de la dette', () async {
      final ids = await journee();
      await depot.annulerVente(ids.pourFacture);

      final z = await rapports.z(quand: heure(23));

      expect(z.total, total - f(45000));
      expect(z.especes, especes - f(45000));
      expect(z.autresReductions, f(45000));
      expect(z.nombreFactures, 11);
    });
  });
}
