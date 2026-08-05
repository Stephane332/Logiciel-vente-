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

  /// Comment le stock de cet article est suivi.
  ///
  /// `aucun`   — pas de suivi. C'est le défaut, et le cas d'un prestataire
  ///             de services ou d'un commerçant qui ne veut pas s'en occuper.
  /// `direct`  — l'article est vendu tel qu'il est acheté. Chaque vente
  ///             décrémente le stock. C'est le cas d'une boutique.
  /// `recette` — l'article est composé d'ingrédients. Le vendre consomme
  ///             autre chose que lui-même. C'est le cas d'un plat au
  ///             restaurant, traité par le module métier.
  TextColumn get suiviStock => text().withDefault(const Constant('aucun'))();

  /// Stock en millièmes d'unité. Nul tant que le commerçant ne l'a pas déclaré.
  IntColumn get stockMilliemes => integer().nullable()();

  TextColumn get photo => text().nullable()();
  DateTimeColumn get derniereVente => dateTime().nullable()();

  /// Quand le commerçant a répondu que ce prix recouvre plusieurs produits
  /// différents.
  ///
  /// Un article né d'un montant libre est identifié par son prix seul. C'est
  /// ce qui permet de démarrer sans rien saisir, mais c'est un pari : deux
  /// produits vendus au même prix tomberaient dans le même article. Le
  /// commerçant doit pouvoir refuser le pari — on cesse alors de lui proposer
  /// un nom, et l'article reste un fourre-tout assumé plutôt qu'un faux
  /// article dont le stock mentirait.
  DateTimeColumn get nommageRefuseLe => dateTime().nullable()();

  /// Quand le commerçant a répondu « plus tard » à la proposition de suivre
  /// le stock de cet article.
  ///
  /// Ça masque la proposition, pas la possibilité : l'article reste listé
  /// dans l'écran de stock, et le suivi peut démarrer à tout moment. Un refus
  /// par erreur ne coûte donc rien.
  DateTimeColumn get propositionSuiviReporteeLe => dateTime().nullable()();

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

  /// Où en est la vente : `ouverte`, `servie`, `soldee`.
  ///
  /// Une vente au comptoir traverse les trois en un seul geste. Une note de
  /// restaurant reste ouverte le temps du repas. Une vente à crédit est
  /// servie sans être soldée.
  TextColumn get etat => text().withDefault(const Constant('soldee'))();

  /// Ce qui regroupe les lignes tant que la vente est ouverte : une table,
  /// un numéro de ticket, un nom, une adresse. Nul au comptoir.
  TextColumn get contenant => text().nullable()();

  /// Nature du contenant : `table`, `ticket`, `client`, `livraison`.
  TextColumn get typeContenant => text().nullable()();

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

  /// Le numéro ramené à sa forme canonique : huit chiffres, sans indicatif
  /// ni espaces.
  ///
  /// C'est la seule identité stable d'une personne ici. Elle permettra de
  /// reconnaître le même client d'une boutique à l'autre — sous réserve de
  /// son consentement, et sans qu'aucun commerçant ne voie jamais ce qu'il
  /// achète ailleurs.
  TextColumn get telephoneNormalise => text().nullable()();

  /// Date à laquelle le client a accepté que son historique le suive d'une
  /// boutique à l'autre. Nulle tant qu'il n'a rien accepté.
  ///
  /// Donner son numéro pour recevoir un reçu n'est pas consentir à un profil
  /// permanent : ce sont deux choses distinctes, et elles le restent ici.
  DateTimeColumn get consentementLe => dateTime().nullable()();
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


/// Les réglages de la boutique.
///
/// Une simple table clé-valeur : ces paramètres sont peu nombreux, lus
/// rarement, et je préfère pouvoir en ajouter un sans migration de schéma.
/// Ils ne passent pas par le journal d'événements — ce n'est pas de
/// l'activité commerciale, et la DGI n'a rien à y vérifier.
/// Projection : ce qui a fait bouger le stock, hors vente.
///
/// Réceptions, comptages et pertes. Les ventes n'y sont pas : elles sont
/// déjà dans les lignes de vente. C'est le contrôle d'inventaire exigé au
/// §2.20, et c'est surtout ce qui permet de répondre à « où est passée la
/// différence ».
@DataClassName('LigneMouvementStock')
class MouvementsStock extends Table {
  TextColumn get id => text()();
  TextColumn get codeArticle => text()();
  DateTimeColumn get horodatage => dateTime()();

  /// `entree`, `inventaire` ou `perte`.
  TextColumn get nature => text()();

  /// Variation appliquée au stock, en millièmes. Négative pour une perte.
  ///
  /// Pour un inventaire, c'est l'écart constaté entre le stock connu et le
  /// stock compté — la valeur qui intéresse vraiment le patron.
  IntColumn get variationMilliemes => integer()();

  /// Stock après le mouvement, pour relire l'historique sans tout recalculer.
  IntColumn get stockApresMilliemes => integer()();

  TextColumn get motif => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LigneReglage')
class Reglages extends Table {
  TextColumn get cle => text()();
  TextColumn get valeur => text()();
  DateTimeColumn get modifieLe => dateTime()();

  @override
  Set<Column> get primaryKey => {cle};
}

@DriftDatabase(tables: [
  Evenements,
  Articles,
  Ventes,
  LignesVente,
  Paiements,
  Clients,
  MouvementsCaisse,
  MouvementsStock,
  Reglages,
])
class BaseLocale extends _$BaseLocale {
  BaseLocale(super.e);

  @override
  int get schemaVersion => 8;

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
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_clients_telephone '
            'ON clients (telephone_normalise)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_mouvements_stock_article '
            'ON mouvements_stock (code_article, horodatage)',
          );
        },
        onUpgrade: (m, depuis, vers) async {
          if (depuis < 2) {
            await m.addColumn(articles, articles.suiviStock);
          }
          if (depuis < 3) {
            await m.addColumn(ventes, ventes.etat);
            await m.addColumn(ventes, ventes.contenant);
            await m.addColumn(ventes, ventes.typeContenant);
          }
          if (depuis < 4) {
            await m.addColumn(clients, clients.telephoneNormalise);
            await m.addColumn(clients, clients.consentementLe);
          }
          if (depuis < 5) {
            await m.createTable(reglages);
          }
          if (depuis < 6) {
            await m.createTable(mouvementsStock);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_mouvements_stock_article '
              'ON mouvements_stock (code_article, horodatage)',
            );
          }
          if (depuis < 7) {
            await m.addColumn(articles, articles.propositionSuiviReporteeLe);
          }
          if (depuis < 8) {
            await m.addColumn(articles, articles.nommageRefuseLe);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
