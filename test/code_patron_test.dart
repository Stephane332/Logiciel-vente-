/// Le code qui protège les numéros marchands.
///
/// C'est le seul réglage qui déplace de l'argent réel : un caissier qui met
/// son numéro à la place de celui de la boutique détourne tous les paiements
/// mobile money, et ça ne se remarque qu'au moment où les SMS cessent
/// d'arriver — ou jamais.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/donnees/sauvegarde.dart';

void main() {
  late BaseLocale base;
  late Parametres parametres;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    parametres = Parametres(base);
  });

  tearDown(() => base.close());

  group('Poser un code', () {
    test("aucun code au départ : il n'y a rien à ouvrir", () async {
      expect(await parametres.codePatronPose(), isFalse);

      // Et surtout, aucun code ne « marche » quand il n'y en a pas : sinon
      // l'écran croirait avoir été ouvert.
      expect(await parametres.codePatronJuste('0000'), isFalse);
      expect(await parametres.codePatronJuste(''), isFalse);
    });

    test('un code posé se reconnaît', () async {
      await parametres.definirCodePatron('4271');

      expect(await parametres.codePatronPose(), isTrue);
      expect(await parametres.codePatronJuste('4271'), isTrue);
    });

    test('un autre code est refusé', () async {
      await parametres.definirCodePatron('4271');

      expect(await parametres.codePatronJuste('4272'), isFalse);
      expect(await parametres.codePatronJuste('427'), isFalse);
      expect(await parametres.codePatronJuste(''), isFalse);
    });

    test('les espaces autour ne changent rien', () async {
      await parametres.definirCodePatron('4271');

      expect(await parametres.codePatronJuste('  4271 '), isTrue);
    });

    test('un code trop court est refusé à la pose', () async {
      expect(() => parametres.definirCodePatron('123'),
          throwsA(isA<ArgumentError>()));
      expect(await parametres.codePatronPose(), isFalse);
    });

    test('un nouveau code remplace le précédent', () async {
      await parametres.definirCodePatron('4271');
      await parametres.definirCodePatron('8890');

      expect(await parametres.codePatronJuste('4271'), isFalse);
      expect(await parametres.codePatronJuste('8890'), isTrue);
    });

    test('on peut le retirer', () async {
      await parametres.definirCodePatron('4271');
      await parametres.retirerCodePatron();

      expect(await parametres.codePatronPose(), isFalse);
      expect(await parametres.codePatronJuste('4271'), isFalse);
    });
  });

  group('Le code ne voyage jamais en clair', () {
    test("il n'est pas lisible dans une sauvegarde", () async {
      await parametres.definirCodePatron('4271');

      final journal = Journal(base, appareil: 'CAISSE1');
      final fichier = await Sauvegardes(base, journal, version: '0.7.1')
          .composer(nomCommerce: 'Chez Awa');

      // Les réglages voyagent avec la sauvegarde, et une sauvegarde s'envoie
      // par WhatsApp. Si le code y était en clair, il suffirait d'ouvrir le
      // fichier pour le lire.
      expect(fichier, isNot(contains('4271')));
    });

    test("ce qui est enregistré n'est pas le code", () async {
      await parametres.definirCodePatron('4271');

      final lignes = await base.select(base.reglages).get();
      final valeur =
          lignes.firstWhere((l) => l.cle == 'patron.code').valeur;

      expect(valeur, isNot('4271'));
      expect(valeur.length, 64, reason: 'une empreinte SHA-256');
    });
  });
}
