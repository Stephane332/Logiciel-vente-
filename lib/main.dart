import 'package:flutter/material.dart';

import 'donnees/analyses.dart';
import 'donnees/depot.dart';
import 'donnees/documents.dart';
import 'donnees/journal.dart';
import 'donnees/ouverture.dart';
import 'interface/ecrans/accueil.dart';
import 'interface/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final base = await ouvrirBaseLocale();
  final appareil = await identifiantAppareil();

  // Le nom du commerce viendra de la fiche entreprise, que la certification
  // imposera de renseigner. En attendant, une valeur par défaut suffit.
  const nomCommerce = 'Ma boutique';

  runApp(Application(
    depot: Depot(base, Journal(base, appareil: appareil)),
    documents: Documents(base, nomCommerce: nomCommerce),
    analyses: Analyses(base),
    nomCommerce: nomCommerce,
  ));
}

class Application extends StatelessWidget {
  final Depot depot;
  final Documents documents;
  final Analyses analyses;
  final String nomCommerce;

  const Application({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    required this.nomCommerce,
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
          nomCommerce: nomCommerce,
        ),
      );
}
