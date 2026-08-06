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

  /// Ce prix recouvre plusieurs produits. La réponse porte alors leurs noms :
  /// on les crée sur-le-champ plutôt que de laisser le commerçant avec un
  /// fourre-tout.
  melange,
}

/// La réponse, avec le ou les noms donnés.
class ResultatNommage {
  final ReponseNommage reponse;

  /// Un seul nom pour [ReponseNommage.nomme], plusieurs pour
  /// [ReponseNommage.melange], aucun pour « plus tard ».
  final List<String> noms;

  const ResultatNommage(this.reponse, [this.noms = const []]);

  String? get nom => noms.isEmpty ? null : noms.first;
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

  /// Vrai une fois que le commerçant a dit qu'il vend plusieurs choses à ce
  /// prix : la feuille passe alors en mode liste.
  bool _plusieurs = false;

  /// Les noms déjà ajoutés, en mode liste.
  final _noms = <String>[];

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  /// Combien de noms partiront à la création, en comptant celui en cours.
  int get _aCreer =>
      _noms.length + (_controleur.text.trim().isEmpty ? 0 : 1);

  bool get _validable => _plusieurs
      ? _aCreer >= 2
      : _controleur.text.trim().isNotEmpty;

  String get _libelleCreation =>
      _aCreer < 2 ? 'Ajoute au moins deux noms' : 'Créer ces $_aCreer articles';

  void _ajouterNom() {
    final nom = _controleur.text.trim();
    if (nom.isEmpty || _noms.contains(nom)) return;
    setState(() {
      _noms.add(nom);
      _controleur.clear();
    });
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
            _plusieurs
                ? "Donne le nom de chacune. Je les crée toutes au même prix, "
                    "et tu les vendras d'un appui."
                : "Donne-lui un nom pour le retrouver d'un geste la prochaine "
                    'fois.',
            textAlign: TextAlign.center,
            style: textes.bodyMedium,
          ),
          if (_plusieurs && _noms.isNotEmpty) ...[
            const SizedBox(height: Espace.m),
            Wrap(
              spacing: Espace.s,
              runSpacing: Espace.s,
              children: [
                for (final nom in _noms)
                  Chip(
                    label: Text(nom),
                    onDeleted: () => setState(() => _noms.remove(nom)),
                    backgroundColor: Couleurs.primaireClair,
                    side: BorderSide.none,
                  ),
              ],
            ),
          ],
          const SizedBox(height: Espace.l),
          TextField(
            controller: _controleur,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction:
                _plusieurs ? TextInputAction.next : TextInputAction.done,
            style: textes.titleLarge,
            onChanged: (_) => setState(() {}),
            onSubmitted: (valeur) {
              if (valeur.trim().isEmpty) return;
              if (_plusieurs) {
                _ajouterNom();
                return;
              }
              Navigator.of(context)
                  .pop(ResultatNommage(ReponseNommage.nomme, [valeur.trim()]));
            },
            decoration: InputDecoration(
              hintText: _plusieurs
                  ? 'Ajoute un nom, puis un autre…'
                  : 'Sachet d\'eau, pain, savon…',
              suffixIcon: _plusieurs
                  ? IconButton(
                      onPressed: vide ? null : _ajouterNom,
                      icon: const Icon(Icons.add_circle_rounded),
                      color: Couleurs.primaire,
                      tooltip: 'Ajouter',
                    )
                  : null,
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
            onPressed: _validable
                ? () {
                    if (!_plusieurs) {
                      Navigator.of(context).pop(ResultatNommage(
                          ReponseNommage.nomme, [_controleur.text.trim()]));
                      return;
                    }
                    // Le dernier nom tapé compte même sans appuyer sur « + ».
                    _ajouterNom();
                    Navigator.of(context).pop(
                        ResultatNommage(ReponseNommage.melange, [..._noms]));
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
            ),
            child: Text(
              _plusieurs ? _libelleCreation : 'Enregistrer',
              style: textes.labelLarge?.copyWith(
                fontSize: 17,
                color: _validable ? Colors.white : Couleurs.encreLegere,
              ),
            ),
          ),
          const SizedBox(height: Espace.s),
          // La troisième réponse, celle qui manquait. Un article né d'un
          // montant libre est reconnu à son prix : si deux produits partagent
          // ce prix, il n'y a aucun nom juste à donner, et insister ferait
          // fabriquer un faux article dont le stock mentirait.
          OutlinedButton(
            onPressed: () => setState(() => _plusieurs = true),
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
