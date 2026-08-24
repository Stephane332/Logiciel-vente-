/// Le rapport du soir.
///
/// C'est ce qui crée l'habitude : le patron qui n'est pas au magasin voit son
/// commerce. Le jour où il arrête de payer, il perd ses yeux.
///
/// Rien n'y est décoratif. Chaque bloc répond à une question qu'un commerçant
/// se pose vraiment : combien j'ai encaissé, à qui j'ai fait crédit, qu'est-ce
/// que je dois racheter, et qu'est-ce qui dort sur mon étagère.
library;

import 'package:flutter/material.dart';

import '../../donnees/analyses.dart';
import '../../donnees/depot.dart';
import '../../domaine/document_client.dart';
import '../../domaine/montant.dart';
import '../../domaine/periode.dart';
import '../../domaine/rapport_fiscal.dart';
import '../../donnees/documents.dart';
import '../../donnees/rapports.dart';
import '../composants/montant_anime.dart';
import '../composants/partage.dart';
import '../theme/palette.dart';

class EcranRapport extends StatefulWidget {
  final Depot depot;
  final Documents documents;
  final Analyses analyses;

  /// Ouvre les réglages. C'est l'écran du patron : c'est ici qu'on règle sa
  /// boutique, pas au milieu d'une vente.
  final VoidCallback? surReglages;

  /// L'arrêté de caisse : X, Z et A. Nul dans les tests d'écran qui ne
  /// regardent pas la clôture — la section disparaît alors entièrement.
  final Rapports? rapports;

  /// Qui tient la caisse au moment de la clôture.
  ///
  /// C'est ce nom qui reste attaché au comptage du soir. Sans lui, l'écart
  /// existe mais n'appartient à personne, et un patron ne peut rien en faire.
  final String? vendeurActif;

  const EcranRapport({
    super.key,
    required this.depot,
    required this.documents,
    required this.analyses,
    this.surReglages,
    this.rapports,
    this.vendeurActif,
  });

  @override
  State<EcranRapport> createState() => EcranRapportState();
}

class EcranRapportState extends State<EcranRapport> {
  RapportDuJour? _rapport;
  List<AlerteStock> _alertes = const [];
  List<ArticleEndormi> _endormis = const [];
  List<PerformanceArticle> _meilleures = const [];
  List<PartDeVendeur> _parVendeur = const [];
  List<EcartsDeVendeur> _ecarts = const [];
  Montant _perdu = const Montant.zero();

  /// La tranche de temps regardée. La journée en cours par défaut : c'est la
  /// question qu'on se pose neuf fois sur dix.
  Periode _periode = Periode.jour;

  /// Ce qui apparaît sous « Ce qui dort ». Au-delà, le commerçant ne lit plus.
  static const _plafondEndormis = 5;

  @override
  void initState() {
    super.initState();
    recharger();
  }

  /// Relit tous les chiffres.
  ///
  /// Publique : la coquille de navigation l'appelle à chaque retour sur
  /// l'écran, sinon le rapport afficherait l'état d'avant la dernière vente.
  Future<void> recharger() async {
    final (debut, fin) = _periode.bornes();

    // Les lectures ne dépendent pas les unes des autres. Les enchaîner ferait
    // six allers-retours au lieu d'un sur un téléphone d'entrée de gamme, à
    // chaque ouverture de l'onglet.
    final (rapport, alertes, endormis, meilleures, perdu, parVendeur, ecarts) =
        await (
          widget.depot.rapportSurPeriode(debut, fin),
          widget.analyses.aReapprovisionner(),
          widget.analyses.articlesQuiDorment(limite: _plafondEndormis),
          widget.analyses.meilleuresVentes(limite: 5),
          widget.analyses.pertesEtEcarts(debut: debut, fin: fin),
          widget.depot.parVendeur(debut, fin),
          widget.depot.ecartsParVendeur(debut, fin),
        ).wait;

    final cloture = await widget.rapports?.derniereCloture(NatureRapport.z);

    if (!mounted) return;
    setState(() {
      _rapport = rapport;
      _alertes = alertes;
      _endormis = endormis;
      _meilleures = meilleures;
      _perdu = perdu;
      _parVendeur = parVendeur;
      _ecarts = ecarts;
      _derniereCloture = cloture;
    });
  }

