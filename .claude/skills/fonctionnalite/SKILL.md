---
name: fonctionnalite
description: >
  Ajouter ou modifier une fonctionnalité de Carnet — une vente, un geste de
  caisse, un champ de stock, un écran, une donnée persistée. À charger avant
  d'écrire la première ligne, dès qu'un changement touche `lib/`. Impose la
  chaîne complète événement → migration → projection → rejeu → écran → tests
  → documentation, dans cet ordre, et nomme les maillons qu'on saute sans
  s'en apercevoir. Ne pas utiliser pour un changement qui ne touche que
  `docs/`, `outils/` ou le workflow.
---

# Ajouter une fonctionnalité

L'application est en **journal d'événements**. Le journal (`evenements`) est
la source de vérité ; les tables `ventes`, `articles`, `clients`… sont des
**projections** reconstructibles. Cette architecture pardonne tout sauf une
chose : oublier un maillon. Le code compile, les tests passent, l'écran
marche — et la donnée disparaît à la première restauration de sauvegarde ou
au premier `reconstruireProjections()`.

Suis les étapes dans l'ordre. Chacune est vérifiable avant de passer à la
suivante.

## 1. Décider si c'est un événement

Un événement, c'est **un fait irréversible de la vie du commerce** : une
vente, un remboursement, un article nommé, un stock ajusté. Pas un état
courant, pas une préférence d'affichage.

- Si c'en est un : ajoute une valeur à `TypeEvenement`
  (`lib/domaine/evenements.dart`).
- Si ce n'en est pas un (nom du commerce, numéro marchand, vendeur actif) :
  ça va dans `Reglages` via `lib/donnees/parametres.dart`, et tu sautes
  directement à l'étape 5.

**La clé d'un événement ne se renomme jamais.** Les valeurs (`'vente_enregistree'`,
`'article_retire'`…) sont écrites telles quelles dans le journal des
commerçants déjà installés. Renommer, c'est rendre leur journal illisible.
Une clé obsolète se garde ; on en ajoute une nouvelle à côté.

**Un événement par intention, pas par table touchée.** `stockAjuste` et
`suiviStockDefini` écrivent tous les deux dans `articles` ; ils sont
distincts parce que le rejeu devait sinon deviner lequel des deux en
reniflant la charge. Un journal ne se relit pas aux devinettes.

## 2. Migrer le schéma si une colonne ou une table change

Dans `lib/donnees/base.dart` :

1. Modifie la table (`class Articles extends Table`…). Toute colonne ajoutée
   à une table existante doit être **nullable ou avoir un défaut** — les
   bases installées ne peuvent pas fabriquer la valeur d'hier.
2. Incrémente `schemaVersion` (actuellement 9).
3. Ajoute une branche dans `onUpgrade` :
   ```dart
   if (depuis < 10) {
     await m.addColumn(articles, articles.nouvelleColonne);
   }
   ```
   Une branche par version, jamais de `else`. Un commerçant peut arriver
   de la version 6 : les branches s'enchaînent toutes.
4. Régénère : `dart run build_runner build --delete-conflicting-outputs`.
   Les `*.g.dart` ne sont pas versionnés.

## 3. Écrire la méthode d'écriture dans `depot.dart`

Le patron est toujours le même — copie-le sans l'inventer :

```dart
Future<String> monGeste(...) async {
  return base.transaction(() async {
    final evenement = await journal.ajouter(
      TypeEvenement.monType,
      { /* charge : des types JSON, jamais d'objet Dart */ },
      horodatage: quand,
    );
    await _appliquerMonGeste(evenement);
    return evenement.id;
  });
}

/// Applique … aux projections. Utilisé à l'écriture et au rejeu.
Future<void> _appliquerMonGeste(Evenement evenement) async { … }
```

Trois règles :

- **Une transaction**, toujours. Journal et projection tombent ensemble ou
  pas du tout.
- **`_appliquerX` ne lit que `evenement`** — sa charge et son horodatage.
  S'il consulte `DateTime.now()`, un identifiant global ou un réglage
  courant, le rejeu produira un autre résultat que l'écriture. C'est le bug
  le plus coûteux de cette architecture, et il ne se voit pas en usage
  normal.
- **La charge contient tout ce qu'il faut pour rejouer.** Le total d'une
  vente est dans la charge, même s'il se recalcule : le jour où le calcul
  change, l'historique ne doit pas bouger.

## 4. Brancher le rejeu — le maillon qu'on saute

`depot.dart` → `reconstruireProjections()`. Ajoute le `case` :

```dart
case TypeEvenement.monType:
  await _appliquerMonGeste(evenement);
```

**Sans ce `case`, tout fonctionne jusqu'au jour où quelqu'un restaure une
sauvegarde — et son geste a disparu.** Le `switch` est exhaustif sur l'enum :
si tu as ajouté la valeur à l'étape 1, l'analyse te le rappellera. Si tu as
réutilisé un type existant, personne ne te le rappellera.

## 5. L'écran

`lib/interface/ecrans/` pour un écran, `lib/interface/composants/` pour un
morceau réutilisé. Les couleurs viennent de `lib/interface/theme/palette.dart` —
aucune couleur en dur.

Trois exigences non négociables, chacune née d'un défaut trouvé sur le
terrain :

- **Tout élément tapable porte un `Semantics` avec un libellé qui se lit à
  voix haute** : `'<nom>, <prix>'`, `'<nom>, doit <montant>, voir le détail'`.
  Sans ça l'élément est invisible aux tests de parcours et aux lecteurs
  d'écran.
- **La zone tapable est exactement ce qui doit être tapable.** Un `InkWell`
  autour d'une carte entière avale les boutons qu'elle contient et fusionne
  leur sémantique. Un bandeau d'annulation dont toute la surface annule est
  un piège : seul le bouton annule.
- **Pas de `Container(alignment: …)` pour centrer une pastille** : il prend
  toute la largeur disponible. `Center(widthFactor: 1)`.

## 6. Les tests — trois familles, pas une

```sh
flutter test
```

Pour chaque geste ajouté :

1. **Le test de comportement** — le geste produit le bon état.
2. **Le test de rejeu** — obligatoire, et c'est celui qu'on oublie :
   ```dart
   test('le geste se rejoue depuis le journal', () async {
     await depot.monGeste(...);
     final avant = await depot.etatObserve();

     await depot.reconstruireProjections();

     expect(await depot.etatObserve(), avant);
   });
   ```
3. **Le test d'écran** si l'utilisateur le voit — dans `ecrans_test.dart`,
   `parcours_test.dart` ou un fichier dédié.

Deux pièges de test connus : `MontantAnime` peint les chiffres un par un,
donc `find.textContaining('600')` échoue — vise un libellé stable. Et un
parcours de vente n'est pas fini sans l'étape « Valider la vente ».

## 7. Vérifier

```sh
flutter analyze && flutter test
```

Les deux doivent être verts avant de committer. L'analyse ne tolère aucun
avertissement.

## 8. La documentation, si le commerçant le voit

Un geste que le commerçant fait doit exister dans le manuel. Charge la skill
`documents` : elle dit où l'ajouter et comment régénérer.

## 9. Le commit

Message à la première personne, qui explique **pourquoi**, pas quoi. Le
diff dit déjà quoi. Un titre court, une ligne vide, puis le raisonnement —
ce qui n'allait pas, ce que ça coûtait, ce que la correction change.
