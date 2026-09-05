# Parcours de vente

## Le principe

L'erreur serait de construire un « mode boutique », un « mode restaurant » et un « mode
services ». C'est faux : un restaurant fait aussi de la vente à emporter immédiate, une
boutique prend aussi commande de ce qu'elle n'a pas en stock, et un prestataire encaisse
parfois au comptoir.

Ce qui change réellement d'un commerce à l'autre, c'est **l'ordre de trois moments** :
commander, servir, payer.

Il n'y a donc qu'un seul concept — la **vente** — qui porte un état, et dont l'ordre entre
« servi » et « payé » varie. Pas trois produits, pas trois bases.

## Les six parcours

| Parcours | Ordre | Pour qui |
|---|---|---|
| **Comptoir** | les trois en même temps | Boutique, kiosque, vente de rue |
| **Note ouverte** | commande → sert → paie | Restaurant, maquis |
| **À emporter** | commande → paie → sert | Fast-food, pâtisserie |
| **Réservation** | commande → acompte → sert → solde | Hôtel, événementiel, atelier |
| **Crédit** | commande → sert → paie plus tard | Tous. Très courant ici. |
| **Devis** | propose → accepte → sert → facture | Prestataires, B2B |

La DGI a d'ailleurs prévu le cas de l'acompte : le type de facture **`FT` — facture d'acompte
ou d'avance** figure dans la spécification (§2.7). Une réservation avec arrhes est
fiscalement anticipée.

## Le cycle de vie d'une vente

```
ouverte ──────► servie ──────► soldée ──────► certifiée
   │                                              ▲
   └──────────── annulée                          │
                                    (au retour du réseau)
```

- **ouverte** — des lignes peuvent encore s'ajouter. C'est la note du restaurant, la commande
  en préparation, le devis en cours.
- **servie** — la marchandise est remise ou le service rendu, mais tout n'est pas encaissé.
  C'est l'état d'une vente à crédit.
- **soldée** — la somme des règlements égale le total. C'est l'état terminal côté commerce.
- **certifiée** — les éléments de sécurité du module de contrôle sont attachés. Cet axe est
  indépendant : une vente peut être soldée depuis trois jours et attendre encore le réseau.
- **annulée** — jamais effacée. Une annulation ajoute un événement, comme l'impose la DGI qui
  traite les annulations par facture d'avoir (§2.28).

Une vente au comptoir traverse les trois premiers états **en un seul geste**. C'est le cas le
plus fréquent, et il ne doit rien coûter de plus au commerçant.

## Le contenant

C'est ce qui regroupe les lignes tant que la vente est ouverte. Même champ, rempli
différemment selon le métier :

| Type | Contenu | Métier |
|---|---|---|
| `table` | « Table 4 » | Restaurant, maquis |
| `ticket` | « 12 » | Fast-food, à emporter |
| `client` | « Awa · 70 11 22 33 » | Réservation, crédit |
| `livraison` | une adresse | Livraison |
| *aucun* | — | Comptoir |

Le vocabulaire affiché change avec lui — « note », « commande », « devis » — mais l'objet
sous-jacent est le même.

## Les clients

Un seul modèle, avec un principe ferme : **ne jamais demander plus que le parcours n'exige.**

| Le client est… | Quand | Ce qu'on lui demande |
|---|---|---|
| **Anonyme** | Comptoir. La grande majorité des ventes. | Rien. Type `CC` de la DGI. |
| **Une place** | Restaurant | Un numéro de table. Ce n'est pas une personne. |
| **Un numéro d'attente** | À emporter | Un ticket, éventuellement un téléphone. |
| **Une personne connue** | Crédit, réservation, livraison | Nom et téléphone. Sans eux, impossible de relancer ni de livrer. |
| **Une entreprise** | B2B, facture certifiée | Nom, IFU, adresse. Types `PM` ou `PC`. |

Le fichier client se construit **tout seul**, comme le catalogue : un client naît d'une dette,
d'une réservation ou d'un paiement mobile money reconnu par son numéro. On ne demande jamais
au commerçant de créer une fiche client avant de pouvoir vendre.

## Ce que ça donne par métier

**Boutique.** Comptoir par défaut. Crédit quand le client est connu. Le contenant ne sert
pas. C'est le parcours le plus simple et le plus fréquent.

**Restaurant, maquis.** Notes ouvertes par table. Des lignes s'ajoutent au fil du repas. Le
règlement vient à la fin, souvent partagé entre plusieurs modes. Les plats sont en suivi de
stock `recette` : ils consomment des ingrédients, pas eux-mêmes.

**Fast-food, à emporter.** Commande, encaissement, puis remise. Le contenant est un numéro de
ticket. La vente est soldée avant d'être servie — l'inverse du restaurant.

**Prestataire de services.** Devis, puis exécution, puis facture. Souvent un acompte au
départ, traité par une facture `FT`. Aucun suivi de stock.

**Hôtel, événementiel.** Réservation avec arrhes, service à la date convenue, solde ensuite.
Le client est nécessairement identifié.

## Conséquence sur la conception

Aucune de ces variantes ne justifie une seconde application ni un second modèle de données.
Elles se règlent avec :

1. un **état** sur la vente,
2. un **contenant** optionnel et typé,
3. des **écrans métier** qui n'exposent que les parcours utiles, et le vocabulaire qui va
   avec.

Les points 1 et 2 sont dans le socle, parce qu'ils coûtent peu maintenant et cher plus tard.
Le point 3 relève des modules métier, en phase 3.
