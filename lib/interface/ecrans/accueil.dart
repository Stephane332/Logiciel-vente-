/// Coquille de navigation.
///
/// Trois destinations, pas une de plus : la caisse, les dettes, le rapport.
/// Un menu qui se déplie serait un menu qu'on n'ouvre jamais.
library;

import 'package:flutter/material.dart';

import '../../donnees/analyses.dart';
import '../../donnees/depot.dart';
import '../../donnees/documents.dart';
import '../theme/palette.dart';
import 'dettes.dart';
import 'rapport.dart';
import 'vente.dart';

class Accueil extends StatefulWidget {
  final Depot depot;
  final Documents documents;
  final Analyses analyses;

  const Accueil({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
  });

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  int _destination = 0;

  /// Les onglets déjà ouverts au moins une fois.
  ///
  /// La pile monte tous ses enfants d'un coup : sans ce filtre, ouvrir
  /// l'application lancerait aussi les analyses de la semaine et le calcul
  /// des dettes, pendant que le commerçant attend sa caisse.
  final _visites = {0};

  final _cleDettes = GlobalKey<EcranDettesState>();
  final _cleRapport = GlobalKey<EcranRapportState>();

  /// Change d'écran et rafraîchit celui qu'on ouvre.
  ///
  /// La pile garde les écrans en vie, donc ils ne se reconstruisent pas tout
  /// seuls : sans ce rappel, le rapport montrerait les chiffres d'avant la
  /// vente qu'on vient d'encaisser.
  void _aller(int index) {
    if (index == _destination) return;

    final premiereVisite = _visites.add(index);
    setState(() => _destination = index);

    // À la première visite l'écran se monte et se charge lui-même.
    if (premiereVisite) return;
    switch (index) {
      case 1:
        _cleDettes.currentState?.recharger();
      case 2:
        _cleRapport.currentState?.recharger();
    }
  }

  /// N'instancie l'écran qu'une fois son onglet ouvert.
  Widget _onglet(int index, Widget Function() construire) =>
      _visites.contains(index) ? construire() : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Les écrans sont conservés en pile : revenir à la caisse ne doit pas
      // faire perdre le panier en cours.
      body: IndexedStack(
        index: _destination,
        children: [
          EcranVente(depot: widget.depot, documents: widget.documents),
          _onglet(
            1,
            () => EcranDettes(
              key: _cleDettes,
              depot: widget.depot,
              documents: widget.documents,
            ),
          ),
          _onglet(
            2,
            () => EcranRapport(
              key: _cleRapport,
              depot: widget.depot,
              documents: widget.documents,
              analyses: widget.analyses,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _destination,
        height: 68,
        backgroundColor: Couleurs.surface,
        indicatorColor: Couleurs.primaireClair,
        onDestinationSelected: _aller,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale_rounded),
            label: 'Caisse',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Dettes',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Rapport',
          ),
        ],
      ),
    );
  }
}
