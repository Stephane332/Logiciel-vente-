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

  const _CarteDebiteur({
    required this.client,
    required this.maintenant,
    required this.surEncaissement,
    required this.surEnvoi,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final jours = client.ageEnJours(maintenant);

    // Une dette qui dort depuis un mois n'est pas de même nature qu'une dette
    // d'hier : elle se signale.
    final ancienne = client.detteAncienne(maintenant);

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
          Row(
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
              // défile, chaque chiffre animé coûte un contrôleur d'animation
              // pour une valeur qui ne bouge jamais.
              Text(
                Montant(client.encoursCentimes).enFrancs,
                style: textes.headlineMedium?.copyWith(color: Couleurs.alerte),
              ),
            ],
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
