/// La numérotation des factures (§2.18).
///
/// « Série ascendante ininterrompue par année de gestion. » Une série trouée
/// est le premier reproche d'un contrôle fiscal, et un trou ne se rattrape
/// pas après coup : il faudrait réécrire des factures déjà remises.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/numerotation.dart';

void main() {
  const numerotation = Numerotation();

  group('Le rang suivant', () {
    test('une série vide commence à 1', () {
      expect(numerotation.rangSuivant(const []), 1);
    });

    test('elle avance d\'un', () {
      expect(numerotation.rangSuivant([1]), 2);
      expect(numerotation.rangSuivant([1, 2, 3]), 4);
    });

    test('elle repart du plus haut, même dans le désordre', () {
      // Les factures peuvent être relues dans n'importe quel ordre après une
      // reconstruction depuis le journal. Prendre la dernière lue au lieu de
      // la plus haute rendrait un numéro déjà attribué.
      expect(numerotation.rangSuivant([3, 1, 2]), 4);
      expect(numerotation.rangSuivant([7, 2]), 8);
    });
  });

  group('La référence imprimée', () {
    test('elle porte le type, l\'année et le rang', () {
      const reference =
          ReferenceFacture(type: 'FV', annee: 2026, rang: 42);

      expect(reference.texte, 'FV-2026-000042');
    });

    test('le rang est cadré pour que les références se trient', () {
      const petite = ReferenceFacture(type: 'FV', annee: 2026, rang: 9);
      const grande = ReferenceFacture(type: 'FV', annee: 2026, rang: 10);

      expect(petite.texte, 'FV-2026-000009');
      // Sans le cadrage, « FV-2026-9 » se trierait après « FV-2026-10 » en
      // tant que texte, et un export trié mentirait sur l'ordre d'émission.
      expect(petite.texte.compareTo(grande.texte), lessThan(0));
    });

    test('une facture d\'avoir a sa propre série', () {
      // Le type fait partie de la référence : FV et FA ne se mélangent pas.
      const vente = ReferenceFacture(type: 'FV', annee: 2026, rang: 1);
      const avoir = ReferenceFacture(type: 'FA', annee: 2026, rang: 1);

      expect(vente, isNot(avoir));
      expect(vente.texte, 'FV-2026-000001');
      expect(avoir.texte, 'FA-2026-000001');
    });

    test('deux références identiques se valent', () {
      expect(const ReferenceFacture(type: 'FV', annee: 2026, rang: 1),
          const ReferenceFacture(type: 'FV', annee: 2026, rang: 1));
    });
  });

  group('L\'année de gestion', () {
    test('c\'est l\'année civile', () {
      expect(Numerotation.anneeDe(DateTime(2026, 8, 16)), 2026);
      expect(Numerotation.anneeDe(DateTime(2026, 12, 31, 23, 59)), 2026);
      expect(Numerotation.anneeDe(DateTime(2027, 1, 1)), 2027);
    });
  });

  group('La série se vérifie', () {
    test('une série complète n\'a pas de trou', () {
      expect(numerotation.trous([1, 2, 3, 4]), isEmpty);
      expect(numerotation.trous(const []), isEmpty);
    });

    test('un trou se nomme', () {
      expect(numerotation.trous([1, 2, 4]), [3]);
      expect(numerotation.trous([1, 5]), [2, 3, 4]);
    });

    test('un doublon est une rupture, pas un trou', () {
      // Deux factures portant le même numéro, c'est pire qu'un trou : c'est
      // la référence unique du §2.18 qui tombe.
      expect(() => numerotation.trous([1, 2, 2]),
          throwsA(isA<SerieRompue>()));
    });

    test('un rang zéro ou négatif est refusé', () {
      expect(() => numerotation.trous([0, 1]), throwsA(isA<SerieRompue>()));
      expect(() => numerotation.trous([-1]), throwsA(isA<SerieRompue>()));
    });
  });
}
