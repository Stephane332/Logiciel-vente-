/// Fichiers de sauvegarde sur Android et iOS.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as chemin;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Une sauvegarde posée sur le téléphone.
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

  /// Taille lisible. Une sauvegarde qui pèse zéro se repère à l'œil.
  String get taille {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) return '${(octets / 1024).round()} Ko';
    return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

/// Le dossier des sauvegardes, créé au besoin.
///
/// Dans le dossier de l'application : c'est le seul endroit où écrire sans
/// demander une permission de stockage, et une permission demandée au moment
/// d'une sauvegarde est une permission refusée.
Future<Directory> _dossier() async {
  final racine = await getApplicationDocumentsDirectory();
  final dossier = Directory(chemin.join(racine.path, 'sauvegardes'));
  if (!await dossier.exists()) await dossier.create(recursive: true);
  return dossier;
}

/// Écrit une sauvegarde et rend son chemin.
Future<String> ecrireSauvegarde(String nom, String contenu) async {
  final fichier = File(chemin.join((await _dossier()).path, nom));
  await fichier.writeAsString(contenu, flush: true);
  return fichier.path;
}

/// Les sauvegardes présentes sur le téléphone, la plus récente en tête.
Future<List<FichierSauvegarde>> sauvegardesLocales() async {
  final dossier = await _dossier();
  final fichiers = <FichierSauvegarde>[];

  await for (final entree in dossier.list()) {
    if (entree is! File || !entree.path.endsWith('.carnet')) continue;
    final infos = await entree.stat();
    fichiers.add(FichierSauvegarde(
      chemin: entree.path,
      nom: chemin.basename(entree.path),
      ecritLe: infos.modified,
      octets: infos.size,
    ));
  }

  fichiers.sort((a, b) => b.ecritLe.compareTo(a.ecritLe));
  return fichiers;
}

Future<String> lireSauvegarde(String chemin) => File(chemin).readAsString();

Future<void> supprimerSauvegarde(String chemin) async {
  final fichier = File(chemin);
  if (await fichier.exists()) await fichier.delete();
}

/// Ouvre le partage du système pour sortir la sauvegarde du téléphone.
///
/// C'est la moitié qui compte vraiment : un fichier qui reste sur le
/// téléphone disparaît avec lui. WhatsApp, Bluetooth, carte mémoire — peu
/// importe, pourvu qu'il finisse ailleurs.
Future<void> partagerSauvegarde(String chemin, {String? texte}) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(chemin, mimeType: 'application/json')],
    text: texte,
  ));
}

/// Demande au commerçant de désigner un fichier reçu de l'extérieur.
///
/// Renvoie `null` s'il ferme le sélecteur. Le contenu est relu ici plutôt que
/// le chemin rendu tel quel : sur Android le sélecteur donne parfois un
/// document sans chemin utilisable.
Future<String?> choisirSauvegarde() async {
  final choix = await FilePicker.platform.pickFiles(withData: true);
  final fichier = choix?.files.singleOrNull;
  if (fichier == null) return null;

  final octets = fichier.bytes;
  if (octets != null) return String.fromCharCodes(octets);

  final chemin = fichier.path;
  if (chemin == null) return null;
  return File(chemin).readAsString();
}

/// Vrai quand la plateforme sait aller chercher un fichier hors du dossier.
const choixDeFichierDisponible = true;
