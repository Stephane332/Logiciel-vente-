/// Deux caisses, une boutique.
///
/// Une vendeuse à l'intérieur, une autre au comptoir de la rue : deux
/// téléphones, chacun sa caisse, chacun ses ventes — et un seul commerce. Le
/// soir, les deux carnets doivent se réunir sans qu'aucune vente ne se perde
/// et sans qu'aucune n'apparaisse deux fois.
///
/// C'est le geste le plus dangereux de l'application après la restauration,
/// pour la raison inverse : la restauration efface trop, une réunion ratée
/// invente. Une vente comptée deux fois, c'est un stock faux et un rapport
/// faux ; une ardoise perdue, c'est de l'argent qu'on ne réclamera plus.
///
/// Ce fichier vérifie donc trois choses, et rien d'autre ne compte autant :
/// ce qui est à moi reste, ce qui vient de l'autre arrive une seule fois, et
/// un fichier qui contredit ce qui est là est refusé avant la moindre
/// écriture.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/domaine/evenements.dart';
import 'package:carnet/domaine/montant.dart';
import 'package:carnet/domaine/references.dart';
import 'package:carnet/donnees/base.dart';
import 'package:carnet/donnees/depot.dart';
import 'package:carnet/donnees/journal.dart';
import 'package:carnet/donnees/parametres.dart';
import 'package:carnet/donnees/sauvegarde.dart';
import 'package:carnet/interface/ecrans/sauvegardes.dart';
import 'package:carnet/interface/theme/theme.dart';

/// Une caisse complète : sa base, son dépôt, ses réglages, son fichier.
class Caisse {
  final String nom;
  final BaseLocale base;
  final Journal journal;
  final Depot depot;
  final Parametres parametres;
  final Sauvegardes sauvegardes;

  factory Caisse(String nom) {
    final base = BaseLocale(NativeDatabase.memory());
    return Caisse._(nom, base, Journal(base, appareil: nom));
  }

  Caisse._(this.nom, this.base, this.journal)
    : depot = Depot(base, journal),
      parametres = Parametres(base),
      sauvegardes = Sauvegardes(base, journal, version: '0.8.3');

  Future<String> fichier() => sauvegardes.composer(nomCommerce: nom);

  /// Reçoit le fichier d'une autre caisse, comme le ferait l'écran.
  Future<ResultatFusion> recevoirDe(Caisse autre) async {
    final ouvert = Sauvegardes.ouvrir(await autre.fichier());
    final resultat = await sauvegardes.fusionner(ouvert!);
    if (resultat.reussie) await depot.reconstruireProjections();
    return resultat;
  }

  Future<void> fermer() => base.close();
}

