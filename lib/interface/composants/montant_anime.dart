/// Affichage animé d'un montant.
///
/// Chaque chiffre qui change défile verticalement, les autres restent en
/// place. C'est la signature visuelle de la caisse : le total réagit, et le
/// commerçant voit que sa saisie a été prise en compte sans avoir à lire.
///
/// L'animation ne porte que sur `transform` et `opacity`, les deux seules
/// propriétés qui restent fluides sur un téléphone d'entrée de gamme.
library;

import 'package:flutter/material.dart';

import '../../domaine/montant.dart';
import '../theme/palette.dart';

class MontantAnime extends StatelessWidget {
  final Montant montant;
  final TextStyle? style;
  final Color? couleur;

  /// Affiche le suffixe « F ».
  final bool avecDevise;

  const MontantAnime(
    this.montant, {
    super.key,
    this.style,
    this.couleur,
    this.avecDevise = true,
  });

  @override
  Widget build(BuildContext context) {
    final styleFinal = (style ?? Theme.of(context).textTheme.displayMedium!)
        .copyWith(color: couleur);

    var texte = montant.enFrancs;
    if (!avecDevise) texte = texte.replaceAll(' F', '');

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (var i = 0; i < texte.length; i++)
          _Caractere(
            caractere: texte[i],
            // La position sert de clé : un chiffre qui change à la même
            // place défile, au lieu d'être reconstruit.
            position: texte.length - i,
            style: styleFinal,
          ),
      ],
    );
  }
}

class _Caractere extends StatelessWidget {
  final String caractere;
  final int position;
  final TextStyle style;

  const _Caractere({
    required this.caractere,
    required this.position,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final estChiffre = RegExp(r'[0-9]').hasMatch(caractere);

    if (!estChiffre) {
      // Espaces, devise : pas d'animation, ils ne « changent » pas.
      return Text(caractere, style: style);
    }

    return AnimatedSwitcher(
      duration: Duree.moyenne,
      switchInCurve: Courbe.sortie,
      switchOutCurve: Courbe.entree,
      transitionBuilder: (enfant, animation) {
        final entrant = enfant.key == ValueKey('$position-$caractere');
        final glissement = Tween<Offset>(
          begin: Offset(0, entrant ? 0.7 : -0.7),
          end: Offset.zero,
        ).animate(animation);

        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(position: glissement, child: enfant),
          ),
        );
      },
      layoutBuilder: (courant, precedents) => Stack(
        alignment: Alignment.center,
        children: [...precedents, ?courant],
      ),
      child: Text(
        caractere,
        key: ValueKey('$position-$caractere'),
        style: style,
      ),
    );
  }
}

/// Pastille de montant, pour les totaux secondaires.
class PastilleMontant extends StatelessWidget {
  final String libelle;
  final Montant montant;
  final Color teinte;
  final IconData icone;

  const PastilleMontant({
    super.key,
    required this.libelle,
    required this.montant,
    required this.teinte,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Espace.m, vertical: Espace.s + 2),
      decoration: BoxDecoration(
        color: teinte.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Rayon.s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 16, color: teinte),
          const SizedBox(width: Espace.s),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(libelle,
                  style: textes.labelSmall?.copyWith(color: teinte)),
              const SizedBox(height: 1),
              MontantAnime(
                montant,
                style: textes.titleMedium,
                couleur: teinte,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
