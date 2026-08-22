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
import '../../domaine/telephone.dart';
import '../../domaine/texte.dart';
import '../../donnees/base.dart';
import '../composants/montant_anime.dart';
import '../composants/partage.dart';
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

  /// Nom de la boutique, tel qu'il apparaît dans le message envoyé au client.
  final String nomCommerce;

  /// Les clients connus, pour retrouver celui à qui l'on fait crédit.
  final List<LigneClient> clients;

  /// Crée un client à la volée et rend son identifiant.
  final Future<String> Function(String nom, String? telephone)? surNouveauClient;

  /// Appelé avec le mode retenu et, s'il y a crédit, le client concerné.
  final Future<void> Function(ModePaiement mode, String? clientId)
      surPaiementChoisi;

  /// Ouvre les réglages. Nul quand il n'y a nulle part où aller — en test,
  /// par exemple.
  final VoidCallback? surConfiguration;

  const FeuillePaiement({
    super.key,
    required this.total,
    required this.surPaiementChoisi,
    this.comptes = const ComptesMarchands.aucun(),
    this.nomCommerce = '',
    this.surConfiguration,
    this.clients = const [],
    this.surNouveauClient,
  });

  static Future<void> presenter(
    BuildContext context, {
    required Montant total,
    required Future<void> Function(ModePaiement mode, String? clientId)
        surPaiementChoisi,
    ComptesMarchands comptes = const ComptesMarchands.aucun(),
    String nomCommerce = '',
    VoidCallback? surConfiguration,
    List<LigneClient> clients = const [],
    Future<String> Function(String nom, String? telephone)? surNouveauClient,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FeuillePaiement(
          total: total,
          comptes: comptes,
          nomCommerce: nomCommerce,
          surPaiementChoisi: surPaiementChoisi,
          surConfiguration: surConfiguration,
          clients: clients,
          surNouveauClient: surNouveauClient,
        ),
      );

  @override
  State<FeuillePaiement> createState() => _FeuillePaiementState();
}

class _FeuillePaiementState extends State<FeuillePaiement> {
  ModePaiement? _mode;
  OperateurMobile? _operateur;

  /// À qui l'on fait crédit. Une dette sans nom n'est pas une dette : c'est
  /// de l'argent perdu, et c'est ce que fait le cahier papier quand on
  /// oublie d'écrire.
  LigneClient? _client;

  /// La liste des clients, enrichie de ceux créés sans quitter la feuille.
  late List<LigneClient> _clients = widget.clients;

  @override
  void initState() {
    super.initState();
    _operateur = widget.comptes.disponibles.firstOrNull;
  }

  /// Une vente à crédit n'est validable qu'une fois qu'on sait à qui.
  bool get _pretAValider =>
      _mode != null && (_mode != ModePaiement.credit || _client != null);

  String get _libelleValidation => switch (_mode) {
        null => 'Choisir un mode',
        ModePaiement.credit when _client == null => 'À qui ?',
        ModePaiement.credit => 'Noter la dette',
        _ => 'Valider la vente',
      };

  /// Envoie le lien de paiement au client, par WhatsApp ou par SMS.
  ///
  /// C'est le repli du code QR : un client dont le téléphone n'a pas
  /// d'appareil photo, ou qui n'est pas devant le comptoir — une livraison,
  /// une commande passée par message.
  ///
  /// Le lien `tel:` ouvre le composeur du client **déjà rempli** : il n'a plus
  /// qu'à saisir son code secret. C'est le geste principal, donc il passe en
  /// premier dans le message.
  ///
  /// Le code brut suit quand même, parce qu'un lien `tel:` n'est pas cliquable
  /// dans toutes les messageries. Au pire le client recopie quelques
  /// caractères : je préfère un repli qui marche partout à un lien élégant qui
  /// échoue chez la moitié des gens.
  Future<void> _envoyerLeCode(OperateurMobile operateur) async {
    final numero = widget.comptes.numeroDe(operateur)!;
    final code = operateur.code(numero: numero, montant: widget.total);
    final lien = operateur.lienComposeur(numero: numero, montant: widget.total);
    final montant = widget.total.enFrancs;

    final complet = [
      if (widget.nomCommerce.isNotEmpty) widget.nomCommerce.toUpperCase(),
      'À payer : $montant',
      '',
      "Appuie sur ce lien : ton téléphone compose tout seul, tu n'as plus "
          "qu'à saisir ton code secret.",
      lien,
      '',
      "Si le lien ne s'ouvre pas, compose :",
      code,
    ].join('\n');

    // Le SMS se paie à l'unité : on le veut court et sans accent, sinon la
    // limite tombe de 160 à 70 caractères et le même message coûte trois fois
    // plus cher au commerçant.
    final court = sansAccents([
      if (widget.nomCommerce.isNotEmpty) widget.nomCommerce.toUpperCase(),
      'A payer: $montant',
      'Appuie: $lien',
      'Sinon compose: $code',
    ].join('\n'));

    await FeuilleDocument.presenter(
      context,
      titre: 'Envoyer au client',
      texte: complet,
      texteSms: court,
      telephone: _client?.telephoneNormalise,
    );
  }

