/// Fabrique les documents destinés au client à partir de la base.
///
/// Tout se génère hors ligne : ce sont des messages, pas des pages servies
/// par un serveur. Le commerçant les envoie par WhatsApp ou par SMS en un
/// geste, et le client n'installe rien.
library;

import 'package:drift/drift.dart' as drift;

import '../domaine/calcul_facture.dart';
import '../domaine/document_client.dart';
import '../domaine/facture.dart';
import '../domaine/fiche_entreprise.dart';
import '../domaine/montant.dart';
import '../domaine/numerotation.dart';
import '../domaine/references.dart';
import 'base.dart';
import 'depot.dart';

class Documents {
  final BaseLocale base;

  /// Nom affiché en tête des documents.
  final String nomCommerce;

  /// La fiche entreprise, quand elle est renseignée. Nulle chez la quasi-
  /// totalité des commerçants, et les documents n'en portent alors aucune
  /// trace.
  final FicheEntreprise? fiche;

  const Documents(this.base, {required this.nomCommerce, this.fiche});

  /// Les mentions de l'émetteur qui coiffent chaque document, sans le nom —
  /// il est déjà porté à part.
  List<String> get _mentions {
    final renseignee = fiche;
    if (renseignee == null || !renseignee.renseignee) return const [];
    return renseignee.enTete.skip(1).toList();
  }

  /// Le reçu d'une vente soldée, ou la note d'une vente encore ouverte.
  ///
  /// La même méthode sert les deux : c'est l'état de la vente qui décide.
  Future<DocumentClient?> pourVente(String venteId) async {
    final vente = await (base.select(base.ventes)
          ..where((v) => v.id.equals(venteId)))
        .getSingleOrNull();
    if (vente == null) return null;

    final lignes = await (base.select(base.lignesVente)
          ..where((l) => l.venteId.equals(venteId)))
        .get();

    final reglements = await (base.select(base.paiements)
          ..where((p) => p.venteId.equals(venteId)))
        .get();

    final regle = reglements
        .where((p) => p.mode != ModePaiement.credit.name)
        .fold(0, (somme, p) => somme + p.montantCentimes);

    final nature = switch (EtatVente.parCle(vente.etat)) {
      EtatVente.ouverte => NatureDocument.note,
      EtatVente.servie => NatureDocument.confirmation,
      EtatVente.soldee => NatureDocument.recu,
    };

    return DocumentClient(
      nature: nature,
      nomCommerce: nomCommerce,
      mentions: _mentions,
      date: vente.horodatage,
      contenant: vente.contenant,
      operateur: vente.operateur,
      lignes: [
        for (final ligne in lignes)
          LigneDocument(
            designation: ligne.designation,
            quantite: Quantite(ligne.quantiteMilliemes),
            prixUnitaire: Montant(ligne.prixUnitaireCentimes),
            montant: Montant(ligne.montantCentimes),
          )
      ],
      total: Montant(vente.totalCentimes),
      regle: Montant(regle),
      modes: reglements
          .map((p) => ModePaiement.values.firstWhere(
                (m) => m.name == p.mode,
                orElse: () => ModePaiement.especes,
              ))
          .toSet()
          .toList(),
    );
  }

  /// Compose la facture d'une vente déjà enregistrée.
  ///
  /// Le numéro n'est pas attribué ici : il vient du dépôt, qui seul sait tenir
  /// une série ininterrompue. Ce module ne fait que mettre en forme.
  ///
  /// Les prix sont pris **toutes taxes comprises**, parce que c'est ainsi
  /// qu'on vend ici : le prix affiché sur l'étagère est celui qu'on paie, et
  /// la caisse n'a jamais demandé au commerçant s'il pensait en HT.
  Future<Facture?> composerFacture(
    String venteId, {
    required ReferenceFacture reference,
    required ClientFacture client,
    Montant timbreQuittance = const Montant.zero(),
    List<Commentaire> commentaires = const [],
    bool duplicata = false,
  }) async {
    final vente = await (base.select(base.ventes)
          ..where((v) => v.id.equals(venteId)))
        .getSingleOrNull();
    if (vente == null) return null;

    final lignes = await (base.select(base.lignesVente)
          ..where((l) => l.venteId.equals(venteId)))
        .get();
    if (lignes.isEmpty) return null;

    final calcul = calculerFacture(
      modePrix: ModePrix.toutesTaxesComprises,
      lignes: [
        for (final ligne in lignes)
          LigneACalculer(
            codeArticle: ligne.codeArticle,
            designation: ligne.designation,
            groupeTaxation: GroupeTaxation.parEtiquette(ligne.groupeTaxation),
            // La remise se calcule à partir du prix catalogue, quand il
            // différait : c'est ce que le §3 veut voir au détail de la ligne,
            // et c'est aussi ce que le client attend d'y lire.
            prixUnitaire: Montant(
                ligne.prixCatalogueCentimes ?? ligne.prixUnitaireCentimes),
            quantite: Quantite(ligne.quantiteMilliemes),
            remise: _remiseDeLigne(ligne),
          )
      ],
    );

    final reglements = <ModePaiement, Montant>{};
    for (final paiement in await (base.select(base.paiements)
          ..where((p) => p.venteId.equals(venteId)))
        .get()) {
      final mode = ModePaiement.values.firstWhere(
        (m) => m.name == paiement.mode,
        orElse: () => ModePaiement.especes,
      );
      reglements[mode] =
          (reglements[mode] ?? const Montant.zero()) + Montant(paiement.montantCentimes);
    }

    return Facture(
      reference: reference,
      type: TypeFacture.vente,
      emetteur: fiche ?? FicheEntreprise(nomCommercial: nomCommerce),
      client: client,
      calcul: calcul,
      date: vente.horodatage,
      operateur: vente.operateur,
      reglements: reglements,
      timbreQuittance: timbreQuittance,
      commentaires: commentaires,
      duplicata: duplicata,
    );
  }