void main() {
  late Caisse interieur;
  late Caisse comptoir;

  setUp(() {
    interieur = Caisse('CAISSE-INTERIEUR');
    comptoir = Caisse('CAISSE-COMPTOIR');
  });

  tearDown(() async {
    await interieur.fermer();
    await comptoir.fermer();
  });

  Montant f(num francs) => Montant.depuisDecimal(francs);

  Future<String> vendre(
    Caisse caisse,
    num prix, {
    String? code = 'RIZ',
    String? designation = 'Riz 1 kg',
    String? clientId,
    int quantite = 1,
    DateTime? quand,
  }) => caisse.depot.enregistrerVente(
    lignes: [
      LigneAEnregistrer(
        codeArticle: code,
        designation: designation,
        prixUnitaire: f(prix),
        quantite: Quantite.unites(quantite),
      ),
    ],
    paiements: [
      PaiementAEnregistrer(
        mode: clientId == null ? ModePaiement.especes : ModePaiement.credit,
        montant: f(prix * quantite),
      ),
    ],
    clientId: clientId,
    horodatage: quand,
  );

  Future<int> nombreDeVentes(Caisse caisse) async {
    final compte = caisse.base.ventes.id.count();
    final ligne = await (caisse.base.selectOnly(
      caisse.base.ventes,
    )..addColumns([compte])).getSingle();
    return ligne.read(compte) ?? 0;
  }

  Future<Montant> encaisseDuJour(Caisse caisse) async =>
      (await caisse.depot.rapportDuJour()).encaisse;

  group('Réunir deux caisses', () {
    test("chacune garde ses ventes et reçoit celles de l'autre", () async {
      await vendre(interieur, 1000);
      await vendre(interieur, 500);
      await vendre(comptoir, 250);

      final resultat = await interieur.recevoirDe(comptoir);

      expect(resultat.reussie, isTrue);
      expect(resultat.caissesRecues, ['CAISSE-COMPTOIR']);
      expect(await nombreDeVentes(interieur), 3);
      expect(await encaisseDuJour(interieur), f(1750));
    });

    test('les deux téléphones finissent avec le même total', () async {
      await vendre(interieur, 1000);
      await vendre(comptoir, 250);

      await interieur.recevoirDe(comptoir);
      await comptoir.recevoirDe(interieur);

      expect(await encaisseDuJour(interieur), f(1250));
      expect(await encaisseDuJour(comptoir), f(1250));
      expect(await nombreDeVentes(interieur), 2);
      expect(await nombreDeVentes(comptoir), 2);
    });

    test("l'ardoise ouverte sur une caisse se lit sur l'autre", () async {
      final salif = await interieur.depot.creerClient(
        nom: 'Salif',
        telephone: '70000000',
      );
      await vendre(interieur, 10500, clientId: salif);

      await comptoir.recevoirDe(interieur);

      final chezComptoir = await comptoir.depot.clientParTelephone('70000000');
      expect(chezComptoir, isNotNull);
      expect(chezComptoir!.nom, 'Salif');
      expect(Montant(chezComptoir.encoursCentimes), f(10500));
    });

    test('un remboursement pris au comptoir efface la dette partout', () async {
      final salif = await interieur.depot.creerClient(nom: 'Salif');
      await vendre(interieur, 10000, clientId: salif);
      await comptoir.recevoirDe(interieur);

      await comptoir.depot.rembourserCredit(salif, f(4000));
      await interieur.recevoirDe(comptoir);

      final ici = await (interieur.base.select(
        interieur.base.clients,
      )..where((c) => c.id.equals(salif))).getSingle();
      expect(Montant(ici.encoursCentimes), f(6000));
    });

    test('le stock tient compte des ventes des deux caisses', () async {
      await interieur.depot.creerArticle(
        designation: 'Sucre 1 kg',
        prix: f(750),
        code: 'SUCRE',
      );
      await interieur.depot.definirSuiviStock('SUCRE', SuiviStock.direct);
      await interieur.depot.ajusterStock('SUCRE', const Quantite.unites(100));

      // Le comptoir doit connaître l'article avant de pouvoir le vendre.
      await comptoir.recevoirDe(interieur);

      // Les ventes portent une heure explicite, et c'est le sujet même du
      // test : deux caisses réunies ne se rejouent que dans l'ordre de leurs
      // horloges. Le stock déclaré doit être posé avant les ventes qui le
      // font descendre, sinon il les efface en les repassant par-dessus.
      final ensuite = DateTime.now().add(const Duration(seconds: 2));

      await vendre(
        interieur,
        750,
        code: 'SUCRE',
        designation: 'Sucre 1 kg',
        quantite: 3,
        quand: ensuite,
      );
      await vendre(
        comptoir,
        750,
        code: 'SUCRE',
        designation: 'Sucre 1 kg',
        quantite: 2,
        quand: ensuite.add(const Duration(seconds: 1)),
      );

      await interieur.recevoirDe(comptoir);
      await comptoir.recevoirDe(interieur);

      final ici = await interieur.depot.articleParCode('SUCRE');
      final laBas = await comptoir.depot.articleParCode('SUCRE');
      expect(Quantite(ici!.stockMilliemes!), const Quantite.unites(95));
      expect(Quantite(laBas!.stockMilliemes!), const Quantite.unites(95));
    });

    test("le nom donné à un article d'un côté vaut de l'autre", () async {
      await vendre(interieur, 500, code: 'AUTO-50000', designation: '500 F');
      await interieur.depot.nommerArticle('AUTO-50000', "Sachet d'eau");

      await comptoir.recevoirDe(interieur);

      final article = await comptoir.depot.articleParCode('AUTO-50000');
      expect(article!.designation, "Sachet d'eau");
      expect(article.nomme, isTrue);
    });
  });

  group('Ce que la réunion ne fait pas', () {
    test('réunir deux fois le même fichier n’ajoute rien', () async {
      await vendre(comptoir, 250);
      final fichier = Sauvegardes.ouvrir(await comptoir.fichier())!;

      final premiere = await interieur.sauvegardes.fusionner(fichier);
      final seconde = await interieur.sauvegardes.fusionner(fichier);
      await interieur.depot.reconstruireProjections();

      expect(premiere.evenementsAjoutes, greaterThan(0));
      expect(seconde.reussie, isTrue);
      expect(seconde.rienDeNouveau, isTrue);
      expect(await nombreDeVentes(interieur), 1);
    });

    test("un fichier vide est refusé plutôt que d'écraser le carnet", () async {
      final neuve = Caisse('CAISSE-NEUVE');
      addTearDown(neuve.fermer);

      await vendre(interieur, 1000);
      final vide = Sauvegardes.ouvrir(await neuve.fichier())!;

      final resultat = await interieur.sauvegardes.fusionner(vide);

      expect(resultat.reussie, isFalse);
      expect(await nombreDeVentes(interieur), 1);
    });

    test("réunir garde les ventes d'ici, restaurer les efface", () async {
      // C'est toute la différence entre les deux gestes, sur le même fichier.
      await vendre(interieur, 1000);
      await vendre(comptoir, 250);
      final duComptoir = Sauvegardes.ouvrir(await comptoir.fichier())!;

      await interieur.sauvegardes.fusionner(duComptoir);
      await interieur.depot.reconstruireProjections();
      expect(await encaisseDuJour(interieur), f(1250));

      await interieur.sauvegardes.restaurer(duComptoir);
      await interieur.depot.reconstruireProjections();
      expect(await encaisseDuJour(interieur), f(250));
    });

    test('deux carnets qui se disent la même caisse sont refusés', () async {
      // Deux téléphones portant le même identifiant d'appareil : chacun a
      // écrit sa propre séquence 1. Réunir effacerait une vente réelle.
      final jumelle = Caisse('CAISSE-INTERIEUR');
      addTearDown(jumelle.fermer);

      await vendre(interieur, 1000);
      await vendre(jumelle, 2000);

      final fichier = Sauvegardes.ouvrir(await jumelle.fichier())!;
      final resultat = await interieur.sauvegardes.fusionner(fichier);

      expect(resultat.reussie, isFalse);
      expect(resultat.motif, contains('CAISSE-INTERIEUR'));
      expect(await nombreDeVentes(interieur), 1);
      expect(await encaisseDuJour(interieur), f(1000));
    });

    test('un fichier abîmé est refusé avant la moindre écriture', () async {
      await vendre(interieur, 1000);
      await vendre(comptoir, 250);

      // Quelqu'un a ouvert le fichier et changé une désignation. Les
      // empreintes se recalculent sur le contenu : ça se voit.
      final contenu = (await comptoir.fichier()).replaceFirst(
        'Riz 1 kg',
        'Riz 5 kg',
      );
      final abime = Sauvegardes.ouvrir(contenu)!;

      final resultat = await interieur.sauvegardes.fusionner(abime);

      expect(resultat.reussie, isFalse);
      expect(resultat.motif, contains('abîmé'));
      expect(await nombreDeVentes(interieur), 1);
    });

    test(
      'la chaîne de chaque caisse reste vérifiable après la réunion',
      () async {
        await vendre(interieur, 1000);
        await vendre(comptoir, 250);
        await vendre(comptoir, 300);

        await interieur.recevoirDe(comptoir);

        final verification = await interieur.journal.verifier();
        expect(verification.intact, isTrue);
        expect(verification.motif, isNull);
      },
    );
  });

  group('La trace de la réunion', () {
    test(
      'elle est écrite une fois, et seulement si quelque chose est arrivé',
      () async {
        await vendre(comptoir, 250);

        await interieur.recevoirDe(comptoir);
        await interieur.recevoirDe(comptoir);

        final traces = [
          for (final e in await interieur.journal.tous())
            if (e.type == TypeEvenement.journalFusionne) e,
        ];
        expect(traces, hasLength(1));
        expect(traces.single.appareil, 'CAISSE-INTERIEUR');
        expect(traces.single.charge['caisses'], ['CAISSE-COMPTOIR']);
        expect(traces.single.charge['ajoutes'], greaterThan(0));
      },
    );

    test('elle se rejoue sans rien changer aux projections', () async {
      await vendre(interieur, 1000);
      await vendre(comptoir, 250);
      await interieur.recevoirDe(comptoir);

      final avant = await encaisseDuJour(interieur);
      final ventes = await nombreDeVentes(interieur);

      await interieur.depot.reconstruireProjections();

      expect(await encaisseDuJour(interieur), avant);
      expect(await nombreDeVentes(interieur), ventes);
    });
  });

  group("L'écran ne mélange pas les deux gestes", () {
    Future<void> ouvrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: themeClair(),
          home: EcranSauvegardes(
            depot: interieur.depot,
            nomCommerce: 'Chez Awa',
          ),
        ),
      );
      // Le stockage du téléphone n'existe pas dans un test : l'écran
      // l'attend trois secondes puis s'affiche sans la liste des fichiers.
      // C'est exactement ce qui doit se passer sur un téléphone qui ne
      // répond pas, et c'est pour ça que l'écran le supporte.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    }

    testWidgets('réunir et restaurer sont deux sections distinctes', (
      tester,
    ) async {
      await ouvrir(tester);

      expect(find.text('Deux caisses, une boutique'), findsOneWidget);
      expect(find.text('Réunir avec une autre caisse'), findsOneWidget);
      expect(find.text('Restaurer'), findsOneWidget);
      expect(find.text('Ouvrir un fichier reçu'), findsOneWidget);
    });

    testWidgets("la réunion promet de ne rien effacer, la restauration "
        "prévient du contraire", (tester) async {
      await vendre(interieur, 1000);
      await ouvrir(tester);

      // Deux textes qui se contredisent volontairement : c'est le seul
      // garde-fou contre quelqu'un qui, plus tard, fondrait les deux gestes
      // en un seul bouton.
      expect(
        find.textContaining("Rien n'est effacé"),
        findsOneWidget,
        reason: "la section « réunir » doit dire qu'elle n'efface rien",
      );
      expect(
        find.textContaining('remplace tout ce qui est là'),
        findsOneWidget,
        reason: 'la section « restaurer » doit dire le contraire',
      );
    });
  });

  group('Ce que deux caisses ne peuvent pas savoir seules', () {
    test("deux articles ouverts au même prix ne se confondent plus", () async {
      // Un article nommé existe déjà à 500 F sur les deux caisses : à partir
      // de là, chaque montant libre à 500 F ouvre un article de plus.
      await interieur.depot.creerArticle(
        designation: "Sachet d'eau",
        prix: f(500),
        code: 'EAU',
      );
      await comptoir.recevoirDe(interieur);

      // Chacune vend autre chose à 500 F, sans voir l'autre.
      await vendre(interieur, 500, code: null, designation: null);
      await vendre(comptoir, 500, code: null, designation: null);
      await interieur.recevoirDe(comptoir);

      // L'une nomme du pain, l'autre des beignets. Si les deux codes étaient
      // les mêmes, il ne resterait qu'une ligne — et un stock mélangé.
      final ouverts = [
        for (final a in await interieur.depot.articlesAuPrix(f(500)))
          if (a.code != 'EAU') a.code,
      ];
      expect(ouverts, hasLength(2), reason: 'deux articles, deux codes');
      expect(ouverts.toSet(), hasLength(2));
    });

    test('deux factures sous le même numéro sont signalées', () async {
      // Chaque caisse compte ses factures dans son propre journal : hors
      // réseau, les deux sortent FV-<année>-000001.
      final venteIci = await vendre(interieur, 12000);
      final venteLaBas = await vendre(comptoir, 8000);
      final ici = await interieur.depot.emettreFacture(venteIci);
      final laBas = await comptoir.depot.emettreFacture(venteLaBas);
      expect(ici.texte, laBas.texte, reason: 'le défaut, avant tout');

      final resultat = await interieur.recevoirDe(comptoir);

      expect(resultat.reussie, isTrue, reason: 'on ne bloque pas la réunion');
      expect(resultat.facturesEnDouble, [ici.texte]);
    });

    test(
      'la même facture reçue deux fois ne compte pas pour un double',
      () async {
        final vente = await vendre(comptoir, 8000);
        await comptoir.depot.emettreFacture(vente);

        await interieur.recevoirDe(comptoir);
        final seconde = await interieur.recevoirDe(comptoir);

        expect(seconde.facturesEnDouble, isEmpty);
      },
    );
  });

  group("L'heure des deux téléphones", () {
    test(
      'une horloge en avance est signalée sans bloquer la réunion',
      () async {
        // Le téléphone du comptoir croit qu'on est deux heures plus tard. Rien
        // ne l'empêche techniquement : les téléphones d'entrée de gamme n'ont
        // pas tous l'heure du réseau, et personne ne vérifie.
        await vendre(
          comptoir,
          250,
          quand: DateTime.now().add(const Duration(hours: 2)),
        );

        final resultat = await interieur.recevoirDe(comptoir);

        expect(resultat.reussie, isTrue);
        expect(resultat.evenementsAjoutes, greaterThan(0));
        expect(resultat.decalageHorloge, isNotNull);
        expect(resultat.decalageHorloge!.inMinutes, greaterThan(100));
      },
    );

    test('quelques secondes ne dérangent personne', () async {
      await vendre(comptoir, 250);

      final resultat = await interieur.recevoirDe(comptoir);

      expect(resultat.reussie, isTrue);
      expect(resultat.decalageHorloge, isNull);
    });
  });

  group("Les réglages de l'équipe", () {
    test("la liste des vendeurs prend l'union des deux téléphones", () async {
      await interieur.parametres.definirVendeurs(['Awa', 'Salif']);
      await comptoir.parametres.definirVendeurs(['Salif', 'Fatou']);
      await vendre(comptoir, 250);

      await interieur.recevoirDe(comptoir);

      final reglage = await interieur.parametres.tout();
      expect(reglage.vendeurs, ['Awa', 'Salif', 'Fatou']);
    });

    test(
      "qui tient la caisse ici ne vient jamais de l'autre téléphone",
      () async {
        await interieur.parametres.definirVendeurs(['Awa', 'Fatou']);
        await interieur.parametres.definirVendeurActif('Awa');
        await comptoir.parametres.definirVendeurs(['Fatou']);
        await comptoir.parametres.definirVendeurActif('Fatou');
        await vendre(comptoir, 250);

        await interieur.recevoirDe(comptoir);

        expect((await interieur.parametres.tout()).vendeurActif, 'Awa');
      },
    );

    test('un réglage qui manque ici est repris du fichier', () async {
      await comptoir.parametres.definirNomCommerce('Alimentation Nabonswendé');
      await vendre(comptoir, 250);

      await interieur.recevoirDe(comptoir);

      expect(
        (await interieur.parametres.tout()).nomCommerce,
        'Alimentation Nabonswendé',
      );
    });

    test(
      'la correction la plus récente gagne, pas le dernier fichier reçu',
      () async {
        // Le patron corrige le nom sur son téléphone après que la vendeuse a
        // posé le sien. Le fichier de la vendeuse ne doit pas défaire ça.
        await comptoir.parametres.definirNomCommerce(
          'Alimentation Nabonswende',
        );
        await vendre(comptoir, 250);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await interieur.parametres.definirNomCommerce(
          'Alimentation Nabonswendé',
        );

        await interieur.recevoirDe(comptoir);

        expect(
          (await interieur.parametres.tout()).nomCommerce,
          'Alimentation Nabonswendé',
        );
      },
    );

    test(
      "un fichier sans dates de réglages ne remplace que ce qui manque",
      () async {
        await comptoir.parametres.definirNomCommerce('Chez le comptoir');
        await vendre(comptoir, 250);
        await interieur.parametres.definirNomCommerce('Chez le patron');

        // Un fichier écrit par une version qui ne datait pas ses réglages.
        final ancien = Sauvegardes.ouvrir(await comptoir.fichier())!;
        final sansDates = Sauvegarde(
          apercu: ancien.apercu,
          evenements: ancien.evenements,
          reglages: ancien.reglages,
        );

        await interieur.sauvegardes.fusionner(sansDates);

        expect(
          (await interieur.parametres.tout()).nomCommerce,
          'Chez le patron',
        );
      },
    );
  });
}
