/// Feuille d'encaissement.
///
/// Le mobile money y est traité comme il se passe réellement dans une
/// boutique : le commerçant annonce le montant, le client sort son téléphone.
/// L'application génère le code USSD marchand pré-rempli, sous deux formes —
/// un code QR à scanner, et le code écrit en grand pour ceux qui le tapent.
///
/// Aucune API payante n'intervient : c'est l'opérateur qui fait le travail.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../domaine/mobile_money.dart';
import '../../domaine/montant.dart';
import '../../domaine/references.dart';
import '../composants/montant_anime.dart';
import '../theme/palette.dart';

/// Couleur d'accompagnement d'un opérateur, à sa charte.
Color teinteDe(OperateurMobile operateur) => switch (operateur) {
      OperateurMobile.orange => const Color(0xFFFF6600),
      OperateurMobile.moov => const Color(0xFF0066B3),
      OperateurMobile.telecel => const Color(0xFFE30613),
    };

class FeuillePaiement extends StatefulWidget {
  final Montant total;

  /// Les comptes sur lesquels le commerçant se fait payer.
  final ComptesMarchands comptes;

  /// Appelé avec le mode retenu, une fois la vente validée.
  final Future<void> Function(ModePaiement mode) surPaiementChoisi;

  /// Ouvre les réglages. Nul quand il n'y a nulle part où aller — en test,
  /// par exemple.
  final VoidCallback? surConfiguration;

  const FeuillePaiement({
    super.key,
    required this.total,
    required this.surPaiementChoisi,
    this.comptes = const ComptesMarchands.aucun(),
    this.surConfiguration,
  });

  static Future<void> presenter(
    BuildContext context, {
    required Montant total,
    required Future<void> Function(ModePaiement mode) surPaiementChoisi,
    ComptesMarchands comptes = const ComptesMarchands.aucun(),
    VoidCallback? surConfiguration,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FeuillePaiement(
          total: total,
          comptes: comptes,
          surPaiementChoisi: surPaiementChoisi,
          surConfiguration: surConfiguration,
        ),
      );

  @override
  State<FeuillePaiement> createState() => _FeuillePaiementState();
}

class _FeuillePaiementState extends State<FeuillePaiement> {
  ModePaiement? _mode;
  OperateurMobile? _operateur;

