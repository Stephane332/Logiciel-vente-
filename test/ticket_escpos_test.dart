/// Le ticket imprimé, vérifié sans imprimante.
///
/// Ce qui se vérifie ici : la mise en page sur 32 colonnes, les commandes
/// ESC/POS, et le traitement des accents. Ce qui ne se vérifie qu'avec du
/// papier : quelle page de code accepte réellement le modèle du commerçant.
/// C'est pour ça que la page est un réglage et pas une constante.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/document_client.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/domaine/ticket_escpos.dart';

void main() {
  Montant f(num francs) => Montant.depuisDecimal(francs);

  DocumentClient document({
    String nomCommerce = 'Chez Awa',
    String? operateur,
    List<LigneDocument>? lignes,
    Montant? total,
    Montant? regle,
  }) {
    final contenu = lignes ??
        [
          LigneDocument(
            designation: 'Riz 1 kg',
            quantite: const Quantite.unites(2),
            prixUnitaire: f(650),
            montant: f(1300),
          ),
        ];
    final somme = total ?? f(1300);
    return DocumentClient(
      nature: NatureDocument.recu,
      nomCommerce: nomCommerce,
      date: DateTime(2026, 8, 16, 9, 5),
      operateur: operateur,
      lignes: contenu,
      total: somme,
      regle: regle ?? somme,
      modes: const [ModePaiement.especes],
    );
  }

  /// Le ticket rendu en lignes de texte, commandes retirées : c'est ce que le
  /// client tient dans la main.
  List<String> papier(List<int> octets) {
    final texte = StringBuffer();
    for (var i = 0; i < octets.length; i++) {
      final octet = octets[i];
      // On saute les séquences d'échappement, qui ne s'impriment pas.
      if (octet == 0x1B || octet == 0x1D) {
        i += octet == 0x1B && octets[i + 1] == 0x40 ? 1 : 2;
        continue;
      }
      texte.writeCharCode(octet);
    }
    return texte.toString().split('\n');
  }

  group('Ce que le client tient dans la main', () {
    test('le commerce, la nature et la date sont en tête', () {
      final lignes = papier(const TicketEscPos().composer(document()));

      expect(lignes[0], 'CHEZ AWA');
      expect(lignes[1], 'Recu');
      expect(lignes[2], '16/08/2026 09h05');
    });

    test('le vendeur figure quand il y en a un', () {
      final lignes =
          papier(const TicketEscPos().composer(document(operateur: 'Awa')));

      expect(lignes, contains('Servi par Awa'));
    });

    test("rien ne s'ajoute quand le commerçant vend seul", () {
      final lignes = papier(const TicketEscPos().composer(document()));

      expect(lignes.any((l) => l.startsWith('Servi par')), isFalse);
    });

    test('chaque article donne sa désignation puis son compte', () {
      final lignes = papier(const TicketEscPos().composer(document()));

      expect(lignes, contains('Riz 1 kg'));
      expect(lignes.any((l) => l.contains('2 x 650 F')), isTrue);
    });

    test('le total est là, et le reste à payer quand il y en a un', () {
      final solde = papier(const TicketEscPos().composer(document()));
      expect(solde.any((l) => l.startsWith('TOTAL')), isTrue);
      expect(solde.any((l) => l.startsWith('Reste')), isFalse);

      final partiel = papier(const TicketEscPos()
          .composer(document(total: f(1300), regle: f(500))));
      expect(partiel.any((l) => l.startsWith('Deja paye')), isTrue);
      expect(partiel.any((l) => l.startsWith('Reste')), isTrue);
    });
  });

  group('Trente-deux colonnes, jamais une de plus', () {
    test('aucune ligne ne dépasse la largeur du papier', () {
      final lignes = papier(const TicketEscPos().composer(document(
        nomCommerce: 'Alimentation Générale Nabonswendé et Fils Réunis',
        lignes: [
          LigneDocument(
            designation:
                'Sac de riz parfumé importé du Vietnam, qualité supérieure',
            quantite: const Quantite.unites(1),
            prixUnitaire: f(25000),
            montant: f(25000),
          ),
        ],
        total: f(25000),
      )));

      // Le nom du commerce et le total s'impriment en double largeur : ils
      // tiennent sur la moitié des colonnes. Tout le reste, sur la totalité.
      for (final ligne in lignes) {
        final large = ligne.startsWith('ALIMENTATION') || ligne.startsWith('TOTAL');
        expect(ligne.length, lessThanOrEqualTo(large ? colonnes58 ~/ 2 : colonnes58),
            reason: ligne);
      }
    });

    test('le montant est collé à droite, et ne se tronque jamais', () {
      final lignes = papier(const TicketEscPos().composer(document()));
      final total = lignes.firstWhere((l) => l.startsWith('TOTAL'));

      // En double largeur, seize caractères occupent les trente-deux colonnes.
      expect(total.length, colonnes58 ~/ 2);
      expect(total.endsWith('1 300 F'), isTrue);
    });

    test("c'est la gauche qui cède quand tout ne tient pas", () {
      // Un montant à sept chiffres ne laisse presque rien à la désignation.
      final lignes = papier(const TicketEscPos().composer(document(
        lignes: [
          LigneDocument(
            designation: 'Groupe électrogène',
            quantite: const Quantite.unites(1),
            prixUnitaire: f(1250000),
            montant: f(1250000),
          ),
        ],
        total: f(1250000),
      )));

      final total = lignes.firstWhere((l) => l.startsWith('TOTAL'));
      expect(total.endsWith('1 250 000 F'), isTrue);
      expect(total.length, colonnes58 ~/ 2);
    });
  });

  group('Les commandes de l’imprimante', () {
    test('le ticket commence par une remise à zéro', () {
      final octets = const TicketEscPos().composer(document());
      expect(octets.take(2), [0x1B, 0x40]);
    });

    test('et finit par une coupe du papier', () {
      final octets = const TicketEscPos().composer(document());
      expect(octets.skip(octets.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });

    test('une page de code demandée est annoncée à l’imprimante', () {
      final octets =
          const TicketEscPos(page: PageDeCode.cp858).composer(document());
      // ESC t 19, juste après la remise à zéro.
      expect(octets.skip(2).take(3), [0x1B, 0x74, 19]);
    });

    test('sans page de code, rien n’est annoncé', () {
      final octets = const TicketEscPos().composer(document());
      expect(octets.skip(2).take(2), isNot([0x1B, 0x74]));
    });
  });

  group('Les accents, le vrai piège', () {
    test('en repli, ils tombent plutôt que de sortir faux', () {
      final octets = const TicketEscPos().composer(document(operateur: 'Rémi'));

      // Chaque octet tient sur sept bits : rien qui puisse dérailler.
      expect(octets.every((o) => o < 0x80), isTrue);
      expect(papier(octets), contains('Servi par Remi'));
    });

    test('avec une page choisie, ils partent sur leur octet', () {
      final octets = const TicketEscPos(page: PageDeCode.cp858)
          .composer(document(operateur: 'Rémi'));

      // « é » vaut 0x82 en CP858.
      expect(octets, contains(0x82));
    });

    test('un caractère absent de la page devient un point d’interrogation', () {
      final octets = const TicketEscPos(page: PageDeCode.cp858)
          .composer(document(nomCommerce: 'Chez 木村'));

      // Jamais un octet au hasard : ça ferait dérailler l'imprimante.
      expect(octets.where((o) => o == 0x3F).isNotEmpty, isTrue);
    });
  });
}
