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

import '../../domaine/montant.dart';
import '../../domaine/references.dart';
import '../composants/montant_anime.dart';
import '../theme/palette.dart';

/// Un opérateur de mobile money et la syntaxe de son code marchand.
class OperateurMobile {
  final String nom;
  final Color teinte;

  /// Modèle du code marchand. `{numero}` et `{montant}` sont substitués.
  final String modeleUssd;

  const OperateurMobile(this.nom, this.teinte, this.modeleUssd);

  String code({required String numero, required Montant montant}) {
    final francs = (montant.centimes / 100).round().toString();
    return modeleUssd
        .replaceAll('{numero}', numero)
        .replaceAll('{montant}', francs);
  }

  /// URL composable. Le `#` doit être encodé, sans quoi le composeur
  /// tronque le code.
  String urlComposeur({required String numero, required Montant montant}) =>
      'tel:${Uri.encodeComponent(code(numero: numero, montant: montant))}';

  static const orange =
      OperateurMobile('Orange Money', Color(0xFFFF6600), '*144*10*{numero}*{montant}#');
  static const moov =
      OperateurMobile('Moov Money', Color(0xFF0066B3), '*555*{numero}*{montant}#');
  static const telecel =
      OperateurMobile('Telecel Money', Color(0xFFE30613), '*800*{numero}*{montant}#');

  static const tous = [orange, moov, telecel];
}

class FeuillePaiement extends StatefulWidget {
  final Montant total;

  /// Appelé avec le mode retenu, une fois la vente validée.
  final Future<void> Function(ModePaiement mode) surPaiementChoisi;

  const FeuillePaiement({
    super.key,
    required this.total,
    required this.surPaiementChoisi,
  });

  static Future<void> presenter(
    BuildContext context, {
    required Montant total,
    required Future<void> Function(ModePaiement mode) surPaiementChoisi,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FeuillePaiement(
          total: total,
          surPaiementChoisi: surPaiementChoisi,
        ),
      );

  @override
  State<FeuillePaiement> createState() => _FeuillePaiementState();
}

class _FeuillePaiementState extends State<FeuillePaiement> {
  /// Numéro marchand, renseigné à la configuration de la boutique.
  static const _numeroMarchand = '70123456';

  ModePaiement? _mode;
  OperateurMobile _operateur = OperateurMobile.orange;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

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
                  teinte: OperateurMobile.orange.teinte,
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
            child: _mode == ModePaiement.mobileMoney
                ? _VoletMobileMoney(
                    total: widget.total,
                    numeroMarchand: _numeroMarchand,
                    operateur: _operateur,
                    surChangementOperateur: (o) =>
                        setState(() => _operateur = o),
                  )
                : const SizedBox(width: double.infinity),
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

class _VoletMobileMoney extends StatelessWidget {
  final Montant total;
  final String numeroMarchand;
  final OperateurMobile operateur;
  final ValueChanged<OperateurMobile> surChangementOperateur;

  const _VoletMobileMoney({
    required this.total,
    required this.numeroMarchand,
    required this.operateur,
    required this.surChangementOperateur,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final code = operateur.code(numero: numeroMarchand, montant: total);
    final url = operateur.urlComposeur(numero: numeroMarchand, montant: total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Espace.l),
        Row(
          children: [
            for (final o in OperateurMobile.tous) ...[
              Expanded(
                child: _PastilleOperateur(
                  operateur: o,
                  actif: o.nom == operateur.nom,
                  onPressed: () => surChangementOperateur(o),
                ),
              ),
              if (o != OperateurMobile.tous.last)
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
                      color: operateur.teinte,
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
                    color: operateur.teinte.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Rayon.s),
                  ),
                  child: Text(
                    code,
                    textAlign: TextAlign.center,
                    style: textes.titleLarge?.copyWith(
                      color: operateur.teinte,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _PointPulsant(),
            const SizedBox(width: Espace.s),
            Text('En attente du SMS de confirmation',
                style: textes.bodyMedium),
          ],
        ),
      ],
    );
  }
}

/// Point qui pulse doucement, pendant l'attente de la confirmation.
class _PointPulsant extends StatefulWidget {
  const _PointPulsant();

  @override
  State<_PointPulsant> createState() => _PointPulsantState();
}

class _PointPulsantState extends State<_PointPulsant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.25, end: 1).animate(_controleur),
        child: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: Couleurs.primaireVif,
            shape: BoxShape.circle,
          ),
        ),
      );
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
              ? operateur.teinte.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Rayon.s),
          border: Border.all(
            color: actif ? operateur.teinte : Couleurs.bordure,
            width: actif ? 2 : 1,
          ),
        ),
        child: Text(
          operateur.nom.split(' ').first,
          textAlign: TextAlign.center,
          style: textes.labelSmall?.copyWith(
            color: actif ? operateur.teinte : Couleurs.encreDouce,
            fontWeight: actif ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
