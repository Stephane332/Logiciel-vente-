/// Les événements du journal.
///
/// Le journal est la source de vérité. Tout ce qui se passe dans la boutique
/// y est écrit une fois, définitivement : rien n'est jamais modifié ni
/// supprimé. L'état courant — stock, encours client, totaux — est une
/// projection reconstructible à partir de ces événements.
///
/// Ce choix sert trois besoins d'un coup : la persistance, la synchronisation
/// entre appareils, et le journal électronique inaltérable exigé au §2.23 de
/// la note de service.
///
/// Une correction ne réécrit donc jamais le passé : elle ajoute un événement
/// qui l'annule. C'est aussi ce qu'impose la DGI, qui traite les annulations
/// et les remises par facture d'avoir (§2.28, §2.29).
library;

import 'dart:convert';

/// Nature d'un événement.
///
/// Les valeurs sont écrites telles quelles dans le journal : **ne jamais les
/// renommer**, un journal existant deviendrait illisible.
enum TypeEvenement {
  venteEnregistree('vente_enregistree'),
  venteOuverte('vente_ouverte'),
  lignesAjoutees('lignes_ajoutees'),
  venteServie('vente_servie'),
  venteSoldee('vente_soldee'),
  venteAnnulee('vente_annulee'),
  articleCree('article_cree'),
  articleNomme('article_nomme'),
  articlePrixModifie('article_prix_modifie'),
  stockAjuste('stock_ajuste'),
  clientCree('client_cree'),
  creditAccorde('credit_accorde'),
  creditRembourse('credit_rembourse'),
  caisseMouvement('caisse_mouvement'),
  ventecertifiee('vente_certifiee');

  final String cle;
  const TypeEvenement(this.cle);

  static TypeEvenement parCle(String cle) => values.firstWhere(
        (t) => t.cle == cle,
        orElse: () => throw ArgumentError("Type d'événement inconnu : $cle"),
      );
}

/// Un événement du journal, tel qu'il est écrit et relu.
class Evenement {
  /// Identifiant unique, trié par ordre chronologique.
  final String id;

  /// Appareil qui a produit l'événement.
  final String appareil;

  /// Compteur monotone propre à l'appareil. Une rupture signale une perte.
  final int sequence;

  final DateTime horodatage;
  final TypeEvenement type;

  /// Contenu de l'événement.
  final Map<String, Object?> charge;

  /// Empreinte de l'événement précédent, sur cet appareil.
  ///
  /// Nulle pour le tout premier événement.
  final String? empreintePrecedente;

  /// Empreinte de cet événement, calculée sur son contenu **et** sur celle
  /// qui précède. C'est ce chaînage qui rend le journal inaltérable :
  /// modifier un événement ancien invalide toute la suite.
  final String empreinte;

  const Evenement({
    required this.id,
    required this.appareil,
    required this.sequence,
    required this.horodatage,
    required this.type,
    required this.charge,
    required this.empreinte,
    this.empreintePrecedente,
  });

  /// Représentation canonique servant au calcul de l'empreinte.
  ///
  /// Les clés sont triées : deux appareils doivent produire exactement la
  /// même chaîne pour un même événement, sinon les empreintes divergent.
  String get representationCanonique {
    final triee = Map.fromEntries(
      charge.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return jsonEncode({
      'id': id,
      'appareil': appareil,
      'sequence': sequence,
      'horodatage': horodatage.toUtc().millisecondsSinceEpoch,
      'type': type.cle,
      'charge': triee,
      'precedente': empreintePrecedente,
    });
  }

  String get chargeJson => jsonEncode(charge);

  static Map<String, Object?> chargeDepuisJson(String json) =>
      Map<String, Object?>.from(jsonDecode(json) as Map);
}

/// Génère des identifiants triés par ordre chronologique.
///
/// Un identifiant purement aléatoire obligerait à trier sur l'horodatage,
/// avec des ex æquo à la milliseconde. Ici, l'ordre alphabétique des
/// identifiants est déjà l'ordre chronologique.
class GenerateurIdentifiant {
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final String appareil;
  int _compteur = 0;

  GenerateurIdentifiant(this.appareil);

  String suivant(DateTime horodatage) {
    final millis = horodatage.toUtc().millisecondsSinceEpoch;
    final temps = _base32(millis, 10);
    final suffixe = _base32(_compteur++, 4);
    return '$temps-$suffixe-$appareil';
  }

  static String _base32(int valeur, int longueur) {
    var v = valeur;
    final tampon = List<String>.filled(longueur, '0');
    for (var i = longueur - 1; i >= 0; i--) {
      tampon[i] = _alphabet[v % 32];
      v ~/= 32;
    }
    return tampon.join();
  }
}
