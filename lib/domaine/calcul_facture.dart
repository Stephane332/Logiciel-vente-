/// Moteur de calcul d'une facture.
///
/// Applique les règles du §6 de la note de service n° 2025-0889/MEF/SG/DGI/DLC
/// du 29 décembre 2025.
///
/// Ce module est volontairement isolé de l'interface et de la persistance :
/// c'est lui qui portera la démonstration devant le comité d'homologation, et
/// il doit rester vérifiable ligne à ligne.
library;

import 'montant.dart';
import 'references.dart';

/// Une ligne de facture avant calcul.
class LigneACalculer {
  final String codeArticle;
  final String designation;
  final GroupeTaxation groupeTaxation;
  final GroupePsvb groupePsvb;

  /// Prix unitaire, interprété selon le [ModePrix] de la facture.
  ///
  /// En mode HT, ce prix s'entend **hors taxe spécifique** (§6.9).
  final Montant prixUnitaire;

  final Quantite quantite;

  /// Remise appliquée à la ligne, exprimée en montant.
  final Montant remise;

  /// Taxe spécifique unitaire, le cas échéant (§6.8).
  ///
  /// Lorsqu'elle s'applique, elle augmente la base de la TVA (§6.9).
  final Montant taxeSpecifiqueUnitaire;

  const LigneACalculer({
    required this.codeArticle,
    required this.designation,
    required this.groupeTaxation,
    required this.prixUnitaire,
    required this.quantite,
    this.groupePsvb = GroupePsvb.d,
    this.remise = const Montant.zero(),
    this.taxeSpecifiqueUnitaire = const Montant.zero(),
  });
}

/// Une ligne après calcul.
class LigneCalculee {
  final LigneACalculer source;

  /// Montant brut de la ligne, avant remise : prix unitaire × quantité (§6.5).
  final Montant montantBrut;

  /// Montant de la ligne après remise.
  final Montant montantNet;

  /// Taxe spécifique totale de la ligne.
  final Montant taxeSpecifique;

  const LigneCalculee({
    required this.source,
    required this.montantBrut,
    required this.montantNet,
    required this.taxeSpecifique,
  });

  GroupeTaxation get groupeTaxation => source.groupeTaxation;
}

/// Totaux d'un groupe de taxation (§3.o, §3.q).
class TotalGroupe {
  final GroupeTaxation groupe;

  /// Montant imposable, hors taxe.
  final Montant montantImposable;

  /// Montant de l'impôt pour ce groupe.
  final Montant taxe;

  /// Montant total du groupe, toutes taxes comprises.
  final Montant montantTotal;

  const TotalGroupe({
    required this.groupe,
    required this.montantImposable,
    required this.taxe,
    required this.montantTotal,
  });

  /// L'égalité imposée par le §6.7.
  bool get estCoherent => montantImposable + taxe == montantTotal;
}

/// Résultat complet du calcul d'une facture.
class FactureCalculee {
  final ModePrix modePrix;
  final List<LigneCalculee> lignes;

  /// Totaux par groupe de taxation, dans l'ordre A à P.
  final List<TotalGroupe> totauxParGroupe;

  final Montant totalImposable;
  final Montant totalTaxe;
  final Montant totalTaxeSpecifique;

  /// Montant total toutes taxes comprises (§3.r).
  final Montant totalTtc;

  /// Prélèvement à la source sur vente de biens, calculé sur le montant
  /// total toutes taxes comprises (§6.10).
  final Montant psvb;

  const FactureCalculee({
    required this.modePrix,
    required this.lignes,
    required this.totauxParGroupe,
    required this.totalImposable,
    required this.totalTaxe,
    required this.totalTaxeSpecifique,
    required this.totalTtc,
    required this.psvb,
  });

  /// Vérifie l'égalité comptable sur chaque groupe et sur l'ensemble.
  bool get estCoherente =>
      totauxParGroupe.every((t) => t.estCoherent) &&
      totalImposable + totalTaxe == totalTtc;
}

/// Erreur de conformité détectée au calcul.
class ErreurConformite implements Exception {
  final String message;
  final String reference;
  const ErreurConformite(this.message, this.reference);

  @override
  String toString() => 'ErreurConformite ($reference) : $message';
}

