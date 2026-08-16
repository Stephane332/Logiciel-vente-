/// Sauvegarder et restaurer.
///
/// Les téléphones sont volés, cassés, reformatés. C'est la panne dont un
/// commerçant ne se relève pas : ses dettes clients sont dans l'appareil, et
/// personne ne rembourse une ardoise que plus personne ne peut montrer.
///
/// L'écran dit donc deux choses et pas une : faire une sauvegarde, et
/// **la sortir du téléphone**. Un fichier qui reste sur l'appareil disparaît
/// avec lui — c'est la moitié qu'on oublie, et c'est celle qui sauve.
library;

import 'package:flutter/material.dart';

import '../../donnees/depot.dart';
import '../../donnees/fichiers.dart';
import '../../donnees/parametres.dart';
import '../../donnees/sauvegarde.dart';
import '../../donnees/version.dart';
import '../theme/palette.dart';

class EcranSauvegardes extends StatefulWidget {
  /// Le dépôt porte déjà la base et le journal : la sauvegarde a besoin des
  /// trois, et les redemander séparément ouvrirait la porte à en passer un
  /// qui ne va pas avec les autres.
  final Depot depot;

  final String nomCommerce;

  /// Pour noter la date du jour où le fichier sort du téléphone. Facultatif :
  /// l'écran sait sauvegarder sans, et les tests n'ont pas à monter des
  /// réglages pour vérifier autre chose.
  final Parametres? parametres;

  const EcranSauvegardes({
    super.key,
    required this.depot,
    required this.nomCommerce,
    this.parametres,
  });

  /// Ouvre l'écran. Rend `true` si une restauration a eu lieu — auquel cas
  /// tout ce qui était affiché est périmé.
  static Future<bool> ouvrir(
    BuildContext context, {
    required Depot depot,
    required String nomCommerce,
    Parametres? parametres,
  }) async =>
      await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => EcranSauvegardes(
          depot: depot,
          nomCommerce: nomCommerce,
          parametres: parametres,
        ),
      )) ??
      false;

  @override
  State<EcranSauvegardes> createState() => _EcranSauvegardesState();
}

class _EcranSauvegardesState extends State<EcranSauvegardes> {
  late final _sauvegardes = Sauvegardes(
    widget.depot.base,
    widget.depot.journal,
    version: versionApplication,
  );

  List<FichierSauvegarde> _fichiers = const [];
  int _evenements = 0;
  bool _chargement = true;

  /// Vrai pendant une écriture ou une restauration : les deux prennent du
  /// temps sur un téléphone d'entrée de gamme, et il ne faut surtout pas
  /// pouvoir en lancer deux.
  bool _occupe = false;

  /// Vrai dès qu'une restauration a eu lieu : l'appelant doit tout relire.
  bool _restaure = false;

  @override
  void initState() {
    super.initState();
    _relire();
  }

  Future<void> _relire() async {
    final (fichiers, evenements) = await (
      sauvegardesLocales(),
      widget.depot.journal.tous(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _fichiers = fichiers;
      _evenements = evenements.length;
      _chargement = false;
    });
  }

