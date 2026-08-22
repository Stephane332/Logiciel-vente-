# Logiciel de gestion pour commerçants — Burkina Faso

Je construis un logiciel qui permet à un commerçant burkinabè — boutique, restaurant,
fast-food, prestataire de services — d'avoir un suivi clair et honnête de son commerce :
tout est calculé, tout est contrôlable, les vérifications sont rapides et l'évolution est
visible dans le temps.

## Le problème

Chaque commerçant tient déjà un cahier : ses ventes, ses dettes, son stock. Ce cahier se
perd, se trompe et ne dit rien de l'évolution du commerce. Les logiciels existants
demandent de saisir un inventaire complet avant de servir à quoi que ce soit, exigent une
connexion permanente, et supposent que le commerçant sait tenir une comptabilité.

À cela s'ajoute une contrainte nouvelle : depuis le 1er juillet 2026, la facture
électronique certifiée est obligatoire pour les entreprises au Régime Normal d'Imposition.

## Ce que je construis

Le carnet du commerçant, en mieux. Pas un ERP.

- **Aucun inventaire à saisir pour démarrer.** Le catalogue et le stock se construisent
  tout seuls au fil des ventes.
- **Aucune formation nécessaire.** Gros boutons, photos des produits, pas de formulaire.
  Objectif tenu : première vente en moins de 60 secondes, sans explication.
- **Fonctionne sans réseau et sans courant.** Le hors-ligne est le mode normal, pas un
  mode dégradé.
- **Encaissement mobile money sans frais d'API**, par code QR et USSD.
- **Crédit client** avec relance automatique — le point de douleur le plus réel.
- **Rapport du soir** envoyé au patron, où qu'il soit.
- **Facturation certifiée** conforme aux spécifications de la DGI.

## Périmètre

Un socle commun — ventes, encaissement, crédit client, stock, rapports, facturation
certifiée — puis des modules par métier : restaurant, services. Le socle sert tous les
secteurs et représente l'essentiel du travail.

## Plateformes

Android et iOS, en une seule base de code Flutter. La caisse tourne principalement sur
Android ; l'iPhone sert de console pour le propriétaire. Les fonctions propres à Android
(USSD, capture des SMS de confirmation) sont isolées derrière une interface commune, avec
un relais qui les rend disponibles côté Apple.

## État du projet

En construction. La feuille de route détaillée se trouve dans
[`docs/06-feuille-de-route.md`](docs/06-feuille-de-route.md).

## Essayer l'application

**Sur un téléphone Android.** Les APK prêts à installer sont sur la
[page des versions](https://github.com/Stephane332/Logiciel-vente-/releases/latest) :
`arm64-v8a` pour la quasi-totalité des téléphones vendus depuis 2016,
`universel` quand on ne sait pas quel téléphone est au bout du WhatsApp. On
ouvre le fichier, Android demande d'autoriser l'installation depuis cette
source-là, et l'application s'ouvre sur la caisse — rien à configurer.

Chaque poussée de code déclenche par ailleurs une compilation chez GitHub :
analyse, tests, puis les mêmes quatre APK dans l'onglet **Actions**. Un
fichier qu'on ne peut refaire qu'à la main est un fichier qui finit périmé. La
marche à suivre, la clé de signature et ce qu'il ne faut pas perdre sont dans
[`docs/13-installation-android.md`](docs/13-installation-android.md).

**Les deux documents pour s'en servir.** `docs/manuel.html` est rangé par
métier puis par situation — c'est celui qu'on ouvre devant un commerçant.
`docs/guide-utilisation.html` est rangé par fonction, dans l'ordre où
l'application se découvre, et existe aussi en PDF. Les deux sont autonomes :
polices et captures embarquées, aucun appel au réseau, lisibles depuis une
clé USB.

**Dans un navigateur.** L'application se compile aussi pour le web, et
`docs/app/` porte cette version prête à servir. Elle montre les gestes, pas
plus : le stockage local d'un navigateur n'accepte pas toujours d'écrire, et
l'application prévient quand c'est le cas. Le composeur téléphonique, le
partage WhatsApp et l'appareil photo n'y existent pas non plus.

Une précision, parce que la page d'accueil promet que rien ne sort du
navigateur : le moteur web de Flutter demande au démarrage une police de
secours à `fonts.gstatic.com`. Aucune donnée de vente n'y passe, la requête
échoue sans conséquence hors ligne, et il n'existe pas d'option pour la
couper — mais elle existe, et autant le dire. Sur téléphone, rien de tel :
les polices sont dans l'APK.

## Démarrer

```sh
flutter pub get
dart run build_runner build    # génère le code de la base locale
flutter test
```

Pour une démonstration sans rien installer, l'application se compile aussi pour le
navigateur — les données vivent alors dans le navigateur, pas sur un serveur :

```sh
flutter build web --release --no-web-resources-cdn \
  --base-href /Logiciel-vente-/app/ --output docs/app
```

`--no-web-resources-cdn` embarque le moteur de rendu au lieu d'aller le
chercher chez Google, et `--base-href` dit à la page qu'elle est servie depuis
un sous-dossier : sans lui elle reste blanche, sans message.

Le code généré par Drift (`*.g.dart`) n'est pas versionné : il se régénère à partir du
schéma. Il faut donc lancer `build_runner` après un clone ou une modification des tables.

## Documentation

| Document | Contenu |
|---|---|
| [`docs/01-cadrage.md`](docs/01-cadrage.md) | Marché, positionnement, modèle économique |
| [`docs/02-conformite-dgi.md`](docs/02-conformite-dgi.md) | Exigences de la facturation certifiée |
| [`docs/03-architecture.md`](docs/03-architecture.md) | Choix techniques et justifications |
| [`docs/04-paiement-mobile-money.md`](docs/04-paiement-mobile-money.md) | Conception de l'encaissement |
| [`docs/05-modele-donnees.md`](docs/05-modele-donnees.md) | Modèle de données |
| [`docs/06-feuille-de-route.md`](docs/06-feuille-de-route.md) | Phases et jalons |
| [`docs/07-protocole-mcf.md`](docs/07-protocole-mcf.md) | Protocole de dialogue avec le module de contrôle |
| [`docs/08-idees-produit.md`](docs/08-idees-produit.md) | Idées à évaluer sur le terrain |
| [`docs/09-homologation.md`](docs/09-homologation.md) | Procédure d'homologation du SFE |
| [`docs/10-parcours-de-vente.md`](docs/10-parcours-de-vente.md) | Parcours de vente et types de clients |
| [`docs/11-cote-client.md`](docs/11-cote-client.md) | Ce que reçoit le client, par parcours |
| [`docs/12-historique-et-donnees-personnelles.md`](docs/12-historique-et-donnees-personnelles.md) | Historique client, identité et confidentialité |
| [`docs/13-installation-android.md`](docs/13-installation-android.md) | Compiler, signer et installer sur un téléphone |
| [`docs/14-rendre-le-depot-public.md`](docs/14-rendre-le-depot-public.md) | Ce qu'ouvrir le dépôt exposerait, et par quelle route |