  /// L'écart entre le prix du catalogue et le prix pratiqué, sur toute la
  /// ligne. Nul quand rien n'a été négocié.
  static Montant _remiseDeLigne(LigneDeVente ligne) {
    final catalogue = ligne.prixCatalogueCentimes;
    if (catalogue == null || catalogue <= ligne.prixUnitaireCentimes) {
      return const Montant.zero();
    }
    return Montant(catalogue - ligne.prixUnitaireCentimes)
        .multiplieParQuantite(Quantite(ligne.quantiteMilliemes));
  }

  /// L'historique des achats d'un client **dans cette boutique**.
  ///
  /// Un commerçant ne voit jamais que ses propres ventes. Ce que le client
  /// achète ailleurs ne le regarde pas, et la règle vaut aussi pour la
  /// version inter-boutiques qui viendra avec le serveur : elle sera
  /// consultable par le client, jamais par un commerçant.
  Future<HistoriqueClient?> historique(
    String clientId, {
    DateTime? depuis,
    DateTime? jusqua,
  }) async {
    final client = await (base.select(base.clients)
          ..where((c) => c.id.equals(clientId)))
        .getSingleOrNull();
    if (client == null) return null;

    final fin = jusqua ?? DateTime.now();
    final debut = depuis ?? DateTime(fin.year, fin.month - 3, fin.day);

    final ventes = await (base.select(base.ventes)
          ..where((v) =>
              v.clientId.equals(clientId) &
              v.annulee.equals(false) &
              v.horodatage.isBiggerOrEqualValue(debut) &
              v.horodatage.isSmallerOrEqualValue(fin))
          ..orderBy([(v) => drift.OrderingTerm.desc(v.horodatage)]))
        .get();

    final achats = <AchatResume>[];
    for (final vente in ventes) {
      final lignes = await (base.select(base.lignesVente)
            ..where((l) => l.venteId.equals(vente.id)))
          .get();

      achats.add(AchatResume(
        date: vente.horodatage,
        montant: Montant(vente.totalCentimes),
        resume: _resumer(lignes),
      ));
    }

    return HistoriqueClient(
      nomCommerce: nomCommerce,
      nomClient: client.nom,
      depuis: debut,
      jusqua: fin,
      achats: achats,
      total: Montant(ventes.fold(0, (s, v) => s + v.totalCentimes)),
      encours: Montant(client.encoursCentimes),
    );
  }

  /// Abrège le contenu d'une vente : le premier article, puis le nombre des
  /// autres. La liste entière ne tiendrait pas sur une ligne.
  static String _resumer(List<LigneDeVente> lignes) {
    if (lignes.isEmpty) return 'Achat';
    if (lignes.length == 1) return lignes.single.designation;
    return '${lignes.first.designation} +${lignes.length - 1}';
  }

  /// L'ardoise d'un client : ce qu'il doit, et depuis quand.
  Future<Ardoise?> ardoise(String clientId, {DateTime? arreteeAu}) async {
    final client = await (base.select(base.clients)
          ..where((c) => c.id.equals(clientId)))
        .getSingleOrNull();
    if (client == null) return null;

    final ventes = await (base.select(base.ventes)
          ..where((v) => v.clientId.equals(clientId) & v.annulee.equals(false))
          ..orderBy([(v) => drift.OrderingTerm.asc(v.horodatage)]))
        .get();

    final identifiants = ventes.map((v) => v.id).toList();
    final aCredit = identifiants.isEmpty
        ? const <LignePaiement>[]
        : await (base.select(base.paiements)
              ..where((p) =>
                  p.venteId.isIn(identifiants) &
                  p.mode.equals(ModePaiement.credit.name)))
            .get();

    final remboursements = await base.customSelect(
      '''
      SELECT COUNT(*) AS nombre
      FROM evenements
      WHERE type = 'credit_rembourse'
        AND charge LIKE ?
      ''',
      variables: [drift.Variable<String>('%"clientId":"$clientId"%')],
      readsFrom: {base.evenements},
    ).getSingle();

    final premiereDette = ventes
        .where((v) => aCredit.any((p) => p.venteId == v.id))
        .map((v) => v.horodatage)
        .firstOrNull;

    return Ardoise(
      nomCommerce: nomCommerce,
      nomClient: client.nom,
      encours: Montant(client.encoursCentimes),
      date: arreteeAu ?? DateTime.now(),
      nombreAchats: aCredit.length,
      nombreRemboursements: remboursements.read<int>('nombre'),
      depuis: premiereDette,
    );
  }

  /// Le rapport du soir, prêt à partir au patron.
  ///
  /// Le texte se compose ici et pas dans l'écran : c'est un document comme
  /// les autres, il doit s'aligner comme les autres, et il doit pouvoir se
  /// vérifier sans lancer d'interface.
  RapportDuSoir rapportDuSoir({
    required RapportDuJour rapport,
    List<String> aRacheter = const [],
    Montant perdu = const Montant.zero(),
    List<PartEncaissee> parts = const [],
    String? intitule,
    DateTime? date,
  }) =>
      RapportDuSoir(
        perdu: perdu,
        nomCommerce: nomCommerce,
        date: date ?? DateTime.now(),
        encaisse: rapport.encaisse,
        aCredit: rapport.aCredit,
        remises: rapport.remisesAccordees,
        nombreVentes: rapport.nombreVentes,
        aRacheter: aRacheter,
        parts: parts,
        intitule: intitule,
      );

}
