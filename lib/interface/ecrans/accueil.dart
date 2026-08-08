/// Coquille de navigation.
///
/// Quatre destinations, pas une de plus : la caisse, les dettes, le stock, le
/// rapport. Un menu qui se déplie serait un menu qu'on n'ouvre jamais.
library;

import 'package:flutter/material.dart';

import '../../donnees/analyses.dart';
import '../../donnees/depot.dart';
import '../../donnees/documents.dart';
import '../../donnees/parametres.dart';
import '../theme/palette.dart';
import 'dettes.dart';
import 'rapport.dart';
import 'reglages.dart';
import 'stock.dart';
import 'vente.dart';

class Accueil extends StatefulWidget {
  final Depot depot;
  final Documents documents;
  final Analyses analyses;
  final Parametres parametres;

  /// L'état des réglages au démarrage, lu une fois avant l'affichage.
  final Reglage reglage;

  const Accueil({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    required this.parametres,
    required this.reglage,
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

  final _cleCaisse = GlobalKey<EcranVenteState>();
  final _cleDettes = GlobalKey<EcranDettesState>();
  final _cleStock = GlobalKey<EcranStockState>();
  final _cleRapport = GlobalKey<EcranRapportState>();

  late Reglage _reglage = widget.reglage;

  /// Le nom du commerce s'imprime sur tous les documents : quand il change,
  /// la fabrique doit changer avec lui.
  late Documents _documents = widget.documents;

  Future<void> _ouvrirReglages() async {
    final maj = await EcranReglages.ouvrir(
      context,
      parametres: widget.parametres,
      reglage: _reglage,
      depot: widget.depot,
    );
    if (maj == null || !mounted) return;

    setState(() {
      _reglage = maj;
      _documents =
          Documents(widget.documents.base, nomCommerce: maj.nomCommerce);
    });

    // Une restauration a pu remplacer tout le carnet pendant qu'on était
    // dans les réglages. Les écrans déjà montés garderaient sinon les
    // chiffres de la boutique d'avant.
    for (final ecran in [_cleCaisse, _cleDettes, _cleStock, _cleRapport]) {
      switch (ecran.currentState) {
        case final EcranVenteState etat:
          etat.recharger();
        case final EcranDettesState etat:
          etat.recharger();
        case final EcranStockState etat:
          etat.recharger();
        case final EcranRapportState etat:
          etat.recharger();
        default:
          break;
      }
    }
  }

  /// Retient qui tient la caisse, pour de bon.
  ///
  /// Une équipe ne se redéclare pas chaque matin : le choix survit à la
  /// fermeture de l'application, comme le reste des réglages.
  Future<void> _changerVendeur(String nom) async {
    await widget.parametres.definirVendeurActif(nom);
    if (!mounted) return;
    setState(() => _reglage = Reglage(
          nomCommerce: _reglage.nomCommerce,
          comptes: _reglage.comptes,
          vendeurs: _reglage.vendeurs,
          vendeurActif: nom,
        ));
  }

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
      case 0:
        _cleCaisse.currentState?.recharger();
      case 1:
        _cleDettes.currentState?.recharger();
      case 2:
        _cleStock.currentState?.recharger();
      case 3:
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
          EcranVente(
            key: _cleCaisse,
            depot: widget.depot,
            documents: _documents,
            comptes: _reglage.comptes,
            surConfiguration: _ouvrirReglages,
            vendeurs: _reglage.vendeurs,
            vendeurActif: _reglage.vendeurActif,
            surVendeur: _changerVendeur,
          ),
          _onglet(
            1,
            () => EcranDettes(
              key: _cleDettes,
              depot: widget.depot,
              documents: _documents,
            ),
          ),
          _onglet(2, () => EcranStock(key: _cleStock, depot: widget.depot)),
          _onglet(
            3,
            () => EcranRapport(
              key: _cleRapport,
              depot: widget.depot,
              documents: _documents,
              analyses: widget.analyses,
              surReglages: _ouvrirReglages,
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
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Stock',
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
