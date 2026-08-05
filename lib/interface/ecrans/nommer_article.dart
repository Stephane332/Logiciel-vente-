/// Nommage d'un article que le commerçant vend souvent.
///
/// C'est le seul moment où l'application demande quelque chose au commerçant,
/// et elle ne le fait qu'après plusieurs ventes du même montant — quand il y
/// a une raison. On ne lui demande jamais de saisir un inventaire.
library;

import 'package:flutter/material.dart';

import '../../domaine/montant.dart';
import '../composants/montant_anime.dart';
import '../theme/palette.dart';

/// Ce que le commerçant répond quand on lui propose de nommer un article.
enum ReponseNommage {
  /// Il donne un nom. La réponse porte alors le nom saisi.
  nomme,

  /// Plus tard. La question reviendra.
  plusTard,

  /// Ce prix recouvre plusieurs produits différents : il n'y a pas de nom à
  /// donner, et il ne faut plus le demander.
  melange,
}

/// La réponse, avec le nom quand il y en a un.
class ResultatNommage {
  final ReponseNommage reponse;
  final String? nom;

  const ResultatNommage(this.reponse, [this.nom]);
}

class NommerArticle extends StatefulWidget {
  final Montant prix;
  final int nombreVentes;

  const NommerArticle({
    super.key,
    required this.prix,
    required this.nombreVentes,
  });

  /// Demande un nom. Renvoie `null` si la feuille est refermée sans répondre.
  static Future<ResultatNommage?> demander(
    BuildContext context, {
    required Montant prix,
    required int nombreVentes,
  }) =>
      showModalBottomSheet<ResultatNommage>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            NommerArticle(prix: prix, nombreVentes: nombreVentes),
      );

  @override
  State<NommerArticle> createState() => _NommerArticleState();
}

class _NommerArticleState extends State<NommerArticle> {
  final _controleur = TextEditingController();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final vide = _controleur.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: Espace.l,
        right: Espace.l,
        bottom: Espace.l + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Text('Tu as vendu ${widget.nombreVentes} fois',
                    style: textes.labelSmall),
                const SizedBox(height: Espace.xs),
                MontantAnime(widget.prix, style: textes.displayMedium),
              ],
            ),
          ),
          const SizedBox(height: Espace.l),
          Text(
            "Donne-lui un nom pour le retrouver d'un geste la prochaine fois.",
            textAlign: TextAlign.center,
            style: textes.bodyMedium,
          ),
          const SizedBox(height: Espace.l),
          TextField(
            controller: _controleur,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: textes.titleLarge,
            onChanged: (_) => setState(() {}),
            onSubmitted: (valeur) {
              if (valeur.trim().isNotEmpty) {
                Navigator.of(context).pop(
                    ResultatNommage(ReponseNommage.nomme, valeur.trim()));
              }
            },
            decoration: InputDecoration(
              hintText: 'Sachet d\'eau, pain, savon…',
              filled: true,
              fillColor: Couleurs.fond,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: Espace.l, vertical: Espace.m),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Rayon.m),
                borderSide: const BorderSide(color: Couleurs.bordure),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Rayon.m),
                borderSide: const BorderSide(color: Couleurs.bordure),
              ),
            ),
          ),
          const SizedBox(height: Espace.l),
          FilledButton(
            onPressed: vide
                ? null
                : () => Navigator.of(context).pop(ResultatNommage(
                    ReponseNommage.nomme, _controleur.text.trim())),
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
            ),
            child: Text(
              'Enregistrer',
              style: textes.labelLarge?.copyWith(
                fontSize: 17,
                color: vide ? Couleurs.encreLegere : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: Espace.s),
          // La troisième réponse, celle qui manquait. Un article né d'un
          // montant libre est reconnu à son prix : si deux produits partagent
          // ce prix, il n'y a aucun nom juste à donner, et insister ferait
          // fabriquer un faux article dont le stock mentirait.
          OutlinedButton(
            onPressed: () => Navigator.of(context)
                .pop(const ResultatNommage(ReponseNommage.melange)),
            child: const Text('Ce sont plusieurs choses différentes'),
          ),
          const SizedBox(height: Espace.s),
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop(const ResultatNommage(ReponseNommage.plusTard)),
            child: Text('Plus tard',
                style: textes.labelLarge?.copyWith(color: Couleurs.encreDouce)),
          ),
        ],
      ),
    );
  }
}
