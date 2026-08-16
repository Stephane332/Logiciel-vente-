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

import '../../domaine/fiche_entreprise.dart';
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

  /// Les mentions de la fiche entreprise, une par champ.
  late final _raisonSociale =
      TextEditingController(text: widget.reglage.fiche.raisonSociale ?? '');
  late final _ifu = TextEditingController(text: widget.reglage.fiche.ifu ?? '');
  late final _cadastre = TextEditingController(
      text: widget.reglage.fiche.cadastre?.lisible ?? '');
  late final _adresse =
      TextEditingController(text: widget.reglage.fiche.adresse ?? '');
  late final _contact =
      TextEditingController(text: widget.reglage.fiche.telephone ?? '');
  late final _courriel =
      TextEditingController(text: widget.reglage.fiche.courriel ?? '');
  late final _serviceImpots =
      TextEditingController(text: widget.reglage.fiche.serviceImpots ?? '');
  late final _banque = TextEditingController(
      text: widget.reglage.fiche.referencesBancaires ?? '');
  late RegimeImposition? _regime = widget.reglage.fiche.regime;

  /// Ce qui cloche dans les deux champs dont la forme est imposée. Affiché
  /// sous le champ, jamais en dialogue : un reproche modal sur un formulaire
  /// facultatif serait hors de proportion.
  String? _defautIfu;
  String? _defautCadastre;

  @override
  void dispose() {
    _nom.dispose();
    _nouveauVendeur.dispose();
    for (final champ in _numeros.values) {
      champ.dispose();
    }
    for (final champ in [
      _raisonSociale,
      _ifu,
      _cadastre,
      _adresse,
      _contact,
      _courriel,
      _serviceImpots,
      _banque,
    ]) {
      champ.dispose();
    }
    super.dispose();
  }

  /// La fiche telle qu'elle est à l'écran en ce moment.
  FicheEntreprise get _ficheSaisie => FicheEntreprise(
        nomCommercial: _nom.text.trim().isEmpty
            ? Parametres.nomCommerceParDefaut
            : _nom.text.trim(),
        raisonSociale: _raisonSociale.text,
        ifu: Ifu.normaliser(_ifu.text),
        cadastre: ReferenceCadastrale.analyser(_cadastre.text),
        adresse: _adresse.text,
        telephone: _contact.text,
        courriel: _courriel.text,
        regime: _regime,
        serviceImpots: _serviceImpots.text,
        referencesBancaires: _banque.text,
      );

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
  ///
  /// La fiche entreprise emporte le nom du commerce : les deux ne doivent
  /// jamais diverger, sinon la facture et le reçu ne portent pas la même
  /// enseigne.
  Future<void> _ecrireReglages() async {
    await widget.parametres.definirFiche(_ficheSaisie);
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

  /// Vrai quand les deux champs à forme imposée sont bons — ou vides.
  ///
  /// Un IFU mal recopié serait sinon rangé à moitié : refusé en silence par
  /// la couche de données, et le commerçant croirait l'avoir enregistré
  /// jusqu'au jour où sa facture partirait sans.
  bool _ficheAcceptable() {
    final ifu = Ifu.defaut(_ifu.text);
    final cadastre = ReferenceCadastrale.defaut(_cadastre.text);

    setState(() {
      _defautIfu = ifu;
      _defautCadastre = cadastre;
    });

    return ifu == null && cadastre == null;
  }

  Future<void> _enregistrer() async {
    if (!_ficheAcceptable()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Corrige ce qui est signalé dans la fiche entreprise.'),
        ));
      return;
    }

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
          _FicheEntrepriseSection(
            depliee: widget.reglage.fiche.renseignee,
            raisonSociale: _raisonSociale,
            ifu: _ifu,
            defautIfu: _defautIfu,
            cadastre: _cadastre,
            defautCadastre: _defautCadastre,
            adresse: _adresse,
            contact: _contact,
            courriel: _courriel,
            serviceImpots: _serviceImpots,
            banque: _banque,
            regime: _regime,
            surRegime: (choisi) => setState(() => _regime = choisi),
            fiche: _ficheSaisie,
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

/// La fiche entreprise, repliée tant qu'elle est vide.
///
/// C'est le seul endroit de l'application qui ressemble à un formulaire
/// d'administration, et c'est pour ça qu'il est replié : la boutique de
/// quartier qui n'aura jamais d'IFU ne doit pas tomber dessus en cherchant
/// comment changer le nom de son commerce. Celle qui en a un le voit ouvert,
/// parce qu'elle y revient.
class _FicheEntrepriseSection extends StatelessWidget {
  final bool depliee;
  final TextEditingController raisonSociale;
  final TextEditingController ifu;
  final String? defautIfu;
  final TextEditingController cadastre;
  final String? defautCadastre;
  final TextEditingController adresse;
  final TextEditingController contact;
  final TextEditingController courriel;
  final TextEditingController serviceImpots;
  final TextEditingController banque;
  final RegimeImposition? regime;
  final ValueChanged<RegimeImposition?> surRegime;
  final FicheEntreprise fiche;

  const _FicheEntrepriseSection({
    required this.depliee,
    required this.raisonSociale,
    required this.ifu,
    required this.defautIfu,
    required this.cadastre,
    required this.defautCadastre,
    required this.adresse,
    required this.contact,
    required this.courriel,
    required this.serviceImpots,
    required this.banque,
    required this.regime,
    required this.surRegime,
    required this.fiche,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Theme(
      // Le trait de séparation par défaut d'un ExpansionTile coupe la page en
      // deux et fait croire à une fin de contenu.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: depliee,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: Espace.m),
        title: Text('Ma fiche entreprise', style: textes.titleLarge),
        subtitle: Text(
          "Pour facturer une entreprise, l'État, ou une ONG. Inutile pour "
          'vendre au comptoir — laisse fermé.',
          style: textes.labelSmall,
        ),
        children: [
          TextField(
            controller: raisonSociale,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Raison sociale',
              helperText: "Le nom légal, s'il diffère de l'enseigne.",
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: ifu,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'IFU',
              hintText: '00012345A',
              helperText: "Sur l'attestation d'immatriculation fiscale.",
              errorText: defautIfu,
              prefixIcon: const Icon(Icons.numbers_rounded),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: adresse,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Adresse de vente',
              hintText: 'Quartier, ville',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: cadastre,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Références cadastrales',
              hintText: '1234 567 8901',
              helperText: 'Onze chiffres : section, lot, parcelle.',
              errorText: defautCadastre,
              prefixIcon: const Icon(Icons.map_outlined),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: contact,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: "Téléphone de l'entreprise",
              prefixIcon: Icon(Icons.call_outlined),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: courriel,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Adresse électronique',
              prefixIcon: Icon(Icons.mail_outlined),
            ),
          ),
          const SizedBox(height: Espace.m),
          DropdownButtonFormField<RegimeImposition?>(
            initialValue: regime,
            decoration: const InputDecoration(
              labelText: "Régime d'imposition",
              prefixIcon: Icon(Icons.account_balance_outlined),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Je ne sais pas')),
              for (final choix in RegimeImposition.values)
                DropdownMenuItem(
                  value: choix,
                  child: Text('${choix.etiquette} — ${choix.libelle}'),
                ),
            ],
            onChanged: surRegime,
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: serviceImpots,
            decoration: const InputDecoration(
              labelText: 'Service des impôts de rattachement',
              hintText: 'DME Ouaga 1',
              prefixIcon: Icon(Icons.apartment_outlined),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: banque,
            decoration: const InputDecoration(
              labelText: 'Références bancaires',
              hintText: 'Banque et numéro de compte',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: Espace.l),
          _EtatDeLaFiche(fiche: fiche),
        ],
      ),
    );
  }
}

/// Ce qui manque à la fiche, et ce qui manque encore après elle.
///
/// Le second point est celui que je tiens à ne pas laisser dans l'ombre : une
/// fiche complète ne fait pas une facture certifiée. Il y faut un module de
/// contrôle, et il ne sort pas d'un formulaire. Laisser croire l'inverse
/// serait la seule vraie faute ici.
class _EtatDeLaFiche extends StatelessWidget {
  final FicheEntreprise fiche;

  const _EtatDeLaFiche({required this.fiche});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final manques = fiche.manques;

    return Container(
      padding: const EdgeInsets.all(Espace.m),
      decoration: BoxDecoration(
        color: manques.isEmpty ? Couleurs.primaireClair : Couleurs.accentClair,
        borderRadius: BorderRadius.circular(Rayon.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                manques.isEmpty
                    ? Icons.check_circle_outline_rounded
                    : Icons.pending_outlined,
                size: 18,
                color: manques.isEmpty ? Couleurs.primaire : Couleurs.accent,
              ),
              const SizedBox(width: Espace.s),
              Expanded(
                child: Text(
                  manques.isEmpty
                      ? 'Ta fiche est complète.'
                      : 'Il manque ${manques.length} mention'
                          '${manques.length > 1 ? 's' : ''} pour facturer.',
                  style: textes.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (manques.isNotEmpty) ...[
            const SizedBox(height: Espace.s),
            for (final manque in manques)
              Padding(
                padding: const EdgeInsets.only(bottom: Espace.xs),
                child: Text('· ${manque.quoi} — ${manque.pourquoi}',
                    style: textes.labelSmall),
              ),
          ],
          const SizedBox(height: Espace.s),
          Text(
            fiche.regime?.certificationObligatoire == true
                ? "Au Régime Normal, la facture électronique certifiée est "
                    "obligatoire. Elle demande en plus un module de contrôle "
                    "agréé, qui ne se règle pas depuis cet écran."
                : "Ces mentions préparent la facture certifiée. Elles ne "
                    "suffisent pas à elles seules : il y faut aussi un module "
                    "de contrôle agréé.",
            style: textes.labelSmall,
          ),
        ],
      ),
    );
  }
}
