/// Écran de vente — le cœur de l'application.
///
/// Tout est conçu pour qu'une vente s'enregistre en moins de dix secondes :
/// le total est toujours visible, les articles sont des cibles larges, et le
/// bouton d'encaissement ne bouge jamais de place.
library;

import 'package:flutter/material.dart';

import '../../domaine/montant.dart';
import '../composants/montant_anime.dart';
import '../composants/tuile_produit.dart';
import '../theme/palette.dart';
import 'feuille_paiement.dart';

/// Un article du catalogue, tel qu'affiché à la caisse.
class ArticleCaisse {
  final String nom;
  final Montant prix;
  const ArticleCaisse(this.nom, this.prix);
}

class EcranVente extends StatefulWidget {
  const EcranVente({super.key});

  @override
  State<EcranVente> createState() => _EcranVenteState();
}

class _EcranVenteState extends State<EcranVente> {
  /// Catalogue de démonstration.
  ///
  /// En vrai, il se construit tout seul au fil des ventes : on ne demande
  /// jamais au commerçant de saisir un inventaire pour démarrer.
  static final _catalogue = <ArticleCaisse>[
    ArticleCaisse('Riz 1 kg', Montant.depuisDecimal(650)),
    ArticleCaisse('Huile 1 L', Montant.depuisDecimal(1200)),
    ArticleCaisse('Sucre 1 kg', Montant.depuisDecimal(750)),
    ArticleCaisse('Savon', Montant.depuisDecimal(300)),
    ArticleCaisse('Lait concentré', Montant.depuisDecimal(500)),
    ArticleCaisse('Thé Lipton', Montant.depuisDecimal(1500)),
    ArticleCaisse('Pain', Montant.depuisDecimal(200)),
    ArticleCaisse('Eau 1,5 L', Montant.depuisDecimal(400)),
  ];

  final _panier = <String, int>{};

  Montant get _total {
    var total = const Montant.zero();
    for (final entree in _panier.entries) {
      final article = _catalogue.firstWhere((a) => a.nom == entree.key);
      total = total +
          article.prix.multiplieParQuantite(Quantite.unites(entree.value));
    }
    return total;
  }

  int get _nombreArticles =>
      _panier.values.fold(0, (somme, quantite) => somme + quantite);

  void _ajouter(ArticleCaisse article) {
    setState(() => _panier[article.nom] = (_panier[article.nom] ?? 0) + 1);
  }

  void _viderPanier() => setState(_panier.clear);

  void _encaisser() {
    if (_panier.isEmpty) return;
    FeuillePaiement.presenter(
      context,
      total: _total,
      surPaiementTermine: _viderPanier,
    );
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

            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                    Espace.l, Espace.l, Espace.l, Espace.xxxl + Espace.xl),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: Espace.m,
                  crossAxisSpacing: Espace.m,
                  // Tuiles légèrement plus larges que hautes : on en voit
                  // davantage à l'écran, et le commerçant fait moins défiler.
                  // La proportion changera quand les articles porteront une
                  // photo, qui occupera la place aujourd'hui vide.
                  childAspectRatio: 1.15,
                ),
                itemCount: _catalogue.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return TuileAction(
                      icone: Icons.dialpad_rounded,
                      libelle: 'Montant\nlibre',
                      onPressed: () {},
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
                    nom: article.nom,
                    prix: article.prix,
                    quantiteAuPanier: _panier[article.nom] ?? 0,
                    onPressed: () => _ajouter(article),
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
                        color: panierVide
                            ? Couleurs.encreLegere
                            : Colors.white,
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
              Icon(Icons.cloud_off_rounded,
                  size: 18, color: Couleurs.encreLegere),
              const SizedBox(width: Espace.xs),
              Text('Hors ligne',
                  style: textes.labelSmall
                      ?.copyWith(color: Couleurs.encreLegere)),
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
