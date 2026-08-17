/// Le rapport du soir.
///
/// C'est ce qui crée l'habitude : le patron qui n'est pas au magasin voit son
/// commerce. Le jour où il arrête de payer, il perd ses yeux.
///
/// Rien n'y est décoratif. Chaque bloc répond à une question qu'un commerçant
/// se pose vraiment : combien j'ai encaissé, à qui j'ai fait crédit, qu'est-ce
/// que je dois racheter, et qu'est-ce qui dort sur mon étagère.
library;

import 'package:flutter/material.dart';

import '../../donnees/analyses.dart';
import '../../donnees/depot.dart';
import '../../domaine/montant.dart';
import '../../domaine/periode.dart';
import '../../domaine/rapport_fiscal.dart';
import '../../donnees/documents.dart';
import '../../donnees/rapports.dart';
import '../composants/montant_anime.dart';
import '../composants/partage.dart';
import '../theme/palette.dart';

class EcranRapport extends StatefulWidget {
  final Depot depot;
  final Documents documents;
  final Analyses analyses;

  /// Ouvre les réglages. C'est l'écran du patron : c'est ici qu'on règle sa
  /// boutique, pas au milieu d'une vente.
  final VoidCallback? surReglages;

  /// L'arrêté de caisse : X, Z et A. Nul dans les tests d'écran qui ne
  /// regardent pas la clôture — la section disparaît alors entièrement.
  final Rapports? rapports;

  const EcranRapport({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    this.surReglages,
    this.rapports,
  });

  @override
  State<EcranRapport> createState() => EcranRapportState();
}

class EcranRapportState extends State<EcranRapport> {
  RapportDuJour? _rapport;
  List<AlerteStock> _alertes = const [];
  List<ArticleEndormi> _endormis = const [];
  List<PerformanceArticle> _meilleures = const [];
  List<PartDeVendeur> _parVendeur = const [];
  Montant _perdu = const Montant.zero();

  /// La tranche de temps regardée. La journée en cours par défaut : c'est la
  /// question qu'on se pose neuf fois sur dix.
  Periode _periode = Periode.jour;

  /// Ce qui apparaît sous « Ce qui dort ». Au-delà, le commerçant ne lit plus.
  static const _plafondEndormis = 5;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  /// Relit tous les chiffres.
  ///
  /// Publique : la coquille de navigation l'appelle à chaque retour sur
  /// l'écran, sinon le rapport afficherait l'état d'avant la dernière vente.
  Future<void> recharger() async {
    final (debut, fin) = _periode.bornes();

    // Les lectures ne dépendent pas les unes des autres. Les enchaîner ferait
    // six allers-retours au lieu d'un sur un téléphone d'entrée de gamme, à
    // chaque ouverture de l'onglet.
    final (rapport, alertes, endormis, meilleures, perdu, parVendeur) = await (
      widget.depot.rapportSurPeriode(debut, fin),
      widget.analyses.aReapprovisionner(),
      widget.analyses.articlesQuiDorment(limite: _plafondEndormis),
      widget.analyses.meilleuresVentes(limite: 5),
      widget.analyses.pertesEtEcarts(debut: debut, fin: fin),
      widget.depot.parVendeur(debut, fin),
    ).wait;

    final cloture =
        await widget.rapports?.derniereCloture(NatureRapport.z);

    if (!mounted) return;
    setState(() {
      _rapport = rapport;
      _alertes = alertes;
      _endormis = endormis;
      _meilleures = meilleures;
      _perdu = perdu;
      _parVendeur = parVendeur;
      _derniereCloture = cloture;
    });
  }

  void _changerPeriode(Periode periode) {
    if (periode == _periode) return;
    setState(() => _periode = periode);
    recharger();
  }

  /// Quand la caisse a été arrêtée pour la dernière fois. Nulle tant qu'elle
  /// ne l'a jamais été.
  DateTime? _derniereCloture;

  static String _dateLisible(DateTime quand) {
    String d(int v) => v.toString().padLeft(2, '0');
    return '${d(quand.day)}/${d(quand.month)} à ${d(quand.hour)}h${d(quand.minute)}';
  }

