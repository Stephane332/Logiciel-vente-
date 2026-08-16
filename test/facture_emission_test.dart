/// L'émission d'une facture et l'attribution de son numéro.
///
/// Le §2.18 tient en une phrase : « série ascendante ininterrompue par année
/// de gestion ». Elle décide de l'architecture — le numéro naît dans le
/// journal, pas dans un compteur à part, parce qu'un compteur à part créerait
/// une seconde vérité qui finirait par mentir.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  late BaseLocale base;
  late Depot depot;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Future<String> vendre({num prix = 10000, DateTime? quand}) =>
      depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'CIM',
            designation: 'Ciment CPJ 45',
            prixUnitaire: f(prix),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(prix))
        ],
        horodatage: quand ?? DateTime(2026, 8, 16, 10),
      );

  group('La série avance', () {
    test('la première facture porte le rang 1', () async {
      final reference = await depot.emettreFacture(await vendre());

      expect(reference.rang, 1);
      expect(reference.annee, 2026);
      expect(reference.texte, 'FV-2026-000001');
    });

    test('elle avance d\'un à chaque facture', () async {
      expect((await depot.emettreFacture(await vendre())).rang, 1);
      expect((await depot.emettreFacture(await vendre())).rang, 2);
      expect((await depot.emettreFacture(await vendre())).rang, 3);
    });

    test('elle ne laisse aucun trou', () async {
      for (var i = 0; i < 5; i++) {
        await depot.emettreFacture(await vendre());
      }

      expect(await depot.trousDeSerie(annee: 2026), isEmpty);
    });

    test('elle repart à un à chaque année de gestion', () async {
      await depot.emettreFacture(await vendre(quand: DateTime(2026, 12, 31)));
      final suivante = await depot
          .emettreFacture(await vendre(quand: DateTime(2027, 1, 2)));

      expect(suivante.annee, 2027);
      expect(suivante.rang, 1);
      // Et la série de 2026 n'a pas bougé.
      expect(await depot.trousDeSerie(annee: 2026), isEmpty);
    });

    test('les avoirs ont leur propre série', () async {
      final vente = await depot.emettreFacture(await vendre());
      final avoir = await depot.emettreFacture(await vendre(),
          type: TypeFacture.avoir);

      expect(vente.texte, 'FV-2026-000001');
      expect(avoir.texte, 'FA-2026-000001');
    });
  });

  group('Une facture ne se numérote qu\'une fois', () {
    test('rééditer une facture rend le numéro d\'origine (§2.18)', () async {
      final vente = await vendre();

      final premiere = await depot.emettreFacture(vente);
      final duplicata = await depot.emettreFacture(vente);

      expect(duplicata, premiere);
    });

    test('et rééditer ne consomme pas de rang', () async {
      final vente = await vendre();
      await depot.emettreFacture(vente);
      await depot.emettreFacture(vente);

      // Sans cette règle, rééditer une facture perdue trouerait la série :
      // le rang 2 serait consommé sans qu'aucun document ne le porte.
      final suivante = await depot.emettreFacture(await vendre());
      expect(suivante.rang, 2);
      expect(await depot.trousDeSerie(annee: 2026), isEmpty);
    });

    test('la référence se retrouve après coup', () async {
      final vente = await vendre();
      expect(await depot.referenceFacture(vente), isNull);

      final reference = await depot.emettreFacture(vente);
      expect(await depot.referenceFacture(vente), reference);
    });
  });

  group('Ce qui ne se facture pas', () {
    test('une vente inconnue', () async {
      expect(() => depot.emettreFacture('vente-qui-nexiste-pas'),
          throwsA(isA<ArgumentError>()));
    });

    test('une vente annulée', () async {
      final vente = await vendre();
      await depot.annulerVente(vente);

      // La note traite les annulations par facture d'avoir (§2.28). Émettre
      // la facture d'une vente qui n'a plus lieu d'être serait un faux.
      expect(() => depot.emettreFacture(vente), throwsA(isA<StateError>()));
    });

    test("une vente annulée après facturation garde sa facture", () async {
      // Le passé ne se réécrit pas : la facture a été remise au client, et
      // c'est un avoir qui la neutralise, pas un effacement.
      final vente = await vendre();
      final reference = await depot.emettreFacture(vente);
      await depot.annulerVente(vente);

      expect(await depot.referenceFacture(vente), reference);
    });
  });

  group('Le journal fait foi', () {
    test('les numéros survivent à une reconstruction', () async {
      final premiere = await vendre();
      final seconde = await vendre();
      final a = await depot.emettreFacture(premiere);
      final b = await depot.emettreFacture(seconde);

      await depot.reconstruireProjections();

      expect(await depot.referenceFacture(premiere), a);
      expect(await depot.referenceFacture(seconde), b);
    });

    test('la projection porte le numéro et l\'année', () async {
      final vente = await vendre();
      await depot.emettreFacture(vente);
      await depot.reconstruireProjections();

      final ligne = await (base.select(base.ventes)
            ..where((v) => v.id.equals(vente)))
          .getSingle();

      expect(ligne.numero, 1);
      expect(ligne.anneeGestion, 2026);
    });

    test('une projection vidée ne fait pas repartir la série à un', () async {
      await depot.emettreFacture(await vendre());
      await depot.emettreFacture(await vendre());

      // C'est le piège du compteur : vider les projections et relire le
      // maximum de la table rendrait 1, et deux factures porteraient le
      // même numéro. Les projections se vident dans l'ordre des clés
      // étrangères, comme le fait la reconstruction.
      await base.delete(base.paiements).go();
      await base.delete(base.lignesVente).go();
      await base.delete(base.ventes).go();

      final suivante = await depot.emettreFacture(await vendre());
      expect(suivante.rang, 3);
    });

    test('une vente non facturée n\'a pas de numéro', () async {
      // Sur mille ventes du jour, deux donneront lieu à une facture.
      // Numéroter les mille laisserait neuf cent quatre-vingt-dix-huit trous.
      final vente = await vendre();

      final ligne = await (base.select(base.ventes)
            ..where((v) => v.id.equals(vente)))
          .getSingle();

      expect(ligne.numero, isNull);
      expect(ligne.anneeGestion, isNull);
    });
  });
}
