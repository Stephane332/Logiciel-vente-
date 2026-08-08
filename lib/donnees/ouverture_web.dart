/// Ouverture de la base dans le navigateur.
///
/// Sert à la démonstration : montrer l'application sur un ordinateur, sans
/// installation. Les données vivent dans le navigateur, pas sur un serveur.
library;

import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

import 'base.dart';

/// Vrai quand ce navigateur a **prouvé** qu'il garde les données.
///
/// Prouvé, pas annoncé. Drift dit avoir choisi un rangement persistant, et
/// pourtant j'ai mesuré le contraire : le fichier de base est créé, puis plus
/// aucune écriture n'atteint le stockage — quarante-huit blocs avant une
/// vente, quarante-huit après, et rien de plus au bout d'une demi-minute.
/// Selon le navigateur et ce qu'il autorise, ça marche ou ça ne marche pas,
/// et la seule façon de savoir laquelle est de laisser passer une session.
///
/// C'est [main] qui pose la réponse, en cherchant le témoin déposé la fois
/// d'avant. Un commerçant qui saisit sa journée et la retrouve vide n'ouvrira
/// pas l'application une deuxième fois : mieux vaut l'avertir avant qu'il ne
/// tape quoi que ce soit.
bool stockagePersistant = false;

/// Vrai : dans un navigateur, la persistance se démontre.
const stockageADemontrer = true;

/// Les rangements que j'accepte, du meilleur au moins bon.
///
/// L'ordre n'est pas celui de drift, et c'est délibéré. Drift préfère
/// `sharedIndexedDb`, qui fait vivre la base dans un *shared worker* partagé
/// entre onglets — élégant, mais quand le navigateur ne sait pas lancer un
/// worker dédié à l'intérieur d'un worker partagé, ce que Chromium annonce
/// justement comme manquant, rien n'est jamais écrit sur le disque. J'ai
/// perdu une vente entière à le vérifier.
///
/// `unsafeIndexedDb` écrit sans détour. Son « unsafe » vise le cas de deux
/// onglets ouverts sur la même boutique, qui s'écraseraient l'un l'autre. Un
/// commerçant a un téléphone et un onglet ; sur mobile, c'est SQLite en
/// fichier de toute façon, et cette liste ne sert plus.
const _preferences = [
  WasmStorageImplementation.opfsShared,
  WasmStorageImplementation.opfsLocks,
  WasmStorageImplementation.unsafeIndexedDb,
  WasmStorageImplementation.sharedIndexedDb,
];

Future<BaseLocale> ouvrirBaseLocale() async {
  final sonde = await WasmDatabase.probe(
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
    databaseName: 'carnet',
  );

  final choisi = _preferences.firstWhere(
    sonde.availableStorages.contains,
    orElse: () => WasmStorageImplementation.inMemory,
  );
  if (kDebugMode) {
    debugPrint('Stockage : $choisi · disponibles ${sonde.availableStorages} '
        '· manquant ${sonde.missingFeatures}');
  }

  final connexion = await sonde.open(choisi, 'carnet');
  return BaseLocale(connexion);
}

Future<String> identifiantAppareil() async => 'DEMO';

String nouvelIdentifiantAppareil() => 'DEMO';
