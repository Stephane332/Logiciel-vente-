/// Le pavé de saisie d'un montant.
///
/// Un seul pavé pour toute l'application : encaisser une vente, fixer un prix
/// négocié, enregistrer un remboursement. Ce sont trois gestes différents mais
/// une seule mécanique — des grosses touches, pas de virgule, et le montant
/// qui grandit à l'écran pendant qu'on tape.
///
/// Pas de virgule justement : ici on compte en francs entiers. Le centime
/// n'existe pas dans la rue, et une touche de moins c'est une erreur de moins.
library;

import 'package:flutter/material.dart';

import '../../domaine/montant.dart';
import '../theme/palette.dart';
import 'montant_anime.dart';

/// Demande un montant au commerçant et renvoie sa saisie.
///
/// Renvoie `null` s'il referme la feuille sans valider.
///
/// [plafond] borne la saisie — au-delà, la validation se bloque et le montant
/// passe en rouge. C'est le cas du remboursement : on ne peut pas rendre plus
/// qu'on ne doit. Quand il est fourni, un raccourci propose le total d'un
/// geste, parce que solder toute la dette est le cas le plus fréquent.
Future<Montant?> demanderMontant(
  BuildContext context, {
  required String titre,
  String? indication,
  String valider = 'Encaisser',
  Montant? plafond,
  String Function(Montant)? libellePlafond,
}) {
  var saisie = '';

  return showModalBottomSheet<Montant>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (contexte) => StatefulBuilder(
      builder: (contexte, rafraichir) {
        final montant = _montantDe(saisie);
        final excessif = plafond != null && montant.centimes > plafond.centimes;

        return PaveNumerique(
          titre: titre,
          indication: indication,
          montant: montant,
          excessif: excessif,
          valider: valider,
          raccourci: plafond == null
              ? null
              : RaccourciMontant(
                  libelle: libellePlafond?.call(plafond) ?? plafond.enFrancs,
                  onPressed: () => rafraichir(
                      () => saisie = (plafond.centimes ~/ 100).toString()),
                ),
          surTouche: (touche) => rafraichir(() => saisie = _frappe(saisie, touche)),
          surValidation: saisie.isEmpty || excessif
              ? null
              : () => Navigator.of(contexte).pop(montant),
        );
      },
    ),
  );
}

/// Applique une touche à la saisie en cours.
///
/// Isolée pour être testable sans écran : c'est la règle qui décide si le
/// commerçant peut taper ce qu'il vient de taper.
String _frappe(String saisie, String touche) {
  if (touche == toucheEffacement) {
    return saisie.isEmpty ? saisie : saisie.substring(0, saisie.length - 1);
  }
  // Neuf chiffres : au-delà, c'est une faute de frappe, pas une vente.
  if (saisie.length >= 9) return saisie;
  // Un montant ne commence pas par zéro.
  if (saisie.isEmpty && touche == '0') return saisie;
  return saisie + touche;
}

Montant _montantDe(String saisie) => saisie.isEmpty
    ? const Montant.zero()
    : Montant.depuisDecimal(int.parse(saisie));

/// Touche d'effacement, distinguée des chiffres par son libellé.
const toucheEffacement = '<';

/// Le raccourci proposé au-dessus des touches : « tout », le plus souvent.
class RaccourciMontant {
  final String libelle;
  final VoidCallback onPressed;

  const RaccourciMontant({required this.libelle, required this.onPressed});
}

class PaveNumerique extends StatelessWidget {
  final String titre;
  final String? indication;
  final Montant montant;

  /// Vrai quand la saisie dépasse le plafond : le montant vire au rouge et la
  /// validation se coupe.
  final bool excessif;

  /// Ce que fait le bouton de validation. Encaisser n'est pas fixer un prix :
  /// le commerçant doit lire ce qu'il s'apprête à déclencher.
  final String valider;

  final ValueChanged<String> surTouche;
  final VoidCallback? surValidation;

  const PaveNumerique({
    super.key,
    required this.titre,
    required this.indication,
    required this.montant,
    required this.valider,
    required this.surTouche,
    required this.surValidation,
    this.excessif = false,
    this.raccourci,
  });

  final RaccourciMontant? raccourci;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Espace.l,
        right: Espace.l,
        bottom: Espace.l + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titre, style: textes.labelSmall),
          const SizedBox(height: Espace.s),
          MontantAnime(
            montant,
            style: textes.displayMedium,
            couleur: excessif
                ? Couleurs.alerte
                : (montant.estNul ? Couleurs.encreLegere : Couleurs.encre),
          ),
          if (indication != null) ...[
            const SizedBox(height: Espace.xs),
            Text(
              indication!,
              style: textes.labelSmall?.copyWith(
                color: excessif ? Couleurs.alerte : Couleurs.encreDouce,
              ),
            ),
          ],
          if (raccourci != null) ...[
            const SizedBox(height: Espace.m),
            OutlinedButton(
              onPressed: raccourci!.onPressed,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(raccourci!.libelle),
            ),
          ],
          const SizedBox(height: Espace.l),
          for (final rangee in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['00', '0', toucheEffacement],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Espace.s),
              child: Row(
                children: [
                  for (final touche in rangee)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _Touche(
                          libelle: touche,
                          onPressed: () => surTouche(touche),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: Espace.s),
          FilledButton(
            onPressed: surValidation,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
            ),
            child: Text(
              valider,
              style: textes.labelLarge?.copyWith(
                fontSize: 17,
                color: surValidation == null
                    ? Couleurs.encreLegere
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Touche extends StatelessWidget {
  final String libelle;
  final VoidCallback onPressed;

  const _Touche({required this.libelle, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final effacement = libelle == toucheEffacement;

    return Material(
      color: effacement ? Couleurs.alerteClair : Couleurs.fond,
      borderRadius: BorderRadius.circular(Rayon.m),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Rayon.m),
        child: SizedBox(
          height: cibleTactile,
          child: Center(
            child: effacement
                ? const Icon(Icons.backspace_outlined,
                    size: 22, color: Couleurs.alerte)
                : Text(libelle, style: textes.headlineMedium),
          ),
        ),
      ),
    );
  }
}
