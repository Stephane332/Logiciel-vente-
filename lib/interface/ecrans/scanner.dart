/// Lire un code-barres avec l'appareil photo.
///
/// Rend le code lu, ou `null` si le commerçant renonce. L'écran ne décide de
/// rien : ce qu'on fait du code — retrouver l'article ou en créer un — se
/// décide à la caisse, qui est le seul endroit à savoir ce qu'il y a au
/// panier.
///
/// Une limite à connaître avant de le vendre : ça suppose des produits
/// emballés et codés. Le riz au détail, le charbon, les beignets, le tissu au
/// mètre n'ont pas de code-barres, et c'est l'essentiel de ce qui se vend dans
/// une boutique de quartier. Le scanner est un confort pour l'alimentation
/// générale bien achalandée, jamais un passage obligé — c'est pourquoi la
/// caisse marche entièrement sans lui.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/palette.dart';

class EcranScanner extends StatefulWidget {
  const EcranScanner({super.key});

  /// Ouvre le scanner. Rend le code lu, ou `null`.
  static Future<String?> lire(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => const EcranScanner(),
        fullscreenDialog: true,
      ));

  @override
  State<EcranScanner> createState() => _EcranScannerState();
}

class _EcranScannerState extends State<EcranScanner> {
  final _controleur = MobileScannerController(
    // Un seul code à la fois : dès qu'on en tient un, on referme. Sans ça le
    // même code part dix fois pendant que l'écran se referme.
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
  );

  /// Vrai dès qu'un code est parti : le second serait lu après le `pop`.
  bool _rendu = false;

  /// Ce qui empêche de scanner, quand ça arrive. L'appareil photo peut être
  /// refusé, absent, ou déjà pris par une autre application.
  String? _empechement;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _surDetection(BarcodeCapture capture) {
    if (_rendu) return;
    final valeur = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (valeur == null) return;

    _rendu = true;
    Navigator.of(context).pop(valeur.trim());
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner un article'),
        actions: [
          IconButton(
            onPressed: () => _controleur.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
            // Une boutique est rarement éclairée, et un code-barres mat dans
            // la pénombre ne se lit pas.
            tooltip: 'Lampe',
          ),
        ],
      ),
      body: _empechement != null
          ? _Empechement(motif: _empechement!)
          : Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controleur,
                  onDetect: _surDetection,
                  errorBuilder: (context, erreur) =>
                      _Empechement(motif: _motifDe(erreur)),
                ),
                // Une mire, pour que le commerçant sache où viser. Sans elle
                // il promène le téléphone au hasard au-dessus du sachet.
                Center(
                  child: Container(
                    width: 240,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(Rayon.m),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(Espace.xl),
                    child: Text(
                      'Vise le code-barres du produit.',
                      textAlign: TextAlign.center,
                      style: textes.bodyMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static String _motifDe(MobileScannerException erreur) =>
      switch (erreur.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          "L'application n'a pas l'autorisation d'utiliser l'appareil photo. "
              'Elle se trouve dans les réglages du téléphone.',
        MobileScannerErrorCode.unsupported =>
          "Ce téléphone ne sait pas scanner. Tape le montant à la main : "
              "c'est ce que fait la caisse depuis toujours.",
        _ => "L'appareil photo ne répond pas. Il est peut-être utilisé par "
            'une autre application.',
      };
}

/// Ce qu'on montre quand la caméra ne peut pas servir.
///
/// Jamais un écran vide ni un message d'erreur technique : le commerçant a un
/// client devant lui, il lui faut la sortie, pas le diagnostic.
class _Empechement extends StatelessWidget {
  final String motif;

  const _Empechement({required this.motif});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      color: Couleurs.fond,
      padding: const EdgeInsets.all(Espace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography_outlined,
              size: 44, color: Couleurs.encreLegere),
          const SizedBox(height: Espace.l),
          Text(motif, textAlign: TextAlign.center, style: textes.bodyMedium),
          const SizedBox(height: Espace.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Revenir à la caisse'),
          ),
        ],
      ),
    );
  }
}
