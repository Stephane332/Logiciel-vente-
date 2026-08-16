/// Le montant en toutes lettres.
///
/// Mention obligatoire de la facture (§3). C'est ce qui empêche d'ajouter un
/// zéro sur un papier signé, et c'est donc un endroit où une faute n'est pas
/// une faute de français : c'est une faute de montant.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/montant_en_lettres.dart';

void main() {
  group('Les petits nombres', () {
    test('de zéro à seize', () {
      expect(entierEnLettres(0), 'zéro');
      expect(entierEnLettres(1), 'un');
      expect(entierEnLettres(7), 'sept');
      expect(entierEnLettres(11), 'onze');
      expect(entierEnLettres(16), 'seize');
    });

    test('de dix-sept à dix-neuf', () {
      expect(entierEnLettres(17), 'dix-sept');
      expect(entierEnLettres(18), 'dix-huit');
      expect(entierEnLettres(19), 'dix-neuf');
    });
  });

  group('Les dizaines, où le français se complique', () {
    test('les dizaines simples', () {
      expect(entierEnLettres(20), 'vingt');
      expect(entierEnLettres(30), 'trente');
      expect(entierEnLettres(60), 'soixante');
    });

    test('« et un » jusqu\'à soixante et un', () {
      expect(entierEnLettres(21), 'vingt et un');
      expect(entierEnLettres(31), 'trente et un');
      expect(entierEnLettres(61), 'soixante et un');
    });

    test('les autres unités prennent un trait', () {
      expect(entierEnLettres(22), 'vingt-deux');
      expect(entierEnLettres(45), 'quarante-cinq');
      expect(entierEnLettres(69), 'soixante-neuf');
    });

    test('soixante-dix se compte à partir de soixante', () {
      expect(entierEnLettres(70), 'soixante-dix');
      expect(entierEnLettres(71), 'soixante et onze');
      expect(entierEnLettres(72), 'soixante-douze');
      expect(entierEnLettres(76), 'soixante-seize');
      expect(entierEnLettres(77), 'soixante-dix-sept');
      expect(entierEnLettres(79), 'soixante-dix-neuf');
    });

    test('quatre-vingts prend un s quand rien ne le suit', () {
      expect(entierEnLettres(80), 'quatre-vingts');
      expect(entierEnLettres(81), 'quatre-vingt-un');
      expect(entierEnLettres(89), 'quatre-vingt-neuf');
    });

    test('quatre-vingt-onze ne prend pas de « et »', () {
      // C'est la faute la plus courante : « quatre-vingt et onze » n'existe
      // pas, parce que quatre-vingt n'est pas une dizaine simple.
      expect(entierEnLettres(90), 'quatre-vingt-dix');
      expect(entierEnLettres(91), 'quatre-vingt-onze');
      expect(entierEnLettres(97), 'quatre-vingt-dix-sept');
      expect(entierEnLettres(99), 'quatre-vingt-dix-neuf');
    });
  });

  group('Les centaines', () {
    test('cent va seul', () {
      expect(entierEnLettres(100), 'cent');
      expect(entierEnLettres(101), 'cent un');
      expect(entierEnLettres(180), 'cent quatre-vingts');
    });

    test('cents prend un s quand rien ne le suit', () {
      expect(entierEnLettres(200), 'deux cents');
      expect(entierEnLettres(201), 'deux cent un');
      expect(entierEnLettres(900), 'neuf cents');
      expect(entierEnLettres(999), 'neuf cent quatre-vingt-dix-neuf');
    });
  });

  group('Les milliers', () {
    test('mille va seul et ne prend jamais de s', () {
      expect(entierEnLettres(1000), 'mille');
      expect(entierEnLettres(2000), 'deux mille');
      expect(entierEnLettres(1001), 'mille un');
      expect(entierEnLettres(1500), 'mille cinq cents');
    });

    test('cent et vingt perdent leur s devant mille', () {
      // La règle qui piège tout le monde : « mille » est un adjectif numéral,
      // il compte comme quelque chose qui suit.
      expect(entierEnLettres(200000), 'deux cent mille');
      expect(entierEnLettres(80000), 'quatre-vingt mille');
      expect(entierEnLettres(280000), 'deux cent quatre-vingt mille');
    });

    test('un montant de tous les jours', () {
      expect(entierEnLettres(145000), 'cent quarante-cinq mille');
      expect(entierEnLettres(7500), 'sept mille cinq cents');
      expect(entierEnLettres(1650), 'mille six cent cinquante');
    });
  });

  group('Les millions et les milliards', () {
    test('ils prennent la marque du pluriel', () {
      expect(entierEnLettres(1000000), 'un million');
      expect(entierEnLettres(2000000), 'deux millions');
      expect(entierEnLettres(1000000000), 'un milliard');
      expect(entierEnLettres(3000000000), 'trois milliards');
    });

    test('cent et vingt gardent leur s devant million', () {
      // « million » est un nom, pas un adjectif numéral : il ne compte pas
      // comme quelque chose qui suit.
      expect(entierEnLettres(200000000), 'deux cents millions');
      expect(entierEnLettres(80000000), 'quatre-vingts millions');
    });

    test('un seuil de régime, en toutes lettres', () {
      expect(entierEnLettres(50000000), 'cinquante millions');
      expect(entierEnLettres(15000000), 'quinze millions');
    });

    test('un nombre qui traverse tous les paliers', () {
      expect(
        entierEnLettres(1234567),
        'un million deux cent trente-quatre mille cinq cent soixante-sept',
      );
    });
  });

  group('Le montant tel qu\'il s\'imprime', () {
    Montant f(num francs) => Montant.depuisDecimal(francs);

    test('la devise suit le nombre', () {
      expect(montantEnLettres(f(650)), 'six cent cinquante francs CFA');
      expect(montantEnLettres(f(7500)), 'sept mille cinq cents francs CFA');
    });

    test('zéro se dit', () {
      expect(montantEnLettres(const Montant.zero()), 'zéro francs CFA');
    });

    test('les centimes n\'apparaissent que s\'il y en a', () {
      // Le franc CFA n'a pas de subdivision en circulation. Écrire « et zéro
      // centime » sur chaque facture serait du bruit.
      expect(montantEnLettres(f(650)), isNot(contains('centime')));
      expect(montantEnLettres(Montant(65050)),
          'six cent cinquante francs CFA et cinquante centimes');
      expect(montantEnLettres(Montant(65001)),
          'six cent cinquante francs CFA et un centime');
    });

    test('un avoir se dit en négatif', () {
      // Une facture d'avoir porte un montant négatif du point de vue du
      // vendeur. Le taire serait ambigu sur un papier signé.
      expect(montantEnLettres(Montant(-65000)), 'moins six cent cinquante francs CFA');
    });

    test('la devise se change', () {
      expect(montantEnLettres(f(100), devise: 'euros'), 'cent euros');
    });
  });
}
