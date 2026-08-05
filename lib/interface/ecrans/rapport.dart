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
import '../../donnees/documents.dart';
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

  const EcranRapport({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    this.surReglages,
  });

  @override
  State<EcranRapport> createState() => EcranRapportState();
}

class EcranRapportState extends State<EcranRapport> {
  RapportDuJour? _rapport;
  List<AlerteStock> _alertes = const [];
  List<ArticleEndormi> _endormis = const [];
  List<PerformanceArticle> _meilleures = const [];
  Montant _perdu = const Montant.zero();

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
    // Les quatre lectures ne dépendent pas les unes des autres. Les enchaîner
    // ferait quatre allers-retours au lieu d'un sur un téléphone d'entrée de
    // gamme, à chaque ouverture de l'onglet.
    final (rapport, alertes, endormis, meilleures, perdu) = await (
      widget.depot.rapportDuJour(),
      widget.analyses.aReapprovisionner(),
      widget.analyses.articlesQuiDorment(limite: _plafondEndormis),
      widget.analyses.meilleuresVentes(limite: 5),
      widget.analyses.pertesEtEcarts(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _rapport = rapport;
      _alertes = alertes;
      _endormis = endormis;
      _meilleures = meilleures;
      _perdu = perdu;
    });
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
                Text("Aujourd'hui", style: textes.labelSmall),
                const Spacer(),
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
            const SizedBox(height: Espace.xs),
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
                titre: 'Résumé du jour',
                texte: _resume(rapport),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: const Text('Envoyer le résumé'),
              style: FilledButton.styleFrom(
                backgroundColor: Couleurs.primaire,
              ),
            ),
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

  final bool urgent;

  const _Ligne({
    required this.libelle,
    required this.detail,
    this.pastille,
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
            child: Text(libelle,
                style: textes.titleMedium, overflow: TextOverflow.ellipsis),
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
