/// Les réglages de la boutique.
///
/// Deux choses seulement : le nom qui s'imprime en tête des documents, et les
/// numéros sur lesquels le commerçant veut être payé. Tout le reste attend
/// d'être réellement demandé sur le terrain.
///
/// Rien n'est obligatoire. L'application encaisse sans qu'on soit passé par
/// ici — c'est la règle à laquelle je ne touche pas.
library;

import 'package:flutter/material.dart';

import '../../domaine/mobile_money.dart';
import '../../domaine/telephone.dart';
import '../../donnees/depot.dart';
import '../../donnees/parametres.dart';
import '../../donnees/version.dart';
import '../theme/palette.dart';
import 'sauvegardes.dart';

class EcranReglages extends StatefulWidget {
  final Parametres parametres;
  final Reglage reglage;

  /// Sert à la sauvegarde, qui a besoin du journal et de la base.
  final Depot depot;

  const EcranReglages({
    super.key,
    required this.parametres,
    required this.reglage,
    required this.depot,
  });

  /// Ouvre les réglages et rend l'état enregistré en sortant.
  static Future<Reglage?> ouvrir(
    BuildContext context, {
    required Parametres parametres,
    required Reglage reglage,
    required Depot depot,
  }) =>
      Navigator.of(context).push<Reglage>(MaterialPageRoute(
        builder: (_) => EcranReglages(
          parametres: parametres,
          reglage: reglage,
          depot: depot,
        ),
      ));

  @override
  State<EcranReglages> createState() => _EcranReglagesState();
}

class _EcranReglagesState extends State<EcranReglages> {
  late final _nom =
      TextEditingController(text: widget.reglage.nomCommerce);

  late final _numeros = {
    for (final operateur in OperateurMobile.values)
      operateur: TextEditingController(
        text: presenterTelephone(widget.reglage.comptes.numeroDe(operateur)),
      ),
  };

  /// L'équipe en cours d'édition. Copiée pour que « Annuler » veuille encore
  /// dire quelque chose : rien n'est écrit avant l'appui sur Enregistrer.
  late final _vendeurs = [...widget.reglage.vendeurs];

  final _nouveauVendeur = TextEditingController();

  @override
  void dispose() {
    _nom.dispose();
    _nouveauVendeur.dispose();
    for (final champ in _numeros.values) {
      champ.dispose();
    }
    super.dispose();
  }

  void _ajouterVendeur() {
    final nom = _nouveauVendeur.text.trim();
    if (nom.isEmpty || _vendeurs.contains(nom)) {
      _nouveauVendeur.clear();
      return;
    }
    setState(() {
      _vendeurs.add(nom);
      _nouveauVendeur.clear();
    });
  }

  /// Passe à la sauvegarde, en gardant d'abord ce qui est tapé ici.
  ///
  /// Sans ça, un nom d'équipe saisi mais pas encore enregistré ne serait pas
  /// dans le fichier — et le commerçant croirait l'avoir sauvegardé.
  Future<void> _ouvrirSauvegardes() async {
    await _ecrireReglages();
    if (!mounted) return;

    final restaure = await EcranSauvegardes.ouvrir(
      context,
      depot: widget.depot,
      nomCommerce: _nom.text.trim().isEmpty
          ? Parametres.nomCommerceParDefaut
          : _nom.text.trim(),
    );
    if (!restaure || !mounted) return;

    // La restauration a remplacé les réglages : ce qui est à l'écran est
    // périmé, et le garder écraserait ce qu'on vient de restaurer.
    Navigator.of(context).pop(await widget.parametres.tout());
  }

  /// Écrit ce qui est à l'écran, sans quitter.
  Future<void> _ecrireReglages() async {
    await widget.parametres.definirNomCommerce(
      _nom.text.trim().isEmpty
          ? Parametres.nomCommerceParDefaut
          : _nom.text,
    );
    if (await _numerosAutorises()) {
      for (final (operateur, champ)
          in _numeros.entries.map((e) => (e.key, e.value))) {
        await widget.parametres.definirNumeroMarchand(operateur, champ.text);
      }
    }
    // Un nom tapé mais pas encore ajouté d'un appui compte quand même :
    // sinon il disparaît en silence et le commerçant croit l'avoir perdu.
    _ajouterVendeur();
    await widget.parametres.definirVendeurs(_vendeurs);
  }

