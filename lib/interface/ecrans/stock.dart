/// Le stock.
///
/// Aucun inventaire à saisir : la liste ne contient que les articles dont le
/// commerçant a lui-même décidé de suivre la quantité, un par un. Tant qu'il
/// n'a rien déclaré, l'écran ne montre rien — et l'application encaisse
/// quand même.
///
/// Trois gestes seulement, parce qu'il n'y en a que trois dans la vraie vie :
/// j'ai reçu, j'ai compté, j'ai perdu.
library;

import 'package:flutter/material.dart';

import '../../domaine/montant.dart';
import '../../domaine/references.dart';
import '../../donnees/base.dart';
import '../../donnees/depot.dart';
import '../composants/pave_numerique.dart';
import '../theme/palette.dart';

class EcranStock extends StatefulWidget {
  final Depot depot;

  const EcranStock({super.key, required this.depot});

  @override
  State<EcranStock> createState() => EcranStockState();
}

class EcranStockState extends State<EcranStock> {
  List<LigneArticle> _articles = const [];
  List<LigneArticle> _aSuivre = const [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  /// Publique : la coquille de navigation l'appelle à chaque retour, sinon
  /// les ventes faites entre-temps n'apparaîtraient pas.
  Future<void> recharger() async {
    final (articles, aSuivre) = await (
      widget.depot.articlesEnStock(),
      widget.depot.articlesASuivre(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _articles = articles;
      _aSuivre = aSuivre;
      _chargement = false;
    });
  }

  /// Demande une quantité en unités entières.
  ///
  /// Le pavé sert déjà à saisir des montants : ici il compte des sacs et des
  /// bidons. Le geste est le même, le commerçant n'a rien de nouveau à
  /// apprendre.
  Future<Quantite?> _demanderQuantite({
    required String titre,
    required String valider,
    String? indication,
  }) async {
    final saisi = await demanderMontant(
      context,
      titre: titre,
      indication: indication,
      valider: valider,
    );
    if (saisi == null) return null;
    return Quantite.unites(saisi.centimes ~/ 100);
  }

  Future<void> _recevoir(LigneArticle article) async {
    final quantite = await _demanderQuantite(
      titre: 'Reçu — ${article.designation}',
      indication: 'En stock : ${_enUnites(article.stockMilliemes)}',
      valider: 'Ajouter au stock',
    );
    if (quantite == null || quantite.milliemes <= 0) return;

    await widget.depot.entrerStock(article.code, quantite);
    await recharger();
  }

  Future<void> _compter(LigneArticle article) async {
    final quantite = await _demanderQuantite(
      titre: 'Compté — ${article.designation}',
      indication: 'Théorique : ${_enUnites(article.stockMilliemes)}',
      valider: 'Corriger le stock',
    );
    if (quantite == null) return;

    await widget.depot.ajusterStock(article.code, quantite);
    await recharger();
  }

  Future<void> _perdre(LigneArticle article) async {
    final quantite = await _demanderQuantite(
      titre: 'Perdu — ${article.designation}',
      indication: 'Casse, vol, périmé, cadeau',
      valider: 'Retirer du stock',
    );
    if (quantite == null || quantite.milliemes <= 0) return;

    await widget.depot.declarerPerte(article.code, quantite);
    await recharger();
  }

  /// Première déclaration : c'est ici que l'article entre dans le stock.
  Future<void> _commencerLeSuivi(LigneArticle article) async {
    final quantite = await _demanderQuantite(
      titre: 'Combien il te reste de ${article.designation} ?',
      valider: 'Commencer à suivre',
    );
    if (quantite == null) return;

    await widget.depot.ajusterStock(article.code, quantite);
    await recharger();
  }

  Future<void> _refuserLeSuivi(LigneArticle article) async {
    // On repasse en « recette » plutôt qu'en « aucun » : c'est ce qui retire
    // la proposition sans la faire revenir à la vente suivante.
    await widget.depot.definirSuiviStock(article.code, SuiviStock.recette);
    await recharger();
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_articles.isEmpty && _aSuivre.isEmpty) {
      return const _AucunStock();
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: recharger,
        child: ListView(
          padding: const EdgeInsets.all(Espace.l),
          children: [
            for (final article in _aSuivre)
              Padding(
                padding: const EdgeInsets.only(bottom: Espace.m),
                child: _Proposition(
                  article: article,
                  surAcceptation: () => _commencerLeSuivi(article),
                  surRefus: () => _refuserLeSuivi(article),
                ),
              ),

            if (_articles.isNotEmpty) ...[
              if (_aSuivre.isNotEmpty) const SizedBox(height: Espace.m),
              Text('Ce que je suis', style: textes.titleLarge),
              const SizedBox(height: 2),
              Text('Les plus bas en premier', style: textes.labelSmall),
              const SizedBox(height: Espace.m),
              for (final article in _articles)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espace.m),
                  child: _CarteStock(
                    article: article,
                    surReception: () => _recevoir(article),
                    surComptage: () => _compter(article),
                    surPerte: () => _perdre(article),
                  ),
                ),
            ],
            const SizedBox(height: Espace.xxl),
          ],
        ),
      ),
    );
  }
}

