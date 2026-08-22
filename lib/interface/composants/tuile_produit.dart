/// Tuile d'un article sur l'écran de vente.
///
/// Gros bouton, nom court, prix lisible, et une couleur stable dérivée du nom
/// pour que l'article se reconnaisse sans savoir lire. Quand l'article a une
/// photo, elle prend toute la place — c'est le repère le plus rapide.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domaine/montant.dart';
import '../../domaine/texte.dart';
import '../theme/palette.dart';

class TuileProduit extends StatefulWidget {
  final String nom;
  final Montant prix;

  /// Nombre d'unités déjà mises au panier. Zéro masque le badge.
  final int quantiteAuPanier;

  /// Vrai quand le prix affiché a été négocié pour cette vente.
  final bool prixNegocie;

  final VoidCallback onPressed;

  /// Appui long : changer le prix pour cette vente seulement.
  final VoidCallback? onLongPress;

  /// Retire une unité du panier.
  ///
  /// C'est la pastille de quantité qui porte ce geste : la tuile ajoute, la
  /// pastille enlève. Sans lui, un appui de trop obligeait à vider tout le
  /// panier et à recommencer devant le client.
  final VoidCallback? onRetirer;

  const TuileProduit({
    super.key,
    required this.nom,
    required this.prix,
    required this.onPressed,
    this.quantiteAuPanier = 0,
    this.prixNegocie = false,
    this.onLongPress,
    this.onRetirer,
  });

  @override
  State<TuileProduit> createState() => _TuileProduitState();
}

class _TuileProduitState extends State<TuileProduit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: Duree.eclair,
    reverseDuration: Duree.rapide,
  );

  late final Animation<double> _echelle = Tween<double>(
    begin: 1.0,
    end: 0.94,
  ).animate(CurvedAnimation(parent: _controleur, curve: Courbe.sortie));

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _appuyer() {
    HapticFeedback.selectionClick();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final teinte = Couleurs.tuilePour(widget.nom);
    final textes = Theme.of(context).textTheme;
    final auPanier = widget.quantiteAuPanier > 0;

    // La tuile est peinte, pas construite avec des boutons : sans étiquette
    // explicite, elle n'existe pas pour un lecteur d'écran, et le commerçant
    // qui voit mal n'a plus de caisse du tout. L'étiquette porte le nom
    // entier, pas sa version rognée.
    return Semantics(
      button: true,
      label: widget.quantiteAuPanier > 0
          ? '${widget.nom}, ${widget.prix.enFrancs}, '
              '${widget.quantiteAuPanier} au panier'
          : '${widget.nom}, ${widget.prix.enFrancs}',
      child: GestureDetector(
        onTapDown: (_) => _controleur.forward(),
        onTapUp: (_) => _controleur.reverse(),
        onTapCancel: () => _controleur.reverse(),
        onTap: _appuyer,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: ScaleTransition(
        scale: _echelle,
        child: AnimatedContainer(
          duration: Duree.rapide,
          curve: Courbe.sortie,
          decoration: BoxDecoration(
            color: teinte.withValues(alpha: auPanier ? 0.16 : 0.09),
            borderRadius: BorderRadius.circular(Rayon.m),
            border: Border.all(
              color: auPanier ? teinte : teinte.withValues(alpha: 0.18),
              width: auPanier ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(Espace.m),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Pastille de repère : première lettre, couleur stable.
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: teinte,
                      borderRadius: BorderRadius.circular(Rayon.s),
                    ),
                    child: Text(
                      widget.nom.characters.first.toUpperCase(),
                      style: textes.titleLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: Espace.s),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Rogné par le milieu, pas par la fin. « Sac de riz
                      // 25 kg qualité supérieure » et « … qualité normale »
                      // donnaient deux tuiles identiques : c'est la fin du
                      // nom qui les distingue, et c'est elle qu'on coupait.
                      Text(
                        nomAbrege(widget.nom),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textes.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (widget.prixNegocie) ...[
                            const Icon(Icons.edit_rounded,
                                size: 13, color: Couleurs.accent),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              widget.prix.enFrancs,
                              overflow: TextOverflow.ellipsis,
                              style: textes.labelLarge?.copyWith(
                                color: widget.prixNegocie
                                    ? Couleurs.accent
                                    : teinte,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

              // Badge de quantité, qui apparaît en rebondissant. C'est aussi
              // le bouton pour retirer une unité : la tuile ajoute, la
              // pastille enlève.
              // Sans décalage négatif : la pile rogne ses enfants, et la
              // pastille sortirait amputée. La zone tactile déborde par le
              // rembourrage, pas par la position.
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedScale(
                  scale: auPanier ? 1 : 0,
                  duration: Duree.moyenne,
                  curve: Courbe.rebond,
                  child: GestureDetector(
                    onTap: widget.onRetirer == null
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            widget.onRetirer!();
                          },
                    // La cible tactile déborde la pastille : un doigt vise mal
                    // un rond de vingt-six pixels.
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(left: 5, right: 9),
                        decoration: BoxDecoration(
                          color: teinte,
                          borderRadius: BorderRadius.circular(Rayon.rond),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onRetirer != null)
                              const Icon(Icons.remove_rounded,
                                  size: 15, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.quantiteAuPanier}',
                              style: textes.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tuile d'action : montant libre, scan, client.
class TuileAction extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final VoidCallback onPressed;

  const TuileAction({
    super.key,
    required this.icone,
    required this.libelle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    return Material(
      color: couleurs.surface,
      borderRadius: BorderRadius.circular(Rayon.m),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Rayon.m),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rayon.m),
            border: Border.all(
              color: couleurs.outlineVariant,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(Espace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icone, size: 28, color: Couleurs.encreDouce),
              Text(
                libelle,
                maxLines: 2,
                style: textes.titleMedium?.copyWith(color: Couleurs.encreDouce),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
