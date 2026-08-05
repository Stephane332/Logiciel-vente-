/// Ouverture de la base dans le navigateur.
///
/// Sert à la démonstration : montrer l'application sur un ordinateur, sans
/// installation. Les données vivent dans le navigateur, pas sur un serveur.
library;

import 'package:drift/wasm.dart';

import 'base.dart';

Future<BaseLocale> ouvrirBaseLocale() async {
  final resultat = await WasmDatabase.open(
    databaseName: 'carnet',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return BaseLocale(resultat.resolvedExecutor);
}

Future<String> identifiantAppareil() async => 'DEMO';

String nouvelIdentifiantAppareil() => 'DEMO';
