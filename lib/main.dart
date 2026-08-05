import 'package:flutter/material.dart';

import 'interface/ecrans/vente.dart';
import 'interface/theme/theme.dart';

void main() => runApp(const Application());

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Carnet',
        debugShowCheckedModeBanner: false,
        theme: themeClair(),
        darkTheme: themeSombre(),
        home: const EcranVente(),
      );
}