  /// Le point de caisse, sans rien arrêter.
  Future<void> _pointDeCaisse() async {
    final rapports = widget.rapports;
    if (rapports == null) return;

    final x = await rapports.x();
    if (!mounted) return;
    await FeuilleDocument.presenter(
      context,
      titre: 'Point de caisse',
      texte: x.texte,
    );
  }

  /// Clôture la journée.
  ///
  /// Demande confirmation, et c'est le seul endroit de l'application où j'en
  /// demande une. Une clôture ne se défait pas : le rapport suivant repartira
  /// d'ici, et un Z tiré par erreur à midi couperait la journée en deux.
  Future<void> _cloturer() async {
    final rapports = widget.rapports;
    if (rapports == null) return;

    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Clôturer la journée ?'),
        content: const Text(
          "Le prochain rapport repartira d'ici. C'est le geste du soir, "
          'quand la caisse est comptée — il ne se défait pas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Pas maintenant'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    final z = await rapports.z();
    if (!mounted) return;

    setState(() => _derniereCloture = z.fin);
    await FeuilleDocument.presenter(
      context,
      titre: 'Clôture n° ${z.numero}',
      texte: z.texte,
    );
  }

  Future<void> _etatDesArticles() async {
    final rapports = widget.rapports;
    if (rapports == null) return;

    final a = await rapports.a();
    if (!mounted) return;
    await FeuilleDocument.presenter(
      context,
      titre: 'État des articles',
      texte: a.texte,
    );
  }

  /// Vrai quand la répartition par vendeur a quelque chose à dire.
  ///
  /// Chez un commerçant seul, tout est sur une seule ligne anonyme : afficher
  /// « Non attribué : tout » n'apprendrait rien à personne.
  bool get _partsUtiles =>
      _parVendeur.length > 1 ||
      (_parVendeur.length == 1 && !_parVendeur.first.estAnonyme);

  /// Le détail sous le nom d'un vendeur : combien de ventes, et ce qu'il a
  /// lâché en remises.
  ///
  /// La remise n'est mentionnée que si elle existe. C'est le chiffre qui
  /// compte vraiment pour le patron — celui qui accorde deux fois plus de
  /// remises que les autres se voit tout de suite — mais un « 0 F de
  /// remises » affiché tous les jours finit par ne plus être lu.
  String _detailVendeur(PartDeVendeur part) {
    final ventes = '${part.nombreVentes} vente'
        '${part.nombreVentes > 1 ? 's' : ''}';
    if (part.remises.estNul) return ventes;
    return '$ventes · ${part.remises.enFrancs} de remises';
  }

  /// Le résumé tel qu'il part au patron, le soir.
  ///
  /// Composé par [Documents], comme le reçu et l'ardoise : c'est un document,
  /// il doit s'aligner comme les autres.
  String _resume(RapportDuJour rapport) => widget.documents
      .rapportDuSoir(
        rapport: rapport,
        aRacheter: [for (final alerte in _alertes.take(5)) alerte.message],
        perdu: _perdu,
        date: _periode.dateDeReference(),
        intitule: _periode.intitule(),
        // Le patron qui emploie quelqu'un veut le détail dans le message
        // aussi : c'est souvent le seul écran qu'il regarde de la journée.
        parts: [
          if (_partsUtiles)
            for (final part in _parVendeur)
              (qui: part.estAnonyme ? 'Non attribué' : part.vendeur,
                  combien: part.total),
        ],
      )
      .texte;

  @override
  Widget build(BuildContext context) {
    final rapport = _rapport;
    if (rapport == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final textes = Theme.of(context).textTheme;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: recharger,
        child: ListView(
          padding: const EdgeInsets.all(Espace.l),
          children: [
            Row(
              children: [
                // Le sélecteur défile : quatre pastilles ne tiennent pas côte
                // à côte sur les écrans les plus étroits, et une pastille
                // coupée en deux ne se tape pas.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final periode in Periode.values) ...[
                          _Pastille(
                            libelle: periode.libelle,
                            choisie: periode == _periode,
                            onPressed: () => _changerPeriode(periode),
                          ),
                          const SizedBox(width: Espace.s),
                        ],
                      ],
                    ),
                  ),
                ),
                if (widget.surReglages != null)
                  IconButton(
                    onPressed: widget.surReglages,
                    icon: const Icon(Icons.tune_rounded, size: 22),
                    color: Couleurs.encreDouce,
                    tooltip: 'Réglages',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: Espace.m),
            MontantAnime(rapport.encaisse, style: textes.displayLarge),
            Text('encaissés', style: textes.bodyMedium),

            const SizedBox(height: Espace.l),
            Wrap(
              spacing: Espace.s,
              runSpacing: Espace.s,
              children: [
                PastilleMontant(
                  libelle: 'À crédit',
                  montant: rapport.aCredit,
                  teinte: Couleurs.alerte,
                  icone: Icons.schedule_rounded,
                ),
                PastilleMontant(
                  libelle: 'Remises',
                  montant: rapport.remisesAccordees,
                  teinte: Couleurs.accent,
                  icone: Icons.discount_outlined,
                ),
                // Marchandise partie sans rapporter un franc. On ne l'affiche
                // que s'il y en a : une pastille à zéro tous les jours finit
                // par ne plus être lue.
                if (_perdu.estPositif)
                  PastilleMontant(
                    libelle: 'Perdu',
                    montant: _perdu,
                    teinte: Couleurs.alerte,
                    icone: Icons.remove_circle_outline_rounded,
                  ),
              ],
            ),

            const SizedBox(height: Espace.s),
            Text(
              '${rapport.nombreVentes} vente'
              '${rapport.nombreVentes > 1 ? 's' : ''}',
              style: textes.bodyMedium,
            ),

            if (_partsUtiles) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'Qui a encaissé',
                sousTitre: _periode.libelle.toLowerCase(),
                enfants: [
                  for (final part in _parVendeur)
                    _Ligne(
                      libelle: part.estAnonyme ? 'Non attribué' : part.vendeur,
                      detail: part.total.enFrancs,
                      // Une part sans nom est un trou dans le compte : elle se
                      // signale, sans accuser personne.
                      pastille:
                          part.estAnonyme ? Couleurs.alerte : Couleurs.primaire,
                      sousLigne: _detailVendeur(part),
                    ),
                ],
              ),
            ],

