import 'package:flutter/material.dart';

import 'donnees/depot.dart';
import 'donnees/journal.dart';
import 'donnees/ouverture.dart';
import 'interface/ecrans/vente.dart';
import 'interface/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final base = await ouvrirBaseLocale();
  final appareil = await identifiantAppareil();
  final depot = Depot(base, Journal(base, appareil: appareil));

  runApp(Application(depot: depot));
}

class Application extends StatelessWidget {
  final Depot depot;

  const Application({super.key, required this.depot});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Carnet',
        debugShowCheckedModeBanner: false,
        theme: themeClair(),
        darkTheme: themeSombre(),
        home: EcranVente(depot: depot),
      );
}
