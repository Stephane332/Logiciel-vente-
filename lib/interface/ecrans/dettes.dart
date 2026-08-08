/// Le cahier de dettes.
///
/// C'est l'objet le plus précieux du commerçant, et celui qu'il tient
/// aujourd'hui sur papier. Les plus anciennes créances remontent en tête :
/// ce sont celles qu'on oublie, et celles qu'on ne récupère plus.
library;

import 'package:flutter/material.dart';

import '../../domaine/montant.dart';
import '../../domaine/telephone.dart';
import '../../donnees/base.dart';
import '../../donnees/depot.dart';
import '../../donnees/documents.dart';
import '../composants/montant_anime.dart';
import '../composants/pave_numerique.dart';
import '../composants/partage.dart';
import '../theme/palette.dart';

class EcranDettes extends StatefulWidget {
  final Depot depot;
  final Documents documents;

  const EcranDettes({super.key, required this.depot, required this.documents});

  @override
  State<EcranDettes> createState() => EcranDettesState();
}

class EcranDettesState extends State<EcranDettes> {
  List<LigneClient> _debiteurs = const [];
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  /// Relit la liste des débiteurs.
  ///
  /// Publique : la coquille de navigation l'appelle à chaque retour sur
  /// l'écran, sinon une vente à crédit faite entre-temps n'apparaîtrait pas.
  Future<void> recharger() async {
    final debiteurs = await widget.depot.clientsDebiteurs();
    if (!mounted) return;
    setState(() {
      _debiteurs = debiteurs;
      _chargement = false;
    });
  }

  Montant get _total =>
      Montant(_debiteurs.fold(0, (s, c) => s + c.encoursCentimes));

  Future<void> _envoyerArdoise(LigneClient client) async {
    final ardoise = await widget.documents.ardoise(client.id);
    if (ardoise == null || !mounted) return;

    await FeuilleDocument.presenter(
      context,
      titre: 'Ardoise de ${client.nom}',
      texte: ardoise.texte,
      telephone: client.telephoneNormalise,
    );
  }