/// Affiche une quantité en millièmes comme un commerçant la dit.
String _enUnites(int? milliemes) {
  if (milliemes == null) return '—';
  final quantite = Quantite(milliemes);
  return quantite.toString();
}

class _AucunStock extends StatelessWidget {
  const _AucunStock();

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 56, color: Couleurs.encreLegere),
            const SizedBox(height: Espace.l),
            Text('Rien à compter pour le moment',
                style: textes.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Espace.s),
            Text(
              "Vends d'abord. Quand un article reviendra souvent, je te "
              'proposerai de compter ce qu'
              "'il t'en reste — et je le suivrai tout seul ensuite.",
              style: textes.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// La proposition de commencer à suivre un article.
class _Proposition extends StatelessWidget {
  final LigneArticle article;
  final VoidCallback surAcceptation;
  final VoidCallback surRefus;

  const _Proposition({
    required this.article,
    required this.surAcceptation,
    required this.surRefus,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Espace.l),
      decoration: BoxDecoration(
        color: Couleurs.primaireClair,
        borderRadius: BorderRadius.circular(Rayon.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu vends souvent ${article.designation}.',
            style: textes.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            "Dis-moi combien il t'en reste, et je compte à ta place à chaque "
            'vente.',
            style: textes.bodyMedium,
          ),
          const SizedBox(height: Espace.m),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: surAcceptation,
                  style: FilledButton.styleFrom(
                    backgroundColor: Couleurs.primaire,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('Compter'),
                ),
              ),
              const SizedBox(width: Espace.m),
              TextButton(
                onPressed: surRefus,
                style: TextButton.styleFrom(
                  foregroundColor: Couleurs.encreDouce,
                  // Hauteur imposée, largeur libre : ce bouton n'est pas
                  // étiré, et Size.fromHeight lui donnerait une largeur
                  // infinie dans une rangée.
                  minimumSize: const Size(0, 46),
                ),
                child: const Text('Pas celui-là'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarteStock extends StatelessWidget {
  final LigneArticle article;
  final VoidCallback surReception;
  final VoidCallback surComptage;
  final VoidCallback surPerte;

  const _CarteStock({
    required this.article,
    required this.surReception,
    required this.surComptage,
    required this.surPerte,
  });

  bool get _enRupture => (article.stockMilliemes ?? 0) <= 0;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Espace.l),
      decoration: BoxDecoration(
        color: Couleurs.surface,
        borderRadius: BorderRadius.circular(Rayon.m),
        border: Border.all(
          color: _enRupture ? Couleurs.alerte : Couleurs.bordure,
          width: _enRupture ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(article.designation, style: textes.titleLarge),
              ),
              const SizedBox(width: Espace.s),
              Text(
                _enRupture ? 'Rupture' : _enUnites(article.stockMilliemes),
                style: textes.headlineMedium?.copyWith(
                  color: _enRupture ? Couleurs.alerte : Couleurs.encre,
                  fontSize: _enRupture ? 18 : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.l),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: surReception,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Reçu'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Couleurs.primaire,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
              const SizedBox(width: Espace.s),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: surComptage,
                  icon: const Icon(Icons.checklist_rounded, size: 18),
                  label: const Text('Compté'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
              const SizedBox(width: Espace.s),
              IconButton(
                onPressed: surPerte,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: Couleurs.alerte,
                tooltip: 'Perdu',
                style: IconButton.styleFrom(
                  minimumSize: const Size(46, 46),
                  side: const BorderSide(color: Couleurs.bordure),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
