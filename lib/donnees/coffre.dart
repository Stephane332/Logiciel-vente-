/// Chiffrer une sauvegarde, quand le commerçant le demande.
///
/// Le fichier de sauvegarde contient tout : le nom de chaque client, son
/// téléphone, ce qu'il doit. Il part par WhatsApp, par Bluetooth, sur une
/// carte mémoire — et il reste lisible par tous ceux qui le reçoivent, ou qui
/// le retrouvent sur un téléphone perdu. C'est le seul endroit où cette
/// application expose les données de quelqu'un d'autre que son utilisateur.
///
/// **Ce n'est pas activé d'office, et c'est délibéré.** Un mot de passe oublié
/// rend la sauvegarde définitivement illisible : on échangerait une perte
/// contre une autre, chez des gens qui n'ont pas de gestionnaire de mots de
/// passe. Le choix revient au commerçant, en connaissance de cause — et sans
/// mot de passe, le fichier reste ce qu'il était : du JSON qu'on peut ouvrir
/// et inspecter le jour où une restauration échoue.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Nombre de tours de dérivation.
///
/// Cent mille sur un téléphone d'entrée de gamme, c'est une petite seconde :
/// assez pour rendre coûteuse l'attaque d'un mot de passe court, assez peu
/// pour que personne ne croie l'application bloquée.
const _tours = 100000;

/// Longueur du sel, en octets. Tiré au hasard à chaque sauvegarde : deux
/// fichiers protégés par le même mot de passe ne doivent pas se ressembler.
const _octetsDeSel = 16;

/// Enveloppe chiffrée, telle qu'elle est écrite dans le fichier.
///
/// Elle reste du JSON, et garde en clair de quoi reconnaître le fichier : son
/// application, son format, la date et le nom du commerce. Ce qui est protégé,
/// c'est le carnet — les clients, les dettes, les ventes.
class Coffre {
  static const marque = 'carnet';

  /// Vrai quand le contenu est une enveloppe chiffrée.
  ///
  /// Se répond sans mot de passe : l'écran de restauration doit savoir s'il
  /// faut en demander un **avant** de demander quoi que ce soit.
  static bool estChiffre(String contenu) {
    final brut = _lire(contenu);
    return brut != null && brut['chiffre'] == true;
  }

  /// Ce que le fichier dit de lui-même sans être déchiffré : le commerce et la
  /// date. De quoi choisir le bon fichier parmi trois, sans le mot de passe.
  static (String nomCommerce, DateTime? faiteLe)? entete(String contenu) {
    final brut = _lire(contenu);
    if (brut == null || brut['chiffre'] != true) return null;
    return (
      brut['nomCommerce'] as String? ?? '',
      DateTime.tryParse(brut['faiteLe'] as String? ?? ''),
    );
  }

  /// Enferme [clair] sous [motDePasse].
  static Future<String> fermer(
    String clair, {
    required String motDePasse,
    required int format,
    String nomCommerce = '',
    DateTime? faiteLe,
  }) async {
    final algorithme = AesGcm.with256bits();
    final sel = _sel();
    final cle = await _deriver(motDePasse, sel);

    final scelle = await algorithme.encrypt(
      utf8.encode(clair),
      secretKey: cle,
    );

    return jsonEncode({
      'application': marque,
      'format': format,
      'chiffre': true,
      'nomCommerce': nomCommerce,
      'faiteLe': (faiteLe ?? DateTime.now()).toIso8601String(),
      'sel': base64Encode(sel),
      'nonce': base64Encode(scelle.nonce),
      'sceau': base64Encode(scelle.mac.bytes),
      'contenu': base64Encode(scelle.cipherText),
    });
  }

  /// Rouvre une enveloppe. Renvoie `null` si le mot de passe ne va pas, ou si
  /// le fichier a été abîmé en route — les deux cas se traitent pareil : on
  /// n'écrit rien.
  static Future<String?> ouvrir(String contenu, String motDePasse) async {
    final brut = _lire(contenu);
    if (brut == null || brut['chiffre'] != true) return null;

    final sel = _octets(brut['sel']);
    final nonce = _octets(brut['nonce']);
    final sceau = _octets(brut['sceau']);
    final chiffre = _octets(brut['contenu']);
    if (sel == null || nonce == null || sceau == null || chiffre == null) {
      return null;
    }

    try {
      final cle = await _deriver(motDePasse, sel);
      final clair = await AesGcm.with256bits().decrypt(
        SecretBox(chiffre, nonce: nonce, mac: Mac(sceau)),
        secretKey: cle,
      );
      return utf8.decode(clair);
    } on SecretBoxAuthenticationError {
      // Mot de passe faux, ou fichier modifié. Le sceau ne fait pas la
      // différence, et c'est très bien ainsi.
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<SecretKey> _deriver(String motDePasse, List<int> sel) =>
      Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _tours,
        bits: 256,
      ).deriveKeyFromPassword(password: motDePasse, nonce: sel);

  static List<int> _sel() =>
      SecretKeyData.random(length: _octetsDeSel).bytes;

  static Map<String, Object?>? _lire(String contenu) {
    try {
      final brut = jsonDecode(contenu);
      if (brut is! Map<String, Object?>) return null;
      if (brut['application'] != marque) return null;
      return brut;
    } on FormatException {
      return null;
    }
  }

  static Uint8List? _octets(Object? valeur) {
    if (valeur is! String) return null;
    try {
      return base64Decode(valeur);
    } on FormatException {
      return null;
    }
  }
}
