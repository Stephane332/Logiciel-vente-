/// Ce qui se passe au bout d'un an.
///
/// Les autres tests travaillent sur cinq événements. Une boutique qui vend
/// depuis un an en a des dizaines de milliers, et c'est là que se révèlent
/// les erreurs qui ne coûtent rien en démonstration : relire tout le journal
/// pour retrouver trois factures, recompter la caisse en chargeant l'année
/// entière en mémoire.
///
/// Ce fichier est lent par nature. C'est le prix d'une vérification qui
/// ressemble à la réalité plutôt qu'à un scénario de bureau.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/fiche_entreprise.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/rapport_fiscal.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/rapports.dart';

void main() {
  late BaseLocale base;
  late Journal journal;
  late Depot depot;
  late Rapports rapports;

  /// Une boutique qui fait une trentaine de ventes par jour sur six mois.
  /// C'est un commerce ordinaire, pas un cas extrême.
  const ventes = 5000;

  setUp(() {
    base = BaseLocale(NativeDatabase.memory());
    journal = Journal(base, appareil: 'CAISSE1');
    depot = Depot(base, journal);
    rapports = Rapports(base, journal,
        fiche: const FicheEntreprise(nomCommercial: 'Chez Awa'));
  });

  tearDown(() => base.close());

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Future<void> remplir({int? nombre, DateTime? depuis}) async {
    final combien = nombre ?? ventes;
    final depart = depuis ?? DateTime(2026, 2, 1, 8);
    for (var i = 0; i < combien; i++) {
      await depot.enregistrerVente(
        lignes: [
          LigneAEnregistrer(
            codeArticle: 'RIZ',
            designation: 'Riz 1 kg',
            prixUnitaire: f(500),
            quantite: const Quantite.unites(1),
          )
        ],
        paiements: [
          PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(500))
        ],
        horodatage: depart.add(Duration(minutes: i * 3)),
      );
    }
  }

  /// Combien de temps met une opération, répétée assez de fois pour que la
  /// mesure ne soit pas du bruit.
  Future<int> mesurer(Future<void> Function() quoi, {int fois = 20}) async {
    // Un tour à vide : la première requête paie la préparation du plan.
    await quoi();
    final chrono = Stopwatch()..start();
    for (var i = 0; i < fois; i++) {
      await quoi();
    }
    chrono.stop();
    return chrono.elapsedMicroseconds ~/ fois;
  }

  group('Le coût ne doit pas suivre la taille du journal', () {
    /// C'est la seule mesure qui prouve quelque chose. Un seuil en
    /// millisecondes dépend de la machine et passe partout ; un **rapport**
    /// entre un petit journal et un grand dit si la lecture est filtrée ou
    /// si elle relit tout. Filtrée, le coût est plat. Non filtrée, il suit.
    test('retrouver une facture coûte pareil à 200 et à 5 000 ventes',
        () async {
      await remplir(nombre: 200);
      final vente = (await (base.select(base.ventes)..limit(1)).get()).single;
      await depot.emettreFacture(vente.id);

      final petit = await mesurer(() => depot.referenceFacture(vente.id));

      await remplir(nombre: 4800, depuis: DateTime(2026, 6, 1, 8));
      final grand = await mesurer(() => depot.referenceFacture(vente.id));

      // Le journal a été multiplié par vingt-cinq. Une lecture filtrée reste
      // dans le même ordre de grandeur ; une lecture intégrale explose.
      expect(grand, lessThan(petit * 5 + 2000),
          reason: 'petit journal : $petit µs · grand journal : $grand µs — '
              'le coût suit la taille, donc on relit tout');
    });

    test('la dernière clôture se retrouve sans relire les ventes', () async {
      await remplir(nombre: 200);
      await rapports.z(quand: DateTime(2026, 2, 15));

      final petit =
          await mesurer(() => rapports.derniereCloture(NatureRapport.z));

      await remplir(nombre: 4800, depuis: DateTime(2026, 6, 1, 8));
      final grand =
          await mesurer(() => rapports.derniereCloture(NatureRapport.z));

      expect(grand, lessThan(petit * 5 + 2000),
          reason: 'petit journal : $petit µs · grand journal : $grand µs');
    });
  });

  group('Un journal de six mois', () {
    test('les factures se retrouvent et la série reste sans trou', () async {
      await remplir();

      // Trois factures dans cinq mille ventes : c'est la proportion réelle.
      final toutes = await (base.select(base.ventes)..limit(3)).get();
      for (final vente in toutes) {
        await depot.emettreFacture(vente.id);
      }

      final reference = await depot.referenceFacture(toutes.first.id);
      final suivante = await depot.emettreFacture(
        (await (base.select(base.ventes)..limit(1, offset: 10)).get()).single.id,
      );

      expect(reference, isNotNull);
      expect(suivante.rang, 4);
      expect(await depot.trousDeSerie(annee: 2026), isEmpty);

    });

    test('le point de caisse totalise juste', () async {
      await remplir();

      final x = await rapports.x();

      expect(x.total, f(500 * ventes));
    });

    test('la clôture repart bien de la précédente', () async {
      await remplir();

      final premier = await rapports.z(quand: DateTime(2026, 3, 1));
      final second = await rapports.z(quand: DateTime(2026, 4, 1));

      expect(second.debut, premier.fin);
      expect(second.numero, 2);
      // Les deux Z ne se recouvrent pas : leur somme ne dépasse pas le total.
      expect((premier.total + second.total).centimes,
          lessThanOrEqualTo(f(500 * ventes).centimes));
    });

    test('trente clôtures se suivent sans se marcher dessus', () async {
      await remplir();

      for (var i = 0; i < 30; i++) {
        await rapports.z(quand: DateTime(2026, 2, 1).add(Duration(days: i * 3)));
      }

      final dernier = await rapports.z(quand: DateTime(2026, 7, 1));

      expect(dernier.numero, 31);
      expect(await rapports.derniereCloture(NatureRapport.z), isNotNull);
    });
  });
}