            if (_alertes.isNotEmpty) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'À racheter',
                sousTitre: 'Calculé sur ton rythme de vente',
                enfants: [
                  for (final alerte in _alertes)
                    _Ligne(
                      libelle: alerte.designation,
                      detail: alerte.detail,
                      pastille:
                          alerte.enRupture ? Couleurs.alerte : Couleurs.accent,
                      urgent: alerte.enRupture,
                    ),
                ],
              ),
            ],

            if (_meilleures.isNotEmpty) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'Ce qui rapporte',
                sousTitre: 'Sur les sept derniers jours',
                enfants: [
                  for (final article in _meilleures)
                    _Ligne(
                      libelle: article.designation,
                      detail: article.chiffre.enFrancs,
                    ),
                ],
              ),
            ],

            if (_endormis.isNotEmpty) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'Ce qui dort',
                sousTitre: "Vendu régulièrement, puis plus rien",
                enfants: [
                  for (final article in _endormis)
                    _Ligne(
                      libelle: article.designation,
                      detail: article.valeurImmobilisee == null
                          ? '${article.joursSansVente} jours'
                          : '${article.joursSansVente} j · '
                              '${article.valeurImmobilisee!.enFrancs} bloqués',
                      pastille: Couleurs.accent,
                    ),
                ],
              ),
            ],

            const SizedBox(height: Espace.xl),
            FilledButton.icon(
              onPressed: () => FeuilleDocument.presenter(
                context,
                titre: 'Résumé · ${_periode.libelle}',
                texte: _resume(rapport),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: const Text('Envoyer le résumé'),
              style: FilledButton.styleFrom(
                backgroundColor: Couleurs.primaire,
              ),
            ),

            if (widget.rapports != null) ...[
              const SizedBox(height: Espace.xxl),
              Text('Arrêter la caisse', style: textes.titleLarge),
              const SizedBox(height: 2),
              Text(
                _derniereCloture == null
                    ? "Tu n'as encore jamais clôturé. La clôture arrête la "
                        'journée et dit ce qui doit rester dans le tiroir.'
                    : 'Dernière clôture le ${_dateLisible(_derniereCloture!)}.',
                style: textes.labelSmall,
              ),
              const SizedBox(height: Espace.m),
              OutlinedButton.icon(
                onPressed: _pointDeCaisse,
                icon: const Icon(Icons.visibility_outlined, size: 20),
                label: const Text('Point de caisse, sans clôturer'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: Espace.s),
              OutlinedButton.icon(
                onPressed: _cloturer,
                icon: const Icon(Icons.lock_outline_rounded, size: 20),
                label: const Text('Clôturer la journée'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: Couleurs.primaire,
                  side: const BorderSide(color: Couleurs.primaire),
                ),
              ),
              const SizedBox(height: Espace.s),
              TextButton.icon(
                onPressed: _etatDesArticles,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('État des articles'),
                style:
                    TextButton.styleFrom(foregroundColor: Couleurs.encreDouce),
              ),
            ],

            const SizedBox(height: Espace.xxl),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String titre;
  final String sousTitre;
  final List<Widget> enfants;

  const _Section({
    required this.titre,
    required this.sousTitre,
    required this.enfants,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titre, style: textes.titleLarge),
        const SizedBox(height: 2),
        Text(sousTitre, style: textes.labelSmall),
        const SizedBox(height: Espace.m),
        Container(
          decoration: BoxDecoration(
            color: Couleurs.surface,
            borderRadius: BorderRadius.circular(Rayon.m),
            border: Border.all(color: Couleurs.bordure),
          ),
          child: Column(children: enfants),
        ),
      ],
    );
  }
}

