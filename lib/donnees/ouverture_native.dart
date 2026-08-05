/// Ouverture de la base sur Android et iOS.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as chemin;
import 'package:path_provider/path_provider.dart';

import 'base.dart';

/// Ouvre la base locale de l'appareil, en la créant si besoin.
Future<BaseLocale> ouvrirBaseLocale() async {
  final dossier = await getApplicationDocumentsDirectory();
  final fichier = File(chemin.join(dossier.path, 'carnet.sqlite'));
  return BaseLocale(NativeDatabase.createInBackground(fichier));
}

/// Identifiant de cet appareil, stable d'un lancement à l'autre.
///
/// Il sert à ordonner les événements du journal et à repérer, à la
/// synchronisation, quel appareil a produit quoi. Il est stocké à côté de la
/// base plutôt qu'en base : il doit survivre à une reconstruction.
Future<String> identifiantAppareil() async {
  final dossier = await getApplicationDocumentsDirectory();
  final fichier = File(chemin.join(dossier.path, 'appareil.txt'));

  if (await fichier.exists()) {
    final contenu = (await fichier.readAsString()).trim();
    if (contenu.isNotEmpty) return contenu;
  }

  final identifiant = nouvelIdentifiantAppareil();
  await fichier.writeAsString(identifiant);
  return identifiant;
}

String nouvelIdentifiantAppareil() {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  var valeur = DateTime.now().microsecondsSinceEpoch;
  final tampon = StringBuffer();
  for (var i = 0; i < 6; i++) {
    tampon.write(alphabet[valeur % 32]);
    valeur ~/= 32;
  }
  return tampon.toString();
}