  void _dire(String message, {bool alerte = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: alerte ? Couleurs.alerte : null,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: alerte ? 6 : 4),
      ));
  }

  Future<void> _sauvegarder({bool puisPartager = true}) async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      final contenu = await _sauvegardes.composer(nomCommerce: widget.nomCommerce);
      final nom = Sauvegardes.nomDeFichier(widget.nomCommerce);
      final chemin = await ecrireSauvegarde(nom, contenu);

      await _relire();
      if (puisPartager) {
        await partagerSauvegarde(chemin, texte: _messageDePartage);
        // Noté seulement quand le fichier est parti. Une sauvegarde restée sur
        // le téléphone disparaît avec lui : la compter éteindrait le rappel
        // sans rien protéger.
        await widget.parametres?.noterSauvegarde();
      }
      _dire('Sauvegarde faite · $_evenements écritures');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  String get _messageDePartage =>
      'Sauvegarde de ${widget.nomCommerce}. Garde ce fichier : '
      "c'est tout le carnet.";

  /// Restaure depuis un fichier posé sur le téléphone.
  Future<void> _restaurerDepuis(FichierSauvegarde fichier) =>
      _restaurerContenu(() => lireSauvegarde(fichier.chemin));

  /// Restaure depuis un fichier reçu de l'extérieur.
  Future<void> _restaurerDuDehors() => _restaurerContenu(choisirSauvegarde);

  Future<void> _restaurerContenu(Future<String?> Function() lire) async {
    if (_occupe) return;

    final contenu = await lire();
    if (contenu == null || contenu.isEmpty) return;

    final sauvegarde = Sauvegardes.ouvrir(contenu);
    if (sauvegarde == null) {
      _dire("Ce fichier n'est pas une sauvegarde de Carnet.", alerte: true);
      return;
    }

    if (!mounted) return;
    final confirme = await _confirmer(sauvegarde.apercu);
    if (confirme != true) return;

    setState(() => _occupe = true);
    try {
      final resultat = await _sauvegardes.restaurer(sauvegarde);
      if (!resultat.reussie) {
        _dire(resultat.motif!, alerte: true);
        return;
      }
      // Les projections ne sont pas dans le fichier : elles se refabriquent
      // à partir des événements qu'on vient d'écrire.
      await widget.depot.reconstruireProjections();
      _restaure = true;
      await _relire();
      _dire('Carnet restauré · ${resultat.evenementsRestaures} écritures');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Demande confirmation, en disant ce qui va disparaître.
  ///
  /// Une restauration écrase. C'est le seul geste de l'application qui
  /// détruit des données sans retour, donc le seul qui mérite un avertissement
  /// aussi net.
  Future<bool?> _confirmer(ApercuSauvegarde apercu) {
    final textes = Theme.of(context).textTheme;

    return showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Remplacer tout le carnet ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La sauvegarde porte ${apercu.nombreEvenements} écritures'
              '${apercu.dernierEvenement == null ? '' : ', '
                  'la dernière du ${_date(apercu.dernierEvenement!)}'}.',
              style: textes.bodyMedium,
            ),
            const SizedBox(height: Espace.m),
            Container(
              padding: const EdgeInsets.all(Espace.m),
              decoration: BoxDecoration(
                color: Couleurs.alerteClair,
                borderRadius: BorderRadius.circular(Rayon.m),
              ),
              child: Text(
                _evenements == 0
                    ? "Le carnet est vide : rien ne sera perdu."
                    : 'Les $_evenements écritures qui sont dans ce téléphone '
                        'seront effacées et remplacées. Fais une sauvegarde '
                        "d'abord si tu n'es pas sûr.",
                style: textes.bodyMedium,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Laisser comme ça'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Couleurs.alerte),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
  }

  Future<void> _supprimer(FichierSauvegarde fichier) async {
    await supprimerSauvegarde(fichier.chemin);
    await _relire();
  }

  static String _date(DateTime quand) =>
      '${_d(quand.day)}/${_d(quand.month)}/${quand.year} à '
      '${_d(quand.hour)}h${_d(quand.minute)}';

  static String _d(int valeur) => valeur < 10 ? '0$valeur' : '$valeur';

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (sorti, _) {
        if (!sorti) Navigator.of(context).pop(_restaure);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Sauvegarde')),
        body: _chargement
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(Espace.l),
                children: [
                  Text('Sortir le carnet du téléphone', style: textes.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    "Un téléphone se vole, se casse, se reformate. Tant que la "
                    "sauvegarde reste dedans, elle disparaît avec lui — "
                    "envoie-la ailleurs : WhatsApp, Bluetooth, carte mémoire.",
                    style: textes.labelSmall,
                  ),
                  const SizedBox(height: Espace.l),

                  FilledButton.icon(
                    onPressed: _occupe ? null : () => _sauvegarder(),
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    label: const Text('Sauvegarder et envoyer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Couleurs.primaire,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: Espace.s),
                  OutlinedButton.icon(
                    onPressed: _occupe ? null : () => _sauvegarder(puisPartager: false),
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: const Text('Garder seulement sur le téléphone'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),

                  const SizedBox(height: Espace.s),
                  Text(
                    _evenements == 0
                        ? "Rien à sauvegarder pour l'instant."
                        : '$_evenements écritures dans le carnet.',
                    style: textes.labelSmall,
                  ),

                  const SizedBox(height: Espace.xxl),
                  Text('Restaurer', style: textes.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    "Nouveau téléphone, ou carnet abîmé : reprends une "
                    "sauvegarde. Elle remplace tout ce qui est là.",
                    style: textes.labelSmall,
                  ),
                  const SizedBox(height: Espace.m),

                  if (choixDeFichierDisponible)
                    OutlinedButton.icon(
                      onPressed: _occupe ? null : _restaurerDuDehors,
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: const Text('Ouvrir un fichier reçu'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),

                  if (_fichiers.isNotEmpty) ...[
                    const SizedBox(height: Espace.l),
                    Text('Sur ce téléphone', style: textes.labelSmall),
                    const SizedBox(height: Espace.s),
                    for (final fichier in _fichiers)
                      _LigneFichier(
                        fichier: fichier,
                        quand: _date(fichier.ecritLe),
                        onRestaurer:
                            _occupe ? null : () => _restaurerDepuis(fichier),
                        onPartager: _occupe
                            ? null
                            : () => partagerSauvegarde(fichier.chemin,
                                texte: _messageDePartage),
                        onSupprimer: _occupe ? null : () => _supprimer(fichier),
                      ),
                  ],

                  const SizedBox(height: Espace.xxl),
                  Center(
                    child: Text(empreinteVersion,
                        style: textes.labelSmall
                            ?.copyWith(color: Couleurs.encreLegere)),
                  ),
                  const SizedBox(height: Espace.xl),
                ],
              ),
      ),
    );
  }
}

/// Une sauvegarde posée sur le téléphone, et ce qu'on peut en faire.
class _LigneFichier extends StatelessWidget {
  final FichierSauvegarde fichier;
  final String quand;
  final VoidCallback? onRestaurer;
  final VoidCallback? onPartager;
  final VoidCallback? onSupprimer;

  const _LigneFichier({
    required this.fichier,
    required this.quand,
    this.onRestaurer,
    this.onPartager,
    this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: Espace.s),
      padding: const EdgeInsets.fromLTRB(Espace.l, Espace.m, Espace.s, Espace.m),
      decoration: BoxDecoration(
        color: Couleurs.surface,
        borderRadius: BorderRadius.circular(Rayon.m),
        border: Border.all(color: Couleurs.bordure),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quand, style: textes.titleMedium),
                Text(fichier.taille, style: textes.labelSmall),
              ],
            ),
          ),
          IconButton(
            onPressed: onPartager,
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            tooltip: 'Envoyer',
            color: Couleurs.encreDouce,
          ),
          IconButton(
            onPressed: onSupprimer,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: 'Supprimer',
            color: Couleurs.encreDouce,
          ),
          TextButton(
            onPressed: onRestaurer,
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
  }
}