  /// Ouvre le détail : ce qui compose la dette, ligne par ligne.
  ///
  /// Le total seul ne règle aucune dispute. Quand le client conteste, il faut
  /// pouvoir poser le téléphone entre eux deux et faire défiler.
  Future<void> _detailler(LigneClient client) async {
    final mouvements = await widget.depot.compteDe(client.id);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (contexte) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, defilement) => _DetailDuCompte(
          client: client,
          mouvements: mouvements,
          defilement: defilement,
        ),
      ),
    );
  }

  Future<void> _encaisser(LigneClient client) async {
    final du = Montant(client.encoursCentimes);
    final montant = await demanderMontant(
      context,
      titre: 'Remboursement de ${client.nom}',
      indication: 'Doit ${du.enFrancs}',
      valider: 'Enregistrer le paiement',
      plafond: du,
      libellePlafond: (tout) => 'Tout : ${tout.enFrancs}',
    );
    if (montant == null || !montant.estPositif) return;

    await widget.depot.rembourserCredit(client.id, montant);
    await recharger();
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    // L'heure est lue une fois pour toute la liste : sinon chaque carte la
    // relit à chaque image pendant qu'on fait défiler.
    final maintenant = DateTime.now();
    final total = _total;

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
                Espace.l, Espace.m, Espace.l, Espace.l),
            decoration: const BoxDecoration(
              color: Couleurs.surface,
              border: Border(bottom: BorderSide(color: Couleurs.bordure)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On te doit', style: textes.labelSmall),
                const SizedBox(height: Espace.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MontantAnime(
                      total,
                      style: textes.displayLarge,
                      couleur:
                          total.estNul ? Couleurs.encreLegere : Couleurs.alerte,
                    ),
                    const Spacer(),
                    if (_debiteurs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Espace.s),
                        child: Text(
                          '${_debiteurs.length} client'
                          '${_debiteurs.length > 1 ? 's' : ''}',
                          style: textes.bodyMedium,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _debiteurs.isEmpty
                ? const _AucuneDette()
                : ListView.separated(
                    padding: const EdgeInsets.all(Espace.l),
                    itemCount: _debiteurs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Espace.m),
                    itemBuilder: (context, index) => _CarteDebiteur(
                      client: _debiteurs[index],
                      maintenant: maintenant,
                      surEncaissement: () => _encaisser(_debiteurs[index]),
                      surEnvoi: () => _envoyerArdoise(_debiteurs[index]),
                      surDetail: () => _detailler(_debiteurs[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AucuneDette extends StatelessWidget {
  const _AucuneDette();

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 56, color: Couleurs.primaireVif),
            const SizedBox(height: Espace.l),
            Text('Personne ne te doit rien',
                style: textes.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Espace.s),
            Text(
              "Les ventes à crédit apparaîtront ici, de la plus ancienne à la "
              'plus récente.',
              style: textes.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteDebiteur extends StatelessWidget {
  final LigneClient client;

  /// L'heure de référence, lue une seule fois par la liste.
  final DateTime maintenant;

  final VoidCallback surEncaissement;
  final VoidCallback surEnvoi;
  final VoidCallback surDetail;

  const _CarteDebiteur({
    required this.client,
    required this.maintenant,
    required this.surEncaissement,
    required this.surEnvoi,
    required this.surDetail,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final jours = client.ageEnJours(maintenant);

    // Une dette qui dort depuis un mois n'est pas de même nature qu'une dette
    // d'hier : elle se signale.
    final ancienne = client.detteAncienne(maintenant);

    final du = Montant(client.encoursCentimes);

    return Container(
      padding: const EdgeInsets.all(Espace.l),
      decoration: BoxDecoration(
        color: Couleurs.surface,
        borderRadius: BorderRadius.circular(Rayon.m),
        border: Border.all(
          color: ancienne ? Couleurs.alerte : Couleurs.bordure,
          width: ancienne ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seule la tête de carte ouvre le détail, et elle porte sa propre
          // étiquette. Rendre la carte entière tactile fusionnait tout ce
          // qu'elle contient en un seul nœud : un lecteur d'écran n'entendait
          // plus que « Envoyer Encaisser », sans le nom du client.
          Semantics(
            button: true,
            label: '${client.nom}, doit ${du.enFrancs}, voir le détail',
            child: InkWell(
              onTap: surDetail,
              borderRadius: BorderRadius.circular(Rayon.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(client.nom, style: textes.titleLarge),
                        if (client.telephoneNormalise != null) ...[
                          const SizedBox(height: 2),
                          Text(presenterTelephone(client.telephoneNormalise),
                              style: textes.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  // Texte simple, pas de montant animé : dans une liste qui
                  // défile, chaque chiffre animé coûte un contrôleur
                  // d'animation pour une valeur qui ne bouge jamais.
                  Text(
                    du.enFrancs,
                    style:
                        textes.headlineMedium?.copyWith(color: Couleurs.alerte),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Couleurs.encreLegere),
                ],
              ),
            ),
          ),
          if (jours != null) ...[
            const SizedBox(height: Espace.s),
            Row(
              children: [
                Icon(
                  ancienne
                      ? Icons.warning_amber_rounded
                      : Icons.schedule_rounded,
                  size: 15,
                  color: ancienne ? Couleurs.alerte : Couleurs.encreLegere,
                ),
                const SizedBox(width: Espace.xs),
                Text(
                  jours == 0
                      ? "Depuis aujourd'hui"
                      : 'Depuis $jours jour${jours > 1 ? 's' : ''}',
                  style: textes.labelSmall?.copyWith(
                    color: ancienne ? Couleurs.alerte : Couleurs.encreLegere,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Espace.l),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: surEnvoi,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Envoyer'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: Espace.m),
              Expanded(
                child: FilledButton.icon(
                  onPressed: surEncaissement,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Encaisser'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: Couleurs.primaire,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ce qui compose une dette, du plus récent au plus ancien.
///
/// Le cahier n'affichait qu'un total, et le total ne règle aucune dispute.
/// Ici le commerçant pose le téléphone entre lui et son client, et ils
/// remontent ensemble.
class _DetailDuCompte extends StatelessWidget {
  final LigneClient client;
  final List<MouvementDeCompte> mouvements;
  final ScrollController defilement;

  const _DetailDuCompte({
    required this.client,
    required this.mouvements,
    required this.defilement,
  });

  static String _date(DateTime quand) =>
      '${_d(quand.day)}/${_d(quand.month)}/${quand.year} · '
      '${_d(quand.hour)}h${_d(quand.minute)}';

  static String _d(int valeur) => valeur < 10 ? '0$valeur' : '$valeur';

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return ListView(
      controller: defilement,
      padding: const EdgeInsets.fromLTRB(Espace.l, 0, Espace.l, Espace.xxl),
      children: [
        Text(client.nom, style: textes.titleLarge),
        Text(
          'Doit ${Montant(client.encoursCentimes).enFrancs}',
          style: textes.bodyMedium?.copyWith(color: Couleurs.alerte),
        ),
        const SizedBox(height: Espace.l),

        if (mouvements.isEmpty)
          Text(
            "Rien à détailler : cette dette a été inscrite sans passer par une "
            'vente.',
            style: textes.bodyMedium,
          ),

        for (final mouvement in mouvements) ...[
          _LigneDeCompte(
            mouvement: mouvement,
            quand: _date(mouvement.quand),
          ),
          const SizedBox(height: Espace.s),
        ],
      ],
    );
  }
}

class _LigneDeCompte extends StatelessWidget {
  final MouvementDeCompte mouvement;
  final String quand;

  const _LigneDeCompte({required this.mouvement, required this.quand});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final achat = mouvement.estAchat;

    // Un achat annulé reste affiché, barré : le faire disparaître ferait
    // croire au client qu'on lui a effacé une ligne dans le dos.
    final teinte = mouvement.annule
        ? Couleurs.encreLegere
        : (achat ? Couleurs.alerte : Couleurs.primaire);

    return Container(
      padding: const EdgeInsets.all(Espace.m),
      decoration: BoxDecoration(
        color: Couleurs.surface,
        borderRadius: BorderRadius.circular(Rayon.m),
        border: Border.all(color: Couleurs.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                achat
                    ? Icons.add_shopping_cart_rounded
                    : Icons.payments_outlined,
                size: 16,
                color: teinte,
              ),
              const SizedBox(width: Espace.s),
              Expanded(child: Text(quand, style: textes.labelSmall)),
              Text(
                '${achat ? '+' : '−'} ${mouvement.montant.enFrancs}',
                style: textes.titleMedium?.copyWith(
                  color: teinte,
                  decoration:
                      mouvement.annule ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          if (mouvement.annule)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Annulée',
                  style: textes.labelSmall
                      ?.copyWith(color: Couleurs.encreLegere)),
            ),
          for (final detail in mouvement.detail)
            Padding(
              padding: const EdgeInsets.only(top: Espace.s, left: Espace.l),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      detail.quantite == const Quantite.unites(1)
                          ? detail.designation
                          : '${detail.designation}  ×${detail.quantite}',
                      style: textes.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Espace.s),
                  Text(detail.total.enFrancs, style: textes.labelSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
