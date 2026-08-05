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
}
