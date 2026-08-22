/// Tests de l'encaissement par mobile money.
///
/// Ces codes sont ce que le client va réellement composer. Une erreur ici ne
/// se voit pas à l'écran : elle se voit quand l'argent part sur le mauvais
/// numéro, ou quand le composeur refuse le code au comptoir. D'où le soin.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/mobile_money.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/parametres.dart';

void main() {
  Montant f(num francs) => Montant.depuisDecimal(francs);

  group('Codes marchands', () {
    test('Orange Money compose le code de paiement marchand', () {
      expect(
        OperateurMobile.orange.code(numero: '70000000', montant: f(2500)),
        '*144*10*70000000*2500#',
      );
    });

    test('chaque opérateur a sa syntaxe', () {
      expect(OperateurMobile.moov.code(numero: '60112233', montant: f(500)),
          '*555*60112233*500#');
      expect(OperateurMobile.telecel.code(numero: '70112233', montant: f(500)),
          '*800*70112233*500#');
    });

    test('le numéro est ramené à sa forme nationale quelle que soit la saisie',
        () {
      for (final saisie in ['70000000', '+226 70 00 00 00', '0022670000000']) {
        expect(
          OperateurMobile.orange.code(numero: saisie, montant: f(1000)),
          '*144*10*70000000*1000#',
        );
      }
    });

    test('le montant part en francs entiers', () {
      // Aucun opérateur d'ici n'accepte de centimes : un code refusé au
      // comptoir fait perdre la vente.
      expect(
        OperateurMobile.orange.code(numero: '70000000', montant: Montant(250050)),
        '*144*10*70000000*2500#',
      );
    });

    test('un numéro invalide est refusé plutôt que composé', () {
      expect(
        () => OperateurMobile.orange.code(numero: '123', montant: f(500)),
        throwsArgumentError,
      );
    });

    test('un montant nul ou négatif est refusé', () {
      expect(
        () => OperateurMobile.orange
            .code(numero: '70000000', montant: const Montant.zero()),
        throwsArgumentError,
      );
    });
  });

  group('Lien du composeur', () {
    test('le dièse est encodé, sans quoi le code est tronqué', () {
      final lien =
          OperateurMobile.orange.lienComposeur(numero: '70000000', montant: f(2500));

      expect(lien, 'tel:*144*10*70000000*2500%23');
      expect(lien, isNot(contains('#')));
    });

    test("l'étoile reste telle quelle : le composeur en a besoin", () {
      final lien =
          OperateurMobile.moov.lienComposeur(numero: '60112233', montant: f(100));
      expect(lien, startsWith('tel:*555*'));
    });
  });

  group('Comptes marchands', () {
    test('un commerçant sans compte ne voit aucun opérateur proposé', () {
      const comptes = ComptesMarchands.aucun();
      expect(comptes.estVide, isTrue);
      expect(comptes.disponibles, isEmpty);
    });

    test('seuls les opérateurs réellement configurés sont proposés', () {
      const comptes = ComptesMarchands({
        OperateurMobile.orange: '70000000',
        OperateurMobile.moov: '60112233',
      });

      expect(comptes.disponibles,
          [OperateurMobile.orange, OperateurMobile.moov]);
      expect(comptes.aUnCompte(OperateurMobile.telecel), isFalse);
    });

    test('un numéro invalide ne rend pas son opérateur disponible', () {
      // Mieux vaut un opérateur absent qu'un code QR qui ne paie personne.
      const comptes = ComptesMarchands({OperateurMobile.orange: '00'});
      expect(comptes.estVide, isTrue);
    });
  });

  group('Réglages enregistrés', () {
    late BaseLocale base;
    late Parametres parametres;

    setUp(() {
      base = BaseLocale(NativeDatabase.memory());
      parametres = Parametres(base);
    });

    tearDown(() => base.close());

    test('une boutique neuve démarre avec des replis utilisables', () async {
      final reglage = await parametres.tout();

      expect(reglage.nomCommerce, Parametres.nomCommerceParDefaut);
      expect(reglage.mobileMoneyAConfigurer, isTrue);
    });

    test('le numéro marchand est rangé sous forme normalisée', () async {
      await parametres.definirNumeroMarchand(
          OperateurMobile.orange, '+226 70 00 00 00');

      final reglage = await parametres.tout();
      expect(reglage.comptes.numeroDe(OperateurMobile.orange), '70000000');
      expect(reglage.mobileMoneyAConfigurer, isFalse);
    });

    test('un numéro invalide est effacé, pas rangé', () async {
      await parametres.definirNumeroMarchand(
          OperateurMobile.orange, '70000000');
      await parametres.definirNumeroMarchand(OperateurMobile.orange, 'zzz');

      final reglage = await parametres.tout();
      expect(reglage.comptes.numeroDe(OperateurMobile.orange), isNull);
    });

    test('vider un champ retire l\'opérateur de la liste', () async {
      await parametres.definirNumeroMarchand(
          OperateurMobile.orange, '70000000');
      await parametres.definirNumeroMarchand(OperateurMobile.orange, '');

      expect((await parametres.tout()).comptes.estVide, isTrue);
    });

    test('le nom du commerce se règle et se relit', () async {
      await parametres.definirNomCommerce('  Alimentation Nabonswendé  ');
      expect((await parametres.tout()).nomCommerce,
          'Alimentation Nabonswendé');
    });

    test('réécrire un réglage le remplace au lieu de le doubler', () async {
      await parametres.definirNomCommerce('Chez Awa');
      await parametres.definirNomCommerce('Chez Salif');

      expect((await parametres.tout()).nomCommerce, 'Chez Salif');
      expect((await base.select(base.reglages).get()).length, 1);
    });
  });
}
