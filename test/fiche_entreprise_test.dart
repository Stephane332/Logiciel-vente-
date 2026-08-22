/// La fiche entreprise : les mentions que la DGI exige de l'émetteur.
///
/// Deux exigences se contredisent presque, et c'est tout l'objet de ces
/// tests : l'application doit encaisser sans qu'on ait rien rempli, **et**
/// une facture certifiée doit porter des mentions dont la forme est imposée.
/// La réponse est la même partout ici — tout est facultatif, mais ce qui est
/// rempli est rempli juste.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/parametres.dart';

void main() {
  group('Les références cadastrales', () {
    test('onze chiffres se découpent en section, lot et parcelle', () {
      final reference = ReferenceCadastrale.analyser('12345678901')!;

      expect(reference.section, '1234');
      expect(reference.lot, '567');
      expect(reference.parcelle, '8901');
      expect(reference.lisible, '1234 567 8901');
      expect(reference.compact, '12345678901');
    });

    test('la ponctuation du papier est ignorée', () {
      // Le commerçant recopie ce qu'il lit, et son papier ponctue comme il
      // veut. Lui reprocher un tiret serait un obstacle sans objet.
      for (final saisie in [
        '1234 567 8901',
        '1234-567-8901',
        '1234.567.8901',
        '  1234  567  8901  ',
      ]) {
        expect(ReferenceCadastrale.analyser(saisie)?.compact, '12345678901',
            reason: saisie);
      }
    });

    test('autre chose que onze chiffres ne passe pas', () {
      expect(ReferenceCadastrale.analyser('1234567890'), isNull);
      expect(ReferenceCadastrale.analyser('123456789012'), isNull);
      expect(ReferenceCadastrale.analyser('ABCD EFG HIJK'), isNull);
      expect(ReferenceCadastrale.analyser(''), isNull);
      expect(ReferenceCadastrale.analyser(null), isNull);
    });

    test('le défaut dit combien il en manque', () {
      expect(ReferenceCadastrale.defaut('1234567'),
          'Onze chiffres attendus, il en manque 4.');
      expect(ReferenceCadastrale.defaut('123456789012'),
          'Onze chiffres attendus, il y en a 1 de trop.');
      expect(ReferenceCadastrale.defaut('AB'),
          'Les références cadastrales sont onze chiffres.');
    });

    test('un champ vide ne reproche rien', () {
      // Rien n'est obligatoire. Un champ laissé vide n'est pas une erreur, et
      // afficher un reproche sous un champ vide ferait fuir.
      expect(ReferenceCadastrale.defaut(''), isNull);
      expect(ReferenceCadastrale.defaut('   '), isNull);
      expect(ReferenceCadastrale.defaut(null), isNull);
      expect(ReferenceCadastrale.defaut('1234 567 8901'), isNull);
    });

    test('deux références identiques se valent', () {
      expect(ReferenceCadastrale.analyser('1234 567 8901'),
          ReferenceCadastrale.analyser('12345678901'));
    });
  });

  group("L'IFU", () {
    test('huit chiffres et une lettre', () {
      expect(Ifu.normaliser('00012345A'), '00012345A');
      expect(Ifu.normaliser('00012345a'), '00012345A');
      expect(Ifu.normaliser('000 123 45 A'), '00012345A');
    });

    test('une autre forme est refusée', () {
      expect(Ifu.normaliser('12345A'), isNull);
      expect(Ifu.normaliser('123456789'), isNull);
      expect(Ifu.normaliser('A00012345'), isNull);
      expect(Ifu.normaliser(''), isNull);
    });

    test('le défaut se tait sur un champ vide', () {
      expect(Ifu.defaut(''), isNull);
      expect(Ifu.defaut(null), isNull);
      expect(Ifu.defaut('00012345A'), isNull);
      expect(Ifu.defaut('123'), "L'IFU est huit chiffres suivis d'une lettre.");
    });
  });

  group("Le régime d'imposition", () {
    test('seul le Régime Normal impose la certification', () {
      expect(RegimeImposition.cme.certificationObligatoire, isFalse);
      expect(RegimeImposition.rsi.certificationObligatoire, isFalse);
      expect(RegimeImposition.rni.certificationObligatoire, isTrue);
    });

    test('le chiffre d\'affaires désigne un régime', () {
      expect(RegimeImposition.depuisChiffreAffaires(3000000),
          RegimeImposition.cme);
      expect(RegimeImposition.depuisChiffreAffaires(15000000),
          RegimeImposition.rsi);
      expect(RegimeImposition.depuisChiffreAffaires(49999999),
          RegimeImposition.rsi);
      expect(RegimeImposition.depuisChiffreAffaires(50000000),
          RegimeImposition.rni);
    });

    test('une étiquette inconnue ne fait pas tomber la lecture', () {
      // Une sauvegarde peut venir d'une version plus récente qui connaît un
      // régime que celle-ci ignore. Mieux vaut un régime nul qu'un plantage
      // au démarrage.
      expect(RegimeImposition.parEtiquette('ZZZ'), isNull);
      expect(RegimeImposition.parEtiquette(null), isNull);
      expect(RegimeImposition.parEtiquette('RNI'), RegimeImposition.rni);
    });
  });

  group('Ce qui manque', () {
    test('une fiche vide manque de tout, et chaque manque se justifie', () {
      const fiche = FicheEntreprise(nomCommercial: 'Chez Awa');

      expect(fiche.complete, isFalse);
      expect(fiche.manques.map((m) => m.quoi), [
        'IFU',
        'Références cadastrales',
        'Adresse de vente',
        'Contact',
        "Régime d'imposition",
        'Service des impôts',
      ]);
      // Chaque manque dit où aller le chercher : une liste de mots seuls
      // laisserait le commerçant deviner.
      for (final manque in fiche.manques) {
        expect(manque.pourquoi, isNotEmpty, reason: manque.quoi);
      }
    });

    test('une fiche remplie ne manque de rien', () {
      final fiche = FicheEntreprise(
        nomCommercial: 'Chez Awa',
        ifu: '00012345A',
        cadastre: ReferenceCadastrale.analyser('1234 567 8901'),
        adresse: 'Gounghin, Ouagadougou',
        telephone: '70 00 00 00',
        regime: RegimeImposition.rni,
        serviceImpots: 'DME Ouaga 1',
      );

      expect(fiche.manques, isEmpty);
      expect(fiche.complete, isTrue);
    });

    test('un champ rempli d\'espaces ne compte pas comme rempli', () {
      const fiche = FicheEntreprise(
        nomCommercial: 'Chez Awa',
        adresse: '   ',
        telephone: '',
      );

      expect(fiche.manques.map((m) => m.quoi),
          containsAll(['Adresse de vente', 'Contact']));
    });
  });

  group("L'en-tête imprimé", () {
    test('une boutique sans mentions ne porte que son nom', () {
      // C'est le cas de la quasi-totalité de mes utilisateurs. Une facture
      // avec cinq lignes blanches à la place des mentions serait pire que
      // pas de mentions du tout.
      const fiche = FicheEntreprise(nomCommercial: 'Chez Awa');

      expect(fiche.enTete, ['CHEZ AWA']);
    });

    test('une entreprise complète porte chaque mention', () {
      final fiche = FicheEntreprise(
        nomCommercial: 'Chez Awa',
        raisonSociale: 'SARL Sawadogo et Frères',
        ifu: '00012345A',
        cadastre: ReferenceCadastrale.analyser('12345678901'),
        adresse: 'Gounghin, Ouagadougou',
        telephone: '70 00 00 00',
        courriel: 'contact@example.bf',
        regime: RegimeImposition.rni,
        serviceImpots: 'DME Ouaga 1',
        referencesBancaires: 'Coris Bank · BF00 0000 0000',
      );

      expect(fiche.enTete, [
        'SARL SAWADOGO ET FRÈRES',
        'Chez Awa',
        'IFU : 00012345A',
        'Gounghin, Ouagadougou',
        'Parcelle : 1234 567 8901',
        'Tél. : 70 00 00 00',
        'contact@example.bf',
        'Régime : RNI',
        'Service des impôts : DME Ouaga 1',
        'Coris Bank · BF00 0000 0000',
      ]);
    });

    test("c'est la raison sociale qui engage, pas l'enseigne", () {
      const avec = FicheEntreprise(
        nomCommercial: 'Chez Awa',
        raisonSociale: 'SARL Sawadogo et Frères',
      );
      const sans = FicheEntreprise(nomCommercial: 'Chez Awa');

      expect(avec.denomination, 'SARL Sawadogo et Frères');
      expect(sans.denomination, 'Chez Awa');
    });
  });

  group('Ce qui est enregistré', () {
    late BaseLocale base;
    late Parametres parametres;

    setUp(() {
      base = BaseLocale(NativeDatabase.memory());
      parametres = Parametres(base);
    });

    tearDown(() => base.close());

    test('une fiche vide se relit vide, sans le nom par défaut ailleurs',
        () async {
      final reglage = await parametres.tout();

      expect(reglage.fiche.nomCommercial, Parametres.nomCommerceParDefaut);
      expect(reglage.fiche.ifu, isNull);
      expect(reglage.fiche.renseignee, isFalse);
    });

    test('une fiche remplie se relit telle quelle', () async {
      await parametres.definirFiche(FicheEntreprise(
        nomCommercial: 'Chez Awa',
        raisonSociale: 'SARL Sawadogo et Frères',
        ifu: '00012345A',
        cadastre: ReferenceCadastrale.analyser('1234 567 8901'),
        adresse: 'Gounghin, Ouagadougou',
        telephone: '70 00 00 00',
        courriel: 'contact@example.bf',
        regime: RegimeImposition.rni,
        serviceImpots: 'DME Ouaga 1',
        referencesBancaires: 'Coris Bank · BF00 0000 0000',
      ));

      final relue = (await parametres.tout()).fiche;

      expect(relue.nomCommercial, 'Chez Awa');
      expect(relue.raisonSociale, 'SARL Sawadogo et Frères');
      expect(relue.ifu, '00012345A');
      expect(relue.cadastre?.lisible, '1234 567 8901');
      expect(relue.regime, RegimeImposition.rni);
      expect(relue.serviceImpots, 'DME Ouaga 1');
      expect(relue.renseignee, isTrue);
      expect(relue.complete, isTrue);
    });

    test('un IFU mal formé ne descend pas dans la base', () async {
      await parametres.definirFiche(const FicheEntreprise(
        nomCommercial: 'Chez Awa',
        ifu: 'pas un ifu',
      ));

      expect((await parametres.tout()).fiche.ifu, isNull);
    });

    test('vider une mention efface la clé au lieu de ranger du vide',
        () async {
      await parametres.definirFiche(const FicheEntreprise(
        nomCommercial: 'Chez Awa',
        adresse: 'Gounghin',
      ));
      await parametres.definirFiche(const FicheEntreprise(
        nomCommercial: 'Chez Awa',
        adresse: '  ',
      ));

      // Une chaîne vide se lirait comme « mention remplie avec rien », et la
      // liste des manques cesserait de la réclamer.
      final lignes = await base.select(base.reglages).get();
      expect(lignes.map((l) => l.cle), isNot(contains('entreprise.adresse')));
      expect((await parametres.tout()).fiche.manques.map((m) => m.quoi),
          contains('Adresse de vente'));
    });

    test('le nom du commerce et celui de la fiche restent le même', () async {
      // Deux noms qui divergeraient, c'est une facture qui ne dit pas la même
      // chose que le reçu.
      await parametres.definirFiche(
          const FicheEntreprise(nomCommercial: 'Chez Awa'));

      final reglage = await parametres.tout();
      expect(reglage.nomCommerce, 'Chez Awa');
      expect(reglage.fiche.nomCommercial, 'Chez Awa');
    });

    test('les mentions ne passent pas par le journal', () async {
      // Ce ne sont pas des faits commerciaux : elles se corrigent, et une
      // correction ne doit pas laisser l'ancienne valeur lisible pour
      // toujours. Le journal, lui, ne se réécrit jamais.
      await parametres.definirFiche(const FicheEntreprise(
        nomCommercial: 'Chez Awa',
        ifu: '00012345A',
      ));

      expect(await base.select(base.evenements).get(), isEmpty);
    });
  });
}