/// Calcule une facture.
///
/// Les calculs partent du prix unitaire (§6.5), pas du total de ligne.
FactureCalculee calculerFacture({
  required ModePrix modePrix,
  required List<LigneACalculer> lignes,
}) {
  if (lignes.isEmpty) {
    throw const ErreurConformite(
        'Une facture doit comporter au moins un article.', '§2.6');
  }

  final lignesCalculees = <LigneCalculee>[];

  for (final ligne in lignes) {
    if (ligne.quantite.estNulle || ligne.quantite.estNegative) {
      throw ErreurConformite(
          'Quantité nulle ou négative sur « ${ligne.designation} ».', '§2.25');
    }

    // §6.5 : le calcul part du prix unitaire.
    final montantBrut = ligne.prixUnitaire.multiplieParQuantite(ligne.quantite);
    final montantNet = montantBrut - ligne.remise;

    if (!montantNet.estPositif) {
      throw ErreurConformite(
          'Montant nul ou négatif sur « ${ligne.designation} ».', '§2.25');
    }

    final taxeSpecifique =
        ligne.taxeSpecifiqueUnitaire.multiplieParQuantite(ligne.quantite);

    lignesCalculees.add(LigneCalculee(
      source: ligne,
      montantBrut: montantBrut,
      montantNet: montantNet,
      taxeSpecifique: taxeSpecifique,
    ));
  }

  final totaux = <TotalGroupe>[];
  var totalImposable = const Montant.zero();
  var totalTaxe = const Montant.zero();
  var totalTaxeSpecifique = const Montant.zero();
  var totalTtc = const Montant.zero();

  for (final groupe in GroupeTaxation.tous) {
    final duGroupe =
        lignesCalculees.where((l) => l.groupeTaxation.etiquette == groupe.etiquette);
    if (duGroupe.isEmpty) continue;

    var cumulNet = const Montant.zero();
    var cumulTaxeSpecifique = const Montant.zero();
    for (final ligne in duGroupe) {
      cumulNet = cumulNet + ligne.montantNet;
      cumulTaxeSpecifique = cumulTaxeSpecifique + ligne.taxeSpecifique;
    }

    final total = _totaliserGroupe(
      groupe: groupe,
      modePrix: modePrix,
      cumulNet: cumulNet,
      taxeSpecifique: cumulTaxeSpecifique,
    );

    totaux.add(total);
    totalImposable = totalImposable + total.montantImposable;
    totalTaxe = totalTaxe + total.taxe;
    totalTaxeSpecifique = totalTaxeSpecifique + cumulTaxeSpecifique;
    totalTtc = totalTtc + total.montantTotal;
  }

  if (!totalTtc.estPositif) {
    throw const ErreurConformite(
        'Une facture ne peut pas avoir un montant nul ou négatif.', '§2.24');
  }

  // §6.10 : le PSVB se calcule sur le montant total toutes taxes comprises.
  var psvb = const Montant.zero();
  for (final groupePsvb in GroupePsvb.tous) {
    if (groupePsvb.tauxDixMillieme == 0) continue;
    var assiette = const Montant.zero();
    for (final ligne in lignesCalculees) {
      if (ligne.source.groupePsvb.etiquette != groupePsvb.etiquette) continue;
      assiette = assiette +
          _montantTtcDeLigne(ligne: ligne, modePrix: modePrix);
    }
    if (assiette.estNul) continue;
    psvb = psvb + assiette.appliqueTauxDixMillieme(groupePsvb.tauxDixMillieme);
  }

  return FactureCalculee(
    modePrix: modePrix,
    lignes: lignesCalculees,
    totauxParGroupe: totaux,
    totalImposable: totalImposable,
    totalTaxe: totalTaxe,
    totalTaxeSpecifique: totalTaxeSpecifique,
    totalTtc: totalTtc,
    psvb: psvb,
  );
}

/// Totalise un groupe de taxation.
///
/// C'est ici que se joue le §6.6 : en mode TTC le montant imposable se déduit
/// du montant total du groupe, en mode HT c'est l'inverse. Dans les deux cas
/// la taxe est arrondie à la valeur supérieure et le troisième terme s'obtient
/// par différence, ce qui garantit l'égalité exacte exigée au §6.7.
TotalGroupe _totaliserGroupe({
  required GroupeTaxation groupe,
  required ModePrix modePrix,
  required Montant cumulNet,
  required Montant taxeSpecifique,
}) {
  if (!groupe.estTaxe) {
    // Aucun taux : la taxe spécifique s'ajoute au montant, sans TVA.
    final total = cumulNet + taxeSpecifique;
    return TotalGroupe(
      groupe: groupe,
      montantImposable: total,
      taxe: const Montant.zero(),
      montantTotal: total,
    );
  }

  final taux = groupe.tauxMillieme!;

  if (modePrix == ModePrix.horsTaxe) {
    // §6.9 : le prix HT s'entend hors taxe spécifique ; lorsqu'elle
    // s'applique, la base de la TVA en est augmentée.
    final base = cumulNet + taxeSpecifique;
    final taxe = base.appliqueTauxArrondiSuperieur(taux);
    return TotalGroupe(
      groupe: groupe,
      montantImposable: base,
      taxe: taxe,
      montantTotal: base + taxe,
    );
  }

  // Mode TTC : le cumul contient déjà la TVA. La taxe spécifique est
  // comprise dans le prix affiché, elle ne s'ajoute donc pas au total.
  final total = cumulNet;
  final taxe = total.taxeIncluseArrondiSuperieur(taux);
  return TotalGroupe(
    groupe: groupe,
    montantImposable: total - taxe,
    taxe: taxe,
    montantTotal: total,
  );
}

/// Montant toutes taxes comprises d'une ligne, pour l'assiette du PSVB.
Montant _montantTtcDeLigne({
  required LigneCalculee ligne,
  required ModePrix modePrix,
}) {
  final groupe = ligne.groupeTaxation;

  if (modePrix == ModePrix.toutesTaxesComprises) {
    return ligne.montantNet;
  }

  final base = ligne.montantNet + ligne.taxeSpecifique;
  if (!groupe.estTaxe) return base;
  return base + base.appliqueTauxArrondiSuperieur(groupe.tauxMillieme!);
}
