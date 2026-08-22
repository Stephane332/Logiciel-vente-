/// Tests des outils de texte.
///
/// Le SMS se paie à l'unité au Burkina. Un commerçant qui découvre qu'envoyer
/// un lien de paiement lui coûte trois messages arrête d'en envoyer — donc ce
/// qui suit n'est pas un détail d'affichage, c'est ce qui décide si la
/// fonction sera utilisée.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/texte.dart';

void main() {
  group('Sans accents', () {
    test('les accents français tombent, le reste ne bouge pas', () {
      expect(sansAccents('Alimentation Nabonswendé'),
          'Alimentation Nabonswende');
      expect(sansAccents('À payer : 2 500 F'), 'A payer : 2 500 F');
      expect(sansAccents('Café éthiopien'), 'Cafe ethiopien');
    });

    test('les codes USSD traversent intacts', () {
      // Une étoile ou un dièse transformés, et le client compose un code faux.
      expect(sansAccents('*144*10*70000000*2500#'), '*144*10*70000000*2500#');
      expect(sansAccents('tel:*144*10*70000000*2500%23'),
          'tel:*144*10*70000000*2500%23');
    });

    test('un texte déjà sans accent est rendu tel quel', () {
      expect(sansAccents('Sinon compose: 500 F'), 'Sinon compose: 500 F');
    });
  });

  group('Coût en SMS', () {
    test('un texte court sans accent tient en un message', () {
      expect(nombreDeSms('A payer: 2 500 F'), 1);
      expect(tientEnUnSms('Appuie: tel:*144*10*70000000*2500%23'), isTrue);
    });

    test('un seul caractère hors alphabet GSM double le coût', () {
      final cent = 'a' * 100;
      expect(nombreDeSms(cent), 1);

      // Le même texte, avec un À : il bascule en Unicode, la limite tombe à
      // 70, et le message passe à deux segments.
      expect(nombreDeSms('$cent\u00C0'), 2);
    });

    test('tous les accents ne coûtent pas la même chose', () {
      // Contre-intuitif, et c'est pour ça que je le fixe ici : l'alphabet GSM
      // contient é, è, à minuscule et É — mais pas À majuscule, ni ç
      // minuscule, ni les guillemets français, ni le tiret long. Retirer les
      // accents à l'aveugle reste donc la règle sûre.
      for (final gratuit in ['é', 'è', 'à', 'É', 'ù', 'ö']) {
        expect(nombreDeSms('${'a' * 100}$gratuit'), 1,
            reason: '$gratuit est dans l\'alphabet GSM');
      }
      for (final couteux in ['À', 'ç', '«', '»', '—', '·', 'ê']) {
        expect(nombreDeSms('${'a' * 100}$couteux'), 2,
            reason: '$couteux force le message en Unicode');
      }
    });

    test('le message de paiement complet tient en un SMS', () {
      final message = sansAccents([
        'ALIMENTATION NABONSWENDÉ',
        'A payer: 2 500 F',
        'Appuie: tel:*144*10*70000000*2500%23',
        'Sinon compose: *144*10*70000000*2500#',
      ].join('\n'));

      expect(message.length, lessThanOrEqualTo(160));
      expect(tientEnUnSms(message), isTrue,
          reason: 'un message de paiement doit coûter un seul SMS');
    });

    test('le même message avec ses accents en coûterait deux', () {
      // C'est la mesure qui justifie de retirer les accents pour le SMS.
      final avecAccents = [
        'ALIMENTATION NABONSWENDÉ',
        'À payer : 2 500 F',
        'Appuie : tel:*144*10*70000000*2500%23',
        "Sinon compose : *144*10*70000000*2500#",
      ].join('\n');

      expect(nombreDeSms(avecAccents), greaterThan(1));
    });

    test('un message vide ne coûte rien', () {
      expect(nombreDeSms(''), 0);
    });

    test('un long texte se compte en segments concaténés', () {
      expect(nombreDeSms('a' * 161), 2);
      expect(nombreDeSms('a' * 400), 3);
    });
  });
}
