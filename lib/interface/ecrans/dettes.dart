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
    final montant = await _demanderMontant(
      titre: 'Remboursement de ${client.nom}',
      maximum: Montant(client.encoursCentimes),
    );
    if (montant == null || !montant.estPositif) return;

    await widget.depot.rembourserCredit(client.id, montant);
    await recharger();
  }

  Future<Montant?> _demanderMontant({
    required String titre,
    required Montant maximum,
  }) {
    var saisie = '';
    return showModalBottomSheet<Montant>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (contexte) => StatefulBuilder(
        builder: (contexte, rafraichir) => _PaveRemboursement(
          titre: titre,
          maximum: maximum,
          saisie: saisie,
          surTouche: (touche) => rafraichir(() {
            if (touche == '<') {
              if (saisie.isNotEmpty) {
                saisie = saisie.substring(0, saisie.length - 1);
              }
            } else if (saisie.length < 9) {
              if (!(saisie.isEmpty && touche == '0')) saisie += touche;
            }
          }),
          surTout: () => rafraichir(
              () => saisie = (maximum.centimes ~/ 100).toString()),
          surValidation: saisie.isEmpty
              ? null
              : () => Navigator.of(contexte)
                  .pop(Montant.depuisDecimal(int.parse(saisie))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

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
                      _total,
                      style: textes.displayLarge,
                      couleur: _total.estNul
                          ? Couleurs.encreLegere
                          : Couleurs.alerte,
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
  final VoidCallback surEncaissement;
  final VoidCallback surEnvoi;

  const _CarteDebiteur({
    required this.client,
    required this.surEncaissement,
    required this.surEnvoi,
  });

  /// Depuis combien de jours la dette n'a pas bougé.
  int? get _anciennete => client.derniereActivite == null
      ? null
      : DateTime.now().difference(client.derniereActivite!).inDays;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final jours = _anciennete;

    // Une dette qui dort depuis un mois n'est pas de même nature qu'une dette
    // d'hier : elle se signale.
    final ancienne = jours != null && jours >= 30;

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
              MontantAnime(
                Montant(client.encoursCentimes),
                style: textes.headlineMedium,
                couleur: Couleurs.alerte,
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

/// Pavé de saisie d'un remboursement, avec un raccourci « tout ».
///
/// Le remboursement intégral est le cas le plus fréquent : il mérite un
/// bouton plutôt que de retaper le montant.
class _PaveRemboursement extends StatelessWidget {
  final String titre;
  final Montant maximum;
  final String saisie;
  final ValueChanged<String> surTouche;
  final VoidCallback surTout;
  final VoidCallback? surValidation;

  const _PaveRemboursement({
    required this.titre,
    required this.maximum,
    required this.saisie,
    required this.surTouche,
    required this.surTout,
    required this.surValidation,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final montant = saisie.isEmpty
        ? const Montant.zero()
        : Montant.depuisDecimal(int.parse(saisie));
    final excessif = montant.centimes > maximum.centimes;

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
                : (saisie.isEmpty ? Couleurs.encreLegere : Couleurs.encre),
          ),
          const SizedBox(height: Espace.xs),
          Text(
            excessif
                ? 'Plus que la dette de ${maximum.enFrancs}'
                : 'Doit ${maximum.enFrancs}',
            style: textes.labelSmall?.copyWith(
              color: excessif ? Couleurs.alerte : Couleurs.encreDouce,
            ),
          ),
          const SizedBox(height: Espace.m),
          OutlinedButton(
            onPressed: surTout,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text('Tout : ${maximum.enFrancs}'),
          ),
          const SizedBox(height: Espace.m),
          for (final rangee in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['00', '0', '<'],
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
            onPressed: excessif ? null : surValidation,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
            ),
            child: Text(
              'Enregistrer le paiement',
              style: textes.labelLarge?.copyWith(
                fontSize: 17,
                color: (surValidation == null || excessif)
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
    final effacement = libelle == '<';

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