  /// Vrai si les numéros marchands peuvent être écrits.
  ///
  /// C'est le seul réglage qui déplace de l'argent : un caissier qui y met le
  /// sien détourne tous les paiements mobile money, et ça ne se remarque qu'au
  /// moment où les SMS cessent d'arriver — ou jamais.
  ///
  /// Le code n'est demandé que dans deux conditions réunies : **un numéro a
  /// changé**, et **une équipe est déclarée**. Un commerçant seul n'a personne
  /// contre qui se protéger, et lui imposer un code serait une porte fermée
  /// sur une maison vide.
  Future<bool> _numerosAutorises() async {
    if (!_numerosModifies) return true;
    if (_vendeurs.isEmpty && widget.reglage.vendeurs.isEmpty) return true;

    final pose = await widget.parametres.codePatronPose();
    if (!mounted) return false;

    if (!pose) {
      final choisi = await _demanderCode(
        titre: 'Protéger les numéros',
        explication: "Tu déclares une équipe. Choisis un code à quatre "
            "chiffres : il sera demandé pour changer un numéro marchand. "
            "Sans lui, n'importe qui derrière le comptoir peut faire payer "
            "sur son propre compte.",
        valider: 'Choisir ce code',
      );
      if (choisi == null || !mounted) return false;
      await widget.parametres.definirCodePatron(choisi);
      return true;
    }

    final propose = await _demanderCode(
      titre: 'Code du patron',
      explication: 'Un numéro marchand a changé.',
      valider: 'Confirmer',
    );
    if (propose == null || !mounted) return false;

    if (await widget.parametres.codePatronJuste(propose)) return true;
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("Code refusé. Les numéros n'ont pas été changés."),
        ));
    }
    return false;
  }

  /// Vrai si un numéro à l'écran diffère de celui qui est enregistré.
  bool get _numerosModifies {
    for (final entree in _numeros.entries) {
      final avant = widget.reglage.comptes.numeroDe(entree.key) ?? '';
      if (normaliserTelephone(entree.value.text) != normaliserTelephone(avant)) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _demanderCode({
    required String titre,
    required String explication,
    required String valider,
  }) {
    final saisie = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explication),
            const SizedBox(height: Espace.m),
            TextField(
              controller: saisie,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final code = saisie.text.trim();
              Navigator.of(contexte).pop(code.length >= 4 ? code : null);
            },
            child: Text(valider),
          ),
        ],
      ),
    );
  }

  Future<void> _enregistrer() async {
    await _ecrireReglages();

    final enregistre = await widget.parametres.tout();
    if (!mounted) return;
    Navigator.of(context).pop(enregistre);
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(Espace.l),
        children: [
          Text('Ma boutique', style: textes.titleLarge),
          const SizedBox(height: 2),
          Text("Le nom qui apparaît en tête des reçus et des ardoises.",
              style: textes.labelSmall),
          const SizedBox(height: Espace.m),
          TextField(
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: Parametres.nomCommerceParDefaut,
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),

          const SizedBox(height: Espace.xxl),
          Text('Se faire payer par téléphone', style: textes.titleLarge),
          const SizedBox(height: 2),
          Text(
            "Le numéro de ton compte marchand, chez chaque opérateur où tu en "
            "as un. Laisse vide ceux que tu n'utilises pas.",
            style: textes.labelSmall,
          ),
          const SizedBox(height: Espace.m),

          for (final operateur in OperateurMobile.values) ...[
            TextField(
              controller: _numeros[operateur],
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: operateur.nom,
                hintText: '70 00 00 00',
                prefixIcon: const Icon(Icons.smartphone_rounded),
              ),
            ),
            const SizedBox(height: Espace.m),
          ],

          const SizedBox(height: Espace.s),
          Container(
            padding: const EdgeInsets.all(Espace.m),
            decoration: BoxDecoration(
              color: Couleurs.alerteClair,
              borderRadius: BorderRadius.circular(Rayon.m),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 18, color: Couleurs.alerte),
                const SizedBox(width: Espace.s),
                Expanded(
                  child: Text(
                    "Il faut un compte marchand, pas un compte ordinaire : "
                    "sinon l'opérateur te prélève les frais de transfert entre "
                    "particuliers sur chaque vente.",
                    style: textes.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Espace.xxl),
          Text('Qui tient la caisse', style: textes.titleLarge),
          const SizedBox(height: 2),
          Text(
            "Laisse vide si tu vends seul. Dès que tu ajoutes quelqu'un, "
            "chaque vente retient qui l'a encaissée, et le rapport te dit "
            "qui a fait combien.",
            style: textes.labelSmall,
          ),
          const SizedBox(height: Espace.m),

          if (_vendeurs.isNotEmpty) ...[
            Wrap(
              spacing: Espace.s,
              runSpacing: Espace.s,
              children: [
                for (final nom in _vendeurs)
                  InputChip(
                    label: Text(nom),
                    onDeleted: () => setState(() => _vendeurs.remove(nom)),
                    deleteIcon: const Icon(Icons.close_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: Espace.m),
          ],

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nouveauVendeur,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _ajouterVendeur(),
                  decoration: const InputDecoration(
                    hintText: 'Nom du vendeur',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
              ),
              const SizedBox(width: Espace.s),
              IconButton.filledTonal(
                onPressed: _ajouterVendeur,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Ajouter',
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(cibleTactile),
                  backgroundColor: Couleurs.primaireClair,
                  foregroundColor: Couleurs.primaire,
                ),
              ),
            ],
          ),

          const SizedBox(height: Espace.xxl),
          Text('Sauvegarde', style: textes.titleLarge),
          const SizedBox(height: 2),
          Text(
            "Un téléphone se vole et se casse. Sans sauvegarde sortie de "
            "l'appareil, tout part avec lui — les ventes, et surtout les "
            "dettes que tes clients te doivent.",
            style: textes.labelSmall,
          ),
          const SizedBox(height: Espace.m),
          OutlinedButton.icon(
            onPressed: _ouvrirSauvegardes,
            icon: const Icon(Icons.backup_outlined, size: 20),
            label: const Text('Sauvegarder ou restaurer'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),

          const SizedBox(height: Espace.xl),
          FilledButton(
            onPressed: _enregistrer,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Enregistrer'),
          ),

          const SizedBox(height: Espace.xl),
          Center(
            child: Text(
              empreinteVersion,
              style:
                  textes.labelSmall?.copyWith(color: Couleurs.encreLegere),
            ),
          ),
          const SizedBox(height: Espace.xxl),
        ],
      ),
    );
  }
}