/// Une ligne de liste : un libellé à gauche, un détail à droite.
///
/// La même pour les alertes et pour les montants — c'est la pastille qui
/// change, pas la mise en page.
class _Ligne extends StatelessWidget {
  final String libelle;
  final String detail;

  /// Couleur du point de tête. Nulle quand la ligne n'en porte pas.
  final Color? pastille;

  /// Précision affichée sous le libellé, en petit. Nulle le plus souvent.
  final String? sousLigne;

  final bool urgent;

  const _Ligne({
    required this.libelle,
    required this.detail,
    this.pastille,
    this.sousLigne,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Espace.l, vertical: Espace.m),
      child: Row(
        children: [
          if (pastille != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: pastille, shape: BoxShape.circle),
            ),
            const SizedBox(width: Espace.m),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(libelle,
                    style: textes.titleMedium, overflow: TextOverflow.ellipsis),
                if (sousLigne != null)
                  Text(sousLigne!,
                      style: textes.labelSmall, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: Espace.s),
          Text(
            detail,
            style: (urgent ? textes.labelSmall : textes.labelLarge)?.copyWith(
              color: urgent ? Couleurs.alerte : Couleurs.encreDouce,
            ),
          ),
        ],
      ),
    );
  }
}

/// Une pastille de choix de période.
///
/// Assez large pour un pouce, et la sélection se lit à la couleur autant
/// qu'au contour : un contour seul ne se voit pas en plein soleil.
class _Pastille extends StatelessWidget {
  final String libelle;
  final bool choisie;
  final VoidCallback onPressed;

  const _Pastille({
    required this.libelle,
    required this.choisie,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Material(
      color: choisie ? Couleurs.primaire : Couleurs.surface,
      borderRadius: BorderRadius.circular(Rayon.rond),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Rayon.rond),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Espace.m, vertical: Espace.s),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rayon.rond),
            border: Border.all(
                color: choisie ? Couleurs.primaire : Couleurs.bordure),
          ),
          child: Text(
            libelle,
            style: textes.labelSmall?.copyWith(
              color: choisie ? Colors.white : Couleurs.encreDouce,
            ),
          ),
        ),
      ),
    );
  }
}
