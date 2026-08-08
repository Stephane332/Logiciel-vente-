/// Fichiers de sauvegarde dans le navigateur.
///
/// La version web sert de démonstration : elle n'a pas de dossier
/// d'application, et une sauvegarde y descend directement dans les
/// téléchargements. Rien n'est conservé d'une session à l'autre.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class FichierSauvegarde {
  final String chemin;
  final String nom;
  final DateTime ecritLe;
  final int octets;

  const FichierSauvegarde({
    required this.chemin,
    required this.nom,
    required this.ecritLe,
    required this.octets,
  });

  String get taille => '${(octets / 1024).round()} Ko';
}

/// Déclenche le téléchargement et rend le nom du fichier.
Future<String> ecrireSauvegarde(String nom, String contenu) async {
  final url = web.URL.createObjectURL(
    web.Blob(
      [contenu.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    ),
  );
  final lien = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = nom;
  lien.click();
  web.URL.revokeObjectURL(url);
  return nom;
}

/// Le navigateur ne garde rien : il n'y a pas de sauvegarde à retrouver.
Future<List<FichierSauvegarde>> sauvegardesLocales() async => const [];

Future<String> lireSauvegarde(String chemin) async => '';

Future<void> supprimerSauvegarde(String chemin) async {}

/// Le téléchargement est déjà la sortie du fichier.
Future<void> partagerSauvegarde(String chemin, {String? texte}) async {}

/// Ouvre le sélecteur de fichiers du navigateur.
Future<String?> choisirSauvegarde() async {
  final champ = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = '.carnet,application/json';
  champ.click();

  await champ.onChange.first;
  final fichier = champ.files?.item(0);
  if (fichier == null) return null;

  return utf8.decode((await fichier.arrayBuffer().toDart).toDart.asUint8List());
}

const choixDeFichierDisponible = true;