  Future<void> _nouveauClient() async {
    final creer = widget.surNouveauClient;
    if (creer == null) return;

    final saisie = await _FeuilleNouveauClient.demander(context);
    if (saisie == null) return;

    final id = await creer(saisie.nom, saisie.telephone);
    if (!mounted) return;

    final nouveau = LigneClient(
      id: id,
      nom: saisie.nom,
      telephone: saisie.telephone,
      telephoneNormalise: normaliserTelephone(saisie.telephone),
      typeClient: TypeClient.comptant.etiquette,
      encoursCentimes: 0,
    );

    setState(() {
      _client = nouveau;
      // Sans ça, la feuille continuerait d'annoncer « personne dans ton
      // cahier » juste après y avoir ajouté quelqu'un.
      _clients = [nouveau, ..._clients];
    });
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
                  surEnvoi: () => _envoyerLeCode(operateur),
                ),
              (ModePaiement.credit, _) => _VoletCredit(
                  clients: _clients,
                  choisi: _client,
                  surChoix: (client) => setState(() => _client = client),
                  surNouveau: _nouveauClient,
                ),
              _ => const SizedBox(width: double.infinity),
            },
          ),

          const SizedBox(height: Espace.xl),
          FilledButton(
            onPressed: _pretAValider
                ? () async {
                    final mode = _mode!;
                    final navigateur = Navigator.of(context);
                    await widget.surPaiementChoisi(mode, _client?.id);
                    navigateur.pop();
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
            ),
            child: Text(
              _libelleValidation,
              style: textes.labelLarge?.copyWith(
                fontSize: 17,
                color: _pretAValider ? Colors.white : Couleurs.encreLegere,
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

  /// Envoie le code au client, quand il ne peut pas scanner.
  final VoidCallback surEnvoi;

  const _VoletMobileMoney({
    required this.total,
    required this.numeroMarchand,
    required this.operateur,
    required this.disponibles,
    required this.surChangementOperateur,
    required this.surEnvoi,
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
              // Le numéro qui va être payé, en clair.
              //
              // Sans lui, le commerçant voit un code QR et une suite de
              // chiffres sans savoir vers quel compte ça part. Un caissier qui
              // remplace le numéro dans les réglages détournerait tous les
              // paiements sans que rien ne se voie — et ça ne se remarquerait
              // qu'au moment où les SMS cessent d'arriver, ou jamais.
              Text(
                'Vers ${presenterTelephone(numeroMarchand)}',
                style: textes.labelSmall?.copyWith(
                  color: teinteDe(operateur),
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Espace.xs),
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
        // Pour le client qui n'est pas devant le comptoir, ou dont le
        // téléphone n'a pas d'appareil photo — et c'est encore le cas de
        // beaucoup. Il compose le code sur son propre téléphone.
        OutlinedButton.icon(
          onPressed: surEnvoi,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Envoyer le lien au client'),
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


/// Ce qu'on saisit pour un client qu'on ne connaît pas encore.
class _SaisieClient {
  final String nom;
  final String? telephone;
  const _SaisieClient(this.nom, this.telephone);
}

/// Le choix du client à qui l'on fait crédit.
///
/// Une dette sans nom n'est pas une dette : c'est de l'argent perdu. C'est
/// exactement ce qui arrive au cahier papier quand on oublie d'écrire.
class _VoletCredit extends StatelessWidget {
  final List<LigneClient> clients;
  final LigneClient? choisi;
  final ValueChanged<LigneClient> surChoix;
  final VoidCallback surNouveau;

  const _VoletCredit({
    required this.clients,
    required this.choisi,
    required this.surChoix,
    required this.surNouveau,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('À qui ?', style: textes.labelSmall),
          const SizedBox(height: Espace.s),
          if (clients.isEmpty)
            Text(
              "Tu n'as encore personne dans ton cahier.",
              style: textes.bodyMedium,
            )
          else
            Wrap(
              spacing: Espace.s,
              runSpacing: Espace.s,
              children: [
                for (final client in clients)
                  ChoiceChip(
                    label: Text(client.nom),
                    selected: choisi?.id == client.id,
                    onSelected: (_) => surChoix(client),
                    selectedColor: Couleurs.primaireClair,
                  ),
              ],
            ),
          const SizedBox(height: Espace.m),
          OutlinedButton.icon(
            onPressed: surNouveau,
            icon: const Icon(Icons.person_add_alt_rounded, size: 18),
            label: const Text('Nouveau client'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          if (choisi != null) ...[
            const SizedBox(height: Espace.m),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: Couleurs.primaireVif),
                const SizedBox(width: Espace.xs),
                Expanded(
                  child: Text(
                    choisi!.encoursCentimes > 0
                        ? '${choisi!.nom} doit déjà '
                            '${Montant(choisi!.encoursCentimes).enFrancs}'
                        : '${choisi!.nom} ne doit rien pour l\'instant',
                    style: textes.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Création d'un client au comptoir : un nom, et le numéro si on l'a.
class _FeuilleNouveauClient extends StatefulWidget {
  const _FeuilleNouveauClient();

  static Future<_SaisieClient?> demander(BuildContext context) =>
      showModalBottomSheet<_SaisieClient>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _FeuilleNouveauClient(),
      );

  @override
  State<_FeuilleNouveauClient> createState() => _FeuilleNouveauClientState();
}

class _FeuilleNouveauClientState extends State<_FeuilleNouveauClient> {
  final _nom = TextEditingController();
  final _telephone = TextEditingController();

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final complet = _nom.text.trim().isNotEmpty;

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
          Center(child: Text('Nouveau client', style: textes.titleLarge)),
          const SizedBox(height: Espace.l),
          TextField(
            controller: _nom,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Salif',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: Espace.m),
          TextField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Téléphone (facultatif)',
              hintText: '70 00 00 00',
              prefixIcon: Icon(Icons.smartphone_rounded),
              helperText: "Sert à lui envoyer son ardoise",
            ),
          ),
          const SizedBox(height: Espace.l),
          FilledButton(
            onPressed: complet
                ? () => Navigator.of(context).pop(_SaisieClient(
                      _nom.text.trim(),
                      _telephone.text.trim().isEmpty
                          ? null
                          : _telephone.text.trim(),
                    ))
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: Couleurs.primaire,
              disabledBackgroundColor: Couleurs.bordure,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
