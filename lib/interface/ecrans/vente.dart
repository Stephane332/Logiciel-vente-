/// Écran de vente — le cœur de l'application.
///
/// Tout est conçu pour qu'une vente s'enregistre en moins de dix secondes :
/// le total est toujours visible, les articles sont des cibles larges, et le
/// bouton d'encaissement ne bouge jamais de place.
///
/// L'écran lit le catalogue depuis la base et écrit chaque vente dans le
/// journal. Rien n'attend le réseau.
library;

import 'package:flutter/material.dart';

import '../../domaine/montant.dart';
import '../../domaine/references.dart';
import '../../donnees/base.dart';
import '../../donnees/depot.dart';
import '../../donnees/documents.dart';
import '../../domaine/mobile_money.dart';
import '../composants/montant_anime.dart';
import '../composants/pave_numerique.dart';
import '../composants/partage.dart';
import '../composants/tuile_produit.dart';
import '../theme/palette.dart';
import 'feuille_paiement.dart';
import 'nommer_article.dart';

class EcranVente extends StatefulWidget {
  final Depot depot;
  final Documents documents;

  /// Les comptes sur lesquels le commerçant encaisse par téléphone.
  final ComptesMarchands comptes;

  /// Emmène aux réglages depuis la feuille d'encaissement, quand rien n'y
  /// est encore renseigné.
  final VoidCallback? surConfiguration;

  const EcranVente({
    super.key,
    required this.depot,
    required this.documents,
    this.comptes = const ComptesMarchands.aucun(),
    this.surConfiguration,
  });

  @override
  State<EcranVente> createState() => EcranVenteState();
}

class EcranVenteState extends State<EcranVente> {
  /// Le panier en cours : code d'article vers quantité.
  final _panier = <String, int>{};

  /// Prix négocié pour cette vente, quand il diffère du catalogue.
  ///
  /// Sur un marché le prix se discute. Le prix du catalogue est une
  /// proposition, pas une contrainte : on garde les deux pour pouvoir montrer
  /// au commerçant ce que ses remises lui coûtent.
  final _prixNegocies = <String, Montant>{};

