/// Sauvegarder et restaurer.
///
/// Les téléphones sont volés, cassés, reformatés. C'est la panne dont un
/// commerçant ne se relève pas : ses dettes clients sont dans l'appareil, et
/// personne ne rembourse une ardoise que plus personne ne peut montrer.
///
/// L'écran dit donc deux choses et pas une : faire une sauvegarde, et
/// **la sortir du téléphone**. Un fichier qui reste sur l'appareil disparaît
/// avec lui — c'est la moitié qu'on oublie, et c'est celle qui sauve.
///
/// Le même fichier sert un troisième geste, et l'écran doit le séparer très
/// nettement des deux autres : **réunir** deux caisses de la même boutique.
/// Restaurer remplace tout ; réunir n'enlève rien. Une vendeuse qui se
/// tromperait de bouton effacerait sa journée, donc les deux gestes ne se
/// ressemblent ni par la place, ni par les mots, ni par la couleur.
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
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EcranSauvegardes(
            depot: depot,
            nomCommerce: nomCommerce,
            parametres: parametres,
          ),
        ),
      ) ??
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

  /// Vrai quand le téléphone ne dit pas ce qu'il a dans son dossier.
  ///
  /// Ça arrive — stockage plein, dossier perdu, permission retirée par une
  /// mise à jour du système, carte mémoire qui met dix secondes à répondre.
  /// L'écran doit alors s'afficher quand même : les boutons qui sortent le
  /// carnet du téléphone sont justement ceux dont on a le plus besoin ce
  /// jour-là. Rester sur un rond qui tourne, c'est fermer la porte de secours
  /// au moment où on y frappe.
  bool _listeIllisible = false;

  /// Au-delà, on n'attend plus le stockage et on affiche la page.
  static const _patience = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _relire();
  }

  Future<void> _relire() async {
    // On compte, on ne relit pas : l'écran n'affiche qu'un nombre, et tout
    // relire pour en connaître la longueur charge une année de ventes en
    // mémoire à chaque ouverture.
    final evenements = await widget.depot.journal.nombreDepuis(null);

    var fichiers = const <FichierSauvegarde>[];
    var illisible = false;
    try {
      fichiers = await sauvegardesLocales().timeout(_patience);
    } catch (_) {
      illisible = true;
    }

    if (!mounted) return;
    setState(() {
      _fichiers = fichiers;
      _evenements = evenements;
      _listeIllisible = illisible;
      _chargement = false;
    });
  }

  void _dire(String message, {bool alerte = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: alerte ? Couleurs.alerte : null,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: alerte ? 6 : 4),
        ),
      );
  }

  /// Demande un mot de passe. `null` si le commerçant renonce.
  Future<String?> _demanderMotDePasse({bool pourFermer = false}) {
    final saisie = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text(pourFermer ? 'Protéger la sauvegarde' : 'Mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pourFermer)
              const Text(
                "Le fichier ne sera lisible qu'avec ce mot de passe. "
                "Personne ne peut le retrouver à ta place — si tu l'oublies, "
                'cette sauvegarde est perdue.',
              )
            else
              const Text('Ce fichier est protégé.'),
            const SizedBox(height: Espace.m),
            TextField(
              controller: saisie,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
              onSubmitted: (valeur) =>
                  Navigator.of(contexte).pop(valeur.isEmpty ? null : valeur),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              contexte,
            ).pop(saisie.text.isEmpty ? null : saisie.text),
            child: Text(pourFermer ? 'Protéger' : 'Ouvrir'),
          ),
        ],
      ),
    );
  }

  Future<void> _sauvegarder({
    bool puisPartager = true,
    bool protegee = false,
  }) async {
    if (_occupe) return;

    String? motDePasse;
    if (protegee) {
      motDePasse = await _demanderMotDePasse(pourFermer: true);
      if (motDePasse == null || !mounted) return;
    }

    setState(() => _occupe = true);
    try {
      final contenu = await _sauvegardes.composer(
        nomCommerce: widget.nomCommerce,
        motDePasse: motDePasse,
      );
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

    // Un fichier scellé se reconnaît avant qu'on demande quoi que ce soit :
    // sinon l'écran croirait tenir une sauvegarde illisible et le dirait mal.
    final Sauvegarde? sauvegarde;
    if (Sauvegardes.estChiffree(contenu)) {
      if (!mounted) return;
      final motDePasse = await _demanderMotDePasse();
      if (motDePasse == null) return;

      sauvegarde = await Sauvegardes.ouvrirAvec(contenu, motDePasse);
      if (sauvegarde == null) {
        _dire(
          'Mot de passe refusé, ou fichier abîmé. Rien n’a été touché.',
          alerte: true,
        );
        return;
      }
    } else {
      sauvegarde = Sauvegardes.ouvrir(contenu);
      if (sauvegarde == null) {
        _dire("Ce fichier n'est pas une sauvegarde de Carnet.", alerte: true);
        return;
      }
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

  /// Réunit le carnet d'une autre caisse à celui-ci.
  ///
  /// Le chemin est le même que pour une restauration jusqu'à l'ouverture du
  /// fichier — c'est le même format — et tout diffère ensuite : la question
  /// posée, l'écriture, et ce qu'on dit à la fin.
  Future<void> _reunir() async {
    if (_occupe) return;

    final contenu = await choisirSauvegarde();
    if (contenu == null || contenu.isEmpty) return;

    final Sauvegarde? sauvegarde;
    if (Sauvegardes.estChiffree(contenu)) {
      if (!mounted) return;
      final motDePasse = await _demanderMotDePasse();
      if (motDePasse == null) return;

      sauvegarde = await Sauvegardes.ouvrirAvec(contenu, motDePasse);
      if (sauvegarde == null) {
        _dire(
          'Mot de passe refusé, ou fichier abîmé. Rien n’a été touché.',
          alerte: true,
        );
        return;
      }
    } else {
      sauvegarde = Sauvegardes.ouvrir(contenu);
      if (sauvegarde == null) {
        _dire("Ce fichier n'est pas une sauvegarde de Carnet.", alerte: true);
        return;
      }
    }

    if (!mounted) return;
    final confirme = await _confirmerReunion(sauvegarde.apercu);
    if (confirme != true) return;

    setState(() => _occupe = true);
    try {
      final resultat = await _sauvegardes.fusionner(sauvegarde);
      if (!resultat.reussie) {
        _dire(resultat.motif!, alerte: true);
        return;
      }

      if (resultat.rienDeNouveau) {
        _dire('Les deux caisses étaient déjà à jour. Rien à ajouter.');
        return;
      }

      await widget.depot.reconstruireProjections();
      // Tout ce que l'écran précédent affichait est périmé : il y a des
      // ventes, des clients et du stock en plus.
      _restaure = true;
      await _relire();
      _dire(
        'Caisses réunies · ${resultat.evenementsAjoutes} écritures '
        'reçues de ${resultat.caissesRecues.join(', ')}',
      );

      // Deux choses se disent à part, et plus fort qu'un bandeau qui passe :
      // ce sont les seules de cette page qui peuvent rendre un chiffre ou un
      // papier faux sans que personne ne s'en aperçoive.
      if (resultat.facturesEnDouble.isNotEmpty && mounted) {
        await _direLesFacturesEnDouble(resultat.facturesEnDouble);
      }
      if (resultat.decalageHorloge != null && mounted) {
        await _direLHeureFausse(resultat.decalageHorloge!);
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Demande confirmation, en disant ce qui va s'ajouter.
  ///
  /// Le contraire mot pour mot de [_confirmer] : ici rien ne disparaît, et
  /// c'est justement ce qu'il faut dire — sinon le commerçant hésite au même
  /// endroit qu'avec une restauration, et finit par ne rien faire.
  Future<bool?> _confirmerReunion(ApercuSauvegarde apercu) {
    final textes = Theme.of(context).textTheme;

    return showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Réunir les deux caisses ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Le fichier de l'autre caisse porte ${apercu.nombreEvenements} "
              'écritures'
              '${apercu.dernierEvenement == null ? '' : ', '
                        'la dernière du ${_date(apercu.dernierEvenement!)}'}.',
              style: textes.bodyMedium,
            ),
            const SizedBox(height: Espace.m),
            Container(
              padding: const EdgeInsets.all(Espace.m),
              decoration: BoxDecoration(
                color: Couleurs.accentClair,
                borderRadius: BorderRadius.circular(Rayon.m),
              ),
              child: Text(
                _evenements == 0
                    ? "Ce carnet est vide : il recevra tout."
                    : 'Rien ne sera effacé. Les $_evenements écritures qui '
                          'sont dans ce téléphone restent, et celles de '
                          "l'autre caisse s'y ajoutent.",
                style: textes.bodyMedium,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Pas maintenant'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(true),
            child: const Text('Réunir'),
          ),
        ],
      ),
    );
  }

  /// Dit que deux factures portent le même numéro.
  ///
  /// Le plus grave que cette page puisse annoncer : une série de factures
  /// doit être ascendante et ininterrompue, une référence par facture. Deux
  /// papiers sous le même numéro sont déjà partis chez des clients, et
  /// personne ne peut les rappeler. Il faut que le commerçant le sache le
  /// jour même, pas au contrôle.
  Future<void> _direLesFacturesEnDouble(List<String> references) {
    final combien = references.length;
    final liste = references.take(5).join(', ');

    return showDialog<void>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text(
          combien == 1
              ? 'Deux factures portent le même numéro'
              : '$combien numéros de facture sont pris deux fois',
        ),
        content: Text(
          '$liste${combien > 5 ? '…' : ''}\n\n'
          'Les deux caisses ont fait des factures chacune de son côté, et '
          'elles ont compté à partir de un toutes les deux. Un numéro de '
          "facture doit être unique : c'est la loi, et l'application ne peut "
          'pas renuméroter un papier déjà remis à un client.\n\n'
          "À partir de maintenant : qu'une seule caisse fasse les factures. "
          "Pour celles qui sont déjà sorties, il faut passer par une facture "
          "d'avoir.",
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(),
            style: FilledButton.styleFrom(backgroundColor: Couleurs.alerte),
            child: const Text("J'ai compris"),
          ),
        ],
      ),
    );
  }

  /// Dit que l'autre téléphone n'est pas à l'heure, et pourquoi ça compte.
  Future<void> _direLHeureFausse(Duration avance) {
    final heures = avance.inHours;
    final combien = heures >= 1
        ? '$heures heure${heures > 1 ? 's' : ''}'
        : '${avance.inMinutes} minutes';

    return showDialog<void>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text("L'autre téléphone n'est pas à l'heure"),
        content: Text(
          "Il avance d'environ $combien sur celui-ci.\n\n"
          'Les écritures ont bien été reçues, mais elles portent cette '
          "heure-là. Tant que les deux téléphones ne sont pas à la même "
          'heure, les journées se coupent au mauvais endroit et le stock '
          "peut se tromper. Règle l'heure des deux appareils.",
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(),
            child: const Text("J'ai compris"),
          ),
        ],
      ),
    );
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
                  Text(
                    'Sortir le carnet du téléphone',
                    style: textes.titleLarge,
                  ),
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
                  // Le fichier porte le nom, le téléphone et la dette de
                  // chaque client, et il part par WhatsApp. Le protéger n'est
                  // pas le défaut : un mot de passe oublié rend la sauvegarde
                  // définitivement illisible, et on échangerait une perte
                  // contre une autre. Le choix est donc offert, et expliqué.
                  OutlinedButton.icon(
                    onPressed: _occupe
                        ? null
                        : () => _sauvegarder(protegee: true),
                    icon: const Icon(Icons.lock_outline_rounded, size: 20),
                    label: const Text('Protéger par un mot de passe'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: Espace.s),
                  OutlinedButton.icon(
                    onPressed: _occupe
                        ? null
                        : () => _sauvegarder(puisPartager: false),
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

                  if (choixDeFichierDisponible) ...[
                    const SizedBox(height: Espace.xxl),
                    Text(
                      'Deux caisses, une boutique',
                      style: textes.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Deux vendeuses, deux téléphones : chacune encaisse de "
                      "son côté, même sans réseau. Réunis les deux carnets et "
                      "les deux téléphones auront les mêmes articles, les "
                      "mêmes ardoises et le même stock. Rien n'est effacé.",
                      style: textes.labelSmall,
                    ),
                    const SizedBox(height: Espace.m),
                    OutlinedButton.icon(
                      onPressed: _occupe ? null : _reunir,
                      icon: const Icon(Icons.merge_rounded, size: 20),
                      label: const Text("Réunir avec une autre caisse"),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],

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

                  if (_listeIllisible) ...[
                    const SizedBox(height: Espace.l),
                    Text(
                      "Je n'arrive pas à lire les sauvegardes déjà posées sur "
                      'ce téléphone. Tout le reste marche : tu peux toujours '
                      'faire une sauvegarde et la partager.',
                      style: textes.labelSmall,
                    ),
                  ],

                  if (_fichiers.isNotEmpty) ...[
                    const SizedBox(height: Espace.l),
                    Text('Sur ce téléphone', style: textes.labelSmall),
                    const SizedBox(height: Espace.s),
                    for (final fichier in _fichiers)
                      _LigneFichier(
                        fichier: fichier,
                        quand: _date(fichier.ecritLe),
                        onRestaurer: _occupe
                            ? null
                            : () => _restaurerDepuis(fichier),
                        onPartager: _occupe
                            ? null
                            : () => partagerSauvegarde(
                                fichier.chemin,
                                texte: _messageDePartage,
                              ),
                        onSupprimer: _occupe ? null : () => _supprimer(fichier),
                      ),
                  ],

                  const SizedBox(height: Espace.xxl),
                  Center(
                    child: Text(
                      empreinteVersion,
                      style: textes.labelSmall?.copyWith(
                        color: Couleurs.encreLegere,
                      ),
                    ),
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
      padding: const EdgeInsets.fromLTRB(
        Espace.l,
        Espace.m,
        Espace.s,
        Espace.m,
      ),
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
          TextButton(onPressed: onRestaurer, child: const Text('Restaurer')),
        ],
      ),
    );
  }
}
