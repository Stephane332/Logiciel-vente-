/// Jeu de tests du moteur de calcul.
///
/// Ce jeu couvre les seize groupes de taxation, les deux modes de prix, la
/// taxe spécifique et le PSVB. C'est lui qui sera présenté au comité
/// d'homologation : chaque test porte la référence du paragraphe qu'il
/// vérifie.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/calcul_facture.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';

Montant f(num francs) => Montant.depuisDecimal(francs);
Quantite q(num unites) => Quantite.depuisDecimal(unites);

LigneACalculer ligne({
  required GroupeTaxation groupe,
  required num prix,
  num quantite = 1,
  num remise = 0,
  num taxeSpecifique = 0,
  GroupePsvb psvb = GroupePsvb.d,
}) =>
    LigneACalculer(
      codeArticle: 'ART',
      designation: 'Article de test',
      groupeTaxation: groupe,
      groupePsvb: psvb,
      prixUnitaire: f(prix),
      quantite: q(quantite),
      remise: f(remise),
      taxeSpecifiqueUnitaire: f(taxeSpecifique),
    );

void main() {
  group('Arithmétique monétaire', () {
    test('aucune dérive de flottant sur des centimes (§6.1)', () {
      var total = const Montant.zero();
      for (var i = 0; i < 10; i++) {
        total = total + Montant.depuisDecimal(0.1);
      }
      expect(total, Montant.depuisDecimal(1));
      expect(total.centimes, 100);
    });

    test('les quantités acceptent trois décimales (§6.1)', () {
      expect(q(1.234).milliemes, 1234);
      expect(q(0.005).milliemes, 5);
    });

    test('les prix acceptent deux décimales (§6.1)', () {
      expect(f(12.34).centimes, 1234);
    });

    test('un prix est ramené à deux décimales dès la saisie (§6.1)', () {
      // 0,335 n'est pas un prix valide : il est arrondi à 0,34.
      expect(f(0.335).centimes, 34);
    });

    test('arrondi à la valeur la plus proche (§6.2)', () {
      // 1,00 × 0,335 = 0,335 → 0,34 au centime le plus proche
      expect(f(1).multiplieParQuantite(q(0.335)).centimes, 34);
      // 1,00 × 0,334 = 0,334 → 0,33
      expect(f(1).multiplieParQuantite(q(0.334)).centimes, 33);
      // 0,33 × 1,5 = 0,495 → 0,50
      expect(f(0.33).multiplieParQuantite(q(1.5)).centimes, 50);
    });

    test('formatage en francs sans décimale', () {
      expect(f(1500).enFrancs, '1 500 F');
      expect(f(145000).enFrancs, '145 000 F');
      expect(f(500).enFrancs, '500 F');
    });
  });

  group('Mode hors taxe (§6.6)', () {
    test('TVA à 18 % sur le groupe B', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [ligne(groupe: GroupeTaxation.b, prix: 1000, quantite: 1)],
      );

      expect(r.totalImposable, f(1000));
      expect(r.totalTaxe, f(180));
      expect(r.totalTtc, f(1180));
      expect(r.estCoherente, isTrue);
    });

    test('TVA à 10 % sur le groupe C', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [ligne(groupe: GroupeTaxation.c, prix: 2000)],
      );

      expect(r.totalImposable, f(2000));
      expect(r.totalTaxe, f(200));
      expect(r.totalTtc, f(2200));
    });

    test('le calcul part du prix unitaire, pas du total (§6.5)', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [ligne(groupe: GroupeTaxation.b, prix: 333.33, quantite: 3)],
      );

      // 333,33 × 3 = 999,99
      expect(r.lignes.single.montantBrut, f(999.99));
    });

    test('la remise se déduit avant la taxe', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [
          ligne(groupe: GroupeTaxation.b, prix: 1000, remise: 200),
        ],
      );

      expect(r.totalImposable, f(800));
      expect(r.totalTaxe, f(144));
      expect(r.totalTtc, f(944));
    });
  });

  group('Mode toutes taxes comprises (§6.6)', () {
    test('la TVA se déduit du montant total du groupe', () {
      final r = calculerFacture(
        modePrix: ModePrix.toutesTaxesComprises,
        lignes: [ligne(groupe: GroupeTaxation.b, prix: 1180)],
      );

      expect(r.totalTtc, f(1180));
      expect(r.totalTaxe, f(180));
      expect(r.totalImposable, f(1000));
      expect(r.estCoherente, isTrue);
    });

    test('un montant non rond reste cohérent', () {
      final r = calculerFacture(
        modePrix: ModePrix.toutesTaxesComprises,
        lignes: [ligne(groupe: GroupeTaxation.b, prix: 1000)],
      );

      expect(r.totalTtc, f(1000));
      expect(r.totalImposable + r.totalTaxe, f(1000));
      expect(r.estCoherente, isTrue);
    });
  });

  group("Égalité comptable et arrondi supérieur (§6.7)", () {
    test('la taxe est arrondie à la valeur supérieure', () {
      // 105 × 18 % = 18,90 exactement
      final exact = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [ligne(groupe: GroupeTaxation.b, prix: 105)],
      );
      expect(exact.totalTaxe, f(18.90));

      // 100,01 × 18 % = 18,0018 → 18,01 par arrondi supérieur
      final arrondi = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [ligne(groupe: GroupeTaxation.b, prix: 100.01)],
      );
      expect(arrondi.totalTaxe, f(18.01));
    });

    test('imposable + taxe = total, sur mille montants en mode HT', () {
      for (var centimes = 1; centimes <= 100000; centimes += 97) {
        final r = calculerFacture(
          modePrix: ModePrix.horsTaxe,
          lignes: [
            LigneACalculer(
              codeArticle: 'A',
              designation: 'x',
              groupeTaxation: GroupeTaxation.b,
              prixUnitaire: Montant(centimes),
              quantite: const Quantite.unites(1),
            )
          ],
        );
        expect(r.estCoherente, isTrue,
            reason: 'incohérence à $centimes centimes');
      }
    });

    test('imposable + taxe = total, sur mille montants en mode TTC', () {
      for (var centimes = 1; centimes <= 100000; centimes += 97) {
        final r = calculerFacture(
          modePrix: ModePrix.toutesTaxesComprises,
          lignes: [
            LigneACalculer(
              codeArticle: 'A',
              designation: 'x',
              groupeTaxation: GroupeTaxation.b,
              prixUnitaire: Montant(centimes),
              quantite: const Quantite.unites(1),
            )
          ],
        );
        expect(r.estCoherente, isTrue,
            reason: 'incohérence à $centimes centimes');
        expect(r.totalTtc.centimes, centimes);
      }
    });
  });

  group('Taxe spécifique (§6.8, §6.9)', () {
    test('la taxe spécifique augmente la base de la TVA en mode HT', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [
          ligne(groupe: GroupeTaxation.b, prix: 1000, taxeSpecifique: 100),
        ],
      );

      // Base = 1000 + 100 = 1100 ; TVA = 198 ; total = 1298
      expect(r.totalTaxeSpecifique, f(100));
      expect(r.totalImposable, f(1100));
      expect(r.totalTaxe, f(198));
      expect(r.totalTtc, f(1298));
      expect(r.estCoherente, isTrue);
    });

    test('la taxe spécifique suit la quantité', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [
          ligne(
              groupe: GroupeTaxation.b,
              prix: 500,
              quantite: 4,
              taxeSpecifique: 25),
        ],
      );

      expect(r.totalTaxeSpecifique, f(100));
      expect(r.totalImposable, f(2100));
    });

    test('sur un groupe exonéré, elle s\'ajoute sans TVA', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [
          ligne(groupe: GroupeTaxation.a, prix: 1000, taxeSpecifique: 50),
        ],
      );

      expect(r.totalTaxe, const Montant.zero());
      expect(r.totalTtc, f(1050));
    });
  });

  group('Les seize groupes de taxation (§2.15)', () {
    test('chaque groupe produit un total cohérent', () {
      for (final groupe in GroupeTaxation.tous) {
        final r = calculerFacture(
          modePrix: ModePrix.horsTaxe,
          lignes: [ligne(groupe: groupe, prix: 1234.56, quantite: 3)],
        );

        expect(r.estCoherente, isTrue,
            reason: 'groupe ${groupe.etiquette} incohérent');

        final total = r.totauxParGroupe.single;
        if (groupe.estTaxe) {
          expect(total.taxe.estPositif, isTrue,
              reason: 'groupe ${groupe.etiquette} devrait être taxé');
        } else {
          expect(total.taxe.estNul, isTrue,
              reason: 'groupe ${groupe.etiquette} ne devrait pas être taxé');
        }
      }
    });

    test('les taux correspondent à la note de service', () {
      expect(GroupeTaxation.b.tauxMillieme, 180); // 18 %
      expect(GroupeTaxation.c.tauxMillieme, 100); // 10 %
      expect(GroupeTaxation.f.tauxMillieme, 180); // 18 %
      expect(GroupeTaxation.g.tauxMillieme, 100); // 10 %
      expect(GroupeTaxation.l.tauxMillieme, 100); // TDT 10 %
      expect(GroupeTaxation.m.tauxMillieme, 100); // séjour 10 %
      expect(GroupeTaxation.a.tauxMillieme, isNull); // exonéré
      expect(GroupeTaxation.tous.length, 16);
    });

    test('les groupes sont totalisés séparément (§3.o, §3.q)', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [
          ligne(groupe: GroupeTaxation.b, prix: 1000),
          ligne(groupe: GroupeTaxation.c, prix: 1000),
          ligne(groupe: GroupeTaxation.a, prix: 1000),
        ],
      );

      expect(r.totauxParGroupe.length, 3);
      expect(r.totalTaxe, f(280)); // 180 + 100 + 0
      expect(r.totalTtc, f(3280));
      expect(r.estCoherente, isTrue);
    });
  });

  group('PSVB (§2.16, §6.10)', () {
    test('se calcule sur le montant toutes taxes comprises', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [
          ligne(groupe: GroupeTaxation.b, prix: 10000, psvb: GroupePsvb.a),
        ],
      );

      // TTC = 11 800 ; PSVB à 2 % = 236
      expect(r.totalTtc, f(11800));
      expect(r.psvb, f(236));
    });

    test('le groupe D ne prélève rien', () {
      final r = calculerFacture(
        modePrix: ModePrix.horsTaxe,
        lignes: [
          ligne(groupe: GroupeTaxation.b, prix: 10000, psvb: GroupePsvb.d),
        ],
      );

      expect(r.psvb, const Montant.zero());
    });

    test('les taux correspondent à la note de service', () {
      expect(GroupePsvb.a.tauxDixMillieme, 200); // 2 %
      expect(GroupePsvb.b.tauxDixMillieme, 100); // 1 %
      expect(GroupePsvb.c.tauxDixMillieme, 20); //  0,2 %
      expect(GroupePsvb.d.tauxDixMillieme, 0); //   0 %
    });
  });

  group('Contrôles de conformité', () {
    test('une facture sans article est refusée (§2.6)', () {
      expect(
        () => calculerFacture(modePrix: ModePrix.horsTaxe, lignes: []),
        throwsA(isA<ErreurConformite>()),
      );
    });

    test('un article à montant nul est refusé (§2.25)', () {
      expect(
        () => calculerFacture(
          modePrix: ModePrix.horsTaxe,
          lignes: [ligne(groupe: GroupeTaxation.b, prix: 0)],
        ),
        throwsA(isA<ErreurConformite>()),
      );
    });

    test('un article à montant négatif est refusé (§2.25)', () {
      expect(
        () => calculerFacture(
          modePrix: ModePrix.horsTaxe,
          lignes: [ligne(groupe: GroupeTaxation.b, prix: 1000, remise: 1500)],
        ),
        throwsA(isA<ErreurConformite>()),
      );
    });

    test('une quantité nulle est refusée (§2.25)', () {
      expect(
        () => calculerFacture(
          modePrix: ModePrix.horsTaxe,
          lignes: [ligne(groupe: GroupeTaxation.b, prix: 1000, quantite: 0)],
        ),
        throwsA(isA<ErreurConformite>()),
      );
    });
  });

  group('Tables de référence', () {
    test('les six types de facture sont définis (§2.7)', () {
      expect(TypeFacture.values.length, 6);
      expect(TypeFacture.vente.etiquette, 'FV');
      expect(TypeFacture.acompte.etiquette, 'FT');
      expect(TypeFacture.avoir.etiquette, 'FA');
      expect(TypeFacture.venteExport.etiquette, 'EV');
      expect(TypeFacture.acompteExport.etiquette, 'ET');
      expect(TypeFacture.avoirExport.etiquette, 'EA');
    });

    test('les quatre types de client sont définis (§2.14)', () {
      expect(TypeClient.values.length, 4);
      expect(TypeClient.comptant.nomRequis, isFalse);
      expect(TypeClient.personneMorale.ifuRequis, isTrue);
      expect(TypeClient.personnePhysique.ifuRequis, isFalse);
      expect(TypeClient.personnePhysiqueCommercant.ifuRequis, isTrue);
    });

    test('les quatre natures de facture d\'avoir sont définies (§2.28)', () {
      expect(NatureAvoir.values.length, 4);
      expect(NatureAvoir.remise.code, 'RRR');
      expect(NatureAvoir.remise.mention, 'RRR');
    });

    test('les six modes de paiement sont définis (§2.21)', () {
      expect(ModePaiement.values.length, 6);
      expect(ModePaiement.mobileMoney.libelle, 'Mobile money');
    });

    test('huit lignes de commentaire au minimum (§2.27)', () {
      expect(LigneCommentaire.values.length, greaterThanOrEqualTo(8));
    });

    test('le service importé porte sa mention', () {
      expect(TypeArticle.serviceImporte.mention, '[IMPSER]');
      expect(TypeArticle.bienLocal.mention, isNull);
    });
  });
}