  void _changerPeriode(Periode periode) {
    if (periode == _periode) return;
    setState(() => _periode = periode);
    recharger();
  }

  /// Quand la caisse a été arrêtée pour la dernière fois. Nulle tant qu'elle
  /// ne l'a jamais été.
  DateTime? _derniereCloture;

  static String _dateLisible(DateTime quand) {
    String d(int v) => v.toString().padLeft(2, '0');
    return '${d(quand.day)}/${d(quand.month)} à ${d(quand.hour)}h${d(quand.minute)}';
  }

  /// Le point de caisse, sans rien arrêter.
  Future<void> _pointDeCaisse() async {
    final rapports = widget.rapports;
    if (rapports == null) return;

    final x = await rapports.x();
    if (!mounted) return;
    await FeuilleDocument.presenter(
      context,
      titre: 'Point de caisse',
      texte: x.texte,
    );
  }

  /// Clôture la journée.
  ///
  /// Demande confirmation, et c'est le seul endroit de l'application où j'en
  /// demande une. Une clôture ne se défait pas : le rapport suivant repartira
  /// d'ici, et un Z tiré par erreur à midi couperait la journée en deux.
  Future<void> _cloturer() async {
    final rapports = widget.rapports;
    if (rapports == null) return;

    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Clôturer la journée ?'),
        content: const Text(
          "Le prochain rapport repartira d'ici. C'est le geste du soir, "
          'quand la caisse est comptée — il ne se défait pas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Pas maintenant'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    // Le comptage vient avant le Z, et l'ordre n'est pas un détail : le Z
    // dit ce qu'il aurait dû y avoir dans le tiroir. Le tirer d'abord, ce
    // serait donner la réponse avant de poser la question.
    await _compterLaCaisse();
    if (!mounted) return;

    final z = await rapports.z();
    if (!mounted) return;

    setState(() => _derniereCloture = z.fin);
    await FeuilleDocument.presenter(
      context,
      titre: 'Clôture n° ${z.numero}',
      texte: z.texte,
    );
  }

  /// Note de l'argent entré ou sorti du tiroir sans que ce soit une vente.
  ///
  /// C'est ce qui manquait le plus, et ça ne se voyait pas tant que personne
  /// ne comptait : un commerçant met un fonds le matin, paie un fournisseur
  /// dans la journée, porte la recette à la banque avant de fermer. Sans ces
  /// lignes, le tiroir ne correspond jamais au total des ventes, et le
  /// comptage du soir accuse quelqu'un pour de l'argent parti avec une
  /// facture.
  Future<void> _bougerLaCaisse({required bool entree}) async {
    final saisie = TextEditingController();
    final motif = TextEditingController();
    final textes = Theme.of(context).textTheme;

    final montant = await showDialog<Montant>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text(
          entree ? 'Mettre de l'"'"'argent en caisse' : 'Sortir de l'"'"'argent',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entree
                  ? "Le fonds du matin, ou un apport en cours de journée. Ce "
                        "n'est pas une vente : ça ne compte pas dans le "
                        'chiffre du jour, seulement dans le tiroir.'
                  : "Un achat payé en liquide, un versement à la banque, une "
                        "course. Note-le : sinon le comptage du soir dira "
                        'que cet argent manque.',
              style: textes.bodyMedium,
            ),
            const SizedBox(height: Espace.m),
            TextField(
              controller: saisie,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(),
              style: textes.headlineSmall,
              decoration: const InputDecoration(
                labelText: 'Combien',
                suffixText: 'F',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Espace.s),
            TextField(
              controller: motif,
              decoration: const InputDecoration(
                labelText: 'Pourquoi (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(contexte).pop(_lireFrancs(saisie.text)),
            child: const Text('Noter'),
          ),
        ],
      ),
    );

    // Zéro n'est pas un mouvement : ça n'ajoute rien au tiroir et ça ajoute
    // une ligne à lire dans le rapport.
    if (montant == null || !montant.estPositif || !mounted) return;

    final pourquoi = motif.text.trim();
    if (entree) {
      await widget.depot.mettreEnCaisse(
        montant,
        motif: pourquoi.isEmpty ? null : pourquoi,
        operateur: widget.vendeurActif,
      );
    } else {
      await widget.depot.sortirDeCaisse(
        montant,
        motif: pourquoi.isEmpty ? null : pourquoi,
        operateur: widget.vendeurActif,
      );
    }

    if (!mounted) return;
    await recharger();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            entree
                ? '${montant.enFrancs} mis en caisse'
                : '${montant.enFrancs} sortis de la caisse',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Demande combien il y a dans le tiroir, puis dit ce qu'il aurait dû y
  /// avoir.
  ///
  /// **Dans cet ordre, et l'écran ne montre jamais l'attendu avant la
  /// saisie.** Un comptage dont on connaît déjà le résultat ne mesure rien :
  /// il suffit de recopier le nombre affiché. C'est toute la valeur du geste,
  /// et c'est aussi ce qui le rend un peu désagréable — tant pis, un
  /// comptage confortable ne sert à rien.
  ///
  /// On peut passer. Une caisse qu'on ne compte pas est un choix du
  /// commerçant, pas une erreur de l'application, et refuser de clôturer
  /// tant qu'il n'a pas compté ferait surtout qu'il ne clôturerait plus.
  Future<void> _compterLaCaisse() async {
    final rapports = widget.rapports;
    if (rapports == null) return;

    final compte = await _demanderLeCompte();
    if (compte == null || !mounted) return;

    final attendu = (await rapports.x()).enCaisse;
    final ecart = await widget.depot.pointerLaCaisse(
      compte: compte,
      attendu: attendu,
      operateur: widget.vendeurActif,
    );
    if (!mounted) return;

    // Le rapport a été lu à l'ouverture de l'écran, donc avant ce comptage :
    // sans cette relecture, le commerçant referme la boîte et ne retrouve
    // nulle part le chiffre qu'on vient de lui montrer. Un écran qui oublie
    // ce qu'il vient d'enregistrer, c'est un écran auquel on cesse de croire.
    await recharger();
    if (!mounted) return;

    await _direLEcart(compte: compte, attendu: attendu, ecart: ecart);
  }

  /// Le champ de saisie. Rien d'autre à l'écran : ni total du jour, ni
  /// attendu, ni rappel de ce qui a été encaissé.
  Future<Montant?> _demanderLeCompte() {
    final saisie = TextEditingController();
    final textes = Theme.of(context).textTheme;

    return showDialog<Montant>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Compte la caisse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Sors l'argent du tiroir et compte-le. Écris ce que tu as "
              'trouvé — je te dirai ensuite ce qu'"'"'il aurait dû y avoir.',
              style: textes.bodyMedium,
            ),
            const SizedBox(height: Espace.m),
            TextField(
              controller: saisie,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(),
              style: textes.headlineSmall,
              decoration: const InputDecoration(
                labelText: 'Ce que je compte',
                suffixText: 'F',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(
                contexte,
              ).pop(_lireFrancs(saisie.text)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(),
            child: const Text('Je ne compte pas'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(contexte).pop(_lireFrancs(saisie.text)),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  /// Le nombre saisi, ou nul si ce n'en est pas un.
  ///
  /// Zéro est une réponse valable — une caisse vidée en fin de journée se
  /// compte à zéro, et c'est même le cas le plus courant chez qui dépose tout
  /// le soir. Seul un champ vide ou illisible vaut « je ne compte pas ».
  static Montant? _lireFrancs(String saisie) {
    final propre = saisie.replaceAll(RegExp(r'[^0-9]'), '');
    if (propre.isEmpty) return null;
    final francs = int.tryParse(propre);
    return francs == null ? null : Montant.depuisDecimal(francs);
  }

  /// Dit ce que le comptage a donné.
  Future<void> _direLEcart({
    required Montant compte,
    required Montant attendu,
    required Montant ecart,
  }) {
    final juste = ecart.centimes == 0;
    final manque = ecart.estNegatif;
    final ecartAbsolu = Montant(ecart.centimes.abs());

    return showDialog<void>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text(
          juste
              ? 'La caisse tombe juste'
              : manque
              ? 'Il manque ${ecartAbsolu.enFrancs}'
              : 'Il y a ${ecartAbsolu.enFrancs} de trop',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LigneComptage(
              libelle: 'Ce que tu as compté',
              montant: compte.enFrancs,
            ),
            _LigneComptage(
              libelle: 'Ce qui aurait dû y être',
              montant: attendu.enFrancs,
            ),
            const SizedBox(height: Espace.m),
            Text(
              juste
                  ? "C'est noté. Compter tous les soirs, même quand tout "
                        'tombe juste, c'"'"'est ce qui rend un écart lisible le '
                        'jour où il arrive.'
                  : "C'est noté, et rattaché à ${widget.vendeurActif ?? 'la caisse'}. "
                        "Un écart isolé n'accuse personne — on se trompe en "
                        'rendant la monnaie. C'"'"'est quand ça se répète que ça '
                        'veut dire quelque chose, et le rapport le montre.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  Future<void> _etatDesArticles() async {
    final rapports = widget.rapports;
    if (rapports == null) return;

    final a = await rapports.a();
    if (!mounted) return;
    await FeuilleDocument.presenter(
      context,
      titre: 'État des articles',
      texte: a.texte,
    );
  }

  /// Vrai quand la répartition par vendeur a quelque chose à dire.
  ///
  /// Chez un commerçant seul, tout est sur une seule ligne anonyme : afficher
  /// « Non attribué : tout » n'apprendrait rien à personne.
  bool get _partsUtiles =>
      _parVendeur.length > 1 ||
      (_parVendeur.length == 1 && !_parVendeur.first.estAnonyme);

  /// Ce qui se lit sous le titre des écarts.
  ///
  /// Il dit la période **et** ce que la section n'est pas. Un tableau qui
  /// nomme des gens à côté de sommes manquantes se lit comme une accusation
  /// si personne ne prévient du contraire, et c'est le genre de malentendu
  /// qui coûte un employé honnête.
  String get _sousTitreEcarts =>
      '${_periode.libelle.toLowerCase()} · une fois ne prouve rien, '
      "c'est la répétition qui parle";

  /// Le chiffre à droite du nom : ce qui manque, ou l'excédent, ou rien.
  String _resultatDuComptage(EcartsDeVendeur ecart) {
    if (ecart.manques.estPositif) return '− ${ecart.manques.enFrancs}';
    if (ecart.cumul.estPositif) return '+ ${ecart.cumul.enFrancs}';
    return 'juste';
  }

  /// Le détail sous le nom : combien de fois la caisse a été comptée, et
  /// combien de fois elle est tombée juste.
  ///
  /// Le nombre de comptages compte autant que la somme : quelqu'un qui manque
  /// 1 000 F en trente soirs et quelqu'un qui les manque en un seul ne
  /// racontent pas la même histoire.
  String _detailComptage(EcartsDeVendeur ecart) {
    final fois =
        '${ecart.comptages} comptage${ecart.comptages > 1 ? 's' : ''}';
    if (ecart.impeccable) return '$fois, tous justes';
    if (!ecart.manques.estPositif) return '$fois, jamais de manque';
    if (ecart.cumul.estPositif) {
      return '$fois · les excédents couvrent les manques';
    }
    return fois;
  }

  /// Le détail sous le nom d'un vendeur : combien de ventes, et ce qu'il a
  /// lâché en remises.
  ///
  /// La remise n'est mentionnée que si elle existe. C'est le chiffre qui
  /// compte vraiment pour le patron — celui qui accorde deux fois plus de
  /// remises que les autres se voit tout de suite — mais un « 0 F de
  /// remises » affiché tous les jours finit par ne plus être lu.
  String _detailVendeur(PartDeVendeur part) {
    final ventes =
        '${part.nombreVentes} vente'
        '${part.nombreVentes > 1 ? 's' : ''}';
    if (part.remises.estNul) return ventes;
    return '$ventes · ${part.remises.enFrancs} de remises';
  }

  /// Le résumé tel qu'il part au patron, le soir.
  ///
  /// Composé par [Documents], comme le reçu et l'ardoise : c'est un document,
  /// il doit s'aligner comme les autres.
  String _resume(RapportDuJour rapport) => widget.documents
      .rapportDuSoir(
        rapport: rapport,
        aRacheter: [for (final alerte in _alertes.take(5)) alerte.message],
        perdu: _perdu,
        date: _periode.dateDeReference(),
        intitule: _periode.intitule(),
        // Le patron qui emploie quelqu'un veut le détail dans le message
        // aussi : c'est souvent le seul écran qu'il regarde de la journée.
        parts: [
          if (_partsUtiles)
            for (final part in _parVendeur)
              (
                qui: part.estAnonyme ? 'Non attribué' : part.vendeur,
                combien: part.total,
              ),
        ],
        comptage: _comptageDuSoir,
      )
      .texte;

  /// Les comptages de la période, réunis en une ligne pour le message.
  ///
  /// Le patron qui n'est pas au magasin ne lit que ce message : mesurer le
  /// tiroir ne sert à rien si la mesure ne lui remonte pas. Nul quand
  /// personne n'a compté — et le message se tait alors, au lieu d'afficher un
  /// zéro qui laisserait croire que la caisse a été vérifiée.
  ComptageDuSoir? get _comptageDuSoir {
    if (_ecarts.isEmpty) return null;

    var comptages = 0;
    var cumul = const Montant.zero();
    var manques = const Montant.zero();
    for (final ecart in _ecarts) {
      comptages += ecart.comptages;
      cumul = cumul + ecart.cumul;
      manques = manques + ecart.manques;
    }
    return ComptageDuSoir(
      comptages: comptages,
      cumul: cumul,
      manques: manques,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rapport = _rapport;
    if (rapport == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final textes = Theme.of(context).textTheme;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: recharger,
        child: ListView(
          padding: const EdgeInsets.all(Espace.l),
          children: [
            Row(
              children: [
                // Le sélecteur défile : quatre pastilles ne tiennent pas côte
                // à côte sur les écrans les plus étroits, et une pastille
                // coupée en deux ne se tape pas.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final periode in Periode.values) ...[
                          _Pastille(
                            libelle: periode.libelle,
                            choisie: periode == _periode,
                            onPressed: () => _changerPeriode(periode),
                          ),
                          const SizedBox(width: Espace.s),
                        ],
                      ],
                    ),
                  ),
                ),
                if (widget.surReglages != null)
                  IconButton(
                    onPressed: widget.surReglages,
                    icon: const Icon(Icons.tune_rounded, size: 22),
                    color: Couleurs.encreDouce,
                    tooltip: 'Réglages',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: Espace.m),
            MontantAnime(rapport.encaisse, style: textes.displayLarge),
            Text('encaissés', style: textes.bodyMedium),

            const SizedBox(height: Espace.l),
            Wrap(
              spacing: Espace.s,
              runSpacing: Espace.s,
              children: [
                PastilleMontant(
                  libelle: 'À crédit',
                  montant: rapport.aCredit,
                  teinte: Couleurs.alerte,
                  icone: Icons.schedule_rounded,
                ),
                PastilleMontant(
                  libelle: 'Remises',
                  montant: rapport.remisesAccordees,
                  teinte: Couleurs.accent,
                  icone: Icons.discount_outlined,
                ),
                // Marchandise partie sans rapporter un franc. On ne l'affiche
                // que s'il y en a : une pastille à zéro tous les jours finit
                // par ne plus être lue.
                if (_perdu.estPositif)
                  PastilleMontant(
                    libelle: 'Perdu',
                    montant: _perdu,
                    teinte: Couleurs.alerte,
                    icone: Icons.remove_circle_outline_rounded,
                  ),
              ],
            ),

            const SizedBox(height: Espace.s),
            Text(
              '${rapport.nombreVentes} vente'
              '${rapport.nombreVentes > 1 ? 's' : ''}',
              style: textes.bodyMedium,
            ),

            if (_partsUtiles) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'Qui a encaissé',
                sousTitre: _periode.libelle.toLowerCase(),
                enfants: [
                  for (final part in _parVendeur)
                    _Ligne(
                      libelle: part.estAnonyme ? 'Non attribué' : part.vendeur,
                      detail: part.total.enFrancs,
                      // Une part sans nom est un trou dans le compte : elle se
                      // signale, sans accuser personne.
                      pastille: part.estAnonyme
                          ? Couleurs.alerte
                          : Couleurs.primaire,
                      sousLigne: _detailVendeur(part),
                    ),
                ],
              ),
            ],

            if (_ecarts.isNotEmpty) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'Ce que la caisse a donné au comptage',
                sousTitre: _sousTitreEcarts,
                enfants: [
                  for (final ecart in _ecarts)
                    _Ligne(
                      libelle: ecart.estAnonyme
                          ? 'Non attribué'
                          : ecart.vendeur,
                      detail: _resultatDuComptage(ecart),
                      // Rouge quand il manque, et seulement là. Un excédent
                      // est une erreur aussi, mais il ne coûte rien : le
                      // signaler de la même couleur ferait lire les deux
                      // avec la même inquiétude, donc aucune des deux.
                      pastille: ecart.manques.estPositif
                          ? Couleurs.alerte
                          : Couleurs.primaire,
                      sousLigne: _detailComptage(ecart),
                    ),
                ],
              ),
            ],

            if (_alertes.isNotEmpty) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'À racheter',
                sousTitre: 'Calculé sur ton rythme de vente',
                enfants: [
                  for (final alerte in _alertes)
                    _Ligne(
                      libelle: alerte.designation,
                      detail: alerte.detail,
                      pastille: alerte.enRupture
                          ? Couleurs.alerte
                          : Couleurs.accent,
                      urgent: alerte.enRupture,
                    ),
                ],
              ),
            ],

            if (_meilleures.isNotEmpty) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'Ce qui rapporte',
                sousTitre: 'Sur les sept derniers jours',
                enfants: [
                  for (final article in _meilleures)
                    _Ligne(
                      libelle: article.designation,
                      detail: article.chiffre.enFrancs,
                    ),
                ],
              ),
            ],

            if (_endormis.isNotEmpty) ...[
              const SizedBox(height: Espace.xl),
              _Section(
                titre: 'Ce qui dort',
                sousTitre: "Vendu régulièrement, puis plus rien",
                enfants: [
                  for (final article in _endormis)
                    _Ligne(
                      libelle: article.designation,
                      detail: article.valeurImmobilisee == null
                          ? '${article.joursSansVente} jours'
                          : '${article.joursSansVente} j · '
                                '${article.valeurImmobilisee!.enFrancs} bloqués',
                      pastille: Couleurs.accent,
                    ),
                ],
              ),
            ],

            const SizedBox(height: Espace.xl),
            FilledButton.icon(
              onPressed: () => FeuilleDocument.presenter(
                context,
                titre: 'Résumé · ${_periode.libelle}',
                texte: _resume(rapport),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: const Text('Envoyer le résumé'),
              style: FilledButton.styleFrom(backgroundColor: Couleurs.primaire),
            ),

            if (widget.rapports != null) ...[
              const SizedBox(height: Espace.xxl),
              Text('Arrêter la caisse', style: textes.titleLarge),
              const SizedBox(height: 2),
              Text(
                _derniereCloture == null
                    ? "Tu n'as encore jamais clôturé. La clôture arrête la "
                          'journée et dit ce qui doit rester dans le tiroir.'
                    : 'Dernière clôture le ${_dateLisible(_derniereCloture!)}.',
                style: textes.labelSmall,
              ),
              const SizedBox(height: Espace.m),
              OutlinedButton.icon(
                onPressed: _pointDeCaisse,
                icon: const Icon(Icons.visibility_outlined, size: 20),
                label: const Text('Point de caisse, sans clôturer'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: Espace.s),
              OutlinedButton.icon(
                onPressed: _cloturer,
                icon: const Icon(Icons.lock_outline_rounded, size: 20),
                label: const Text('Clôturer la journée'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: Couleurs.primaire,
                  side: const BorderSide(color: Couleurs.primaire),
                ),
              ),
              const SizedBox(height: Espace.s),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _bougerLaCaisse(entree: true),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Mettre'),
                      style: TextButton.styleFrom(
                        foregroundColor: Couleurs.encreDouce,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _bougerLaCaisse(entree: false),
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      label: const Text('Sortir'),
                      style: TextButton.styleFrom(
                        foregroundColor: Couleurs.encreDouce,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                "De l'argent qui entre ou sort du tiroir sans être une vente : "
                'le fonds du matin, un achat, un versement à la banque.',
                style: textes.labelSmall,
              ),
              const SizedBox(height: Espace.s),
              TextButton.icon(
                onPressed: _etatDesArticles,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('État des articles'),
                style: TextButton.styleFrom(
                  foregroundColor: Couleurs.encreDouce,
                ),
              ),
            ],

            const SizedBox(height: Espace.xxl),
          ],
        ),
      ),
    );
  }
}

