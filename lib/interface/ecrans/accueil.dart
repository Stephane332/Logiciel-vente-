/// Coquille de navigation.
///
/// Quatre destinations, pas une de plus : la caisse, les dettes, le stock, le
/// rapport. Un menu qui se déplie serait un menu qu'on n'ouvre jamais.
library;

import 'package:flutter/material.dart';

import '../../domaine/rappel_sauvegarde.dart';
import '../../donnees/analyses.dart';
import '../../donnees/depot.dart';
import '../../donnees/documents.dart';
import '../../donnees/parametres.dart';
import '../theme/palette.dart';
import 'dettes.dart';
import 'sauvegardes.dart';
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

  /// Faux tant qu'on n'a pas la preuve que ce qui est saisi sera relu.
  ///
  /// C'est le cas de la démonstration dans un navigateur, au premier
  /// lancement. Sur un téléphone, la base est un fichier et la question ne se
  /// pose pas.
  final bool stockageSur;

  const Accueil({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    required this.parametres,
    required this.reglage,
    this.stockageSur = true,
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

  /// L'avertissement de démonstration se ferme, et ne revient pas de la
  /// session. On prévient, on n'assiège pas.
  bool _avertissementEcarte = false;

  /// Le rappel de sauvegarde, quand il y a lieu de le faire. Nul le reste du
  /// temps, c'est-à-dire la plupart du temps.
  RappelSauvegarde? _rappel;

  /// Écarté d'un appui, pour la session. Même règle que l'autre bandeau : on
  /// prévient une fois, on ne se met pas en travers de la caisse.
  bool _rappelEcarte = false;

  @override
  void initState() {
    super.initState();
    _examinerLaSauvegarde();
  }

  /// Regarde si le carnet est sorti du téléphone récemment.
  ///
  /// Deux lectures courtes, faites une fois à l'ouverture : la date du dernier
  /// envoi, et le nombre d'écritures depuis. On compte, on ne relit pas le
  /// journal — il fait des milliers de lignes au bout d'un an.
  Future<void> _examinerLaSauvegarde() async {
    final derniere = await widget.parametres.derniereSauvegarde();
    final nouveautes = await widget.depot.journal.nombreDepuis(derniere);
    if (!mounted) return;

    setState(() => _rappel = RappelSauvegarde(
          nouveautes: nouveautes,
          derniere: derniere,
          maintenant: DateTime.now(),
        ));
  }

  Future<void> _ouvrirSauvegardes() async {
    await EcranSauvegardes.ouvrir(
      context,
      depot: widget.depot,
      nomCommerce: _reglage.nomCommerce,
      parametres: widget.parametres,
    );
    if (!mounted) return;
    setState(() => _rappelEcarte = true);
    await _examinerLaSauvegarde();
  }

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

    // Le bandeau « Vente enregistrée · Annuler » appartient à la caisse. Il
    // vivait au niveau de la coquille, donc il suivait sur les autres onglets :
    // on le retrouvait sous la dette d'un client, avec un bouton « Annuler »
    // juste dessous. Le commerçant pouvait raisonnablement croire qu'il annule
    // ce qu'il a sous les yeux — il annulait la vente, donc la dette.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

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
      body: Column(children: [
        if (!widget.stockageSur && !_avertissementEcarte)
          _BandeauDemonstration(onFermer: () =>
              setState(() => _avertissementEcarte = true)),
        if (_rappel != null && _rappel!.faut && !_rappelEcarte)
          _BandeauSauvegarde(
            message: _rappel!.message,
            surSauvegarde: _ouvrirSauvegardes,
            onFermer: () => setState(() => _rappelEcarte = true),
          ),
        Expanded(child: IndexedStack(
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
        )),
      ]),
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

/// Prévient que ce qui est saisi ne sera peut-être pas retrouvé.
///
/// Uniquement dans un navigateur, et seulement tant que la preuve du
/// contraire n'a pas été faite. Un commerçant qui saisit sa journée et la
/// retrouve vide n'ouvrira pas l'application une deuxième fois — autant le
/// dire avant qu'il ne tape quoi que ce soit.
/// Le rappel de sauvegarde.
///
/// En ocre, pas en rouge : rien n'est cassé, il y a quelque chose à faire.
/// Et avec un bouton, parce qu'un rappel sans le geste qu'il demande oblige
/// le commerçant à chercher — ce qu'il ne fera pas entre deux clients.
class _BandeauSauvegarde extends StatelessWidget {
  final String message;
  final VoidCallback surSauvegarde;
  final VoidCallback onFermer;

  const _BandeauSauvegarde({
    required this.message,
    required this.surSauvegarde,
    required this.onFermer,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Material(
      color: Couleurs.accentClair,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Espace.l, Espace.s, Espace.s, Espace.s),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 18, color: Couleurs.accent),
              const SizedBox(width: Espace.s),
              Expanded(child: Text(message, style: textes.labelSmall)),
              const SizedBox(width: Espace.s),
              TextButton(
                onPressed: surSauvegarde,
                child: const Text('Sauvegarder'),
              ),
              IconButton(
                onPressed: onFermer,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Plus tard',
                color: Couleurs.encreDouce,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandeauDemonstration extends StatelessWidget {
  final VoidCallback onFermer;

  const _BandeauDemonstration({required this.onFermer});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Material(
      color: Couleurs.alerteClair,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espace.l, Espace.s, Espace.s,
              Espace.s),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: Couleurs.alerte),
              const SizedBox(width: Espace.s),
              Expanded(
                child: Text(
                  'Démonstration : selon ce navigateur, ce que tu saisis peut '
                  "ne pas être retrouvé après fermeture. Sur téléphone, rien "
                  'ne se perd.',
                  style: textes.labelSmall,
                ),
              ),
              IconButton(
                onPressed: onFermer,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: "J'ai compris",
                color: Couleurs.encreDouce,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