  @override
  void initState() {
    super.initState();
    _operateur = widget.comptes.disponibles.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final disponibles = widget.comptes.disponibles;

    // La feuille défile : le volet mobile money l'agrandit, et sur un écran
    // court ou clavier ouvert elle déborderait sinon.
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
          Center(
            child: Column(
              children: [
                Text('Montant à encaisser', style: textes.labelSmall),
                const SizedBox(height: Espace.xs),
                MontantAnime(widget.total, style: textes.displayMedium),
              ],
            ),
          ),
          const SizedBox(height: Espace.xl),

          // Le choix du mode se fait d'un geste, sans menu.
          Row(
            children: [
              Expanded(
                child: _BoutonMode(
                  icone: Icons.payments_outlined,
                  libelle: 'Espèces',
                  teinte: Couleurs.primaire,
                  actif: _mode == ModePaiement.especes,
                  onPressed: () =>
                      setState(() => _mode = ModePaiement.especes),
                ),
              ),
              const SizedBox(width: Espace.m),
              Expanded(
                child: _BoutonMode(
                  icone: Icons.smartphone_rounded,
                  libelle: 'Mobile money',
                  teinte: teinteDe(OperateurMobile.orange),
                  actif: _mode == ModePaiement.mobileMoney,
                  onPressed: () =>
                      setState(() => _mode = ModePaiement.mobileMoney),
                ),
              ),
              const SizedBox(width: Espace.m),
              Expanded(
                child: _BoutonMode(
                  icone: Icons.schedule_rounded,
                  libelle: 'Crédit',
                  teinte: Couleurs.alerte,
                  actif: _mode == ModePaiement.credit,
                  onPressed: () => setState(() => _mode = ModePaiement.credit),
                ),
              ),
            ],
          ),

          AnimatedSize(
            duration: Duree.moyenne,
            curve: Courbe.sortie,
            alignment: Alignment.topCenter,
            child: switch ((_mode, _operateur)) {
              // Rien n'est configuré : plutôt qu'un code QR qui ne paierait
              // personne, on dit ce qu'il manque et on y emmène.
              (ModePaiement.mobileMoney, null) => _AConfigurer(
                  surConfiguration: widget.surConfiguration,
                ),
              (ModePaiement.mobileMoney, final operateur?) => _VoletMobileMoney(
                  total: widget.total,
                  numeroMarchand: widget.comptes.numeroDe(operateur)!,
                  operateur: operateur,
                  disponibles: disponibles,
                  surChangementOperateur: (o) =>
                      setState(() => _operateur = o),
                ),
              _ => const SizedBox(width: double.infinity),
            },
          ),

          const SizedBox(height: Espace.xl),
          FilledButton(
            onPressed: _mode == null
                ? null
                : () async {
                    final mode = _mode!;
                    final navigateur = Navigator.of(context);
                    await widget.surPaiementChoisi(mode);
                    navigateur.pop();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
            ),
            child: Text(
              _mode == null ? 'Choisir un mode' : 'Valider la vente',
              style: textes.labelLarge?.copyWith(
                fontSize: 17,
                color: _mode == null ? Couleurs.encreLegere : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ce qui s'affiche quand aucun compte marchand n'est encore renseigné.
class _AConfigurer extends StatelessWidget {
  final VoidCallback? surConfiguration;

  const _AConfigurer({required this.surConfiguration});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: Espace.l),
      padding: const EdgeInsets.all(Espace.l),
      decoration: BoxDecoration(
        color: Couleurs.fond,
        borderRadius: BorderRadius.circular(Rayon.m),
        border: Border.all(color: Couleurs.bordure),
      ),
      child: Column(
        children: [
          const Icon(Icons.smartphone_rounded,
              size: 32, color: Couleurs.encreLegere),
          const SizedBox(height: Espace.m),
          Text(
            "Dis-moi sur quel numéro tu veux être payé, et je génère le code "
            "que ton client n'aura plus qu'à scanner.",
            textAlign: TextAlign.center,
            style: textes.bodyMedium,
          ),
          if (surConfiguration != null) ...[
            const SizedBox(height: Espace.m),
            OutlinedButton.icon(
              onPressed: surConfiguration,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Renseigner mon numéro'),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoletMobileMoney extends StatelessWidget {
  final Montant total;
  final String numeroMarchand;
  final OperateurMobile operateur;

  /// Les opérateurs chez qui le commerçant a un compte. Proposer les autres
  /// afficherait un code qui ne le paierait pas.
  final List<OperateurMobile> disponibles;

  final ValueChanged<OperateurMobile> surChangementOperateur;

  const _VoletMobileMoney({
    required this.total,
    required this.numeroMarchand,
    required this.operateur,
    required this.disponibles,
    required this.surChangementOperateur,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final code = operateur.code(numero: numeroMarchand, montant: total);
    final url = operateur.lienComposeur(numero: numeroMarchand, montant: total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Espace.l),
        Row(
          children: [
            for (final o in disponibles) ...[
              Expanded(
                child: _PastilleOperateur(
                  operateur: o,
                  actif: o == operateur,
                  onPressed: () => surChangementOperateur(o),
                ),
              ),
              if (o != disponibles.last)
                const SizedBox(width: Espace.s),
            ],
          ],
        ),
        const SizedBox(height: Espace.l),

        Container(
          padding: const EdgeInsets.all(Espace.l),
          decoration: BoxDecoration(
            color: Couleurs.fond,
            borderRadius: BorderRadius.circular(Rayon.l),
            border: Border.all(color: Couleurs.bordure),
          ),
          child: Column(
            children: [
              Text(
                'Le client scanne, ou tape le code',
                style: textes.labelSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Espace.l),

              // Le QR contient l'URL du composeur : l'appareil photo du
              // client ouvre son téléphone avec le code déjà rempli.
              // Cela fonctionne sur Android comme sur iPhone.
              TweenAnimationBuilder<double>(
                key: ValueKey(url),
                tween: Tween(begin: 0.85, end: 1),
                duration: Duree.moyenne,
                curve: Courbe.rebond,
                builder: (context, echelle, enfant) =>
                    Transform.scale(scale: echelle, child: enfant),
                child: Container(
                  padding: const EdgeInsets.all(Espace.m),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Rayon.m),
                  ),
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 168,
                    padding: EdgeInsets.zero,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: teinteDe(operateur),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Couleurs.encre,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: Espace.l),
              // Le code écrit en grand : indispensable pour les téléphones
              // sans appareil photo, et c'est encore le cas de beaucoup.
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Espace.l, vertical: Espace.m),
                  decoration: BoxDecoration(
                    color: teinteDe(operateur).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Rayon.s),
                  ),
                  child: Text(
                    code,
                    textAlign: TextAlign.center,
                    style: textes.titleLarge?.copyWith(
                      color: teinteDe(operateur),
                      letterSpacing: 0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: Espace.m),
        // Pas de « en attente de confirmation » : rien n'écoute encore les
        // SMS de l'opérateur. Tant que la capture automatique n'est pas là,
        // c'est le commerçant qui confirme, et l'écran le dit franchement
        // plutôt que d'afficher une attente qui n'existe pas.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 15, color: Couleurs.encreLegere),
            const SizedBox(width: Espace.s),
            Flexible(
              child: Text(
                'Valide la vente quand tu as reçu le SMS '
                '${operateur.abrege}.',
                style: textes.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BoutonMode extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final Color teinte;
  final bool actif;
  final VoidCallback onPressed;

  const _BoutonMode({
    required this.icone,
    required this.libelle,
    required this.teinte,
    required this.actif,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: Duree.rapide,
        curve: Courbe.sortie,
        padding: const EdgeInsets.symmetric(vertical: Espace.m),
        decoration: BoxDecoration(
          color: actif ? teinte.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(Rayon.m),
          border: Border.all(
            color: actif ? teinte : Couleurs.bordure,
            width: actif ? 2 : 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icone,
                size: 24, color: actif ? teinte : Couleurs.encreDouce),
            const SizedBox(height: Espace.xs),
            Text(
              libelle,
              textAlign: TextAlign.center,
              style: textes.labelSmall?.copyWith(
                color: actif ? teinte : Couleurs.encreDouce,
                fontWeight: actif ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastilleOperateur extends StatelessWidget {
  final OperateurMobile operateur;
  final bool actif;
  final VoidCallback onPressed;

  const _PastilleOperateur({
    required this.operateur,
    required this.actif,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: Duree.rapide,
        curve: Courbe.sortie,
        padding: const EdgeInsets.symmetric(vertical: Espace.s + 2),
        decoration: BoxDecoration(
          color: actif
              ? teinteDe(operateur).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Rayon.s),
          border: Border.all(
            color: actif ? teinteDe(operateur) : Couleurs.bordure,
            width: actif ? 2 : 1,
          ),
        ),
        child: Text(
          operateur.abrege,
          textAlign: TextAlign.center,
          style: textes.labelSmall?.copyWith(
            color: actif ? teinteDe(operateur) : Couleurs.encreDouce,
            fontWeight: actif ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