/// Une ligne du récapitulatif de comptage : le libellé à gauche, le montant
/// à droite, alignés pour qu'on lise la différence sans la calculer.
class _LigneComptage extends StatelessWidget {
  final String libelle;
  final String montant;

  const _LigneComptage({required this.libelle, required this.montant});

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(libelle, style: textes.bodyMedium),
          Text(
            montant,
            style: textes.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String titre;
  final String sousTitre;
  final List<Widget> enfants;

  const _Section({
    required this.titre,
    required this.sousTitre,
    required this.enfants,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titre, style: textes.titleLarge),
        const SizedBox(height: 2),
        Text(sousTitre, style: textes.labelSmall),
        const SizedBox(height: Espace.m),
        Container(
          decoration: BoxDecoration(
            color: Couleurs.surface,
            borderRadius: BorderRadius.circular(Rayon.m),
            border: Border.all(color: Couleurs.bordure),
          ),
          child: Column(children: enfants),
        ),
      ],
    );
  }
}

/// Une ligne de liste : un libellé à gauche, un détail à droite.
///
/// La même pour les alertes et pour les montants — c'est la pastille qui
/// change, pas la mise en page.
class _Ligne extends StatelessWidget {
  final String libelle;
  final String detail;

  /// Couleur du point de tête. Nulle quand la ligne n'en porte pas.
  final Color? pastille;

