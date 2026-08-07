/// Tests des fenêtres de temps du rapport.
///
/// Un commerçant ne consulte pas son rapport le soir même : il ouvre
/// l'application le lendemain matin en levant son rideau. À ce moment-là sa
/// journée d'hier ne doit pas avoir disparu — sinon il croit que
/// l'application a perdu ses chiffres, et il retourne à son cahier.
///
/// Les bornes se calculent en journées entières et la fenêtre se ferme au
/// prochain minuit : la vente qu'on vient d'encaisser est justement celle
/// qu'on cherche des yeux.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/periode.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';

void main() {
  // Un mercredi, à midi passé. Une heure quelconque de la journée : rien ne
  // doit dépendre du moment où le commerçant regarde.
  final maintenant = DateTime(2026, 8, 5, 14, 32);

  group('Les bornes', () {
    test('la journée commence à minuit et finit au prochain', () {
      final (debut, fin) = Periode.jour.bornes(maintenant);

      expect(debut, DateTime(2026, 8, 5));
      expect(fin, DateTime(2026, 8, 6));
    });

    test('hier est la journée pleine qui précède', () {
      final (debut, fin) = Periode.hier.bornes(maintenant);

      expect(debut, DateTime(2026, 8, 4));
      expect(fin, DateTime(2026, 8, 5));
    });

    test('sept jours comptent aujourd\'hui compris', () {
      final (debut, fin) = Periode.semaine.bornes(maintenant);

      expect(debut, DateTime(2026, 7, 30));
      expect(fin, DateTime(2026, 8, 6));
      expect(fin.difference(debut).inDays, 7);
    });

    test('trente jours comptent aujourd\'hui compris', () {
      final (debut, fin) = Periode.mois.bornes(maintenant);

      expect(debut, DateTime(2026, 7, 7));
      expect(fin.difference(debut).inDays, 30);
    });

    test('les bornes ne dépendent pas de l\'heure', () {
      final matin = Periode.jour.bornes(DateTime(2026, 8, 5, 6, 15));
      final soir = Periode.jour.bornes(DateTime(2026, 8, 5, 23, 59, 59));

      expect(matin, soir);
    });

    test('la fenêtre se ferme après maintenant, jamais dessus', () {
      // Fermer à l'instant présent ferait disparaître la vente qu'on vient
      // d'enregistrer — la seule que le commerçant cherche vraiment.
      for (final periode in Periode.values) {
        if (periode == Periode.hier) continue;
        final (_, fin) = periode.bornes(maintenant);
        expect(fin.isAfter(maintenant), isTrue, reason: periode.name);
      }
    });

    test('chaque période porte un début avant sa fin', () {
      for (final periode in Periode.values) {
        final (debut, fin) = periode.bornes(maintenant);
        expect(debut.isBefore(fin), isTrue, reason: periode.name);
      }
    });
  });

  group("L'intitulé du résumé", () {
    test('une journée se nomme par sa date', () {
      expect(Periode.jour.intitule(maintenant), 'Journée du 05/08/2026');
      expect(Periode.hier.intitule(maintenant), 'Journée du 04/08/2026');
    });

    test('une période se nomme par ses deux bouts, fin comprise', () {
      // La borne de fin est exclue : le dernier jour couvert est la veille,
      // et c'est celui-là qu'il faut annoncer.
      expect(Periode.semaine.intitule(maintenant), 'Du 30/07/2026 au 05/08/2026');
    });

    test('le résumé porte la date du jour concerné, pas du jour d\'envoi', () {
      // Le patron qui envoie le rapport d'hier à midi doit voir « 04/08 ».
      expect(Periode.hier.dateDeReference(maintenant), DateTime(2026, 8, 4));
    });
  });

  group('Le rapport suit la période', () {
    late BaseLocale base;
    late Depot depot;

    setUp(() {
      base = BaseLocale(NativeDatabase.memory());
      depot = Depot(base, Journal(base, appareil: 'CAISSE1'));
    });

    tearDown(() => base.close());

    Montant f(num francs) => Montant.depuisDecimal(francs);

    Future<void> vendre(num prix, {DateTime? quand}) => depot.enregistrerVente(
          lignes: [
            LigneAEnregistrer(
              prixUnitaire: f(prix),
              quantite: const Quantite.unites(1),
            )
          ],
          paiements: [
            PaiementAEnregistrer(mode: ModePaiement.especes, montant: f(prix))
          ],
          horodatage: quand,
        );

    /// Un instant à l'intérieur de la journée voulue, jamais sur sa frontière.
    DateTime ilYA(int jours) {
      final minuit = DateTime.now().subtract(Duration(days: jours));
      return DateTime(minuit.year, minuit.month, minuit.day, 10, 30);
    }

    Future<RapportDuJour> sur(Periode periode) {
      final (debut, fin) = periode.bornes();
      return depot.rapportSurPeriode(debut, fin);
    }

    test('la journée ne montre que ses propres ventes', () async {
      await vendre(1000);
      await vendre(5000, quand: ilYA(1));

      final jour = await sur(Periode.jour);
      expect(jour.encaisse, f(1000));
      expect(jour.nombreVentes, 1);
    });

    test("hier ne disparaît pas au passage de minuit", () async {
      await vendre(5000, quand: ilYA(1));
      await vendre(1000);

      final hier = await sur(Periode.hier);
      expect(hier.encaisse, f(5000));
      expect(hier.nombreVentes, 1);
    });

    test('la semaine additionne les deux', () async {
      await vendre(1000);
      await vendre(5000, quand: ilYA(1));
      await vendre(2000, quand: ilYA(6));

      final semaine = await sur(Periode.semaine);
      expect(semaine.encaisse, f(8000));
      expect(semaine.nombreVentes, 3);
    });

    test('une vente trop vieille sort de la semaine mais reste au mois',
        () async {
      await vendre(4000, quand: ilYA(10));

      expect((await sur(Periode.semaine)).nombreVentes, 0);
      expect((await sur(Periode.mois)).encaisse, f(4000));
    });

    test('le rapport du jour et la période du jour disent la même chose',
        () async {
      // Les deux chemins doivent rester alignés : le premier est un raccourci
      // sur le second, et une divergence passerait inaperçue longtemps.
      await vendre(1500);
      await vendre(2500);

      final direct = await depot.rapportDuJour();
      final periode = await sur(Periode.jour);

      expect(periode.encaisse, direct.encaisse);
      expect(periode.nombreVentes, direct.nombreVentes);
      expect(periode.aCredit, direct.aCredit);
    });
  });
}
