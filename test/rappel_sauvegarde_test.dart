/// Quand l'application réclame une sauvegarde, et surtout quand elle se tait.
///
/// Deux façons de rater ce rappel : ne rien dire, et le dire tout le temps.
/// La seconde est la plus facile à écrire et la plus difficile à rattraper —
/// un bandeau qui revient à chaque ouverture devient un décor, et le jour où
/// il compte, personne ne le lit.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/rappel_sauvegarde.dart';

void main() {
  final maintenant = DateTime(2026, 8, 16, 10);
  DateTime ilYA(int jours) => maintenant.subtract(Duration(days: jours));

  RappelSauvegarde rappel({
    required int nouveautes,
    DateTime? derniere,
  }) =>
      RappelSauvegarde(
        nouveautes: nouveautes,
        derniere: derniere,
        maintenant: maintenant,
      );

  group('Se taire', () {
    test("rien n'a bougé depuis la dernière sauvegarde", () {
      expect(rappel(nouveautes: 0, derniere: ilYA(90)).faut, isFalse);
    });

    test('un carnet tout neuf ne se fait pas interrompre', () {
      // Trois ventes ne valent pas qu'on coupe quelqu'un dans sa journée.
      expect(rappel(nouveautes: 3).faut, isFalse);
    });

    test('une sauvegarde récente suffit, même après une grosse journée', () {
      expect(rappel(nouveautes: 300, derniere: ilYA(2)).faut, isFalse);
    });

    test('la veille du seuil, on se tait encore', () {
      expect(
          rappel(nouveautes: 50, derniere: ilYA(RappelSauvegarde.apresJours - 1))
              .faut,
          isFalse);
      expect(rappel(nouveautes: RappelSauvegarde.avantLePremier - 1).faut,
          isFalse);
    });
  });

  group('Parler', () {
    test("un carnet qui n'est jamais sorti du téléphone, une fois garni", () {
      expect(rappel(nouveautes: RappelSauvegarde.avantLePremier).faut, isTrue);
    });

    test('une sauvegarde qui date, et du travail depuis', () {
      expect(
          rappel(nouveautes: 1, derniere: ilYA(RappelSauvegarde.apresJours))
              .faut,
          isTrue);
    });
  });

  group('Ce qui est dit', () {
    test("nommer le risque plutôt que la règle, quand rien n'a été fait", () {
      final message = rappel(nouveautes: 40).message;
      expect(message, contains("jamais sorti"));
      expect(message, contains('tout se perd'));
    });

    test('compter les jours quand il y en a', () {
      expect(rappel(nouveautes: 5, derniere: ilYA(12)).message,
          contains('il y a 12 jours'));
    });

    test("« hier » se dit, « il y a 1 jours » ne se dit pas", () {
      expect(rappel(nouveautes: 5, derniere: ilYA(1)).message, contains('hier'));
    });
  });

  group("Le compte des jours", () {
    test('se fait sur des jours entiers, pas sur des heures', () {
      // Sauvegardé hier à 23 h, il est 10 h : ça fait un jour, pas zéro.
      final hierSoir = DateTime(2026, 8, 15, 23);
      expect(rappel(nouveautes: 1, derniere: hierSoir).jours, 1);
    });

    test("n'existe pas quand il n'y a jamais eu de sauvegarde", () {
      expect(rappel(nouveautes: 1).jours, isNull);
    });

    test('ne part jamais dans le négatif si la date est en avance', () {
      // Une horloge remise à l'heure peut poser une date dans le futur.
      final demain = maintenant.add(const Duration(days: 3));
      expect(rappel(nouveautes: 1, derniere: demain).jours, 0);
      expect(rappel(nouveautes: 1, derniere: demain).faut, isFalse);
    });
  });
}
