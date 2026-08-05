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

import '../../domaine/montant.dart';
import '../../donnees/analyses.dart';
import '../../donnees/depot.dart';
import '../composants/montant_anime.dart';
import '../composants/partage.dart';
import '../theme/palette.dart';

class EcranRapport extends StatefulWidget {
  final Depot depot;
  final Analyses analyses;
  final String nomCommerce;

  const EcranRapport({
    super.key,
    required this.depot,
    required this.analyses,
    required this.nomCommerce,
  });

  @override
  State<EcranRapport> createState() => EcranRapportState();
}

class EcranRapportState extends State<EcranRapport> {
  RapportDuJour? _rapport;
  List<AlerteStock> _alertes = const [];
  List<ArticleEndormi> _endormis = const [];
  List<PerformanceArticle> _meilleures = const [];
  bool _chargement = true;

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
    final maintenant = DateTime.now();

    // La semaine se compte en journées entières et se ferme à minuit
    // prochain. Borner à l'instant présent ferait disparaître la vente qui
    // vient d'être encaissée — c'est justement celle que le commerçant
    // cherche des yeux quand il ouvre son rapport.
    final finDeJournee =
        DateTime(maintenant.year, maintenant.month, maintenant.day)
            .add(const Duration(days: 1));

    final rapport = await widget.depot.rapportDuJour(maintenant);
    final alertes = await widget.analyses.aReapprovisionner();
    final endormis = await widget.analyses.articlesQuiDorment();
    final meilleures = await widget.analyses.meilleuresVentes(
      debut: finDeJournee.subtract(const Duration(days: 7)),
      fin: finDeJournee,
      limite: 5,
    );

    if (!mounted) return;
    setState(() {
      _rapport = rapport;
      _alertes = alertes;
      _endormis = endormis;
      _meilleures = meilleures;
      _chargement = false;
    });
  }

  /// Le résumé tel qu'il partirait au patron, le soir.
  String get _resume {
    final rapport = _rapport!;
    final lignes = <String>[
      widget.nomCommerce.toUpperCase(),
      "Aujourd'hui",
      '',
      '${rapport.encaisse.enFrancs} encaissés',
      if (rapport.aCredit.estPositif) '${rapport.aCredit.enFrancs} à crédit',
      '${rapport.nombreVentes} vente${rapport.nombreVentes > 1 ? 's' : ''}',
      if (rapport.remisesAccordees.estPositif)
        '${rapport.remisesAccordees.enFrancs} de remises accordées',
    ];

    if (_alertes.isNotEmpty) {
      lignes
        ..add('')
        ..add('À racheter :');
      for (final alerte in _alertes.take(5)) {
        lignes.add('· ${alerte.message}');
      }
    }

    return lignes.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement || _rapport == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final rapport = _rapport!;
    final textes = Theme.of(context).textTheme;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: recharger,
        child: ListView(
          padding: const EdgeInsets.all(Espace.l),
          children: [
            Text("Aujourd'hui", style: textes.labelSmall),
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
                    _LigneAlerte(
                      libelle: alerte.designation,
                      detail: alerte.enRupture
                          ? 'Rupture'
                          : alerte.joursRestants == null
                              ? 'Ne se vend plus'
                              : 'Encore ${alerte.joursRestants} jour'
                                  '${alerte.joursRestants! > 1 ? 's' : ''}',
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
                    _LigneMontant(
                      libelle: article.designation,
                      montant: article.chiffre,
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
                  for (final article in _endormis.take(5))
                    _LigneAlerte(
                      libelle: article.designation,
                      detail: article.valeurImmobilisee == null
                          ? '${article.joursSansVente} jours'
                          : '${article.joursSansVente} j · '
                              '${article.valeurImmobilisee!.enFrancs} bloqués',
                      urgent: false,
                    ),
                ],
              ),
            ],

            const SizedBox(height: Espace.xl),
            FilledButton.icon(
              onPressed: () => FeuilleDocument.presenter(
                context,
                titre: 'Résumé du jour',
                texte: _resume,
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

class _LigneAlerte extends StatelessWidget {
  final String libelle;
  final String detail;
  final bool urgent;

  const _LigneAlerte({
    required this.libelle,
    required this.detail,
    required this.urgent,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Espace.l, vertical: Espace.m),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: urgent ? Couleurs.alerte : Couleurs.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Espace.m),
          Expanded(
            child: Text(libelle,
                style: textes.titleMedium, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: Espace.s),
          Text(
            detail,
            style: textes.labelSmall?.copyWith(
              color: urgent ? Couleurs.alerte : Couleurs.encreDouce,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneMontant extends StatelessWidget {
  final String libelle;
  final Montant montant;

  const _LigneMontant({required this.libelle, required this.montant});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Espace.l, vertical: Espace.m),
      child: Row(
        children: [
          Expanded(
            child: Text(libelle,
                style: textes.titleMedium, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: Espace.s),
          Text(montant.enFrancs, style: textes.labelLarge),
        ],
      ),
    );
  }
}
