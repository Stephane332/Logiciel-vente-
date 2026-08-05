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
import '../../donnees/parametres.dart';
import '../theme/palette.dart';

class EcranReglages extends StatefulWidget {
  final Parametres parametres;
  final Reglage reglage;

  const EcranReglages({
    super.key,
    required this.parametres,
    required this.reglage,
  });

  /// Ouvre les réglages et rend l'état enregistré en sortant.
  static Future<Reglage?> ouvrir(
    BuildContext context, {
    required Parametres parametres,
    required Reglage reglage,
  }) =>
      Navigator.of(context).push<Reglage>(MaterialPageRoute(
        builder: (_) =>
            EcranReglages(parametres: parametres, reglage: reglage),
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

  @override
  void dispose() {
    _nom.dispose();
    for (final champ in _numeros.values) {
      champ.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    await widget.parametres.definirNomCommerce(
      _nom.text.trim().isEmpty
          ? Parametres.nomCommerceParDefaut
          : _nom.text,
    );
    for (final (operateur, champ) in _numeros.entries.map((e) => (e.key, e.value))) {
      await widget.parametres.definirNumeroMarchand(operateur, champ.text);
    }

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

          const SizedBox(height: Espace.xl),
          FilledButton(
            onPressed: _enregistrer,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Enregistrer'),
          ),
          const SizedBox(height: Espace.xxl),
        ],
      ),
    );
  }
}
