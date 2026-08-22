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
  List<LigneArticle> _sansSuivi = const [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  /// Publique : la coquille de navigation l'appelle à chaque retour, sinon
  /// les ventes faites entre-temps n'apparaîtraient pas.
  Future<void> recharger() async {
    final (articles, aSuivre, sansSuivi) = await (
      widget.depot.articlesEnStock(),
      widget.depot.articlesASuivre(),
      widget.depot.articlesSansSuivi(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _articles = articles;
      _aSuivre = aSuivre;
      // Les articles déjà mis en avant par une proposition ne sont pas
      // répétés plus bas.
      final proposes = aSuivre.map((a) => a.code).toSet();
      _sansSuivi = sansSuivi.where((a) => !proposes.contains(a.code)).toList();
      _chargement = false;
    });
  }

  /// Crée un article à la main, pour qui veut saisir son stock d'avance.
  Future<void> _creerArticle() async {
    final saisie = await FicheArticle.creer(context);
    if (saisie == null) return;

    await widget.depot.creerArticle(
      designation: saisie.nom,
      prix: saisie.prix,
      stock: saisie.stock,
    );
    await recharger();
  }

  /// Donne ou corrige le nom d'un article, à tout moment.
  ///
  /// L'application ne peut pas deviner ce nom : un montant libre ne porte
  /// aucune information. Elle finit par le demander d'elle-même, mais le
  /// commerçant ne devrait jamais avoir à attendre qu'on le lui demande.
  Future<void> _renommer(LigneArticle article) async {
    final saisie = await FicheArticle.modifier(context, article);
    if (saisie == null) return;

    if (saisie.retirer) {
      await widget.depot.retirerArticle(article.code);
      await recharger();
      _annoncerRetrait(article);
      return;
    }

    if (saisie.nom != article.designation) {
      await widget.depot.nommerArticle(article.code, saisie.nom);
    }
    if (saisie.prix.centimes != article.prixCentimes) {
      await widget.depot.modifierPrix(article.code, saisie.prix);
    }
    await recharger();
  }

  /// Dit ce qui vient d'être retiré, et propose de revenir en arrière.
  ///
  /// Un retrait est réversible : le dire tout de suite est ce qui permet
  /// d'oser le geste.
  void _annoncerRetrait(LigneArticle article) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${article.designation} retiré du catalogue'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Remettre',
          onPressed: () async {
            await widget.depot
                .retirerArticle(article.code, retire: false);
            await recharger();
          },
        ),
      ));
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

  /// « Plus tard » : la proposition disparaît, l'article reste.
  ///
  /// Il descend simplement dans la liste du bas, où le suivi peut démarrer
  /// d'un bouton. Un appui par erreur ne coûte rien, et un changement d'avis
  /// non plus.
  Future<void> _plusTard(LigneArticle article) async {
    await widget.depot.reporterPropositionSuivi(article.code);
    await recharger();

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${article.designation} reste dans la liste du bas.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => _commencerLeSuivi(article),
        ),
      ));
  }

  /// Arrête de suivre un article sans perdre la possibilité d'y revenir.
  Future<void> _arreterLeSuivi(LigneArticle article) async {
    await widget.depot.definirSuiviStock(article.code, SuiviStock.aucun);
    await recharger();
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final vide = _articles.isEmpty && _aSuivre.isEmpty && _sansSuivi.isEmpty;

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Toujours accessible, même quand rien n'a encore été vendu : le
        // commerçant qui veut préparer son catalogue d'avance ne doit pas
        // avoir à attendre que l'application le lui propose.
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _creerArticle,
          backgroundColor: Couleurs.primaire,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Article'),
        ),
        body: vide
            ? const _AucunStock()
            : RefreshIndicator(
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
                          surRefus: () => _plusTard(article),
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
                            surFiche: () => _renommer(article),
                            surArret: () => _arreterLeSuivi(article),
                          ),
                        ),
                    ],

                    // Le filet de sécurité : quoi qu'il ait répondu aux
                    // propositions, le commerçant retrouve ici tous ses
                    // articles et peut en démarrer le suivi. Rien n'est
                    // jamais définitif.
                    if (_sansSuivi.isNotEmpty) ...[
                      const SizedBox(height: Espace.xl),
                      Text('Pas encore suivis', style: textes.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Appuie sur un article pour compter ce qu\'il t\'en '
                        'reste',
                        style: textes.labelSmall,
                      ),
                      const SizedBox(height: Espace.m),
                      Container(
                        decoration: BoxDecoration(
                          color: Couleurs.surface,
                          borderRadius: BorderRadius.circular(Rayon.m),
                          border: Border.all(color: Couleurs.bordure),
                        ),
                        child: Column(
                          children: [
                            for (final article in _sansSuivi)
                              _LigneSansSuivi(
                                article: article,
                                surSuivi: () => _commencerLeSuivi(article),
                                surFiche: () => _renommer(article),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 88),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Une ligne de la liste « pas encore suivis ».
class _LigneSansSuivi extends StatelessWidget {
  final LigneArticle article;
  final VoidCallback surSuivi;
  final VoidCallback surFiche;

  const _LigneSansSuivi({
    required this.article,
    required this.surSuivi,
    required this.surFiche,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return InkWell(
      onTap: surSuivi,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Espace.l, vertical: Espace.s),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.designation,
                    style: textes.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    Montant(article.prixCentimes).enFrancs,
                    style: textes.labelSmall,
                  ),
                ],
              ),
            ),
            // Un article encore sans nom se signale : c'est le seul moment
            // où l'application a besoin du commerçant pour avancer.
            if (!article.nomme)
              IconButton(
                onPressed: surFiche,
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: Couleurs.accent,
                tooltip: 'Donner un nom',
              )
            else
              IconButton(
                onPressed: surFiche,
                icon: const Icon(Icons.tune_rounded, size: 20),
                color: Couleurs.encreLegere,
                tooltip: 'Modifier',
              ),
            TextButton(onPressed: surSuivi, child: const Text('Compter')),
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
            'vente. Tu pourras arrêter quand tu veux.',
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
                child: const Text('Plus tard'),
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
  final VoidCallback surFiche;
  final VoidCallback surArret;

  const _CarteStock({
    required this.article,
    required this.surReception,
    required this.surComptage,
    required this.surPerte,
    required this.surFiche,
    required this.surArret,
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
                child: GestureDetector(
                  onTap: surFiche,
                  child: Text(article.designation, style: textes.titleLarge),
                ),
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
              PopupMenuButton<void>(
                tooltip: 'Autres actions',
                itemBuilder: (_) => [
                  PopupMenuItem(
                    onTap: surFiche,
                    child: const Text('Nom et prix'),
                  ),
                  PopupMenuItem(
                    onTap: surArret,
                    child: const Text('Arrêter de suivre'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ce que le commerçant a saisi dans la fiche d'un article.
class SaisieArticle {
  final String nom;
  final Montant prix;

  /// Stock de départ. Nul quand on ne fait que renommer.
  final Quantite? stock;

  /// Vrai quand le commerçant demande à sortir l'article du catalogue.
  ///
  /// Le nom et le prix sont alors sans objet : c'est le seul cas où la fiche
  /// rend autre chose qu'une correction.
  final bool retirer;

  const SaisieArticle({
    required this.nom,
    required this.prix,
    this.stock,
    this.retirer = false,
  });

  const SaisieArticle.retrait()
      : nom = '',
        prix = const Montant.zero(),
        stock = null,
        retirer = true;
}

/// La fiche d'un article : son nom, son prix, et sa quantité de départ.
///
/// Sert à deux choses opposées et pourtant identiques : créer un article
/// d'avance pour qui veut préparer son catalogue, et corriger celui qui s'est
/// créé tout seul à la vente.
class FicheArticle extends StatefulWidget {
  final String titre;
  final String? nom;
  final Montant? prix;
  final bool avecStock;

  /// Vrai quand l'article existe déjà et peut donc être retiré.
  final bool retirable;

  const FicheArticle({
    super.key,
    required this.titre,
    this.nom,
    this.prix,
    this.avecStock = false,
    this.retirable = false,
  });

  static Future<SaisieArticle?> creer(BuildContext context) =>
      _presenter(context,
          const FicheArticle(titre: 'Nouvel article', avecStock: true));

  static Future<SaisieArticle?> modifier(
    BuildContext context,
    LigneArticle article,
  ) =>
      _presenter(
        context,
        FicheArticle(
          titre: "Fiche de l'article",
          nom: article.nomme ? article.designation : null,
          prix: Montant(article.prixCentimes),
          // Un article créé par erreur restait à vie : une faute de frappe
          // se corrigeait, jamais ne s'effaçait.
          retirable: true,
        ),
      );

  static Future<SaisieArticle?> _presenter(
          BuildContext context, FicheArticle fiche) =>
      showModalBottomSheet<SaisieArticle>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => fiche,
      );

  @override
  State<FicheArticle> createState() => _FicheArticleState();
}

class _FicheArticleState extends State<FicheArticle> {
  late final _nom = TextEditingController(text: widget.nom ?? '');
  late final _prix = TextEditingController(
      text: widget.prix == null ? '' : '${widget.prix!.centimes ~/ 100}');
  late final _stock = TextEditingController();

  @override
  void dispose() {
    _nom.dispose();
    _prix.dispose();
    _stock.dispose();
    super.dispose();
  }

  Montant get _prixSaisi =>
      Montant.depuisDecimal(int.tryParse(_prix.text.trim()) ?? 0);

  bool get _complet => _nom.text.trim().isNotEmpty && _prixSaisi.estPositif;

  void _valider() {
    if (!_complet) return;
    final stock = int.tryParse(_stock.text.trim());

    Navigator.of(context).pop(SaisieArticle(
      nom: _nom.text.trim(),
      prix: _prixSaisi,
      stock: stock == null ? null : Quantite.unites(stock),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: Espace.l,
        right: Espace.l,
        bottom: Espace.l + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text(widget.titre, style: textes.titleLarge)),
          const SizedBox(height: Espace.l),
          TextField(
            controller: _nom,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: "Nom de l'article",
              hintText: 'Riz 1 kg',
              prefixIcon: Icon(Icons.label_outline_rounded),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: _prix,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Prix de vente',
              suffixText: 'F',
              prefixIcon: Icon(Icons.sell_outlined),
            ),
          ),
          if (widget.avecStock) ...[
            const SizedBox(height: Espace.m),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantité en stock (facultatif)',
                hintText: 'Laisse vide si tu ne comptes pas',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
          ],
          const SizedBox(height: Espace.l),
          FilledButton(
            onPressed: _complet ? _valider : null,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Enregistrer'),
          ),
          if (widget.retirable) ...[
            const SizedBox(height: Espace.s),
            TextButton.icon(
              onPressed: _retirer,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
              label: const Text('Retirer du catalogue'),
              style: TextButton.styleFrom(
                foregroundColor: Couleurs.alerte,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Sort l'article de la caisse, après confirmation.
  ///
  /// La confirmation dit ce qui ne bougera pas : les ventes déjà faites
  /// restent comptées. Sans ça, le commerçant hésitera à retirer quoi que ce
  /// soit de peur de fausser sa journée.
  Future<void> _retirer() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Retirer du catalogue ?'),
        content: const Text(
          "Il disparaît de la caisse et du stock. Les ventes déjà faites "
          "restent comptées — ta journée ne bouge pas.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Couleurs.alerte),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    Navigator.of(context).pop(const SaisieArticle.retrait());
  }
}
