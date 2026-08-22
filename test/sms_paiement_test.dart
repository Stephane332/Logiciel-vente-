/// La lecture des SMS de confirmation.
///
/// C'est le seul endroit de l'application où un message venu de l'extérieur
/// peut décider qu'une vente est payée. Les tests portent donc autant sur ce
/// qui doit être **refusé** que sur ce qui doit être lu : un faux positif
/// encaisserait une vente que personne n'a payée, et ça ne se rattrape pas au
/// comptoir.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/mobile_money.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/sms_paiement.dart';

void main() {
  final lecteur = LecteurSms.parDefaut;
  final quand = DateTime(2026, 8, 16, 14, 30);

  Montant f(num francs) => Montant.depuisDecimal(francs);

  PaiementRecu? lire(String expediteur, String corps) =>
      lecteur.lire(expediteur: expediteur, corps: corps, recuLe: quand);

  group('Reconnaître un paiement', () {
    test('un message Orange ordinaire', () {
      final recu = lire('OrangeMoney',
          'Vous avez recu 3500 FCFA de 70000000. Nouveau solde: 12000 FCFA');

      expect(recu, isNotNull);
      expect(recu!.operateur, OperateurMobile.orange);
      expect(recu.montant, f(3500));
      expect(recu.expediteur, '70000000');
    });

    test("l'expéditeur se reconnaît quelle que soit son écriture", () {
      for (final nom in ['OrangeMoney', 'orange money', 'ORANGE-MONEY', '144']) {
        expect(lire(nom, 'Vous avez recu 500 F de 70000000'), isNotNull,
            reason: nom);
      }
    });

    test('Moov et Telecel aussi', () {
      expect(lire('MoovMoney', 'Vous avez recu 1000 F de 70000000')?.operateur,
          OperateurMobile.moov);
      expect(
          lire('TelecelMoney', 'Vous avez recu 1000 F de 70000000')?.operateur,
          OperateurMobile.telecel);
    });

    test('la référence de transaction est retenue quand il y en a une', () {
      final recu = lire('OrangeMoney',
          'Vous avez recu 3500 FCFA de 70000000. Ref: PP260816.1430.A12345');

      expect(recu?.reference, 'PP260816.1430.A12345');
    });
  });

  group('Le montant, écrit comme les opérateurs l’écrivent', () {
    test('avec ou sans séparateur de milliers', () {
      for (final ecriture in ['3500', '3 500', '3.500', '3,500']) {
        final recu = lire('OrangeMoney', 'Vous avez recu $ecriture F de 70000000');
        expect(recu?.montant, f(3500), reason: ecriture);
      }
    });

    test('avec les différentes façons de nommer la monnaie', () {
      for (final monnaie in ['F', 'FCFA', 'XOF']) {
        expect(lire('OrangeMoney', 'Vous avez recu 750 $monnaie de 70000000')
            ?.montant,
            f(750),
            reason: monnaie);
      }
    });

    test("un gros montant ne perd pas ses milliers", () {
      expect(lire('OrangeMoney', 'Vous avez recu 1 250 000 FCFA de 70000000')
          ?.montant,
          f(1250000));
    });

    test("le premier montant est le bon, pas le solde qui suit", () {
      final recu = lire('OrangeMoney',
          'Vous avez recu 500 FCFA de 70000000. Nouveau solde: 99000 FCFA');
      expect(recu?.montant, f(500));
    });
  });

  group('Refuser ce qui n’est pas un encaissement', () {
    test("un message d'un expéditeur inconnu", () {
      expect(lire('PROMO225', 'Vous avez recu 3500 F de 70000000'), isNull);
    });

    test('un transfert sortant', () {
      expect(
          lire('OrangeMoney', 'Transfert vers 70000000 de 3500 F effectue'),
          isNull);
    });

    test('un retrait chez un agent', () {
      expect(lire('OrangeMoney', 'Retrait de 3500 F effectue. Solde: 200 F'),
          isNull);
    });

    test('une publicité du même expéditeur', () {
      // Le message porte un montant, et c'est exactement le piège.
      expect(
          lire('OrangeMoney',
              'Promo ! Rechargez 5000 F et gagnez 1000 F de bonus.'),
          isNull);
    });

    test('un message sans montant', () {
      expect(lire('OrangeMoney', 'Vous avez recu un paiement.'), isNull);
    });

    test('un montant nul', () {
      expect(lire('OrangeMoney', 'Vous avez recu 0 F de 70000000'), isNull);
    });
  });

  group('Rapprocher de la vente en cours', () {
    PaiementRecu paiement(num francs, {Duration apres = Duration.zero}) =>
        PaiementRecu(
          operateur: OperateurMobile.orange,
          montant: f(francs),
          recuLe: quand.add(apres),
        );

    bool correspond(PaiementRecu recu, {num attendu = 3500}) =>
        Rapprochement.correspond(
          paiement: recu,
          attendu: f(attendu),
          operateur: OperateurMobile.orange,
          depuis: quand,
        );

    test('même montant, tout de suite : ça correspond', () {
      expect(correspond(paiement(3500)), isTrue);
    });

    test("un montant différent ne correspond jamais, même à un franc près", () {
      expect(correspond(paiement(3499)), isFalse);
      expect(correspond(paiement(3501)), isFalse);
    });

    test('un autre opérateur ne correspond pas', () {
      final autre = PaiementRecu(
          operateur: OperateurMobile.moov, montant: f(3500), recuLe: quand);
      expect(correspond(autre), isFalse);
    });

    test('un SMS trop tardif ne correspond plus', () {
      // Le client compose devant le comptoir : la confirmation arrive en
      // quelques secondes. Une heure après, ce message parle d'autre chose.
      expect(correspond(paiement(3500, apres: const Duration(hours: 1))),
          isFalse);
      expect(
          correspond(paiement(3500, apres: Rapprochement.fenetre)), isTrue);
      expect(
          correspond(paiement(3500,
              apres: Rapprochement.fenetre + const Duration(seconds: 1))),
          isFalse);
    });

    test("un SMS arrivé avant l'encaissement ne correspond pas", () {
      // C'est le paiement du client précédent.
      expect(correspond(paiement(3500, apres: const Duration(minutes: -2))),
          isFalse);
    });
  });

  group('Les règles sont des données', () {
    test('elles font l’aller-retour en JSON sans rien perdre', () {
      final json = LecteurSms.parDefaut.versJson();
      final relu = LecteurSms.depuisJson(json);

      expect(relu.regles.length, LecteurSms.parDefaut.regles.length);
      expect(
          relu.lire(
              expediteur: 'OrangeMoney',
              corps: 'Vous avez recu 3500 F de 70000000',
              recuLe: quand)
              ?.montant,
          f(3500));
    });

    test('une règle corrigée prend effet sans toucher au code', () {
      // Le jour où Orange change le format, c'est cette ligne-là qu'on
      // remplace — pas une version de l'application.
      final lecteur = LecteurSms.depuisJson('''
        [{"operateur":"orange","expediteurs":["MonNouvelExpediteur"],
          "montant":"credite de ([\\\\d ]+)"}]
      ''');

      final recu = lecteur.lire(
          expediteur: 'MonNouvelExpediteur',
          corps: 'Compte credite de 4 250 le 16/08',
          recuLe: quand);

      expect(recu?.montant, f(4250));
    });
  });
}
