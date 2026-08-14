# Carnet — repères de travail

Application de gestion pour les commerçants du Burkina Faso. Flutter, hors
ligne d'abord, Android en premier. Le positionnement tient en une phrase :
**le carnet du commerçant, en mieux** — pas un ERP.

## Les règles qui ne se discutent pas

- **Mon vrai numéro Orange Money ne va jamais dans le dépôt.** Ni dans un
  test, ni dans une capture, ni dans un exemple, ni dans un message de
  commit. Le numéro fictif est `70000000`. Ce qui est commité un jour reste
  lisible dans l'historique.
- **La documentation est à la première personne**, professionnelle, et ne
  laisse pas voir comment elle a été produite.
- **Aucun abonnement à une API payante.** Le mobile money passe par USSD et
  code QR, sans contrat.
- **Branche de travail : `claude/commerce-management-software-fr1baz`.**
  Pas de poussée ailleurs, pas de *pull request* sans demande explicite.
- **Le journal ne se réécrit pas.** Une clé de `TypeEvenement` ne se renomme
  jamais ; une correction s'ajoute, elle n'efface pas.
- **L'argent est entier.** `Montant` en centimes, `Quantite` en millièmes.
  Aucun flottant ne touche à une somme.

## L'architecture en trois phrases

Le journal d'événements (`evenements`) est la source de vérité. Les tables
`ventes`, `articles`, `clients` sont des projections que
`reconstruireProjections()` sait refaire à partir de zéro. Ce choix sert la
persistance, la synchronisation à venir, et le journal électronique exigé par
la DGI — construit une fois, il répond aux trois.

```
lib/domaine/     règles métier pures, sans base ni écran
lib/donnees/     base Drift, journal, dépôt, sauvegarde, réglages
lib/interface/   écrans, composants, thème
test/            410 tests
docs/            documentation et documents produits
outils/          générateurs de documents et scripts de pilotage
```

## Les commandes

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # les *.g.dart ne sont pas versionnés
flutter analyze && flutter test
```

## Les skills

Elles portent les enchaînements complets, avec les maillons qu'on saute sans
s'en apercevoir. Les charger avant de commencer, pas après.

| Skill | Quand |
|---|---|
| `fonctionnalite` | Tout changement dans `lib/` |
| `livraison` | Publier une version, transmettre l'APK, la clé de signature |
| `terrain` | Piloter l'application dans un navigateur, capturer, chercher un défaut d'usage |
| `documents` | Manuel, guide, page d'accueil, captures |
| `conformite` | Facture, taxe, rapport X/Z/A, annulation, homologation |
