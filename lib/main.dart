import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'donnees/analyses.dart';
import 'donnees/depot.dart';
import 'donnees/documents.dart';
import 'donnees/journal.dart';
import 'donnees/ouverture.dart';
import 'donnees/parametres.dart';
import 'interface/ecrans/accueil.dart';
import 'interface/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final base = await ouvrirBaseLocale();
  final appareil = await identifiantAppareil();

  // Les réglages sont lus une fois, avant le premier écran : ce sont
  // quelques lignes, et tout a un repli si rien n'a jamais été renseigné.
  final parametres = Parametres(base);
  final reglage = await parametres.tout();

  // Dans un navigateur, la persistance ne se promet pas : elle se constate.
  // On dépose un témoin au premier lancement, et c'est de le retrouver au
  // suivant qui prouve que ce qu'on écrit sera relu.
  final stockageSur =
      stockageADemontrer ? await parametres.temoinRetrouve() : true;

  runApp(Application(
    depot: Depot(base, Journal(base, appareil: appareil)),
    documents: Documents(base, nomCommerce: reglage.nomCommerce),
    analyses: Analyses(base),
    parametres: parametres,
    reglage: reglage,
    stockageSur: stockageSur,
  ));
}

class Application extends StatelessWidget {
  final Depot depot;
  final Documents documents;
  final Analyses analyses;
  final Parametres parametres;
  final Reglage reglage;

  /// Faux tant qu'on n'a pas la preuve que ce qui est saisi sera relu.
  final bool stockageSur;

  const Application({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    required this.parametres,
    required this.reglage,
    this.stockageSur = true,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Carnet',
        debugShowCheckedModeBanner: false,

        // Le français est imposé, pas déduit du téléphone. Toute
        // l'application est écrite en français : sur un téléphone réglé en
        // anglais, suivre le système donnerait « Paste » sous « Donne-lui un
        // nom ». Et un téléphone dont la langue n'est pas reconnue faisait
        // tomber l'application sur un écran blanc, sans message.
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        theme: themeClair(),
        darkTheme: themeSombre(),
        home: Accueil(
          depot: depot,
          documents: documents,
          analyses: analyses,
          parametres: parametres,
          reglage: reglage,
          stockageSur: stockageSur,
        ),
      );
}
