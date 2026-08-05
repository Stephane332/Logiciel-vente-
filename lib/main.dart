import 'package:flutter/material.dart';

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

  runApp(Application(
    depot: Depot(base, Journal(base, appareil: appareil)),
    documents: Documents(base, nomCommerce: reglage.nomCommerce),
    analyses: Analyses(base),
    parametres: parametres,
    reglage: reglage,
  ));
}

class Application extends StatelessWidget {
  final Depot depot;
  final Documents documents;
  final Analyses analyses;
  final Parametres parametres;
  final Reglage reglage;

  const Application({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    required this.parametres,
    required this.reglage,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Carnet',
        debugShowCheckedModeBanner: false,
        theme: themeClair(),
        darkTheme: themeSombre(),
        home: Accueil(
          depot: depot,
          documents: documents,
          analyses: analyses,
          parametres: parametres,
          reglage: reglage,
        ),
      );
}
