/// Tests des éléments de sécurité et du code QR.
///
/// Le cas de référence est celui de la documentation officielle e-MECeF v1.0.
/// Il servira de cas de test dans le dossier d'homologation.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/certification.dart';

void main() {
  // Exemple tiré de la documentation officielle :
  // qrCode       F;IN01000005;X537E4DBAJUUHHXNFWISFEKJ;9999900000001;20201123131708
  // codeMECeFDGI X537-E4DB-AJUU-HHXN-FWIS-FEKJ
  // nim          IN01000005
  // counters     64/64 FV
  // dateTime     23/11/2020 13:17:08
  const qrReference =
      'F;IN01000005;X537E4DBAJUUHHXNFWISFEKJ;9999900000001;20201123131708';

  final reference = ElementsSecurite(
    nim: 'IN01000005',
    codeSecefDgi: 'X537-E4DB-AJUU-HHXN-FWIS-FEKJ',
    ifu: '9999900000001',
    horodatage: DateTime(2020, 11, 23, 13, 17, 8),
    compteurs: '64/64 FV',
  );

  group('Composition du code QR', () {
    test('reproduit exactement le cas de la documentation officielle', () {
      expect(reference.codeQr, qrReference);
    });

    test('le code SECeF/DGI perd ses tirets dans le QR', () {
      expect(reference.codeCompact, 'X537E4DBAJUUHHXNFWISFEKJ');
      expect(reference.codeCompact.length, 24);
    });

    test('le QR ne contient ni montant ni adresse de vérification', () {
      expect(reference.codeQr, isNot(contains('http')));
      expect(reference.codeQr.split(';'), hasLength(5));
    });

    test("l'horodatage est complété à gauche par des zéros", () {
      final tot = ElementsSecurite(
        nim: 'BF01000001',
        codeSecefDgi: 'AAAA-BBBB',
        ifu: '00012345678',
        horodatage: DateTime(2026, 1, 5, 8, 4, 9),
        compteurs: '1/1 FV',
      );
      expect(tot.codeQr.split(';').last, '20260105080409');
    });
  });

  group('Relecture du code QR', () {
    test('un aller-retour conserve toutes les données', () {
      final relu = ElementsSecurite.depuisCodeQr(qrReference);

      expect(relu.marqueur, 'F');
      expect(relu.nim, 'IN01000005');
      expect(relu.codeSecefDgi, 'X537E4DBAJUUHHXNFWISFEKJ');
      expect(relu.ifu, '9999900000001');
      expect(relu.horodatage, DateTime(2020, 11, 23, 13, 17, 8));
      expect(relu.codeQr, qrReference);
    });

    test('un nombre de champs incorrect est refusé', () {
      expect(
        () => ElementsSecurite.depuisCodeQr('F;IN01000005;ABC'),
        throwsA(isA<CodeQrInvalide>()),
      );
    });

    test('un horodatage mal formé est refusé', () {
      expect(
        () => ElementsSecurite.depuisCodeQr(
            'F;IN01000005;ABC;9999900000001;2020112313'),
        throwsA(isA<CodeQrInvalide>()),
      );
      expect(
        () => ElementsSecurite.depuisCodeQr(
            'F;IN01000005;ABC;9999900000001;AAAAMMJJHHMMSS'),
        throwsA(isA<CodeQrInvalide>()),
      );
    });
  });

  group('État de certification', () {
    test('une vente traverse quatre états possibles', () {
      // Le hors-ligne étant le mode normal, une vente naît non certifiée et
      // le devient plus tard, quand le réseau le permet.
      expect(EtatCertification.values, hasLength(4));
      expect(EtatCertification.values.first, EtatCertification.enAttente);
    });
  });
}