  /// Précision affichée sous le libellé, en petit. Nulle le plus souvent.
  final String? sousLigne;

  final bool urgent;

  const _Ligne({
    required this.libelle,
    required this.detail,
    this.pastille,
    this.sousLigne,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Espace.l,
        vertical: Espace.m,
      ),
      child: Row(
        children: [
          if (pastille != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: pastille,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Espace.m),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libelle,
                  style: textes.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sousLigne != null)
                  Text(
                    sousLigne!,
                    style: textes.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: Espace.s),
          Text(
            detail,
            style: (urgent ? textes.labelSmall : textes.labelLarge)?.copyWith(
              color: urgent ? Couleurs.alerte : Couleurs.encreDouce,
            ),
          ),
        ],
      ),
    );
  }
}

/// Une pastille de choix de période.
///
/// Assez large pour un pouce, et la sélection se lit à la couleur autant
/// qu'au contour : un contour seul ne se voit pas en plein soleil.
class _Pastille extends StatelessWidget {
  final String libelle;
  final bool choisie;
  final VoidCallback onPressed;

  const _Pastille({
    required this.libelle,
    required this.choisie,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Material(
      color: choisie ? Couleurs.primaire : Couleurs.surface,
      borderRadius: BorderRadius.circular(Rayon.rond),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Rayon.rond),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Espace.m,
            vertical: Espace.s,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rayon.rond),
            border: Border.all(
              color: choisie ? Couleurs.primaire : Couleurs.bordure,
            ),
          ),
          child: Text(
            libelle,
            style: textes.labelSmall?.copyWith(
              color: choisie ? Colors.white : Couleurs.encreDouce,
            ),
          ),
        ),
      ),
    );
  }
}
