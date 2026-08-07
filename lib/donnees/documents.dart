/// Fabrique les documents destinés au client à partir de la base.
///
/// Tout se génère hors ligne : ce sont des messages, pas des pages servies
/// par un serveur. Le commerçant les envoie par WhatsApp ou par SMS en un
/// geste, et le client n'installe rien.
library;

import 'package:drift/drift.dart' as drift;

import '../domaine/document_client.dart';
import '../domaine/montant.dart';
import '../domaine/references.dart';
import 'base.dart';
import 'depot.dart';

class Documents {
  final BaseLocale base;

  /// Nom affiché en tête des documents.
  ///
  /// Il viendra de la fiche entreprise quand la certification l'imposera ;
  /// en attendant, il est réglé à l'installation.
  final String nomCommerce;

  const Documents(this.base, {required this.nomCommerce});

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
      date: vente.horodatage,
      contenant: vente.contenant,
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