  List<LigneArticle> _catalogue = const [];
  List<LigneArticle> _aNommer = const [];
  List<LigneClient> _clients = const [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  /// Relit le catalogue et les clients.
  ///
  /// Publique : la coquille l'appelle au retour sur la caisse. Un article
  /// créé depuis l'écran de stock doit être vendable tout de suite, sinon le
  /// commerçant croit que sa saisie n'a servi à rien.
  Future<void> recharger() async {
    final (catalogue, aNommer, clients) = await (
      widget.depot.catalogue(),
      widget.depot.articlesANommer(),
      widget.depot.clients(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _catalogue = catalogue;
      _aNommer = aNommer;
      _clients = clients;
      _chargement = false;
    });
  }

  LigneArticle? _article(String code) {
    for (final article in _catalogue) {
      if (article.code == code) return article;
    }
    return null;
  }

  /// Le prix pratiqué pour un article : le prix négocié s'il y en a un,
  /// sinon celui du catalogue.
  Montant _prixPratique(LigneArticle article) =>
      _prixNegocies[article.code] ?? Montant(article.prixCentimes);

  Montant get _total {
    var total = const Montant.zero();
    _panier.forEach((code, quantite) {
      final article = _article(code);
      if (article == null) return;
      total = total +
          _prixPratique(article).multiplieParQuantite(Quantite.unites(quantite));
    });
    return total;
  }

  int get _nombreArticles =>
      _panier.values.fold(0, (somme, quantite) => somme + quantite);

  void _ajouter(LigneArticle article) {
    setState(() => _panier[article.code] = (_panier[article.code] ?? 0) + 1);
  }

  void _viderPanier() => setState(() {
        _panier.clear();
        _prixNegocies.clear();
      });

  /// Change le prix d'un article pour cette vente seulement.
  ///
  /// Un appui long : le geste rapide reste l'appui simple, qui vend au prix
  /// du catalogue.
  Future<void> _negocier(LigneArticle article) async {
    final montant = await demanderMontant(
      context,
      titre: 'Prix pour ${article.designation}',
      indication: 'Catalogue : ${Montant(article.prixCentimes).enFrancs}',
      valider: 'Utiliser ce prix',
    );
    if (montant == null || !montant.estPositif) return;

    setState(() {
      _prixNegocies[article.code] = montant;
      _panier[article.code] = _panier[article.code] ?? 1;
    });
  }

  Future<void> _encaisser() async {
    if (_panier.isEmpty) return;

    await FeuillePaiement.presenter(
      context,
      total: _total,
      comptes: widget.comptes,
      nomCommerce: widget.documents.nomCommerce,
      surConfiguration: widget.surConfiguration,
      clients: _clients,
      surNouveauClient: (nom, telephone) =>
          widget.depot.creerClient(nom: nom, telephone: telephone),
      surPaiementChoisi: _enregistrer,
    );
  }

  Future<void> _enregistrer(ModePaiement mode, String? clientId) async {
    final lignes = <LigneAEnregistrer>[];
    _panier.forEach((code, quantite) {
      final article = _article(code);
      if (article == null) return;
      final negocie = _prixNegocies[code];
      lignes.add(LigneAEnregistrer(
        codeArticle: code,
        designation: article.designation,
        prixUnitaire: negocie ?? Montant(article.prixCentimes),
        // Le prix du catalogue n'est conservé que s'il a été modifié :
        // sinon il n'y a pas de remise à mesurer.
        prixCatalogue: negocie == null ? null : Montant(article.prixCentimes),
        quantite: Quantite.unites(quantite),
        groupeTaxation: GroupeTaxation.parEtiquette(article.groupeTaxation),
      ));
    });
    if (lignes.isEmpty) return;

    final venteId = await widget.depot.enregistrerVente(
      lignes: lignes,
      paiements: [PaiementAEnregistrer(mode: mode, montant: _total)],
      // Sans client, une vente à crédit n'entrerait jamais dans le cahier
      // de dettes : la feuille de paiement l'exige donc avant de valider.
      clientId: clientId,
    );

    final encaisse = _total;
    _panier.clear();
    _prixNegocies.clear();
    await recharger();
    _proposerRecu(venteId, encaisse);
  }

  /// Propose le reçu après la vente.
  ///
  /// Sans insister : au comptoir, la plupart des clients n'en veulent pas, et
  /// une question posée à chaque vente ferait perdre plus de temps qu'elle
  /// n'en fait gagner.
  ///
  /// Le document n'est composé que si le reçu est réellement demandé. Le
  /// construire à chaque vente coûterait trois requêtes sur le geste le plus
  /// répété de la journée, pour un texte que presque personne ne lira.
  void _proposerRecu(String venteId, Montant total) {
    if (!mounted) return;

    final messager = ScaffoldMessenger.of(context);
    messager.hideCurrentSnackBar();
    messager.showSnackBar(SnackBar(
      content: Text('Vente enregistrée · ${total.enFrancs}'),
      behavior: SnackBarBehavior.floating,
      // Le bandeau flotte au-dessus de la barre d'encaissement, jamais
      // dessus : au comptoir, la vente suivante commence dans la seconde,
      // et un bouton masqué pendant trois secondes fait perdre le client.
      margin: const EdgeInsets.fromLTRB(Espace.m, 0, Espace.m, 92),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(label: 'Reçu', onPressed: () => _recu(venteId)),
    ));
  }

  Future<void> _recu(String venteId) async {
    final recu = await widget.documents.pourVente(venteId);
    if (recu == null || !mounted) return;
    await FeuilleDocument.presenter(context, titre: 'Reçu', texte: recu.texte);
  }

  /// Encaisse un montant libre : aucun article n'est choisi, seul le montant
  /// compte. Le catalogue se construira tout seul si le montant revient.
  Future<void> _montantLibre() async {
    final montant =
        await demanderMontant(context, titre: 'Montant de la vente');
    if (montant == null || !montant.estPositif) return;

    final venteId = await widget.depot.enregistrerVente(
      lignes: [
        LigneAEnregistrer(
          prixUnitaire: montant,
          quantite: const Quantite.unites(1),
        )
      ],
      paiements: [
        PaiementAEnregistrer(mode: ModePaiement.especes, montant: montant)
      ],
    );
    await recharger();
    _proposerRecu(venteId, montant);
  }

  Future<void> _proposerNommage() async {
    if (_aNommer.isEmpty) return;
    final article = _aNommer.first;

    final resultat = await NommerArticle.demander(
      context,
      prix: Montant(article.prixCentimes),
      nombreVentes: article.nombreVentes,
    );
    if (resultat == null) return;

    switch (resultat.reponse) {
      case ReponseNommage.nomme:
        final nom = resultat.nom?.trim() ?? '';
        if (nom.isEmpty) return;
        await widget.depot.nommerArticle(article.code, nom);

      case ReponseNommage.melange:
        // Le commerçant vend plusieurs choses à ce prix-là. Plutôt que de le
        // laisser avec un fourre-tout, on crée ses articles maintenant :
        // c'est le seul moment où il y pense déjà.
        await _separer(article, resultat.noms);

      case ReponseNommage.plusTard:
        return;
    }
    await recharger();
  }

  /// Crée un article par nom, au prix du fourre-tout, et cesse de demander.
  ///
  /// Les ventes déjà faites restent sur l'ancien article : le journal ne se
  /// réécrit pas, et personne ne saurait dire lesquelles étaient quoi. À
  /// partir de maintenant, le commerçant appuie sur les tuiles — chemin où le
  /// prix ne sert plus d'identité.
  Future<void> _separer(LigneArticle article, List<String> noms) async {
    final prix = Montant(article.prixCentimes);
    for (final nom in noms) {
      await widget.depot.creerArticle(designation: nom, prix: prix);
    }
    await widget.depot.refuserNommage(article.code);

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          '${noms.length} articles créés à ${prix.enFrancs}. '
          'Appuie dessus au lieu de taper le montant.',
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(Espace.m, 0, Espace.m, 92),
        duration: const Duration(seconds: 5),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;
    final panierVide = _panier.isEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _EnTete(total: _total, nombreArticles: _nombreArticles),
            if (_aNommer.isNotEmpty)
              _BandeauNommage(
                article: _aNommer.first,
                onPressed: _proposerNommage,
              ),
            Expanded(
              child: _chargement
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(Espace.l, Espace.l,
                          Espace.l, Espace.xxxl + Espace.xl),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisSpacing: Espace.m,
                        crossAxisSpacing: Espace.m,
                        // Tuiles légèrement plus larges que hautes : on en
                        // voit davantage et le commerçant fait moins défiler.
                        childAspectRatio: 1.15,
                      ),
                      itemCount: _catalogue.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return TuileAction(
                            icone: Icons.dialpad_rounded,
                            libelle: 'Montant\nlibre',
                            onPressed: _montantLibre,
                          );
                        }
                        if (index == 1) {
                          return TuileAction(
                            icone: Icons.qr_code_scanner_rounded,
                            libelle: 'Scanner',
                            onPressed: () {},
                          );
                        }

                        final article = _catalogue[index - 2];
                        return TuileProduit(
                          nom: article.designation,
                          prix: _prixPratique(article),
                          prixNegocie: _prixNegocies.containsKey(article.code),
                          quantiteAuPanier: _panier[article.code] ?? 0,
                          onPressed: () => _ajouter(article),
                          onLongPress: () => _negocier(article),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // Le bouton d'encaissement ne change jamais de place : c'est le geste
      // le plus répété de la journée.
      bottomSheet: AnimatedContainer(
        duration: Duree.moyenne,
        curve: Courbe.sortie,
        padding: EdgeInsets.fromLTRB(
          Espace.l,
          Espace.m,
          Espace.l,
          Espace.m + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: couleurs.surface,
          border: Border(top: BorderSide(color: couleurs.outlineVariant)),
        ),
        child: Row(
          children: [
            AnimatedSize(
              duration: Duree.moyenne,
              curve: Courbe.sortie,
              child: panierVide
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(right: Espace.m),
                      child: IconButton.filledTonal(
                        onPressed: _viderPanier,
                        iconSize: 22,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(cibleTactile),
                          backgroundColor: Couleurs.alerteClair,
                          foregroundColor: Couleurs.alerte,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: panierVide ? null : _encaisser,
                style: FilledButton.styleFrom(
                  backgroundColor: Couleurs.primaire,
                  disabledBackgroundColor: Couleurs.bordure,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      panierVide ? 'Choisir un article' : 'Encaisser',
                      style: textes.labelLarge?.copyWith(
                        fontSize: 17,
                        color:
                            panierVide ? Couleurs.encreLegere : Colors.white,
                      ),
                    ),
                    if (!panierVide) ...[
                      const SizedBox(width: Espace.m),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Colors.white54,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Espace.m),
                      MontantAnime(
                        _total,
                        style: textes.labelLarge?.copyWith(fontSize: 17),
                        couleur: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau qui propose de nommer un article vendu souvent.
///
/// Il n'apparaît qu'après plusieurs ventes du même montant : on ne demande
/// jamais rien au commerçant avant qu'il n'y ait une raison.
class _BandeauNommage extends StatelessWidget {
  final LigneArticle article;
  final VoidCallback onPressed;

  const _BandeauNommage({required this.article, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Material(
      color: Couleurs.accentClair,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Espace.l, vertical: Espace.m),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  size: 20, color: Couleurs.accent),
              const SizedBox(width: Espace.m),
              Expanded(
                child: Text(
                  'Tu vends souvent à ${Montant(article.prixCentimes).enFrancs}. '
                  "C'est quoi ?",
                  style: textes.titleMedium,
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Couleurs.encreDouce),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pavé numérique pour la saisie d'un montant libre.
///
/// Gros chiffres, pas de clavier système : la saisie d'un montant est le seul
/// endroit où l'on tape, et elle doit rester rapide debout.
class _EnTete extends StatelessWidget {
  final Montant total;
  final int nombreArticles;

  const _EnTete({required this.total, required this.nombreArticles});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Espace.l, Espace.m, Espace.l, Espace.l),
      decoration: const BoxDecoration(
        color: Couleurs.surface,
        border: Border(bottom: BorderSide(color: Couleurs.bordure)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Espace.m, vertical: 6),
                decoration: BoxDecoration(
                  color: Couleurs.primaireClair,
                  borderRadius: BorderRadius.circular(Rayon.rond),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Couleurs.primaireVif,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Espace.s),
                    Text('Caisse ouverte',
                        style: textes.labelSmall
                            ?.copyWith(color: Couleurs.primaire)),
                  ],
                ),
              ),
              const Spacer(),
              // L'état hors-ligne est une information neutre, pas une alarme :
              // c'est le mode de fonctionnement normal.
              const Icon(Icons.cloud_off_rounded,
                  size: 18, color: Couleurs.encreLegere),
              const SizedBox(width: Espace.xs),
              Text('Hors ligne',
                  style:
                      textes.labelSmall?.copyWith(color: Couleurs.encreLegere)),
            ],
          ),
          const SizedBox(height: Espace.l),
          Text('Total à encaisser', style: textes.labelSmall),
          const SizedBox(height: Espace.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MontantAnime(
                total,
                style: textes.displayLarge,
                couleur: total.estNul ? Couleurs.encreLegere : Couleurs.encre,
              ),
              const Spacer(),
              AnimatedOpacity(
                opacity: nombreArticles == 0 ? 0 : 1,
                duration: Duree.rapide,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Espace.s),
                  child: Text(
                    '$nombreArticles article${nombreArticles > 1 ? 's' : ''}',
                    style: textes.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
