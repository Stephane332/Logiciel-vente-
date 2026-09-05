---
name: defaut
description: >
  Corriger un défaut de Carnet — quelque chose qui ne marche pas, un écran qui
  ment, un chiffre faux, un bouton mort, un commerçant qui rapporte un
  problème. À charger dès qu'il s'agit de « corriger », « réparer », « ça ne
  marche pas », « c'est faux », « bug ». Différent de `fonctionnalite`, qui
  construit du neuf : ici on part d'un symptôme, on remonte à la cause, et on
  laisse derrière un test qui échouerait sans la correction.
---

# Corriger un défaut

Un défaut corrigé sans test revient. Un défaut corrigé sans avoir été
reproduit n'est pas corrigé — on a soigné autre chose.

## 1. Reproduire avant de comprendre

Ne jamais corriger sur la foi d'une lecture de code. Trois façons de
reproduire, par ordre de préférence :

- **Un test qui échoue.** C'est la meilleure : il devient le garde-fou.
- **Piloter l'application** — charge la skill `terrain`. C'est ainsi qu'ont
  été trouvés le bandeau dont toute la surface annulait les ventes, les
  pastilles qui prenaient une ligne entière, la tuile morte, et le dernier mot
  anglais de l'interface.
- **Lire la donnée**, quand le symptôme est un chiffre : rejouer le journal et
  regarder ce qui en sort.

Si le défaut ne se reproduit pas, dis-le. Une correction posée sur une
hypothèse est une deuxième chance de casser quelque chose.

## 2. Remonter à la cause, pas au symptôme

Trois questions qui évitent les fausses corrections :

- **Est-ce que ça ment, ou est-ce que ça casse ?** Un écran qui affiche une
  valeur constante en la présentant comme un état est un défaut, même si rien
  ne plante.
- **Est-ce que ça touche le journal ?** Si oui, la correction s'**ajoute**,
  elle ne réécrit jamais. Une clé de `TypeEvenement` ne se renomme pas, un
  événement passé ne se modifie pas — même faux. On corrige par un événement
  qui annule, comme la DGI l'impose pour les factures.
- **Combien d'endroits font la même chose ?** Si la même règle est écrite à
  deux endroits, l'un des deux est déjà en train de diverger. Corriger le
  symptôme aux deux endroits, c'est signer pour une troisième fois.

## 3. Le test d'abord, la correction ensuite

Écris le test, lance-le, **vérifie qu'il échoue**. Un test écrit après la
correction et qui passe du premier coup ne prouve rien : il peut très bien
passer aussi sans elle.

Puis corrige, et relance : il doit passer. **Retire la correction une fois
pour voir le test retomber** — c'est ce qui distingue un garde-fou d'une
décoration. Deux minutes, et c'est ce qui a prouvé que les quatre tests de
langue tenaient vraiment.

Le test se range là où vit la règle, pas là où le symptôme est apparu : une
erreur de calcul va dans les tests du domaine, un écran qui ment dans les
tests d'écran.

## 4. Vérifier de la même façon qu'on a trouvé

Si le défaut a été trouvé en pilotant, la correction se vérifie en pilotant.
Un test widget vert ne prouve pas qu'un écran a cessé de mentir — c'est
exactement ce qui avait laissé passer les défauts d'origine.

```sh
flutter analyze && flutter test
```

Les deux verts, sans exception.

## 5. Regarder ce que la correction déplace

Ce qui casse le plus souvent après une correction d'interface :

- **Les tests qui comptaient.** Retirer une tuile d'action fait échouer les
  tests qui en attendaient deux, ailleurs que là où on a touché.
- **Les captures de la documentation.** Un écran qui change périme les images
  du manuel et du guide — charge la skill `documents`.
- **Ce qui est écrit ailleurs.** Un comportement corrigé rend faux le
  paragraphe qui le décrivait.

## 6. Le garder

Un défaut d'usage trouvé et corrigé a sa place dans `docs/audit-usage.html` :
ce qui n'allait pas, ce que ça coûtait, ce que ça change. Publier ses défauts
est une force quand on les a corrigés.

Le message de commit dit **pourquoi**, pas quoi : ce que le défaut coûtait à
un commerçant, et ce que la correction lui rend. Le diff dit déjà quoi.
