/// La facture (§3 de la note de service n° 2025-0889).
///
/// Ces tests portent deux choses très différentes. D'abord que chaque mention
/// obligatoire figure bien sur le papier — c'est ce que je montrerai au comité
/// d'homologation. Ensuite, et c'est le plus important tant que le module de
/// contrôle me manque, qu'une facture **non certifiée le dise**. Un document
/// qui aurait l'air en règle sans l'être exposerait mon client à une sanction.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/calcul_facture.dart';
import 'package:carnet/domaine/facture.dart';
import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/numerotation.dart';
import 'package:carnet/domaine/references.dart';

void main() {
  Montant f(num francs) => Montant.depuisDecimal(francs);

  final emetteur = FicheEntreprise(
    nomCommercial: 'Chez Awa',
    ifu: '00012345A',
    adresse: 'Gounghin, Ouagadougou',
    cadastre: ReferenceCadastrale.analyser('12345678901'),
    telephone: '70 00 00 00',
    regime: RegimeImposition.rni,
    serviceImpots: 'DME Ouaga 1',
  );

  FactureCalculee calcul({
    GroupeTaxation groupe = GroupeTaxation.b,
    num prix = 10000,
    num quantite = 1,
    ModePrix mode = ModePrix.toutesTaxesComprises,
    Montant remise = const Montant.zero(),
  }) =>
      calculerFacture(
        modePrix: mode,
        lignes: [
          LigneACalculer(
            codeArticle: 'CIM',
            designation: 'Ciment CPJ 45, sac de 50 kg',
            groupeTaxation: groupe,
            prixUnitaire: f(prix),
            quantite: Quantite.depuisDecimal(quantite),
            remise: remise,
          )
        ],
      );

  Facture facture({
    ClientFacture? client,
    FactureCalculee? calculee,
    TypeFacture type = TypeFacture.vente,
    Map<ModePaiement, Montant> reglements = const {},
    Montant timbre = const Montant.zero(),
    bool duplicata = false,
    NatureAvoir? nature,
    String? origine,
    String? operateur,
    List<Commentaire> commentaires = const [],
  }) =>
      Facture(
        reference: const ReferenceFacture(type: 'FV', annee: 2026, rang: 42),
        type: type,
        emetteur: emetteur,
        client: client ??
            const ClientFacture(
              type: TypeClient.personneMorale,
              nom: 'SONABEL',
              ifu: '00099887B',
            ),
        calcul: calculee ?? calcul(),
        date: DateTime(2026, 8, 16, 10, 5),
        operateur: operateur,
        reglements: reglements,
        timbreQuittance: timbre,
        duplicata: duplicata,
        natureAvoir: nature,
        factureOrigine: origine,
        commentaires: commentaires,
      );

  group("Ce que la facture dit d'elle-même", () {
    test("une facture sans module de contrôle annonce qu'elle ne vaut pas "
        'facture normalisée', () {
      final texte = facture().texte;

      expect(facture().certifiee, isFalse);
      expect(texte, contains('FACTURE NON CERTIFIÉE'));
      expect(texte, contains('article 564'));
    });

    test("elle ne prétend porter aucun élément de sécurité", () {
      // Ni code SECeF, ni compteurs, ni QR : les inventer serait le pire de
      // tout ce que je pourrais faire ici.
      final texte = facture().texte.toLowerCase();

      expect(texte, isNot(contains('code secef')));
      expect(texte, isNot(contains('compteur')));
    });
  });

  group("Les mentions de l'émetteur", () {
    test('le nom, l\'IFU, l\'adresse et la parcelle sont en tête', () {
      final texte = facture().texte;

      expect(texte, contains('CHEZ AWA'));
      expect(texte, contains('IFU : 00012345A'));
      expect(texte, contains('Gounghin, Ouagadougou'));
      expect(texte, contains('Parcelle : 1234 567 8901'));
      expect(texte, contains('Régime : RNI'));
      expect(texte, contains('Service des impôts : DME Ouaga 1'));
    });

    test("le nom de l'opérateur y figure (mention 25)", () {
      expect(facture(operateur: 'Salif').texte, contains('Établie par Salif'));
      // Et rien de tel chez un commerçant qui vend seul.
      expect(facture().texte, isNot(contains('Établie par')));
    });
  });

  group('Le client', () {
    test('un client comptant ne décline rien', () {
      expect(ClientFacture.comptant.defaut, isNull);
      expect(facture(client: ClientFacture.comptant).texte,
          contains('Client comptant'));
    });

    test('une personne morale doit être nommée et porter un IFU', () {
      expect(const ClientFacture(type: TypeClient.personneMorale).defaut,
          contains('doit être nommé'));
      expect(
        const ClientFacture(type: TypeClient.personneMorale, nom: 'SONABEL')
            .defaut,
        contains('IFU'),
      );
      expect(
        const ClientFacture(
          type: TypeClient.personneMorale,
          nom: 'SONABEL',
          ifu: '00099887B',
        ).defaut,
        isNull,
      );
    });

    test('une personne physique se nomme sans IFU', () {
      expect(
        const ClientFacture(type: TypeClient.personnePhysique, nom: 'Salif')
            .defaut,
        isNull,
      );
    });

    test("l'identité du client s'imprime", () {
      final texte = facture().texte;

      expect(texte, contains('Personne morale'));
      expect(texte, contains('SONABEL'));
      expect(texte, contains('IFU client : 00099887B'));
    });
  });

  group('Les totaux', () {
    test('chaque groupe de taxation porte sa base, son taux et son impôt', () {
      final texte = facture().texte;

      expect(texte, contains('B · TVA taxable 1'));
      expect(texte, contains('Base 18 %'));
      expect(texte, contains('Impôt'));
      expect(texte, contains('TOTAL TTC'));
    });

    test('un groupe exonéré n\'affiche pas de taux', () {
      final texte = facture(calculee: calcul(groupe: GroupeTaxation.a)).texte;

      expect(texte, contains('A · Exonéré'));
      expect(texte, contains('Base —'));
    });

    test('le mode de prix figure sur la facture (§6.4)', () {
      expect(facture().texte, contains('Prix exprimés en TTC'));
      expect(
        facture(calculee: calcul(mode: ModePrix.horsTaxe)).texte,
        contains('Prix exprimés en HT'),
      );
    });

    test('une remise de ligne figure au détail (§3, q)', () {
      final texte = facture(calculee: calcul(remise: f(500))).texte;

      expect(texte, contains('Remise : 500 F'));
    });

    test('le total est repris en toutes lettres', () {
      // 10 000 F TTC.
      expect(facture().texte, contains('dix mille francs CFA'));
      expect(facture().texte, contains('Arrêtée à la somme de'));
    });
  });

  group('Le règlement', () {
    test('la somme des modes doit égaler le total (§2.22)', () {
      expect(
        facture(reglements: {ModePaiement.especes: f(10000)}).defaut,
        isNull,
      );
      expect(
        facture(reglements: {ModePaiement.especes: f(9000)}).defaut,
        contains('§2.22'),
      );
      // Un encaissement mixte se recoupe aussi.
      expect(
        facture(reglements: {
          ModePaiement.especes: f(4000),
          ModePaiement.mobileMoney: f(6000),
        }).defaut,
        isNull,
      );
    });

    test('les modes s\'impriment', () {
      final texte = facture(reglements: {
        ModePaiement.especes: f(4000),
        ModePaiement.mobileMoney: f(6000),
      }).texte;

      expect(texte, contains('Espèces'));
      expect(texte, contains('Mobile money'));
    });

    test('la mention du timbre suit un règlement en espèces', () {
      final avec = facture(
        reglements: {ModePaiement.especes: f(10000)},
        timbre: f(50),
      );
      final sans = facture(reglements: {ModePaiement.mobileMoney: f(10000)});

      expect(avec.regleeEnEspeces, isTrue);
      expect(avec.texte, contains('Montant timbre quittance'));
      expect(sans.regleeEnEspeces, isFalse);
      expect(sans.texte, isNot(contains('Montant timbre quittance')));
    });
  });

  group('Les mentions selon le cas (§3, g)', () {
    test('un duplicata le dit et garde son numéro (§2.18)', () {
      final original = facture();
      final copie = facture(duplicata: true);

      expect(copie.texte, contains('DUPLICATA'));
      expect(copie.reference, original.reference);
    });

    test("une facture d'avoir le dit et porte sa nature (§2.28)", () {
      final avoir = facture(
        type: TypeFacture.avoir,
        nature: NatureAvoir.correction,
        origine: 'FV-2026-000011',
      );

      expect(avoir.texte, contains("FACTURE D'AVOIR"));
      expect(avoir.texte, contains('Correction'));
      expect(avoir.texte, contains("Facture d'origine : FV-2026-000011"));
      expect(avoir.defaut, isNull);
    });

    test("un avoir sans nature est refusé", () {
      expect(facture(type: TypeFacture.avoir).defaut, contains('§2.28'));
    });

    test('une remise passe par un avoir dont la nature vaut RRR (§2.29)', () {
      final remise = facture(
        type: TypeFacture.avoir,
        nature: NatureAvoir.remise,
        origine: 'FV-2026-000011',
      );

      expect(NatureAvoir.remise.code, 'RRR');
      expect(remise.texte, contains('RRR'));
    });

    test("une vente à l'exportation le dit", () {
      expect(facture(type: TypeFacture.venteExport).texte,
          contains('EXPORTATION'));
    });
  });

  group('Les commentaires (§2.27)', () {
    test('huit lignes sont prévues, dont deux dont l\'objet est fixé', () {
      expect(LigneCommentaire.values.length, greaterThanOrEqualTo(8));
      expect(LigneCommentaire.referenceExoneration.code, 'A');
      expect(LigneCommentaire.baseJuridique.code, 'B');
    });

    test('seules les lignes remplies s\'impriment', () {
      final texte = facture(commentaires: const [
        Commentaire(LigneCommentaire.referenceExoneration, 'CE-2026-014'),
        Commentaire(LigneCommentaire.reserveC, '   '),
      ]).texte;

      expect(texte, contains('Réf. exo. : CE-2026-014'));
      expect(texte, isNot(contains('Réservé :')));
    });
  });

  group('Ce qui empêche d\'émettre', () {
    test('un client incomplet', () {
      expect(
        facture(client: const ClientFacture(type: TypeClient.personneMorale))
            .defaut,
        isNotNull,
      );
    });

    test('une facture valable ne reproche rien', () {
      expect(facture().defaut, isNull);
    });

    test('un montant nul est refusé au calcul (§2.24)', () {
      // Le calcul refuse avant même qu'une facture existe : c'est le bon
      // endroit, une facture à zéro ne doit pas pouvoir être construite.
      expect(
        () => calculerFacture(modePrix: ModePrix.toutesTaxesComprises, lignes: [
          LigneACalculer(
            codeArticle: 'X',
            designation: 'Cadeau',
            groupeTaxation: GroupeTaxation.a,
            prixUnitaire: const Montant.zero(),
            quantite: const Quantite.unites(1),
          )
        ]),
        throwsA(isA<ErreurConformite>()),
      );
    });
  });
}
