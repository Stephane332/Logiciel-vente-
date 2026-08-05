/// Base locale.
///
/// Deux couches très différentes cohabitent ici.
///
/// La table `Evenements` est le **journal** : append-only, source de vérité,
/// jamais modifiée. Toutes les autres tables sont des **projections** :
/// l'état courant, reconstructible à partir du journal, stocké séparément
/// pour que l'affichage soit instantané.
///
/// Si une projection est corrompue, on la jette et on la reconstruit. Si le
/// journal est corrompu, on a perdu des données — d'où le chaînage
/// d'empreintes qui permet au moins de le détecter.
library;

import 'package:drift/drift.dart';

part 'base.g.dart';

/// Le journal. Append-only.
@DataClassName('LigneEvenement')
class Evenements extends Table {
  TextColumn get id => text()();
  TextColumn get appareil => text()();
  IntColumn get sequence => integer()();
  DateTimeColumn get horodatage => dateTime()();
  TextColumn get type => text()();
  TextColumn get charge => text()();
  TextColumn get empreinte => text()();
  TextColumn get empreintePrecedente => text().nullable()();

  /// Remonté au serveur ou non. Seule colonne du journal qui évolue.
  BoolColumn get synchronise => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projection : le catalogue.
///
/// Il n'est jamais saisi à l'avance. Un article naît de la première vente et
/// se précise au fil de l'usage.
@DataClassName('LigneArticle')
class Articles extends Table {
  TextColumn get code => text()();
  TextColumn get designation => text()();
  IntColumn get prixCentimes => integer()();
  TextColumn get groupeTaxation => text().withDefault(const Constant('A'))();
  TextColumn get groupePsvb => text().withDefault(const Constant('D'))();
  TextColumn get typeArticle => text().withDefault(const Constant('LOCBIE'))();

  /// Nombre de fois que l'article a été vendu.
  ///
  /// C'est ce compteur qui déclenche la proposition de nommage : au bout de
  /// quelques ventes, l'application demande au commerçant comment s'appelle
  /// ce qu'il vend si souvent.
  IntColumn get nombreVentes => integer().withDefault(const Constant(0))();

  /// Faux tant que le commerçant n'a pas donné de nom à l'article.
  BoolColumn get nomme => boolean().withDefault(const Constant(false))();

  /// Stock en millièmes d'unité. Nul tant que le commerçant ne l'a pas déclaré.
  IntColumn get stockMilliemes => integer().nullable()();

  TextColumn get photo => text().nullable()();
  DateTimeColumn get derniereVente => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {code};
}

/// Projection : les ventes.
@DataClassName('LigneVente')
class Ventes extends Table {
  TextColumn get id => text()();
  DateTimeColumn get horodatage => dateTime()();
  IntColumn get totalCentimes => integer()();

  /// Total des remises accordées : écart entre prix catalogue et prix pratiqué.
  IntColumn get remiseCentimes => integer().withDefault(const Constant(0))();

  TextColumn get clientId => text().nullable()();
  TextColumn get operateur => text().nullable()();

  /// Où en est la certification. Une vente naît non certifiée : la caisse
  /// fonctionne hors ligne, la certification vient ensuite.
  TextColumn get etatCertification =>
      text().withDefault(const Constant('enAttente'))();

  /// Numéro de facture, attribué à la certification. Nul avant.
  IntColumn get numero => integer().nullable()();
  IntColumn get anneeGestion => integer().nullable()();

  BoolColumn get annulee => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projection : les lignes de vente.
@DataClassName('LigneDeVente')
class LignesVente extends Table {
  TextColumn get id => text()();
  TextColumn get venteId => text().references(Ventes, #id)();
  TextColumn get codeArticle => text()();
  TextColumn get designation => text()();
  IntColumn get quantiteMilliemes => integer()();

  /// Prix réellement pratiqué.
  IntColumn get prixUnitaireCentimes => integer()();

  /// Prix du catalogue au moment de la vente, s'il en différait.
  ///
  /// Sur un marché le prix se négocie. On enregistre les deux, ce qui permet
  /// de montrer au commerçant l'écart entre sa marge théorique et sa marge
  /// réelle. La norme prévoit d'ailleurs ces deux champs.
  IntColumn get prixCatalogueCentimes => integer().nullable()();

  TextColumn get groupeTaxation => text()();
  IntColumn get montantCentimes => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projection : les règlements.
///
/// Une vente porte plusieurs règlements : l'encaissement mixte est courant,
/// et la DGI impose que leur somme égale le total de la facture (§2.22).
@DataClassName('LignePaiement')
class Paiements extends Table {
  TextColumn get id => text()();
  TextColumn get venteId => text().references(Ventes, #id)();
  TextColumn get mode => text()();
  IntColumn get montantCentimes => integer()();

  /// Référence de transaction mobile money, quand elle est connue.
  TextColumn get reference => text().nullable()();

  /// Numéro de l'expéditeur, extrait du SMS de confirmation.
  TextColumn get expediteur => text().nullable()();

  /// `attendu`, `confirmeAutomatiquement` ou `confirmeManuellement`.
  TextColumn get confirmation => text().withDefault(const Constant('attendu'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projection : les clients et leur encours.
///
/// Le fichier client se construit tout seul, comme le catalogue : un client
/// naît d'une vente à crédit ou d'un paiement mobile money reconnu.
@DataClassName('LigneClient')
class Clients extends Table {
  TextColumn get id => text()();
  TextColumn get nom => text()();
  TextColumn get telephone => text().nullable()();
  TextColumn get typeClient => text().withDefault(const Constant('CC'))();
  TextColumn get ifu => text().nullable()();

  /// Ce que le client doit, en centimes. C'est le cahier de dettes.
  IntColumn get encoursCentimes => integer().withDefault(const Constant(0))();

  DateTimeColumn get derniereActivite => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Projection : les mouvements de caisse.
///
/// Dépôts et retraits de numéraire, exigés au §2.13, et écarts constatés à la
/// clôture — la matière première de la détection d'anomalies.
@DataClassName('LigneMouvementCaisse')
class MouvementsCaisse extends Table {
  TextColumn get id => text()();
  DateTimeColumn get horodatage => dateTime()();

  /// `depot`, `retrait` ou `ecart`.
  TextColumn get nature => text()();

  IntColumn get montantCentimes => integer()();
  TextColumn get motif => text().nullable()();
  TextColumn get operateur => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Evenements,
  Articles,
  Ventes,
  LignesVente,
  Paiements,
  Clients,
  MouvementsCaisse,
])
class BaseLocale extends _$BaseLocale {
  BaseLocale(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Le journal se lit presque toujours dans l'ordre, par appareil.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_evenements_appareil_sequence '
            'ON evenements (appareil, sequence)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_evenements_synchronise '
            'ON evenements (synchronise)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ventes_horodatage '
            'ON ventes (horodatage)',
          );
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
